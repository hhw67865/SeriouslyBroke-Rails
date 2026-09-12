# frozen_string_literal: true

FactoryBot.define do
  factory :adjustment do
    source { association :rule }
    amount { 100 }
    date { Date.current }

    trait :release do
      amount { -100 }
    end

    trait :on_account do
      source { association :account, :savings }
      amount { -50 }
    end
  end
end
