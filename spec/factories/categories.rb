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
    #
    # `user.default_account || association(...)` (main-account spec §6, `Category#pool_must_be_
    # reachable`): a category may point only at the user's MAIN account, singular — minting a fresh
    # account on every implicit-pool category would give a user with two such categories two
    # different accounts, and the validator refuses the second. Reusing the user's existing default
    # account when there is one keeps every implicit-pool category on the SAME account; minting one
    # only happens for that user's first, and the `:account` trait's own `after(:create)` is what
    # makes that first one the default.
    pool { user.default_account || association(:pool, :account, user: user) }

    trait :income do
      category_type { :income }
      name { Faker::Job.field + Faker::Number.number(digits: 2).to_s }
    end

    trait :expense do
      category_type { :expense }
      name { Faker::Commerce.department + Faker::Number.number(digits: 2).to_s }
    end

    # THE DATE THE CATEGORY STARTED HOLDING MONEY (two-ledger spec §4), and the whole of what
    # makes a category a holder: `Category#holder?` is `expense? && funded_since.present?`, and
    # `CategoryLedger::ENTRY_CATEGORY_ID` drains this category only for spending dated on or after
    # it. A year back, so an entry dated "today" or "last month" in any fixture counts against the
    # category without the fixture having to say a date twice.
    trait :funded do
      funded_since { 1.year.ago.to_date }
    end

    # A SAVINGS CATEGORY IS A FUNDED CATEGORY WITH A TARGET AND NO RULE (spec §3) — there is no
    # savings TYPE any more and this trait sets none. `:funded` is included rather than assumed
    # because a target on a category that holds nothing is a goal nothing can progress toward.
    trait :savings do
      funded
      target_amount { 500 }
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
