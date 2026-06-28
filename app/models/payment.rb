class Payment < ApplicationRecord
  belongs_to :order

  enum :status, { pending: 0, succeeded: 1, failed: 2 }

  validates :idempotency_key, presence: true, uniqueness: true
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
end
