FactoryBot.define do
  factory :anomaly_detection do
    anomaly_type { "unusual_amount" }
    description { "Transaction amount significantly deviates from historical average" }
    severity { 3 }
    resolved { false }
    metadata { { "expected_range" => "10-100", "actual_amount" => "500" } }
    detected_at { Time.current }

    association :transaction, factory: :transaction

    trait :resolved do
      resolved { true }
      resolved_at { Time.current }
    end

    trait :high_severity do
      severity { 5 }
      description { "Critical anomaly requiring immediate attention" }
    end

    trait :low_severity do
      severity { 1 }
      description { "Minor anomaly for review" }
    end

    trait :potential_duplicate do
      anomaly_type { "potential_duplicate" }
      description { "Transaction appears to be a duplicate of an existing entry" }
      metadata { { "similar_transaction_id" => "123", "similarity_score" => "0.95" } }
    end

    trait :incomplete_data do
      anomaly_type { "incomplete_data" }
      description { "Transaction is missing required metadata" }
      metadata { { "missing_fields" => [ "merchant", "location" ] } }
    end

    trait :unusual_timing do
      anomaly_type { "unusual_timing" }
      description { "Transaction occurred at an unusual time" }
      metadata { { "transaction_time" => "3:00 AM", "typical_range" => "9:00 AM - 6:00 PM" } }
    end
  end
end
