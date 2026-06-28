FactoryBot.define do
  factory :payment do
    order
    amount_cents { 2_000 }
    currency { "USD" }
    status { :pending }
    sequence(:idempotency_key) { |n| "idem_#{n}" }
  end
end
