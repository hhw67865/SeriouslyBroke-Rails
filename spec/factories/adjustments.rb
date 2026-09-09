# frozen_string_literal: true

FactoryBot.define do
  factory :adjustment do
    rule { association :rule }
    amount { 100 }
    date { Date.current }

    trait :release do
      amount { -100 }
    end
  end
end
