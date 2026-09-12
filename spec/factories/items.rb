# frozen_string_literal: true

FactoryBot.define do
  factory :item do
    name { Faker::Commerce.product_name }
    description { Faker::Lorem.sentence }
    association :category

    trait :expense do
      transient do
        user { create(:user) }
      end
      category { association :category, :expense, user: user }
    end

    trait :income do
      transient do
        user { create(:user) }
      end
      category { association :category, :income, user: user }
    end

    trait :with_entries do
      transient do
        entries_count { rand(2..5) }
      end

      after(:create) do |item, evaluator|
        create_list(:entry, evaluator.entries_count, item: item)
      end
    end
  end
end
