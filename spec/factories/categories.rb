# frozen_string_literal: true

FactoryBot.define do
  factory :category do
    name { Faker::Commerce.department + Faker::Number.number(digits: 2).to_s }
    color { Faker::Color.hex_color }
    category_type { :expense }
    association :user

    # `pool` IS GONE WITH `categories.pool_id` (two-ledger spec §5, Task 8). A category does not
    # name a lane any more — it holds its own money from `funded_since` on, and spending before
    # that drains available.

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
