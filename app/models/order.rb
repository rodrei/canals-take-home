# == Schema Information
#
# Table name: orders
#
#  id                   :bigint           not null, primary key
#  currency             :string
#  failure_reason       :string
#  payment_method_token :string
#  ship_city            :string
#  ship_country         :string
#  ship_line1           :string
#  ship_line2           :string
#  ship_postal_code     :string
#  ship_state           :string
#  shipping_lat         :decimal(10, 6)
#  shipping_lng         :decimal(10, 6)
#  status               :integer          default("pending"), not null
#  total_cents          :integer
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  customer_id          :bigint           not null
#  warehouse_id         :bigint
#
# Indexes
#
#  index_orders_on_customer_id   (customer_id)
#  index_orders_on_warehouse_id  (warehouse_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (warehouse_id => warehouses.id)
#
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
  validates :ship_city, :ship_country, :ship_line1, :ship_postal_code, :ship_state, presence: true

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
