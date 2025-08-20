FactoryBot.define do
  factory :rule do
    sequence(:name) { |n| "Rule #{n}" }
    description { Faker::Lorem.sentence }
    conditions { { "description_contains" => "grocery" } }
    actions { { "set_category" => "Groceries" } }
    active { true }
    
    association :category
    
    trait :inactive do
      active { false }
    end
    
    trait :grocery_rule do
      name { "Grocery Store Rule" }
      description { "Automatically categorize grocery store purchases" }
      conditions { { "description_contains" => ["grocery", "supermarket", "food"] } }
      actions { { "set_category" => "Groceries" } }
    end
    
    trait :gas_station_rule do
      name { "Gas Station Rule" }
      description { "Automatically categorize gas station purchases" }
      conditions { { "description_contains" => ["gas station", "shell", "exxon"] } }
      actions { { "set_category" => "Transportation" } }
    end
    
    trait :amount_based_rule do
      name { "Large Purchase Rule" }
      description { "Flag large purchases for review" }
      conditions { { "amount_greater_than" => 1000.0 } }
      actions { { "set_status" => "flagged" } }
    end
  end
end