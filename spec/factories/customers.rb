FactoryBot.define do
  factory :customer do
    name { Faker::Name.name }
    email { Faker::Internet.unique.email }
    sequence(:auth_token) { |n| "token_#{n}_#{SecureRandom.hex(8)}" }
  end
end
