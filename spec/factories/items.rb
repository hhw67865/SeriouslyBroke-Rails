# frozen_string_literal: true

FactoryBot.define do
  factory :item do
    name { Faker::Commerce.product_name }
    description { Faker::Lorem.sentence }
    frequency { :one_time }
    association :category

    trait :expense do
      transient do
        user { create(:user) }
      end
      association :category, factory: [:category, :expense]
    end

    trait :income do
      transient do
        user { create(:user) }
      end
      association :category, factory: [:category, :income]
    end

    trait :savings do
      transient do
        user { create(:user) }
      end
      association :category, factory: [:category, :savings]
    end

    trait :one_time do
      frequency { :one_time }
    end

    trait :monthly do
      frequency { :monthly }
    end

    trait :yearly do
      frequency { :yearly }
    end
  end
end
