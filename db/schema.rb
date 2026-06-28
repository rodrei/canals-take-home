# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_28_170115) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "customers", force: :cascade do |t|
    t.string "auth_token"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["auth_token"], name: "index_customers_on_auth_token", unique: true
  end

  create_table "inventories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.integer "quantity", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "warehouse_id", null: false
    t.index ["product_id"], name: "index_inventories_on_product_id"
    t.index ["warehouse_id", "product_id"], name: "index_inventories_on_warehouse_id_and_product_id", unique: true
    t.index ["warehouse_id"], name: "index_inventories_on_warehouse_id"
  end

  create_table "order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "order_id", null: false
    t.bigint "product_id", null: false
    t.integer "quantity"
    t.integer "unit_price_cents"
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
  end

  create_table "orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency"
    t.bigint "customer_id", null: false
    t.string "failure_reason"
    t.string "payment_method_token"
    t.string "ship_city"
    t.string "ship_country"
    t.string "ship_line1"
    t.string "ship_line2"
    t.string "ship_postal_code"
    t.string "ship_state"
    t.decimal "shipping_lat", precision: 10, scale: 6
    t.decimal "shipping_lng", precision: 10, scale: 6
    t.integer "status", default: 0, null: false
    t.integer "total_cents"
    t.datetime "updated_at", null: false
    t.bigint "warehouse_id"
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["warehouse_id"], name: "index_orders_on_warehouse_id"
  end

  create_table "payments", force: :cascade do |t|
    t.integer "amount_cents"
    t.datetime "created_at", null: false
    t.string "currency"
    t.string "error_code"
    t.string "error_message"
    t.string "idempotency_key"
    t.bigint "order_id", null: false
    t.string "provider_payment_id"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_payments_on_idempotency_key", unique: true
    t.index ["order_id"], name: "index_payments_on_order_id"
  end

  create_table "products", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency"
    t.string "name"
    t.integer "price_cents"
    t.string "sku"
    t.datetime "updated_at", null: false
    t.index ["sku"], name: "index_products_on_sku", unique: true
  end

  create_table "warehouses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.string "name"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "inventories", "products"
  add_foreign_key "inventories", "warehouses"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "products"
  add_foreign_key "orders", "customers"
  add_foreign_key "orders", "warehouses"
  add_foreign_key "payments", "orders"
end
