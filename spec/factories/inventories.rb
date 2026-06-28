FactoryBot.define do
  factory :inventory do
    warehouse
    product
    quantity { 100 }
  end
end
