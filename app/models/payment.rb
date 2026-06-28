# == Schema Information
#
# Table name: payments
#
#  id                  :bigint           not null, primary key
#  amount_cents        :integer
#  currency            :string
#  error_code          :string
#  error_message       :string
#  idempotency_key     :string
#  status              :integer          default("pending"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  order_id            :bigint           not null
#  provider_payment_id :string
#
# Indexes
#
#  index_payments_on_idempotency_key  (idempotency_key) UNIQUE
#  index_payments_on_order_id         (order_id)
#
# Foreign Keys
#
#  fk_rails_...  (order_id => orders.id)
#
class Payment < ApplicationRecord
  belongs_to :order

  enum :status, { pending: 0, succeeded: 1, failed: 2 }

  validates :idempotency_key, presence: true, uniqueness: true
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
end
