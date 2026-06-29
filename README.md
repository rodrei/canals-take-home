# Canals Order Management API

A minimal, production-rigor order management service. `POST /orders` accepts an
order, fulfills it from the single closest warehouse that stocks every item, and
charges the customer via a mocked payment provider. Validation is synchronous;
warehouse selection and the charge happen asynchronously via Sidekiq.

## Run

    cp .env.example .env   # (a working .env is already committed)
    docker compose up

The API boots on http://localhost:3000. On first boot the entrypoint waits for
Postgres, then prepares and seeds the database. Sidekiq runs in the `worker`
container; Redis and Postgres run as their own services. No local Ruby required.

## Seed credentials

Two customers are seeded with bearer tokens: `alice-token` and `bob-token`.
Products are seeded with ids 1 (Widget), 2 (Gadget), 3 (Gizmo).

## Example

    # Create an order (async fulfillment kicks off in the background)
    curl -s localhost:3000/orders \
      -H "Authorization: Bearer alice-token" \
      -H "Content-Type: application/json" \
      -d '{"order":{"shipping_address":{"line1":"1 Main","city":"New York","state":"NY","postal_code":"10001","country":"US"},"items":[{"product_id":1,"quantity":2}],"payment":{"card_number":"4111111111111111"}}}'

    # Poll for the outcome
    curl -s localhost:3000/orders/1 -H "Authorization: Bearer alice-token"

Test cards: `4111111111111111` succeeds; `4000000000000002` is declined (order
ends `payment_failed`, stock restored); a Luhn-invalid number is rejected at
creation with `422`.

## API

- `POST /orders` — `201` (order `pending`), `401` (bad/missing token),
  `422` (invalid payload, unknown product, non-US address, invalid card).
- `GET /orders/:id` — `200` with current status + latest payment status,
  `404` (not the caller's order), `401`.

Order lifecycle: `pending → processing → { confirmed | unfulfillable | payment_failed }`.

## Tests

    docker compose run --rm web bundle exec rspec

## Design

Full design and rationale: `docs/superpowers/specs/2026-06-28-order-management-api-design.md`.
Implementation plan: `docs/superpowers/plans/2026-06-28-order-management-api.md`.

Entity-relationship diagram: [`docs/erd.png`](docs/erd.png) (Mermaid source:
[`docs/erd.mmd`](docs/erd.mmd)), generated with `rails-erd`.

## Notable design decisions / tradeoffs

- **Sync vs async split.** The request validates the payload, confirms a
  supported US address, and tokenizes the card (real billing validation) before
  returning `201`. Warehouse selection and the charge run in a Sidekiq job, so
  the card is only charged after a fillable warehouse is reserved — no charge for
  an order we can't fulfill, and no refund path.
- **No overselling.** Stock is decremented with a row-locked atomic update
  inside a transaction. The external charge happens *outside* any transaction
  (never hold DB locks across network I/O); on a declined charge the decrement is
  compensated (stock restored). The job is idempotent on Sidekiq retry — it won't
  double-decrement or double-charge.
- **Warehouse selection** uses straight-line (haversine) distance behind a
  swappable strategy. An optimal strategy would also weigh transit time, shipping
  cost, delivery SLA, capacity, and inventory balancing — see the note in
  `app/services/warehouse_selection/haversine_distance.rb`.
- **Money** is stored as integer cents; product prices are snapshotted onto order
  items so later price changes don't rewrite order history.
- **Payments** are first-class records (one order → many attempts) for an audit
  trail, with a unique idempotency key per charge.
- **Config via ENV, no Rails credentials / master key.** Every external
  integration is mocked, so there are no real secrets; encrypted credentials
  would only add a key-distribution problem for reviewers. In real production,
  secrets would live in a secrets manager and be injected as ENV — same
  `ENV[...]` read path, no code change.
- **Auth** is a simple bearer token matched against `customers.auth_token` — a
  deliberate stand-in for a real identity/token-issuance system.

## Stack

Ruby 4.0, Rails 8.1 (API mode), PostgreSQL, Sidekiq + Redis (via ActiveJob),
RSpec + factory_bot + faker, Docker Compose.
