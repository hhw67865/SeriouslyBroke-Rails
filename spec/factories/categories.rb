# frozen_string_literal: true

FactoryBot.define do
  factory :category do
    name { Faker::Commerce.department + Faker::Number.number(digits: 2).to_s }
    color { Faker::Color.hex_color }
    category_type { :expense }
    association :user

    trait :income do
      category_type { :income }
      name { Faker::Job.field + Faker::Number.number(digits: 2).to_s }
    end

    trait :expense do
      category_type { :expense }
      name { Faker::Commerce.department + Faker::Number.number(digits: 2).to_s }
    end

    trait :savings do
      category_type { :savings }
      name { "Savings for #{Faker::Commerce.product_name} + Faker::Number.number(digits: 2).to_s" }
      association :savings_pool
    end

    trait :with_items_and_entries do
      transient do
        items_count { rand(2..4) }
      end

      after(:create) do |category, evaluator|
        create_list(:item, evaluator.items_count, :with_entries, category: category)
      end
    end
  end
end
