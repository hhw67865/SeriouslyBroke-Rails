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

    # ** `:savings` IS GONE WITH `categories.target_amount` (rules-own-the-budget spec §7). ** It was
    # `funded` plus a figure, on the era's reading that a goal is a KIND OF CATEGORY. A goal is a
    # building rule that names a target now (§2.1 rows 3-4), so the trait's second half has no column
    # to write and its first half is `:funded` verbatim — a trait that is a synonym for another one
    # is a second name for one shape, which is how two fixtures come to mean different things by the
    # same word. Its call sites read `:funded` and reach for `create(:budget, :capped, …)` where the
    # goal itself is the subject.

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
