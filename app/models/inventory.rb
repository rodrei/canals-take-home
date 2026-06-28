# == Schema Information
#
# Table name: inventories
#
#  id           :bigint           not null, primary key
#  quantity     :integer          default(0), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  product_id   :bigint           not null
#  warehouse_id :bigint           not null
#
# Indexes
#
#  index_inventories_on_product_id                   (product_id)
#  index_inventories_on_warehouse_id                 (warehouse_id)
#  index_inventories_on_warehouse_id_and_product_id  (warehouse_id,product_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (product_id => products.id)
#  fk_rails_...  (warehouse_id => warehouses.id)
#
class Inventory < ApplicationRecord
  belongs_to :warehouse
  belongs_to :product

  validates :quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :product_id, uniqueness: { scope: :warehouse_id }
end
