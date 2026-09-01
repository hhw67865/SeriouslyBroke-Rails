# frozen_string_literal: true

FactoryBot.define do
  # THE DEFAULT IS STILL POOL-OWNED, AND ONLY BECAUSE THE POOL LAYER IS STILL STANDING. A rule
  # belongs to the category that holds the money now (two-ledger spec §3) — that is the
  # `:category_rule` trait below, and after Task 8 it is the only shape there is. Changing the
  # DEFAULT would rewrite the fixture of every pool spec on the branch at once, which is the one
  # thing the transition cannot afford: `Budget#for_user` reads both lanes precisely so both keep
  # working while the fixtures move over a task at a time.
  #
  # `:pool_budget` is kept as an alias for the hundreds of call sites that name it.
  factory :budget do
    amount { Faker::Number.decimal(l_digits: 3, r_digits: 2) }
    pool { association :pool, :budget_pool }
    basis { :monthly }
    interval_months { 1 }
    anchor_date { nil }

    factory :pool_budget

    # A RULE ON THE THING THAT HOLDS THE MONEY (two-ledger spec §3) — the shape every rule takes
    # after Task 8, and a variant rather than the default for one transitional reason: the pool
    # form still writes pool-owned rules and hundreds of fixtures still name one. `pool { nil }`
    # is the whole difference; `#must_have_an_owner` accepts either owner and no rule carries both
    # by hand (Task 1's migration is the only writer that ever wrote both onto a row).
    #
    # `:funded` on the category, because a rule is one of the two things that make a category a
    # holder: a rule on a category with no `funded_since` demands money into an envelope whose own
    # spending drains available instead.
    trait :category_rule do
      pool { nil }
      category { association :category, :expense, :funded }
    end

    # $300 every pay period, no due date — the catch-all
    trait :per_period_rate do
      basis { :per_period }
      interval_months { nil }
      anchor_date { nil }
    end

    # $600 a month, no due date
    trait :rate do
      basis { :monthly }
      interval_months { 1 }
      anchor_date { nil }
    end

    # $800 every 6 months, next due Jun 1
    trait :recurring do
      basis { :monthly }
      interval_months { 6 }
      anchor_date { Date.new(2026, 6, 1) }
    end

    # a savings goal or one-off bill — never rolls
    trait :one_time do
      basis { :monthly }
      interval_months { nil }
      anchor_date { Date.new(2026, 8, 1) }
    end
  end
end
