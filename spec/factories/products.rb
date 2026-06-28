FactoryBot.define do
  factory :product do
    name { Faker::Commerce.product_name }
    sequence(:sku) { |n| "SKU-#{n}" }
    price_cents { 1_000 }
    currency { "USD" }
  end
end
