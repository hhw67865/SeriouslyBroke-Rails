# frozen_string_literal: true

FactoryBot.define do
  factory :budget do
    amount { Faker::Number.decimal(l_digits: 3, r_digits: 2) }
    association :category, factory: [:category, :expense]

    trait :prorated do
      prorated { true }
    end
  end
end
