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
