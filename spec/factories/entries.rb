# frozen_string_literal: true

FactoryBot.define do
  factory :entry do
    amount { Faker::Number.decimal(l_digits: 2, r_digits: 2) }
    date { Date.current }
    description { Faker::Lorem.sentence }
    association :item

    trait :expense do
      transient do
        user { create(:user) }
      end
      item { association :item, :expense, user: user }
    end

    trait :income do
      transient do
        user { create(:user) }
      end
      item { association :item, :income, user: user }
    end

    trait :last_month do
      date { Date.current - 1.month }
    end

    trait :this_month do
      date { Date.current }
    end
  end
end
