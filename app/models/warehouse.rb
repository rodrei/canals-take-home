# == Schema Information
#
# Table name: warehouses
#
#  id         :bigint           not null, primary key
#  latitude   :decimal(10, 6)
#  longitude  :decimal(10, 6)
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class Warehouse < ApplicationRecord
  has_many :inventories, dependent: :destroy
  has_many :products, through: :inventories

  validates :name, presence: true
  validates :latitude, :longitude, presence: true
end
