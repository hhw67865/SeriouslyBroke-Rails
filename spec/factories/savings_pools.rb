# frozen_string_literal: true

FactoryBot.define do
  factory :savings_pool do
    name { Faker::Commerce.product_name }
    target_amount { Faker::Number.decimal(l_digits: 3, r_digits: 2) } # e.g., 1000.00
    start_date { 1.year.ago.to_date }
    association :user
  end
end
