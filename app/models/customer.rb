# == Schema Information
#
# Table name: customers
#
#  id         :bigint           not null, primary key
#  auth_token :string
#  email      :string
#  name       :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_customers_on_auth_token  (auth_token) UNIQUE
#
class Customer < ApplicationRecord
  has_many :orders, dependent: :destroy

  validates :name, presence: true
  validates :auth_token, presence: true, uniqueness: true
end
