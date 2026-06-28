class CreateCustomers < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.string :name
      t.string :email
      t.string :auth_token

      t.timestamps
    end

    add_index :customers, :auth_token, unique: true
  end
end
