FactoryBot.define do
  factory :order do
    customer
    status { :pending }
    ship_line1 { "123 Main St" }
    ship_city { "New York" }
    ship_state { "NY" }
    ship_postal_code { "10001" }
    ship_country { "US" }
    total_cents { 2_000 }
    currency { "USD" }
    payment_method_token { "pm_ok_test" }
  end
end
