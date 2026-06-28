# == Schema Information
#
# Table name: products
#
#  id          :bigint           not null, primary key
#  currency    :string
#  name        :string
#  price_cents :integer
#  sku         :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_products_on_sku  (sku) UNIQUE
#
class Product < ApplicationRecord
  validates :name, presence: true
  validates :sku, presence: true, uniqueness: true
  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
end
