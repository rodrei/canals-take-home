FactoryBot.define do
  factory :order_item do
    order
    product
    quantity { 1 }
    unit_price_cents { 1_000 }
  end
end
