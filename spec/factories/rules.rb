FactoryBot.define do
  factory :rule do
    sequence(:name) { |n| "Rule #{n}" }
    condition_field { "description" }
    condition_operator { "contains" }
    condition_value { "grocery" }
    action_type { "categorize" }
    action_value { "Groceries" }
    active { true }

    trait :inactive do
      active { false }
    end

    trait :grocery_rule do
      name { "Grocery Store Rule" }
      condition_field { "description" }
      condition_operator { "contains" }
      condition_value { "grocery" }
      action_type { "categorize" }
      action_value { "Groceries" }
    end

    trait :gas_station_rule do
      name { "Gas Station Rule" }
      condition_field { "description" }
      condition_operator { "contains" }
      condition_value { "gas station" }
      action_type { "categorize" }
      action_value { "Transportation" }
    end

    trait :amount_based_rule do
      name { "Large Purchase Rule" }
      condition_field { "amount" }
      condition_operator { "greater_than" }
      condition_value { "1000" }
      action_type { "flag" }
      action_value { "Large transaction" }
    end

    trait :categorization_rule do
      action_type { "categorize" }
    end

    trait :flagging_rule do
      action_type { "flag" }
    end
  end
end
