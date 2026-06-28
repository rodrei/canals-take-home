# Order Management API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a production-rigor Rails API that accepts an order, fulfills it from the closest single warehouse that stocks every item, and charges the customer via a mocked payment provider — synchronous validation, asynchronous fulfillment.

**Architecture:** Rails (API mode) + PostgreSQL + Sidekiq. `POST /orders` synchronously authenticates, validates, tokenizes the card, persists a `pending` order, and enqueues a fulfillment job. The job geocodes the address, atomically decrements stock at the closest eligible warehouse, charges the card, and transitions the order to a terminal state. Core logic lives in single-purpose service classes under `app/services`. `GET /orders/:id` exposes the async outcome.

**Tech Stack:** Ruby 3.4, Rails 8 (API mode), PostgreSQL, Sidekiq + Redis (via ActiveJob with the Sidekiq adapter), RSpec + factory_bot + faker, Docker Compose, dotenv-rails.

## Global Constraints

- **Ruby (latest, 3.4.x) + Rails (latest, 8.x), API mode** (`rails new --api`).
- **PostgreSQL** for all persistence. **No SQLite.**
- **Money is stored as integer cents** — never floats. Columns: `price_cents`, `total_cents`, `unit_price_cents`, `amount_cents`.
- **Raw card numbers are NEVER persisted** — only the opaque `payment_method_token`.
- **No Rails credentials / no `master.key`.** All config via `ENV[...]`. `dotenv-rails` in `:development, :test` only. Commit `.env` (non-secret defaults) + `.env.example`.
- **Core logic in `app/services`**, each class a single-purpose object with a `call` (or `self.call`) method.
- **Background work via ActiveJob with `config.active_job.queue_adapter = :sidekiq`.**
- **External integrations (geocoding, payment) are mocked behind service-class seams** that specs stub.
- **Tests:** request specs as the backbone (one happy + one error path each, except complex flows); unit specs only for complex/sensitive service logic.
- **Runs via `docker compose up` with zero local Ruby install.**
- Money currency default: `"USD"`.

---

### Task 1: Project scaffold, Docker, and test harness

**Files:**
- Create: entire Rails app at repo root (`Gemfile`, `config/`, `app/`, etc.)
- Create: `Dockerfile`, `docker-compose.yml`, `bin/docker-entrypoint`, `.env`, `.env.example`, `.dockerignore`
- Create: `config/initializers/sidekiq.rb`
- Create: `spec/rails_helper.rb`, `spec/spec_helper.rb` (via generator)
- Test: `spec/requests/health_spec.rb`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a booting Rails API app; ActiveJob configured with `:sidekiq` adapter; RSpec + factory_bot + faker available; `docker compose up` boots `web`, `worker`, `db`, `redis`.

- [ ] **Step 1: Generate the Rails API app at repo root**

The repo already contains `instructions.md` and `docs/`. Generate into the current directory.

Run:
```bash
gem install rails
rails new . --api --database=postgresql --skip-test --skip-kamal --skip-solid --force
```
Expected: Rails 8 app files created; `instructions.md` and `docs/` preserved.

- [ ] **Step 2: Add gems to the Gemfile**

Add to `Gemfile`:
```ruby
gem "sidekiq"

group :development, :test do
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "dotenv-rails"
end
```
Run: `bundle install`
Expected: bundle completes.

- [ ] **Step 3: Install RSpec**

Run: `bundle exec rails generate rspec:install`
Expected: creates `.rspec`, `spec/spec_helper.rb`, `spec/rails_helper.rb`.

Add factory_bot syntax methods to `spec/rails_helper.rb` inside `RSpec.configure do |config|`:
```ruby
  config.include FactoryBot::Syntax::Methods
```

- [ ] **Step 4: Configure the Sidekiq queue adapter**

In `config/application.rb`, inside `class Application < Rails::Application`:
```ruby
    config.active_job.queue_adapter = :sidekiq
```

Create `config/initializers/sidekiq.rb`:
```ruby
redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

Sidekiq.configure_server { |config| config.redis = { url: redis_url } }
Sidekiq.configure_client { |config| config.redis = { url: redis_url } }
```

- [ ] **Step 5: Write env files**

Create `.env.example`:
```
DATABASE_URL=postgres://postgres:postgres@db:5432/canals_development
TEST_DATABASE_URL=postgres://postgres:postgres@db:5432/canals_test
REDIS_URL=redis://redis:6379/0
RAILS_ENV=development
```
Copy it to `.env` with the same values (non-secret defaults, safe to commit).

In `config/database.yml`, set the `default` to read the URL and the `test` env to use `TEST_DATABASE_URL`:
```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS", 5) %>
  url: <%= ENV["DATABASE_URL"] %>

development:
  <<: *default

test:
  <<: *default
  url: <%= ENV["TEST_DATABASE_URL"] %>

production:
  <<: *default
```

- [ ] **Step 6: Write Docker files**

Create `Dockerfile`:
```dockerfile
FROM ruby:3.4

RUN apt-get update -qq && apt-get install -y postgresql-client && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
```

Create `bin/docker-entrypoint`:
```bash
#!/usr/bin/env bash
set -e

until pg_isready -h db -U postgres >/dev/null 2>&1; do
  echo "Waiting for postgres..."
  sleep 1
done

if [ "${1}" = "bundle" ] && [ "${2}" = "exec" ] && [ "${3}" = "rails" ] && [ "${4}" = "server" ]; then
  bundle exec rails db:prepare
  bundle exec rails db:seed
fi

exec "$@"
```
Run: `chmod +x bin/docker-entrypoint`

Create `docker-compose.yml`:
```yaml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    volumes:
      - pg_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  redis:
    image: redis:7
    ports:
      - "6379:6379"

  web:
    build: .
    command: bundle exec rails server -b 0.0.0.0 -p 3000
    env_file: .env
    ports:
      - "3000:3000"
    depends_on:
      - db
      - redis

  worker:
    build: .
    command: bundle exec sidekiq
    env_file: .env
    depends_on:
      - db
      - redis

volumes:
  pg_data:
```

Create `.dockerignore`:
```
.git
tmp
log
.env
```

- [ ] **Step 7: Write the failing health request spec**

Rails 8 ships a `/up` health endpoint. Create `spec/requests/health_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Health", type: :request do
  it "returns 200 from the health endpoint" do
    get "/up"
    expect(response).to have_http_status(:ok)
  end
end
```

- [ ] **Step 8: Prepare the test DB and run the spec**

Run:
```bash
bundle exec rails db:prepare
bundle exec rspec spec/requests/health_spec.rb
```
Expected: PASS (1 example, 0 failures).

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "chore: scaffold Rails API app with Docker, Sidekiq, and RSpec"
```

---

### Task 2: Catalog models (customers, products, warehouses, inventories)

**Files:**
- Create: migrations under `db/migrate/`
- Create: `app/models/customer.rb`, `app/models/product.rb`, `app/models/warehouse.rb`, `app/models/inventory.rb`
- Create: `spec/factories/customers.rb`, `spec/factories/products.rb`, `spec/factories/warehouses.rb`, `spec/factories/inventories.rb`
- Test: `spec/models/inventory_spec.rb`

**Interfaces:**
- Consumes: Task 1 app.
- Produces:
  - `Customer(name:string, email:string, auth_token:string unique)`
  - `Product(name:string, sku:string unique, price_cents:integer, currency:string)`
  - `Warehouse(name:string, latitude:decimal, longitude:decimal)` with `has_many :inventories`
  - `Inventory(warehouse_id, product_id, quantity:integer)` unique on `[warehouse_id, product_id]`, `belongs_to :warehouse`, `belongs_to :product`

- [ ] **Step 1: Generate migrations**

Run:
```bash
bundle exec rails g model Customer name:string email:string auth_token:string
bundle exec rails g model Product name:string sku:string price_cents:integer currency:string
bundle exec rails g model Warehouse name:string latitude:decimal longitude:decimal
bundle exec rails g model Inventory warehouse:references product:references quantity:integer
```

- [ ] **Step 2: Edit migrations for constraints**

In the customers migration, add after `t.timestamps`: nothing — instead add an index. Edit the customers migration to add:
```ruby
    add_index :customers, :auth_token, unique: true
```
In the products migration add:
```ruby
    add_index :products, :sku, unique: true
```
In the warehouses migration, change the decimal columns to carry precision:
```ruby
    t.decimal :latitude, precision: 10, scale: 6
    t.decimal :longitude, precision: 10, scale: 6
```
In the inventories migration, set a non-null default and a unique composite index:
```ruby
    t.integer :quantity, null: false, default: 0
    # ...
    add_index :inventories, [:warehouse_id, :product_id], unique: true
```

- [ ] **Step 3: Write the models**

`app/models/customer.rb`:
```ruby
class Customer < ApplicationRecord
  has_many :orders, dependent: :destroy

  validates :name, presence: true
  validates :auth_token, presence: true, uniqueness: true
end
```

`app/models/product.rb`:
```ruby
class Product < ApplicationRecord
  validates :name, presence: true
  validates :sku, presence: true, uniqueness: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
end
```

`app/models/warehouse.rb`:
```ruby
class Warehouse < ApplicationRecord
  has_many :inventories, dependent: :destroy
  has_many :products, through: :inventories

  validates :name, presence: true
  validates :latitude, :longitude, presence: true
end
```

`app/models/inventory.rb`:
```ruby
class Inventory < ApplicationRecord
  belongs_to :warehouse
  belongs_to :product

  validates :quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :product_id, uniqueness: { scope: :warehouse_id }
end
```

- [ ] **Step 4: Write factories**

`spec/factories/customers.rb`:
```ruby
FactoryBot.define do
  factory :customer do
    name { Faker::Name.name }
    email { Faker::Internet.unique.email }
    sequence(:auth_token) { |n| "token_#{n}_#{SecureRandom.hex(8)}" }
  end
end
```

`spec/factories/products.rb`:
```ruby
FactoryBot.define do
  factory :product do
    name { Faker::Commerce.product_name }
    sequence(:sku) { |n| "SKU-#{n}" }
    price_cents { 1_000 }
    currency { "USD" }
  end
end
```

`spec/factories/warehouses.rb`:
```ruby
FactoryBot.define do
  factory :warehouse do
    name { Faker::Company.name }
    latitude { 40.7128 }
    longitude { -74.0060 }
  end
end
```

`spec/factories/inventories.rb`:
```ruby
FactoryBot.define do
  factory :inventory do
    warehouse
    product
    quantity { 100 }
  end
end
```

- [ ] **Step 5: Write the failing inventory uniqueness spec**

`spec/models/inventory_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Inventory, type: :model do
  it "forbids duplicate product rows within a warehouse" do
    warehouse = create(:warehouse)
    product = create(:product)
    create(:inventory, warehouse: warehouse, product: product)

    dup = build(:inventory, warehouse: warehouse, product: product)

    expect(dup).not_to be_valid
  end
end
```

- [ ] **Step 6: Migrate and run the spec**

Run:
```bash
bundle exec rails db:migrate
RAILS_ENV=test bundle exec rails db:migrate
bundle exec rspec spec/models/inventory_spec.rb
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add catalog models (customer, product, warehouse, inventory)"
```

---

### Task 3: Order models and state machine (orders, order_items, payments)

**Files:**
- Create: migrations for `orders`, `order_items`, `payments`
- Create: `app/models/order.rb`, `app/models/order_item.rb`, `app/models/payment.rb`
- Create: `spec/factories/orders.rb`, `spec/factories/order_items.rb`, `spec/factories/payments.rb`
- Test: `spec/models/order_spec.rb`

**Interfaces:**
- Consumes: Task 2 models.
- Produces:
  - `Order` with enum `status: { pending: 0, processing: 1, confirmed: 2, unfulfillable: 3, payment_failed: 4 }`, `belongs_to :customer`, `belongs_to :warehouse, optional: true`, `has_many :order_items`, `has_many :payments`. Columns: ship address fields, `shipping_lat`, `shipping_lng`, `total_cents`, `currency`, `payment_method_token`, `failure_reason`.
  - Guarded transition methods: `start_processing!`, `mark_confirmed!`, `mark_unfulfillable!(reason)`, `mark_payment_failed!`.
  - `OrderItem(order_id, product_id, quantity, unit_price_cents)`.
  - `Payment(order_id, amount_cents, currency, status enum {pending,succeeded,failed}, provider_payment_id, error_code, error_message, idempotency_key unique)`.

- [ ] **Step 1: Generate migrations**

Run:
```bash
bundle exec rails g model Order customer:references warehouse:references status:integer ship_line1:string ship_line2:string ship_city:string ship_state:string ship_postal_code:string ship_country:string shipping_lat:decimal shipping_lng:decimal total_cents:integer currency:string payment_method_token:string failure_reason:string
bundle exec rails g model OrderItem order:references product:references quantity:integer unit_price_cents:integer
bundle exec rails g model Payment order:references amount_cents:integer currency:string status:integer provider_payment_id:string error_code:string error_message:string idempotency_key:string
```

- [ ] **Step 2: Edit migrations**

In the orders migration:
- Make `warehouse` reference optional: change `t.references :warehouse, null: false, foreign_key: true` to `t.references :warehouse, null: true, foreign_key: true`.
- Set status default and not-null: `t.integer :status, null: false, default: 0`.
- Give lat/lng precision: `t.decimal :shipping_lat, precision: 10, scale: 6` and same for `shipping_lng`.

In the payments migration add a unique index and status default:
```ruby
    t.integer :status, null: false, default: 0
    # ...
    add_index :payments, :idempotency_key, unique: true
```

- [ ] **Step 3: Write the models**

`app/models/order.rb`:
```ruby
class Order < ApplicationRecord
  belongs_to :customer
  belongs_to :warehouse, optional: true
  has_many :order_items, dependent: :destroy
  has_many :payments, dependent: :destroy

  enum :status, {
    pending: 0,
    processing: 1,
    confirmed: 2,
    unfulfillable: 3,
    payment_failed: 4
  }

  validates :total_cents, numericality: { greater_than_or_equal_to: 0 }

  def start_processing!
    raise InvalidTransition, "expected pending, was #{status}" unless pending?
    update!(status: :processing)
  end

  def mark_confirmed!(warehouse:)
    raise InvalidTransition, "expected processing, was #{status}" unless processing?
    update!(status: :confirmed, warehouse: warehouse)
  end

  def mark_unfulfillable!(reason)
    update!(status: :unfulfillable, failure_reason: reason)
  end

  def mark_payment_failed!
    update!(status: :payment_failed)
  end

  class InvalidTransition < StandardError; end
end
```

`app/models/order_item.rb`:
```ruby
class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, numericality: { greater_than_or_equal_to: 0 }
end
```

`app/models/payment.rb`:
```ruby
class Payment < ApplicationRecord
  belongs_to :order

  enum :status, { pending: 0, succeeded: 1, failed: 2 }

  validates :idempotency_key, presence: true, uniqueness: true
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
end
```

- [ ] **Step 4: Write factories**

`spec/factories/orders.rb`:
```ruby
FactoryBot.define do
  factory :order do
    customer
    status { :pending }
    ship_line1 { "123 Main St" }
    ship_city { "New York" }
    ship_state { "NY" }
    ship_postal_code { "10001" }
    ship_country { "US" }
    total_cents { 2_000 }
    currency { "USD" }
    payment_method_token { "pm_ok_test" }
  end
end
```

`spec/factories/order_items.rb`:
```ruby
FactoryBot.define do
  factory :order_item do
    order
    product
    quantity { 1 }
    unit_price_cents { 1_000 }
  end
end
```

`spec/factories/payments.rb`:
```ruby
FactoryBot.define do
  factory :payment do
    order
    amount_cents { 2_000 }
    currency { "USD" }
    status { :pending }
    sequence(:idempotency_key) { |n| "idem_#{n}" }
  end
end
```

- [ ] **Step 5: Write the failing state-machine spec**

`spec/models/order_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Order, type: :model do
  it "transitions pending -> processing -> confirmed" do
    order = create(:order, status: :pending)
    warehouse = create(:warehouse)

    order.start_processing!
    expect(order).to be_processing

    order.mark_confirmed!(warehouse: warehouse)
    expect(order).to be_confirmed
    expect(order.warehouse).to eq(warehouse)
  end

  it "rejects confirming an order that is not processing" do
    order = create(:order, status: :pending)
    warehouse = create(:warehouse)

    expect { order.mark_confirmed!(warehouse: warehouse) }
      .to raise_error(Order::InvalidTransition)
  end
end
```

- [ ] **Step 6: Migrate and run**

Run:
```bash
bundle exec rails db:migrate
RAILS_ENV=test bundle exec rails db:migrate
bundle exec rspec spec/models/order_spec.rb
```
Expected: PASS (2 examples).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add order, order_item, payment models with state machine"
```

---

### Task 4: Seed data

**Files:**
- Modify: `db/seeds.rb`
- Test: none (verified by running seeds)

**Interfaces:**
- Consumes: all models.
- Produces: deterministic seed data — at least 2 customers with known `auth_token`s, several products, 3 warehouses at distinct US coordinates, inventory rows. Idempotent (safe to re-run).

- [ ] **Step 1: Write idempotent seeds**

Replace `db/seeds.rb`:
```ruby
# Idempotent seeds — safe to run repeatedly.

alice = Customer.find_or_create_by!(auth_token: "alice-token") do |c|
  c.name = "Alice"
  c.email = "alice@example.com"
end

Customer.find_or_create_by!(auth_token: "bob-token") do |c|
  c.name = "Bob"
  c.email = "bob@example.com"
end

widget = Product.find_or_create_by!(sku: "WIDGET") { |p| p.name = "Widget"; p.price_cents = 1_500; p.currency = "USD" }
gadget = Product.find_or_create_by!(sku: "GADGET") { |p| p.name = "Gadget"; p.price_cents = 2_500; p.currency = "USD" }
gizmo  = Product.find_or_create_by!(sku: "GIZMO")  { |p| p.name = "Gizmo";  p.price_cents = 800;   p.currency = "USD" }

# Warehouses at distinct US coordinates.
nyc = Warehouse.find_or_create_by!(name: "NYC DC")     { |w| w.latitude = 40.7128; w.longitude = -74.0060 }
chi = Warehouse.find_or_create_by!(name: "Chicago DC") { |w| w.latitude = 41.8781; w.longitude = -87.6298 }
lax = Warehouse.find_or_create_by!(name: "LA DC")      { |w| w.latitude = 34.0522; w.longitude = -118.2437 }

def stock(warehouse, product, quantity)
  inv = Inventory.find_or_initialize_by(warehouse: warehouse, product: product)
  inv.quantity = quantity
  inv.save!
end

# NYC stocks everything; Chicago stocks widget+gadget; LA stocks only widget.
stock(nyc, widget, 100); stock(nyc, gadget, 100); stock(nyc, gizmo, 100)
stock(chi, widget, 100); stock(chi, gadget, 100)
stock(lax, widget, 100)

puts "Seeded #{Customer.count} customers, #{Product.count} products, #{Warehouse.count} warehouses."
```

- [ ] **Step 2: Run seeds twice to prove idempotency**

Run:
```bash
bundle exec rails db:seed
bundle exec rails db:seed
bundle exec rails runner 'puts Customer.count'
```
Expected: second run does not error; customer count stays at 2.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add idempotent seed data"
```

---

### Task 5: Authentication via bearer token

**Files:**
- Create: `app/controllers/concerns/authenticable.rb`
- Modify: `app/controllers/application_controller.rb`
- Test: covered by request specs in later tasks (no standalone spec — the concern is exercised through `GET /orders/:id` and `POST /orders`)

**Interfaces:**
- Consumes: `Customer`.
- Produces: `current_customer` helper available in controllers; `authenticate_customer!` before-action returning `401` with `{ "error": "unauthorized" }` when the `Authorization: Bearer <token>` header is missing or unknown.

- [ ] **Step 1: Write the concern**

`app/controllers/concerns/authenticable.rb`:
```ruby
module Authenticable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_customer!
  end

  private

  def current_customer
    @current_customer
  end

  def authenticate_customer!
    token = bearer_token
    @current_customer = Customer.find_by(auth_token: token) if token.present?
    return if @current_customer

    render json: { error: "unauthorized" }, status: :unauthorized
  end

  def bearer_token
    header = request.headers["Authorization"]
    return if header.blank?

    header.split(" ").last
  end
end
```

- [ ] **Step 2: Include it in ApplicationController**

`app/controllers/application_controller.rb`:
```ruby
class ApplicationController < ActionController::API
  include Authenticable
end
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add bearer-token authentication concern"
```

(Behavioral verification happens in Task 10 and Task 11 request specs.)

---

### Task 6: Geocoding service

**Files:**
- Create: `app/services/geocoding/geocode_service.rb`
- Create: `app/services/geocoding/unsupported_address_error.rb`
- Test: `spec/services/geocoding/geocode_service_spec.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `Geocoding::GeocodeService.call(address_hash) → { lat: Float, lng: Float }`. Raises `Geocoding::UnsupportedAddressError` when `country != "US"` or `state` is not a recognized US state abbreviation. `address_hash` keys: `:city, :state, :postal_code, :country` (string or symbol keys both accepted via `with_indifferent_access`). Deterministic.

- [ ] **Step 1: Write the failing spec**

`spec/services/geocoding/geocode_service_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Geocoding::GeocodeService do
  it "returns deterministic coordinates for a US address" do
    address = { city: "New York", state: "NY", postal_code: "10001", country: "US" }

    first = described_class.call(address)
    second = described_class.call(address)

    expect(first[:lat]).to be_within(0.0001).of(second[:lat])
    expect(first[:lng]).to be_within(0.0001).of(second[:lng])
    expect(first[:lat]).to be_between(24.0, 50.0)
  end

  it "raises for a non-US country" do
    address = { city: "Toronto", state: "ON", postal_code: "M5V", country: "CA" }

    expect { described_class.call(address) }
      .to raise_error(Geocoding::UnsupportedAddressError)
  end

  it "raises for an unrecognized state" do
    address = { city: "Nowhere", state: "ZZ", postal_code: "00000", country: "US" }

    expect { described_class.call(address) }
      .to raise_error(Geocoding::UnsupportedAddressError)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/services/geocoding/geocode_service_spec.rb`
Expected: FAIL (uninitialized constant `Geocoding`).

- [ ] **Step 3: Write the error class and service**

`app/services/geocoding/unsupported_address_error.rb`:
```ruby
module Geocoding
  class UnsupportedAddressError < StandardError; end
end
```

`app/services/geocoding/geocode_service.rb`:
```ruby
module Geocoding
  # Mocked geocoder. A real implementation would call a 3rd-party geocoding API.
  # Returns deterministic coordinates: the centroid of the address's US state,
  # nudged by a small deterministic offset derived from the postal code so that
  # distinct addresses within a state still differ slightly.
  class GeocodeService
    STATE_CENTROIDS = {
      "NY" => [42.9538, -75.5268], "CA" => [37.1841, -119.4696],
      "IL" => [40.0417, -89.1965], "TX" => [31.4757, -99.3312],
      "FL" => [28.6305, -82.4497], "WA" => [47.3826, -120.4472],
      "MA" => [42.2596, -71.8083], "GA" => [32.6415, -83.4426],
      "CO" => [38.9972, -105.5478], "PA" => [40.8781, -77.7996]
    }.freeze

    def self.call(address)
      new(address).call
    end

    def initialize(address)
      @address = address.to_h.with_indifferent_access
    end

    def call
      raise UnsupportedAddressError, "only US addresses are supported" unless us?

      centroid = STATE_CENTROIDS[state]
      raise UnsupportedAddressError, "unrecognized state: #{state}" unless centroid

      lat = centroid[0] + offset(0)
      lng = centroid[1] + offset(1)
      { lat: lat.round(6), lng: lng.round(6) }
    end

    private

    attr_reader :address

    def us?
      address[:country].to_s.upcase == "US"
    end

    def state
      address[:state].to_s.upcase
    end

    def offset(index)
      digest = Digest::SHA256.hexdigest("#{address[:postal_code]}:#{index}")
      (digest[0, 4].to_i(16) % 1000) / 10_000.0 # 0.0..0.0999
    end
  end
end
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec spec/services/geocoding/geocode_service_spec.rb`
Expected: PASS (3 examples).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add deterministic mock geocoding service"
```

---

### Task 7: Payment services (tokenize + charge)

**Files:**
- Create: `app/services/payments/tokenize_service.rb`
- Create: `app/services/payments/charge_service.rb`
- Create: `app/services/payments/errors.rb`
- Test: `spec/services/payments/tokenize_service_spec.rb`, `spec/services/payments/charge_service_spec.rb`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Payments::TokenizeService.call(card_number) → "pm_ok_<digest>"` (or `"pm_decline_<digest>"` for the designated decline card `4000000000000002`). Raises `Payments::InvalidCardError` when the number fails the Luhn check.
  - `Payments::ChargeService.call(token:, amount_cents:, idempotency_key:, description:) → "ch_<idempotency_key>"`. Raises `Payments::PaymentDeclinedError` when `token` begins with `pm_decline`. Deterministic; the same `idempotency_key` always yields the same provider id.

- [ ] **Step 1: Write the failing specs**

`spec/services/payments/tokenize_service_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Payments::TokenizeService do
  it "tokenizes a valid card" do
    token = described_class.call("4111111111111111")
    expect(token).to start_with("pm_ok_")
  end

  it "marks the designated decline card" do
    token = described_class.call("4000000000000002")
    expect(token).to start_with("pm_decline_")
  end

  it "raises on a Luhn-invalid card" do
    expect { described_class.call("1234567812345678") }
      .to raise_error(Payments::InvalidCardError)
  end
end
```

`spec/services/payments/charge_service_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Payments::ChargeService do
  it "charges a valid token deterministically by idempotency key" do
    id1 = described_class.call(token: "pm_ok_abc", amount_cents: 1000, idempotency_key: "k1", description: "order 1")
    id2 = described_class.call(token: "pm_ok_abc", amount_cents: 1000, idempotency_key: "k1", description: "order 1")

    expect(id1).to eq("ch_k1")
    expect(id2).to eq(id1)
  end

  it "declines a decline token" do
    expect {
      described_class.call(token: "pm_decline_abc", amount_cents: 1000, idempotency_key: "k2", description: "order 2")
    }.to raise_error(Payments::PaymentDeclinedError)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/services/payments/`
Expected: FAIL (uninitialized constant `Payments`).

- [ ] **Step 3: Write the errors and services**

`app/services/payments/errors.rb`:
```ruby
module Payments
  class InvalidCardError < StandardError; end
  class PaymentDeclinedError < StandardError; end
end
```

`app/services/payments/tokenize_service.rb`:
```ruby
module Payments
  # Mocked payment tokenization. A real implementation would call the payment
  # provider's vault API. Validates the card with the Luhn algorithm so the
  # synchronous "billing validation" is real, then returns an opaque token.
  # The card number is never returned or persisted.
  class TokenizeService
    DECLINE_CARD = "4000000000000002"

    def self.call(card_number)
      new(card_number).call
    end

    def initialize(card_number)
      @card_number = card_number.to_s.gsub(/\s+/, "")
    end

    def call
      raise InvalidCardError, "card failed validation" unless luhn_valid?

      prefix = (@card_number == DECLINE_CARD) ? "pm_decline_" : "pm_ok_"
      "#{prefix}#{Digest::SHA256.hexdigest(@card_number)[0, 16]}"
    end

    private

    def luhn_valid?
      return false unless @card_number.match?(/\A\d{13,19}\z/)

      digits = @card_number.chars.map(&:to_i).reverse
      sum = digits.each_with_index.sum do |digit, index|
        if index.odd?
          doubled = digit * 2
          doubled > 9 ? doubled - 9 : doubled
        else
          digit
        end
      end
      (sum % 10).zero?
    end
  end
end
```

`app/services/payments/charge_service.rb`:
```ruby
module Payments
  # Mocked payment charge. A real implementation would call the provider's
  # charge API with the idempotency key. Deterministic: a token beginning with
  # "pm_decline" is declined; otherwise the charge succeeds and the provider id
  # is derived from the idempotency key so retries return the same id.
  class ChargeService
    def self.call(token:, amount_cents:, idempotency_key:, description:)
      new(token: token, amount_cents: amount_cents, idempotency_key: idempotency_key, description: description).call
    end

    def initialize(token:, amount_cents:, idempotency_key:, description:)
      @token = token
      @amount_cents = amount_cents
      @idempotency_key = idempotency_key
      @description = description
    end

    def call
      raise PaymentDeclinedError, "card declined" if @token.to_s.start_with?("pm_decline")

      "ch_#{@idempotency_key}"
    end
  end
end
```

- [ ] **Step 4: Run to verify pass**

Run: `bundle exec rspec spec/services/payments/`
Expected: PASS (5 examples).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add mock payment tokenize and charge services"
```

---

### Task 8: Warehouse selection (eligibility query + haversine strategy)

**Files:**
- Create: `app/services/warehouse_selection/haversine_distance.rb`
- Create: `app/services/warehouse_selection/eligible_query.rb`
- Create: `app/services/warehouse_selection/select_service.rb`
- Test: `spec/services/warehouse_selection/haversine_distance_spec.rb`, `spec/services/warehouse_selection/select_service_spec.rb`

**Interfaces:**
- Consumes: `Warehouse`, `Inventory`.
- Produces:
  - `WarehouseSelection::HaversineDistance.call(lat1:, lng1:, lat2:, lng2:) → Float` (kilometers).
  - `WarehouseSelection::EligibleQuery.call(item_quantities) → ActiveRecord::Relation<Warehouse>` where `item_quantities` is `{ product_id => quantity }`; returns warehouses whose inventory covers every product at the requested quantity.
  - `WarehouseSelection::SelectService.call(warehouses:, lat:, lng:, strategy: HaversineDistance) → Warehouse | nil` (nearest by strategy; `nil` if `warehouses` empty).

- [ ] **Step 1: Write the failing haversine spec**

`spec/services/warehouse_selection/haversine_distance_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe WarehouseSelection::HaversineDistance do
  it "computes zero for identical points" do
    expect(described_class.call(lat1: 40.0, lng1: -74.0, lat2: 40.0, lng2: -74.0)).to be_within(0.001).of(0.0)
  end

  it "approximates the NYC-to-Chicago distance (~1145 km)" do
    km = described_class.call(lat1: 40.7128, lng1: -74.0060, lat2: 41.8781, lng2: -87.6298)
    expect(km).to be_within(50).of(1145)
  end
end
```

- [ ] **Step 2: Write the haversine strategy**

`app/services/warehouse_selection/haversine_distance.rb`:
```ruby
module WarehouseSelection
  # Great-circle distance in kilometers.
  #
  # NOTE: distance is only a proxy for fulfillment optimality. An optimal
  # selection strategy would also weigh real transit time (road/carrier
  # routing, not straight-line), shipping cost and carrier zones, the delivery
  # SLA, warehouse capacity/throughput, and inventory balancing across the
  # network. True fulfillment is a cost-minimization problem, not nearest-
  # neighbor. This strategy is intentionally swappable behind SelectService.
  class HaversineDistance
    EARTH_RADIUS_KM = 6371.0

    def self.call(lat1:, lng1:, lat2:, lng2:)
      rlat1 = to_rad(lat1)
      rlat2 = to_rad(lat2)
      dlat = to_rad(lat2 - lat1)
      dlng = to_rad(lng2 - lng1)

      a = (Math.sin(dlat / 2)**2) +
          (Math.cos(rlat1) * Math.cos(rlat2) * (Math.sin(dlng / 2)**2))
      c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
      EARTH_RADIUS_KM * c
    end

    def self.to_rad(degrees)
      degrees.to_f * Math::PI / 180
    end
  end
end
```

- [ ] **Step 3: Run haversine spec**

Run: `bundle exec rspec spec/services/warehouse_selection/haversine_distance_spec.rb`
Expected: PASS (2 examples).

- [ ] **Step 4: Write the eligibility query**

`app/services/warehouse_selection/eligible_query.rb`:
```ruby
module WarehouseSelection
  # Returns warehouses that can fill the ENTIRE order from a single location:
  # every requested product must be stocked at >= the requested quantity.
  class EligibleQuery
    def self.call(item_quantities)
      new(item_quantities).call
    end

    def initialize(item_quantities)
      @item_quantities = item_quantities
    end

    def call
      return Warehouse.none if @item_quantities.blank?

      product_count = @item_quantities.size

      # A warehouse is eligible if, counting only rows where it stocks enough of
      # a requested product, it covers all requested products.
      conditions = @item_quantities.map do |product_id, quantity|
        Inventory.sanitize_sql_array(
          ["(inventories.product_id = ? AND inventories.quantity >= ?)", product_id, quantity]
        )
      end.join(" OR ")

      eligible_ids = Inventory
        .where(Arel.sql(conditions))
        .group(:warehouse_id)
        .having("COUNT(DISTINCT inventories.product_id) = ?", product_count)
        .pluck(:warehouse_id)

      Warehouse.where(id: eligible_ids)
    end
  end
end
```

- [ ] **Step 5: Write the failing select-service spec**

`spec/services/warehouse_selection/select_service_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe WarehouseSelection::SelectService do
  let(:product) { create(:product) }

  it "returns only eligible warehouses' nearest to the destination" do
    near = create(:warehouse, latitude: 40.71, longitude: -74.00)   # NYC-ish
    far  = create(:warehouse, latitude: 34.05, longitude: -118.24)  # LA-ish
    create(:inventory, warehouse: near, product: product, quantity: 10)
    create(:inventory, warehouse: far, product: product, quantity: 10)

    eligible = WarehouseSelection::EligibleQuery.call({ product.id => 2 })
    chosen = described_class.call(warehouses: eligible, lat: 40.73, lng: -73.99)

    expect(chosen).to eq(near)
  end

  it "returns nil when no warehouse is eligible" do
    create(:inventory, warehouse: create(:warehouse), product: product, quantity: 1)

    eligible = WarehouseSelection::EligibleQuery.call({ product.id => 5 })
    chosen = described_class.call(warehouses: eligible, lat: 40.73, lng: -73.99)

    expect(chosen).to be_nil
  end
end
```

- [ ] **Step 6: Write the select service**

`app/services/warehouse_selection/select_service.rb`:
```ruby
module WarehouseSelection
  # Given candidate warehouses already known to be able to fill the order,
  # returns the one closest to the destination per the distance strategy.
  class SelectService
    def self.call(warehouses:, lat:, lng:, strategy: HaversineDistance)
      new(warehouses: warehouses, lat: lat, lng: lng, strategy: strategy).call
    end

    def initialize(warehouses:, lat:, lng:, strategy:)
      @warehouses = warehouses
      @lat = lat
      @lng = lng
      @strategy = strategy
    end

    def call
      @warehouses.min_by do |warehouse|
        @strategy.call(
          lat1: @lat, lng1: @lng,
          lat2: warehouse.latitude.to_f, lng2: warehouse.longitude.to_f
        )
      end
    end
  end
end
```

- [ ] **Step 7: Run the select spec**

Run: `bundle exec rspec spec/services/warehouse_selection/`
Expected: PASS (4 examples total).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add warehouse eligibility query and haversine selection"
```

---

### Task 9: Order creation service (synchronous path)

**Files:**
- Create: `app/services/orders/create_service.rb`
- Create: `app/services/orders/errors.rb`
- Create: `app/jobs/orders/fulfillment_job.rb` (stub — real body in Task 10)
- Test: `spec/services/orders/create_service_spec.rb`

**Interfaces:**
- Consumes: `Customer`, `Product`, `Geocoding::GeocodeService` (US validation only — full geocode happens in the job), `Payments::TokenizeService`, `Order`, `OrderItem`.
- Produces: `Orders::CreateService.call(customer:, params:) → Order` (persisted, `pending`, with `order_items` and `payment_method_token`; enqueues `Orders::FulfillmentJob`). Raises `Orders::ValidationError` (→ 422) for unknown products, empty items, or unsupported address; raises `Payments::InvalidCardError` (→ 422) for a bad card. `params` is the permitted `order` hash: `{ shipping_address: {...}, items: [{product_id, quantity}], payment: { card_number } }`.

- [ ] **Step 1: Write the failing spec**

`spec/services/orders/create_service_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Orders::CreateService do
  let(:customer) { create(:customer) }
  let(:product) { create(:product, price_cents: 1_000) }

  def params(overrides = {})
    {
      shipping_address: { line1: "1 Main", city: "New York", state: "NY", postal_code: "10001", country: "US" },
      items: [{ product_id: product.id, quantity: 2 }],
      payment: { card_number: "4111111111111111" }
    }.merge(overrides)
  end

  it "creates a pending order with snapshotted prices and a token" do
    order = nil
    expect {
      order = described_class.call(customer: customer, params: params)
    }.to change(Order, :count).by(1)

    expect(order).to be_pending
    expect(order.total_cents).to eq(2_000)
    expect(order.order_items.first.unit_price_cents).to eq(1_000)
    expect(order.payment_method_token).to start_with("pm_ok_")
  end

  it "enqueues the fulfillment job" do
    expect {
      described_class.call(customer: customer, params: params)
    }.to have_enqueued_job(Orders::FulfillmentJob)
  end

  it "rejects an unsupported (non-US) address" do
    bad = params(shipping_address: { line1: "1", city: "Toronto", state: "ON", postal_code: "M5V", country: "CA" })
    expect { described_class.call(customer: customer, params: bad) }
      .to raise_error(Orders::ValidationError)
  end

  it "rejects an unknown product" do
    bad = params(items: [{ product_id: -1, quantity: 1 }])
    expect { described_class.call(customer: customer, params: bad) }
      .to raise_error(Orders::ValidationError)
  end

  it "rejects an invalid card" do
    bad = params(payment: { card_number: "1234567812345678" })
    expect { described_class.call(customer: customer, params: bad) }
      .to raise_error(Payments::InvalidCardError)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/services/orders/create_service_spec.rb`
Expected: FAIL (uninitialized constant `Orders`).

- [ ] **Step 3: Write the error class and job stub**

`app/services/orders/errors.rb`:
```ruby
module Orders
  class ValidationError < StandardError; end
end
```

`app/jobs/orders/fulfillment_job.rb`:
```ruby
module Orders
  class FulfillmentJob < ApplicationJob
    queue_as :default

    def perform(order_id)
      # Real body added in Task 10.
    end
  end
end
```

- [ ] **Step 4: Write the create service**

`app/services/orders/create_service.rb`:
```ruby
module Orders
  # Synchronous order-creation path. Validates input, confirms the address is a
  # supported US address, snapshots prices, tokenizes the card (real billing
  # validation), persists a pending order, and enqueues asynchronous
  # fulfillment. Does NOT geocode-to-coordinates or charge — those happen in the
  # fulfillment job.
  class CreateService
    def self.call(customer:, params:)
      new(customer: customer, params: params).call
    end

    def initialize(customer:, params:)
      @customer = customer
      @params = params.to_h.with_indifferent_access
    end

    def call
      validate_address!
      line_items = build_line_items! # [{ product:, quantity:, unit_price_cents: }]
      token = Payments::TokenizeService.call(card_number)

      order = Order.create!(
        customer: @customer,
        status: :pending,
        ship_line1: address[:line1], ship_line2: address[:line2],
        ship_city: address[:city], ship_state: address[:state],
        ship_postal_code: address[:postal_code], ship_country: address[:country],
        total_cents: line_items.sum { |li| li[:unit_price_cents] * li[:quantity] },
        currency: "USD",
        payment_method_token: token
      )

      line_items.each do |li|
        order.order_items.create!(
          product: li[:product], quantity: li[:quantity], unit_price_cents: li[:unit_price_cents]
        )
      end

      Orders::FulfillmentJob.perform_later(order.id)
      order
    end

    private

    def address
      @address ||= (@params[:shipping_address] || {}).with_indifferent_access
    end

    def card_number
      (@params[:payment] || {}).with_indifferent_access[:card_number]
    end

    def validate_address!
      # Reuse the geocoder's US/state validation; full coordinates come later.
      Geocoding::GeocodeService.call(address)
    rescue Geocoding::UnsupportedAddressError => e
      raise ValidationError, e.message
    end

    def build_line_items!
      items = @params[:items]
      raise ValidationError, "items required" if items.blank?

      items.map do |item|
        product = Product.find_by(id: item[:product_id])
        raise ValidationError, "unknown product: #{item[:product_id]}" unless product

        quantity = item[:quantity].to_i
        raise ValidationError, "quantity must be positive" unless quantity.positive?

        { product: product, quantity: quantity, unit_price_cents: product.price_cents }
      end
    end
  end
end
```

- [ ] **Step 5: Run to verify pass**

Run: `bundle exec rspec spec/services/orders/create_service_spec.rb`
Expected: PASS (5 examples).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add synchronous order creation service"
```

---

### Task 10: Fulfillment service + job (asynchronous path)

**Files:**
- Create: `app/services/orders/fulfillment_service.rb`
- Modify: `app/jobs/orders/fulfillment_job.rb`
- Test: `spec/services/orders/fulfillment_service_spec.rb`

**Interfaces:**
- Consumes: `Order`, `Inventory`, `Geocoding::GeocodeService`, `WarehouseSelection::EligibleQuery`, `WarehouseSelection::SelectService`, `Payments::ChargeService`, `Payment`.
- Produces: `Orders::FulfillmentService.call(order) → Order`. Runs the two-transaction + compensation pipeline: geocode → eligible+select → Tx A atomic decrement (row-locked) + set warehouse → charge → Tx B settle (confirm, or restore stock + payment_failed). Idempotent on retry: skips Tx A if `warehouse_id` already set; skips charge if a `succeeded` payment exists. Terminal business failures (no eligible warehouse, geocode failure) → `unfulfillable` without raising. Transient errors propagate so Sidekiq retries.

- [ ] **Step 1: Write the failing spec (happy path, no-warehouse, decline+restore, retry idempotency)**

`spec/services/orders/fulfillment_service_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Orders::FulfillmentService do
  let(:product) { create(:product, price_cents: 1_000) }

  def build_order(card_token:, quantity: 2)
    order = create(:order, status: :pending, payment_method_token: card_token, total_cents: 1_000 * quantity,
                           ship_state: "NY", ship_country: "US", ship_postal_code: "10001", ship_city: "New York")
    create(:order_item, order: order, product: product, quantity: quantity, unit_price_cents: 1_000)
    order
  end

  it "confirms the order and decrements stock at the nearest eligible warehouse" do
    near = create(:warehouse, latitude: 40.71, longitude: -74.00)
    inv = create(:inventory, warehouse: near, product: product, quantity: 10)
    order = build_order(card_token: "pm_ok_x")

    described_class.call(order)

    expect(order.reload).to be_confirmed
    expect(order.warehouse).to eq(near)
    expect(inv.reload.quantity).to eq(8)
    expect(order.payments.where(status: :succeeded).count).to eq(1)
  end

  it "marks unfulfillable when no warehouse can fill the order" do
    create(:inventory, warehouse: create(:warehouse), product: product, quantity: 1)
    order = build_order(card_token: "pm_ok_x", quantity: 5)

    described_class.call(order)

    expect(order.reload).to be_unfulfillable
    expect(order.failure_reason).to be_present
  end

  it "restores stock and marks payment_failed on a declined charge" do
    near = create(:warehouse, latitude: 40.71, longitude: -74.00)
    inv = create(:inventory, warehouse: near, product: product, quantity: 10)
    order = build_order(card_token: "pm_decline_x")

    described_class.call(order)

    expect(order.reload).to be_payment_failed
    expect(inv.reload.quantity).to eq(10) # restored
    expect(order.payments.where(status: :failed).count).to eq(1)
  end

  it "does not double-charge or double-decrement when re-run after success" do
    near = create(:warehouse, latitude: 40.71, longitude: -74.00)
    inv = create(:inventory, warehouse: near, product: product, quantity: 10)
    order = build_order(card_token: "pm_ok_x")

    described_class.call(order)
    described_class.call(order.reload) # simulate Sidekiq retry

    expect(inv.reload.quantity).to eq(8)        # decremented once
    expect(order.payments.count).to eq(1)       # charged once
    expect(order.reload).to be_confirmed
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/services/orders/fulfillment_service_spec.rb`
Expected: FAIL (uninitialized constant `Orders::FulfillmentService`).

- [ ] **Step 3: Write the fulfillment service**

`app/services/orders/fulfillment_service.rb`:
```ruby
module Orders
  # Asynchronous fulfillment pipeline.
  #
  # The external charge MUST NOT happen inside an open DB transaction (holding
  # row locks across network I/O is a production hazard). So this runs as two
  # transactions with a compensating action:
  #   Tx A  - lock inventory rows, verify stock, atomic decrement, set warehouse
  #   charge - call the provider (no transaction)
  #   Tx B  - settle: confirm, OR restore stock + mark payment_failed
  #
  # Idempotent on Sidekiq retry: skips Tx A if a warehouse is already assigned,
  # and skips the charge if a succeeded payment already exists.
  class FulfillmentService
    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      return @order if @order.confirmed? || @order.unfulfillable?

      @order.start_processing! if @order.pending?

      reserve_stock! unless @order.warehouse_id.present?
      return @order if @order.unfulfillable? # reserve_stock! may have marked it

      settle_payment!
      @order
    end

    private

    def reserve_stock!
      coords = geocode
      return mark_unfulfillable("unsupported shipping address") if coords.nil?

      item_quantities = @order.order_items.pluck(:product_id, :quantity).to_h
      eligible = WarehouseSelection::EligibleQuery.call(item_quantities)
      warehouse = WarehouseSelection::SelectService.call(
        warehouses: eligible, lat: coords[:lat], lng: coords[:lng]
      )
      return mark_unfulfillable("no warehouse can fulfill this order") if warehouse.nil?

      Order.transaction do
        inventories = Inventory
          .where(warehouse_id: warehouse.id, product_id: item_quantities.keys)
          .lock("FOR UPDATE")
          .index_by(&:product_id)

        item_quantities.each do |product_id, quantity|
          inv = inventories[product_id]
          if inv.nil? || inv.quantity < quantity
            raise ActiveRecord::Rollback, :insufficient
          end
        end

        item_quantities.each do |product_id, quantity|
          inv = inventories[product_id]
          inv.update!(quantity: inv.quantity - quantity)
        end

        @order.update!(shipping_lat: coords[:lat], shipping_lng: coords[:lng], warehouse_id: warehouse.id)
      end

      # If the transaction rolled back, warehouse_id is still nil -> unfulfillable.
      mark_unfulfillable("warehouse stock changed before reservation") if @order.warehouse_id.blank?
    end

    def settle_payment!
      return if @order.payments.exists?(status: :succeeded)

      idempotency_key = "order-#{@order.id}-charge"
      begin
        provider_id = Payments::ChargeService.call(
          token: @order.payment_method_token,
          amount_cents: @order.total_cents,
          idempotency_key: idempotency_key,
          description: "Order #{@order.id}"
        )
        Order.transaction do
          @order.payments.create!(
            amount_cents: @order.total_cents, currency: @order.currency,
            status: :succeeded, provider_payment_id: provider_id, idempotency_key: idempotency_key
          )
          @order.mark_confirmed!(warehouse: @order.warehouse)
        end
      rescue Payments::PaymentDeclinedError => e
        Order.transaction do
          restore_stock!
          @order.payments.create!(
            amount_cents: @order.total_cents, currency: @order.currency,
            status: :failed, error_code: "declined", error_message: e.message,
            idempotency_key: idempotency_key
          )
          @order.mark_payment_failed!
        end
      end
    end

    def restore_stock!
      @order.order_items.each do |item|
        inv = Inventory.lock("FOR UPDATE").find_by(warehouse_id: @order.warehouse_id, product_id: item.product_id)
        inv&.update!(quantity: inv.quantity + item.quantity)
      end
    end

    def geocode
      Geocoding::GeocodeService.call(
        city: @order.ship_city, state: @order.ship_state,
        postal_code: @order.ship_postal_code, country: @order.ship_country
      )
    rescue Geocoding::UnsupportedAddressError
      nil
    end

    def mark_unfulfillable(reason)
      @order.mark_unfulfillable!(reason)
      @order
    end
  end
end
```

- [ ] **Step 4: Wire the job to the service**

`app/jobs/orders/fulfillment_job.rb`:
```ruby
module Orders
  class FulfillmentJob < ApplicationJob
    queue_as :default

    def perform(order_id)
      order = Order.find(order_id)
      Orders::FulfillmentService.call(order)
    end
  end
end
```

- [ ] **Step 5: Run to verify pass**

Run: `bundle exec rspec spec/services/orders/fulfillment_service_spec.rb`
Expected: PASS (4 examples).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add asynchronous fulfillment service and job"
```

---

### Task 11: Orders controller and routes (POST + GET)

**Files:**
- Create: `app/controllers/orders_controller.rb`
- Modify: `config/routes.rb`
- Create: `app/serializers/order_serializer.rb` (plain Ruby presenter)
- Modify: `app/controllers/application_controller.rb` (rescue handlers)
- Test: `spec/requests/orders_spec.rb`

**Interfaces:**
- Consumes: `Orders::CreateService`, `Orders::ValidationError`, `Payments::InvalidCardError`, `Order`, `current_customer` (Task 5).
- Produces: `POST /orders` (201/401/422) and `GET /orders/:id` (200/401/404), JSON bodies wrapped under `"order"`.

- [ ] **Step 1: Write the failing request spec**

`spec/requests/orders_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Orders", type: :request do
  let(:customer) { create(:customer) }
  let(:product) { create(:product, price_cents: 1_000) }
  let(:auth) { { "Authorization" => "Bearer #{customer.auth_token}" } }

  let(:valid_body) do
    {
      order: {
        shipping_address: { line1: "1 Main", city: "New York", state: "NY", postal_code: "10001", country: "US" },
        items: [{ product_id: product.id, quantity: 2 }],
        payment: { card_number: "4111111111111111" }
      }
    }
  end

  describe "POST /orders" do
    it "creates a pending order" do
      post "/orders", params: valid_body, headers: auth, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body.dig("order", "status")).to eq("pending")
      expect(body.dig("order", "total_cents")).to eq(2_000)
    end

    it "returns 401 without a valid token" do
      post "/orders", params: valid_body, headers: {}, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 422 for an invalid card" do
      body = valid_body.deep_dup
      body[:order][:payment][:card_number] = "1234567812345678"

      post "/orders", params: body, headers: auth, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 for a non-US address" do
      body = valid_body.deep_dup
      body[:order][:shipping_address] = { line1: "1", city: "Toronto", state: "ON", postal_code: "M5V", country: "CA" }

      post "/orders", params: body, headers: auth, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /orders/:id" do
    it "returns the caller's order" do
      order = create(:order, customer: customer)

      get "/orders/#{order.id}", headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("order", "id")).to eq(order.id)
    end

    it "returns 404 for another customer's order" do
      other = create(:order, customer: create(:customer))

      get "/orders/#{other.id}", headers: auth, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bundle exec rspec spec/requests/orders_spec.rb`
Expected: FAIL (routing error / no controller).

- [ ] **Step 3: Add routes**

`config/routes.rb` (inside `Rails.application.routes.draw do`):
```ruby
  resources :orders, only: [:create, :show]
```

- [ ] **Step 4: Write the serializer**

`app/serializers/order_serializer.rb`:
```ruby
class OrderSerializer
  def self.call(order)
    {
      order: {
        id: order.id,
        status: order.status,
        total_cents: order.total_cents,
        currency: order.currency,
        warehouse_id: order.warehouse_id,
        failure_reason: order.failure_reason,
        items: order.order_items.map do |item|
          { product_id: item.product_id, quantity: item.quantity, unit_price_cents: item.unit_price_cents }
        end,
        latest_payment_status: order.payments.order(:created_at).last&.status
      }
    }
  end
end
```

- [ ] **Step 5: Add rescue handlers to ApplicationController**

`app/controllers/application_controller.rb`:
```ruby
class ApplicationController < ActionController::API
  include Authenticable

  rescue_from Orders::ValidationError, with: :render_unprocessable
  rescue_from Payments::InvalidCardError, with: :render_unprocessable
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  def render_unprocessable(error)
    render json: { error: error.message }, status: :unprocessable_content
  end

  def render_not_found(_error)
    render json: { error: "not found" }, status: :not_found
  end
end
```

- [ ] **Step 6: Write the controller**

`app/controllers/orders_controller.rb`:
```ruby
class OrdersController < ApplicationController
  def create
    order = Orders::CreateService.call(customer: current_customer, params: order_params)
    render json: OrderSerializer.call(order), status: :created
  end

  def show
    order = current_customer.orders.find(params[:id])
    render json: OrderSerializer.call(order), status: :ok
  end

  private

  def order_params
    params.require(:order).permit(
      shipping_address: [:line1, :line2, :city, :state, :postal_code, :country],
      payment: [:card_number],
      items: [:product_id, :quantity]
    )
  end
end
```

- [ ] **Step 7: Run to verify pass**

Run: `bundle exec rspec spec/requests/orders_spec.rb`
Expected: PASS (6 examples).

- [ ] **Step 8: Run the full suite**

Run: `bundle exec rspec`
Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add orders controller with create and show endpoints"
```

---

### Task 12: README and end-to-end Docker verification

**Files:**
- Create: `README.md`
- Test: manual `docker compose up` smoke test

**Interfaces:**
- Consumes: the whole app.
- Produces: documentation for running and exercising the service; a verified end-to-end Docker run.

- [ ] **Step 1: Write the README**

Create `README.md` covering:
```markdown
# Canals Order Management API

## Run

    cp .env.example .env   # already committed with working defaults
    docker compose up

The web app boots on http://localhost:3000. On first boot the entrypoint
prepares and seeds the database. Sidekiq runs in the `worker` container.

## Seed credentials

Two customers are seeded with bearer tokens: `alice-token`, `bob-token`.

## Example

    # Create an order (async fulfillment kicks off in the background)
    curl -s localhost:3000/orders \
      -H "Authorization: Bearer alice-token" \
      -H "Content-Type: application/json" \
      -d '{"order":{"shipping_address":{"line1":"1 Main","city":"New York","state":"NY","postal_code":"10001","country":"US"},"items":[{"product_id":1,"quantity":2}],"payment":{"card_number":"4111111111111111"}}}'

    # Poll for the outcome
    curl -s localhost:3000/orders/1 -H "Authorization: Bearer alice-token"

Test cards: `4111111111111111` succeeds; `4000000000000002` is declined
(order ends `payment_failed`); a Luhn-invalid number is rejected at creation
with 422.

## Design

See `docs/superpowers/specs/2026-06-28-order-management-api-design.md`.

## Tests

    docker compose run --rm web bundle exec rspec

## Notable design decisions / tradeoffs

- Synchronous validation + tokenization; asynchronous warehouse selection and
  charge (Sidekiq).
- Warehouse selection uses straight-line (haversine) distance behind a swappable
  strategy. An optimal strategy would weigh transit time, shipping cost, SLA,
  capacity, and inventory balancing — see `WarehouseSelection::HaversineDistance`.
- Atomic, row-locked stock decrement; no overselling. Payment charged only after
  a fillable warehouse is reserved; stock restored if the charge fails.
- No Rails credentials/master key — all config via ENV (everything external is
  mocked, so there are no real secrets). Real secrets would live in a secrets
  manager in production.
- Money stored as integer cents.
```

- [ ] **Step 2: End-to-end Docker smoke test**

Run:
```bash
docker compose build
docker compose up -d
sleep 15
curl -s localhost:3000/orders \
  -H "Authorization: Bearer alice-token" \
  -H "Content-Type: application/json" \
  -d '{"order":{"shipping_address":{"line1":"1 Main","city":"New York","state":"NY","postal_code":"10001","country":"US"},"items":[{"product_id":1,"quantity":2}],"payment":{"card_number":"4111111111111111"}}}'
```
Expected: `201`-style JSON with `"status":"pending"`. Then:
```bash
sleep 3
curl -s localhost:3000/orders/1 -H "Authorization: Bearer alice-token"
docker compose down
```
Expected: order shows `"status":"confirmed"` and `latest_payment_status":"succeeded"`.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "docs: add README and verify end-to-end Docker run"
```

---

## Self-Review Notes

- **Spec coverage:** stack/config (Task 1), data model incl. payments + money-as-cents (Tasks 2–3), state machine (Task 3), seeds (Task 4), bearer auth (Task 5), deterministic geocoding + US check (Task 6), tokenize/charge mocks + idempotency (Task 7), eligibility + haversine strategy with optimality comment (Task 8), sync create path (Task 9), two-transaction async fulfillment + compensation + retry idempotency (Task 10), POST/GET contract + status codes (Task 11), Docker run + README tradeoffs (Task 12). All spec sections map to a task.
- **Type consistency:** service signatures used by callers match their definitions — `Geocoding::GeocodeService.call(address)`, `Payments::TokenizeService.call(card_number)`, `Payments::ChargeService.call(token:, amount_cents:, idempotency_key:, description:)`, `WarehouseSelection::EligibleQuery.call(item_quantities)`, `WarehouseSelection::SelectService.call(warehouses:, lat:, lng:)`, `Orders::CreateService.call(customer:, params:)`, `Orders::FulfillmentService.call(order)`. Order transition methods (`start_processing!`, `mark_confirmed!(warehouse:)`, `mark_unfulfillable!`, `mark_payment_failed!`) are consistent across Tasks 3 and 10.
- **Note on `unprocessable_content`:** Rails 8 renames the `:unprocessable_entity` symbol to `:unprocessable_content` (HTTP 422). Specs and handlers use `:unprocessable_content`; if running on an older Rails, substitute `:unprocessable_entity`.
