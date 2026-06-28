# Order Management API — Design

**Date:** 2026-06-28
**Status:** Approved (ready for implementation planning)

## Overview

A backend service for an e-commerce platform exposing a minimal order
management API. The single core endpoint, `POST /orders`, accepts a customer's
order (shipping address + items + payment), finds a single warehouse that can
fill the entire order, picks the one closest to the shipping address, and
charges the customer via an external payment provider. A companion
`GET /orders/:id` endpoint lets clients observe the asynchronous fulfillment
outcome.

The assignment intentionally leaves out customer/product/warehouse management
APIs and auth; those entities are seeded. Functionality is built to
production-rigor standards (real database, concurrency safety, no overselling).

## Stack

- **Ruby (latest) + Rails (latest), API mode**
- **PostgreSQL** for persistence
- **Sidekiq + Redis** for background jobs
- **RSpec** + factory_bot + faker for tests
- **Docker / Docker Compose** — runs with zero local Ruby install
- Core logic lives in **service classes** under `app/services`

### Configuration

- **No Rails credentials / no `master.key`.** Every external integration is
  mocked, so there are genuinely no secrets to protect; encrypted credentials
  would only add a key-distribution problem for reviewers.
- All config via **environment variables** read as `ENV[...]`.
- **`dotenv-rails`** in the `:development, :test` groups so host-side commands
  (`bundle exec rspec`, `rails console`) auto-load `.env`. Not loaded in
  production.
- A committed **`.env`** (non-secret defaults) plus **`.env.example`** as
  documentation. Compose services use `env_file: .env`.
- Production note (README): real secrets would live in Rails credentials or a
  secrets manager, injected as ENV at deploy time — same `ENV[...]` read path,
  no code change.

## Architecture & Layering

- **Controllers** — thin: authentication, param validation, serialization, HTTP
  status codes only.
- **Services** (`app/services`) — all core logic; each a single-purpose class
  with a `call` method.
- **Models** — persistence, associations, validations, atomic-decrement /
  row-locking primitives.
- **Jobs** (`app/jobs`) — Sidekiq workers orchestrating the async pipeline by
  invoking services.

### Core services

- `Orders::CreateService` — sync path: validate, tokenize card, persist
  `pending` order, enqueue fulfillment job.
- `Orders::FulfillmentService` — async orchestration: geocode → select warehouse
  → atomic decrement → charge → state transition.
- `Geocoding::GeocodeService` — deterministic mock address → lat/long.
- `WarehouseSelection::SelectService` + `WarehouseSelection::HaversineDistance`
  (swappable distance/cost strategy).
- `Payments::TokenizeService` / `Payments::ChargeService` — mock payment client.

## Data Model

```
customers   id, name, email, auth_token (unique, indexed), timestamps
products    id, name, sku (unique), price_cents, currency, timestamps
warehouses  id, name, latitude, longitude, timestamps
inventories warehouse_id, product_id, quantity
            unique index [warehouse_id, product_id]
orders      id, customer_id, status, 
            ship_line1, ship_line2, ship_city, ship_state,
            ship_postal_code, ship_country,
            shipping_lat, shipping_lng,
            warehouse_id (nullable until selected),
            total_cents, currency,
            payment_method_token,
            failure_reason (nullable; non-payment failures only),
            timestamps
order_items id, order_id, product_id, quantity, unit_price_cents (snapshot)
payments    id, order_id, amount_cents, currency,
            status (pending | succeeded | failed),
            provider_payment_id (nullable),
            error_code (nullable), error_message (nullable),
            idempotency_key (unique),
            timestamps
```

Notes:
- **Money as integer cents** (`price_cents`, `total_cents`, `unit_price_cents`,
  `amount_cents`) — no floats.
- `unit_price_cents` is **snapshotted** at order creation so later price changes
  don't rewrite order history. Order `total_cents` = Σ(quantity × unit_price).
- **Raw card number is never persisted.** Only the opaque
  `payment_method_token` (from tokenization) is stored on the order.
- **Payments are first-class records** (one order → many attempts) for an audit
  trail and retry safety. Payment failure detail lives on the `payment` row;
  `orders.failure_reason` is reserved for non-payment failures (e.g. "no
  warehouse can fulfill").
- **Seed data** (`db/seeds.rb`): customers (with `auth_token`s), products,
  warehouses, inventory — since there are no management APIs.

## Authentication

- Customer identified by `Authorization: Bearer <auth_token>`, looked up via
  `customers.auth_token`.
- Missing/invalid token → `401 Unauthorized`.
- Deliberate simplification (documented): a real system would use a proper
  identity/session/token-issuance mechanism.

## API Contract

### `POST /orders` (auth required)

```jsonc
// Authorization: Bearer <auth_token>
{ "order": {
    "shipping_address": {
      "line1": "...", "line2": "...",
      "city": "...", "state": "CA",
      "postal_code": "...", "country": "US"
    },
    "items": [ { "product_id": 1, "quantity": 2 } ],
    "payment": { "card_number": "4111..." }
} }
```

Synchronous responses:
- `201 Created` — order persisted as `pending`; returns the order resource
  (id, status, total_cents, items).
- `401 Unauthorized` — missing/invalid bearer token.
- `422 Unprocessable Entity` — invalid payload, unknown product, non-US /
  unsupported address, or **card tokenization failure**.

### `GET /orders/:id` (auth required)

Lets the client poll the asynchronous outcome. Returns the order with its
current `status`, selected `warehouse_id`, and latest payment status.
- `404 Not Found` — order doesn't exist or doesn't belong to the caller.
- `401 Unauthorized` — unauthenticated.

Included beyond the brief because fulfillment is asynchronous — without it a
client has no way to learn whether an order confirmed or failed.

## Order State Machine

States: `pending → processing → { confirmed | unfulfillable | payment_failed }`

Implemented as a **Rails enum with guarded transition methods** on the `Order`
model (no AASM dependency).

```
            POST /orders (sync)
authenticate → validate payload → validate US address
   → tokenize card → persist order(pending) → enqueue job → 201
                                   │
                          FulfillmentJob (async)
                                   ▼
                            pending → processing
        ┌──────────────────────────┼───────────────────────────┐
   geocode fails /            warehouse found              charge succeeds
   no US warehouse /                │                           │
   no stock                        ▼                            ▼
        ▼                  atomic decrement stock          confirmed
   unfulfillable                   │
   (failure_reason)          charge fails
                                   ▼
                             payment_failed
```

## Fulfillment Flow & Failure Handling

The external payment call **must not** happen inside an open DB transaction
(holding row locks across network I/O is a production hazard). The fulfillment
job therefore runs as **two transactions with a compensating action**:

1. **Tx A — reserve stock:** lock candidate warehouse inventory rows
   (`SELECT … FOR UPDATE`), verify all items in stock, **atomic decrement**, set
   `orders.warehouse_id`. Commit. Order stays `processing`.
2. **Charge — no transaction:** call `Payments::ChargeService` with the
   order-derived idempotency key.
3. **Tx B — settle:**
   - success → create `payment(succeeded)`, transition `confirmed`.
   - failure → create `payment(failed)`, **restore decremented stock**
     (compensating increment), transition `payment_failed`.

### Retry safety (Sidekiq retries)

- Job is **idempotent by inspecting order state**: if `warehouse_id` is already
  set, skip Tx A (no double-decrement); if a `succeeded` payment exists, skip the
  charge.
- The **idempotency key** guards the external charge so a retry after a network
  blip never double-charges.
- **Terminal business failures** (geocode failure, no US warehouse, no stock) →
  transition `unfulfillable` with `failure_reason`; the job does **not** retry
  these. Only transient errors (e.g. provider timeouts) use Sidekiq retry/backoff.

## Warehouse Selection

- `WarehouseSelection::SelectService` takes the candidate warehouses that can
  fill the entire order and returns the chosen one; ranking is an implementation
  detail behind a swappable **strategy**.
- First strategy: `WarehouseSelection::HaversineDistance` (cheap, deterministic,
  testable). A code comment notes that an optimal strategy would also weigh
  transit time, shipping cost, delivery SLA, warehouse capacity, and inventory
  balancing — i.e. true fulfillment is a cost-minimization/optimization problem,
  not nearest-neighbor.

## Mock External Services

Each behind a single-seam service class so specs stub them and real HTTP clients
could be swapped in later.

- **`Geocoding::GeocodeService`** — `call(address) → { lat:, lng: }`.
  Deterministic: built-in lookup keyed by state/postal_code with a deterministic
  hash fallback. The synchronous US check (`country == "US"` + recognized state)
  lives in `Orders::CreateService` and rejects pre-persist with `422`.
- **`Payments::TokenizeService`** — `call(card_number) → token` or raises a typed
  error (→ `422` at creation). Validates basic card format (e.g. Luhn) so
  billing validation is real; returns an opaque `pm_...` token.
- **`Payments::ChargeService`** — `call(token:, amount_cents:, idempotency_key:,
  description:) → provider_payment_id` or raises a typed failure. Deterministic;
  honors the idempotency key (same key → same result, never double-charges).

## Testing Strategy

- **Request specs** (backbone):
  - `POST /orders` — happy path (`201` + `pending`); error paths (`401`, `422`
    invalid card, `422` non-US address).
  - `GET /orders/:id` — happy path + not-found.
- **Unit specs** for complex/sensitive logic only:
  - `WarehouseSelection::HaversineDistance` + `SelectService` (ranking, ties,
    no-eligible-warehouse).
  - `Orders::FulfillmentService` — atomic decrement under concurrency, stock
    restore on payment failure, retry idempotency (no double-decrement /
    double-charge).
  - `Payments::ChargeService` idempotency, `Payments::TokenizeService`
    validation.
- **Tooling:** RSpec, factory_bot, faker; external services stubbed at the
  service seam.

## Docker

- `docker-compose.yml` with `web`, `worker` (Sidekiq), `db` (Postgres), `redis`.
- `Dockerfile` + entrypoint that waits for Postgres and runs `db:prepare` +
  `db:seed`.
- `env_file: .env`; DB + Redis URLs via ENV.
- README: reviewer runs `docker compose up` with zero local Ruby.

## Documented Tradeoffs (README + spec)

- Haversine vs. true fulfillment optimization (transit time, cost, SLA,
  capacity, inventory balancing) — with the strategy seam called out.
- Mocked geocoding/payment behind swappable seams.
- Bearer-token-via-column as a deliberate auth simplification.
- Synchronous tokenize / asynchronous charge rationale.
- ENV-based config / no Rails credentials, with the production secrets story.
