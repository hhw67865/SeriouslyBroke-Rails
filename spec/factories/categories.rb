# frozen_string_literal: true

FactoryBot.define do
  factory :category do
    sequence(:name) { |n| "#{Faker::Commerce.department} #{n}" }
    color { Faker::Color.hex_color }
    category_type { :expense }
    association :user

    trait :income do
      category_type { :income }
      sequence(:name) { |n| "#{Faker::Job.field} #{n}" }
    end

    trait :expense do
      category_type { :expense }
    end

    trait :irregular do
      regular { false }
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
