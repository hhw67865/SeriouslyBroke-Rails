# frozen_string_literal: true

FactoryBot.define do
  factory :pool do
    name { "#{Faker::Commerce.product_name} #{Faker::Number.number(digits: 3)}" }
    target_amount { Faker::Number.decimal(l_digits: 3, r_digits: 2) } # e.g., 1000.00
    start_date { 1.year.ago.to_date }
    pool_type { :savings }
    association :user

    trait :account do
      pool_type { :account }
      name { "#{Faker::Bank.name} #{Faker::Number.number(digits: 3)}" }
      target_amount { nil }
      account { nil }
    end

    trait :budget_pool do
      pool_type { :budget }
      target_amount { nil }
      account { association :pool, :account, user: user }
    end

    trait :savings_pool do
      pool_type { :savings }
      account { association :pool, :account, user: user }
    end
  end
end
