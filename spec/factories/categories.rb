# frozen_string_literal: true

FactoryBot.define do
  factory :category do
    name { Faker::Commerce.department }
    color { Faker::Color.hex_color }
    category_type { :expense }
    association :user

    trait :income do
      category_type { :income }
      name { Faker::Job.field }
    end

    trait :expense do
      category_type { :expense }
      name { Faker::Commerce.department }
    end

    trait :savings do
      category_type { :savings }
      name { "Savings for #{Faker::Commerce.product_name}" }
      association :savings_pool
    end
  end
end
