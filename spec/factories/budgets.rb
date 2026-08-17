# frozen_string_literal: true

FactoryBot.define do
  # A RULE IS OWNED BY A POOL, FULL STOP (plan 3, task 3). This factory used to default to a
  # category — the monthly cap — with a `:pool_budget` sub-factory for the funding rule; the cap is
  # deleted, so the default IS the funding rule and `:pool_budget` is kept as an alias so the
  # hundreds of call sites that name it do not all have to be rewritten to say the same thing.
  factory :budget do
    amount { Faker::Number.decimal(l_digits: 3, r_digits: 2) }
    pool { association :pool, :budget_pool }
    basis { :monthly }
    interval_months { 1 }
    anchor_date { nil }

    factory :pool_budget

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
