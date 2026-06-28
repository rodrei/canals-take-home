class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :customer, null: false, foreign_key: true
      t.references :warehouse, null: true, foreign_key: true
      t.integer :status, null: false, default: 0
      t.string :ship_line1
      t.string :ship_line2
      t.string :ship_city
      t.string :ship_state
      t.string :ship_postal_code
      t.string :ship_country
      t.decimal :shipping_lat, precision: 10, scale: 6
      t.decimal :shipping_lng, precision: 10, scale: 6
      t.integer :total_cents
      t.string :currency
      t.string :payment_method_token
      t.string :failure_reason

      t.timestamps
    end
  end
end
