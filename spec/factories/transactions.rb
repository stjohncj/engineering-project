FactoryBot.define do
  factory :transaction do
    description { Faker::Commerce.product_name }
    amount { Faker::Number.decimal(l_digits: 3, r_digits: 2) }
    transaction_date { Faker::Date.between(from: 30.days.ago, to: Date.current) }
    status { "pending" }

    # Optional association - transaction can exist without category
    category { nil }

    trait :with_category do
      association :category
    end

    trait :positive_amount do
      amount { Faker::Number.positive(from: 1.0, to: 1000.0).round(2) }
    end

    trait :negative_amount do
      amount { -Faker::Number.positive(from: 1.0, to: 1000.0).round(2) }
    end

    trait :approved do
      status { "approved" }
    end

    trait :flagged do
      status { "flagged" }
    end

    trait :rejected do
      status { "rejected" }
    end


    trait :large_amount do
      amount { Faker::Number.between(from: 10000.0, to: 50000.0).round(2) }
    end
  end
end
