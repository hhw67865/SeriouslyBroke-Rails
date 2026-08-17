# frozen_string_literal: true

FactoryBot.define do
  factory :category do
    name { Faker::Commerce.department + Faker::Number.number(digits: 2).to_s }
    color { Faker::Color.hex_color }
    category_type { :expense }
    association :user

    # EVERY CATEGORY NAMES ITS LANE (plan 3 decision 3), so the factory has to give one. An ACCOUNT
    # of the category's OWN user is the default for three reasons: it is what the cutover migration
    # filled every nil `pool_id` with, it is what `CategoriesController#new` prefills the form with,
    # and it is the only pool type an INCOME category may point at
    # (Category#income_must_land_in_an_account) — so one default serves every type.
    #
    # `user: user` rather than a bare `association :pool, :account`: that would mint a pool owned by
    # a DIFFERENT user, and a category whose pool belongs to someone else is a fixture no screen can
    # render honestly.
    pool { association :pool, :account, user: user }

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
      pool { association :pool, :savings_pool, user: user }
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
