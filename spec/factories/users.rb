# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    name { Faker::Name.name }
    email { Faker::Internet.unique.email }
    password { "password123" }
    password_confirmation { "password123" }

    trait :biweekly do
      period_cadence { :biweekly }
      period_anchor_date { Date.new(2026, 2, 6) }
    end

    trait :monthly do
      period_cadence { :monthly }
      period_anchor_date { Date.new(2026, 1, 15) }
    end
  end
end
