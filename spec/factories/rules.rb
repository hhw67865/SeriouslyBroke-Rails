# frozen_string_literal: true

FactoryBot.define do
  # The default is a $300 per-period usage allowance that started a year ago, on a fresh expense
  # category. Traits pick the shape.
  factory :rule do
    amount { 300 }
    category { association :category, :expense }
    starts_on { Date.current - 1.year }
    rule_type { :usage }

    transient { due { Date.current + 9.months } }

    trait :rate do
      anchor_date { nil }
      interval_months { nil }
      keeps_unspent { false }
    end

    trait :keeps_unspent do
      anchor_date { nil }
      interval_months { nil }
      keeps_unspent { true }
    end

    trait :capped do
      keeps_unspent { true }
      anchor_date { nil }
      cap { 1_000 }
    end

    trait :one_off do
      anchor_date { Date.current + 20 }
      interval_months { nil }
    end

    trait :by_date do
      anchor_date { due }
      interval_months { nil }
    end

    trait :rolling do
      anchor_date { Date.current + 20 }
      interval_months { 6 }
    end

    trait :bill do
      rule_type { :bill }
    end

    trait :usage do
      rule_type { :usage }
    end

    trait :choice do
      rule_type { :choice }
    end
  end
end
