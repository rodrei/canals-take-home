class Inventory < ApplicationRecord
  belongs_to :warehouse
  belongs_to :product

  validates :quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :product_id, uniqueness: { scope: :warehouse_id }
end
