# frozen_string_literal: true

FactoryBot.define do
  factory :budget do
    amount { Faker::Number.decimal(l_digits: 3, r_digits: 2) }
    period { :month }
    association :category, factory: [:category, :expense]

    trait :monthly do
      period { :month }
    end

    trait :yearly do
      period { :year }
    end
  end
end
