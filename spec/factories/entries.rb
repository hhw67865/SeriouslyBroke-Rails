# frozen_string_literal: true

FactoryBot.define do
  factory :entry do
    amount { Faker::Number.decimal(l_digits: 2, r_digits: 2) }
    date { Date.current }
    description { Faker::Lorem.sentence }
    association :item

    trait :january_2024 do
      date { Date.new(2024, 1, 15) }
    end

    trait :june_2024 do
      date { Date.new(2024, 6, 15) }
    end

    trait :december_2023 do
      date { Date.new(2023, 12, 15) }
    end

    trait :june_2023 do
      date { Date.new(2023, 6, 15) }
    end

    trait :last_month do
      date { 1.month.ago }
    end

    trait :last_year do
      date { 1.year.ago }
    end

    trait :this_month do
      date { Date.current }
    end

    trait :this_year do
      date { Date.current.beginning_of_year + 1.month }
    end

    trait :next_month do
      date { 1.month.from_now }
    end
  end
end
