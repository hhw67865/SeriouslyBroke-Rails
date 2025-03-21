# frozen_string_literal: true

FactoryBot.define do
  factory :item do
    name { Faker::Commerce.product_name }
    description { Faker::Lorem.sentence }
    frequency { :one_time }
    association :category

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
