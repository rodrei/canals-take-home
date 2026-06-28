# AGENTS.md

Guidance for AI agents (and humans) working in this repo. Read this before making changes.

## What this is

A Rails **API-only** order management service. The single core endpoint
`POST /orders` accepts an order, fulfills it from the closest single warehouse
that stocks every item, and charges the customer via a mocked payment provider.
`GET /orders/:id` exposes the (asynchronous) outcome.

- **Design spec:** `docs/superpowers/specs/2026-06-28-order-management-api-design.md`
- **Implementation plan:** `docs/superpowers/plans/2026-06-28-order-management-api.md`

Read the design spec first — it explains the *why* behind the architecture.

## Stack

- **Ruby 4.0.5** (`.ruby-version`), **Rails 8.1** (API mode)
- **PostgreSQL**, **Sidekiq + Redis** (background jobs via ActiveJob; adapter is `:sidekiq` in dev/prod, `:test` in test)
- **RSpec** + factory_bot + faker
- **Docker Compose** for `web`, `worker`, `db`, `redis`
- RuboCop (rails-omakase), annotaterb

## Running & testing

The app runs entirely in Docker — no local Ruby needed by a reviewer:

```bash
docker compose up                 # web on :3000, worker, db, redis; auto-prepares + seeds
docker compose run --rm web bundle exec rspec
```

**Working on the host (faster TDD loop):** Postgres and Redis must be reachable
on `localhost`. Bring them up with `docker compose up -d db redis`. Host commands
read DB/Redis URLs from gitignored `.env.test.local` / `.env.development.local`
(localhost), which override the committed `.env` (which uses Docker service
hostnames `db`/`redis`). Then:

```bash
bundle exec rspec                 # full suite
bundle exec rubocop               # must be clean before committing
bundle exec rails db:migrate      # dev DB; RAILS_ENV=test ... for test DB
```

If you add a migration, the annotaterb hook re-annotates models on `db:migrate`.

## Architecture

```
Controller (thin: auth, params, status codes)
  └─ Orders::CreateService        (SYNC: validate, tokenize card, persist pending, enqueue)
       └─ Orders::FulfillmentJob  (Sidekiq)
            └─ Orders::FulfillmentService  (ASYNC: geocode, pick warehouse, decrement, charge, settle)
```

- **Sync vs async split:** the request validates + tokenizes the card and returns
  `201 pending`. Warehouse selection and the *charge* happen in the job, so we
  only charge after a fillable warehouse is reserved (no charge for an order we
  can't fulfill, no refund path).
- **Order state machine** (`app/models/order.rb`): `pending → processing →
  { confirmed | unfulfillable | payment_failed }`. Plain Rails enum + guarded
  `mark_*!` transition methods that raise `Order::InvalidTransition`.
- **Fulfillment is two transactions + compensation** (never hold a DB lock across
  the payment network call): Tx A locks inventory rows (`FOR UPDATE`), verifies
  stock, atomically decrements, sets the warehouse → charge (no transaction) →
  Tx B settles (confirm, or restore stock + `payment_failed`). The job is
  idempotent on retry (skips Tx A if a warehouse is set; skips charge if a
  succeeded payment exists; `payments.idempotency_key` is unique).
- **External services are mocked behind seams:** `Geocoding::GeocodeService`,
  `Payments::TokenizeService` / `ChargeService`. Warehouse ranking is a swappable
  strategy (`WarehouseSelection::HaversineDistance`) behind
  `WarehouseSelection::SelectService`.

## Conventions — follow these

- **Service objects** live in `app/services/<domain>/`, expose `self.call(...)`
  delegating to an instance `#call`. Keep core logic in services, not controllers
  or models.
- **One error type per boundary.** `Orders::CreateService` raises **only**
  `Orders::ValidationError` for *any* validation failure — it translates
  `Payments::InvalidCardError` and `ActiveRecord::RecordInvalid` internally.
  Don't make the controller rescue many types.
- **Errors handled at the action level**, not in `ApplicationController` —
  except generic framework errors (`ActiveRecord::RecordNotFound`) which stay
  global. See `OrdersController#create`.
- **Validations live on the models** (e.g. `Order` presence, `OrderItem`
  numericality). Don't duplicate them in services; build via associations and
  `save!` so AR validations run atomically.
- **Money is integer cents** (`*_cents`), never floats. Prices are snapshotted
  onto `order_items.unit_price_cents` at creation.
- **Raw card numbers are never persisted** — only the `payment_method_token`.
- **Request payloads are wrapped under the resource key**: `{ "order": { ... } }`.
  Strong params expect that shape.
- **Config via ENV only — no Rails credentials / `master.key`.** Everything
  external is mocked, so there are no secrets. Read config with `ENV[...]`.
- **Zeitwerk file-per-constant:** one class/module per file, path matching the
  constant. Error classes get their own files (e.g.
  `payments/invalid_card_error.rb`) — do NOT group them in an `errors.rb`
  (Zeitwerk expects `errors.rb` to define `Errors`).

## Testing approach

- **Request specs are the backbone** (`spec/requests/`): one happy path + the
  key error paths per endpoint.
- **Unit specs only for complex/sensitive logic** (`spec/services/`): warehouse
  selection, the fulfillment pipeline (concurrency, stock restore, retry
  idempotency), payment idempotency, geocoding.
- Factories use faker + sequences. The `:test` ActiveJob adapter means
  `have_enqueued_job` works without Redis.
- Keep the suite and RuboCop green before every commit. RuboCop is rails-omakase
  with `Layout/SpaceInsideArrayLiteralBrackets` disabled (`.rubocop.yml`).

## Gotchas (learned the hard way)

- **HTTP 422 is `:unprocessable_content`** in Rails 8 (not `:unprocessable_entity`).
- **Use `annotaterb`, not the classic `annotate` gem** — the latter caps at
  `activerecord < 8`. annotaterb is configured to annotate models only
  (`.annotaterb.yml` excludes factories/specs/serializers).
- Host-side commands need `db`/`redis` running in Docker and the `.env.*.local`
  overrides; otherwise they try to resolve the Docker hostnames and fail.

## Git

- Commit per logical change with a clear message; keep tests + RuboCop green.
- Don't push to the default branch or create PRs without explicit user request.
