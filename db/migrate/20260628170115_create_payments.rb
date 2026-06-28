class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :order, null: false, foreign_key: true
      t.integer :amount_cents
      t.string :currency
      t.integer :status, null: false, default: 0
      t.string :provider_payment_id
      t.string :error_code
      t.string :error_message
      t.string :idempotency_key

      t.timestamps
    end

    add_index :payments, :idempotency_key, unique: true
  end
end
