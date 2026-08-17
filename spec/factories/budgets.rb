# frozen_string_literal: true

FactoryBot.define do
  factory :budget do
    amount { Faker::Number.decimal(l_digits: 3, r_digits: 2) }
    association :category, factory: [:category, :expense]

    trait :prorated do
      prorated { true }
    end

    factory :pool_budget do
      category { nil }
      association :pool, factory: [:pool, :budget_pool]
      basis { :monthly }
      interval_months { 1 }
      anchor_date { nil }
    end

    # $300 every pay period, no due date — the catch-all
    trait :per_period_rate do
      basis { :per_period }
      interval_months { nil }
      anchor_date { nil }
    end

    # $600 a month, no due date
    trait :rate do
      basis { :monthly }
      interval_months { 1 }
      anchor_date { nil }
    end

    # $800 every 6 months, next due Jun 1
    trait :recurring do
      basis { :monthly }
      interval_months { 6 }
      anchor_date { Date.new(2026, 6, 1) }
    end

    # a savings goal or one-off bill — never rolls
    trait :one_time do
      basis { :monthly }
      interval_months { nil }
      anchor_date { Date.new(2026, 8, 1) }
    end
  end
end
