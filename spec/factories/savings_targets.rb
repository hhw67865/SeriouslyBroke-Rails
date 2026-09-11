# frozen_string_literal: true

FactoryBot.define do
  # A fixed $200 a period since the start of the year, on a fresh savings account. The :share
  # trait swaps that for 10% of a fresh income item of the same user.
  factory :savings_target do
    account { association :account, :savings }
    amount { 200 }
    percent { nil }
    item { nil }
    starts_on { Date.new(2026, 1, 1) }

    trait :share do
      amount { nil }
      percent { 10 }
      item { association :item, :income, user: account.user }
    end
  end
end
