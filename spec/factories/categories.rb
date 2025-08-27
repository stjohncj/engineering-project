FactoryBot.define do
  factory :category do
    sequence(:name) { |n| "#{Faker::Commerce.department} #{n}" }
    description { Faker::Lorem.sentence }

    trait :groceries do
      name { "Groceries" }
      description { "Food and household items" }
    end

    trait :utilities do
      name { "Utilities" }
      description { "Electric, gas, water, and other utilities" }
    end

    trait :transportation do
      name { "Transportation" }
      description { "Gas, public transport, and vehicle expenses" }
    end
  end
end
