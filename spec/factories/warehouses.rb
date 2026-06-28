FactoryBot.define do
  factory :warehouse do
    name { Faker::Company.name }
    latitude { 40.7128 }
    longitude { -74.0060 }
  end
end
