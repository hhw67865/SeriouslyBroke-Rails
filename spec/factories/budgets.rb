# frozen_string_literal: true

FactoryBot.define do
  # A RULE BELONGS TO THE CATEGORY THAT HOLDS THE MONEY (two-ledger spec §3), and after Task 8 that
  # is the only shape there is — `budgets.category_id` is NOT NULL and `budgets.pool_id` is gone.
  #
  # `:funded` on the category, because a rule is one of the two things that make a category a
  # holder: a rule on a category with no `funded_since` demands money into an envelope whose own
  # spending drains available instead.
  #
  # `:category_rule` IS KEPT because the fixtures that spell it out mean exactly what it says — it
  # was `pool { nil }` while a rule could still be owned by a pool — and it restates the default
  # owner rather than standing as an empty block.
  factory :budget do
    amount { Faker::Number.decimal(l_digits: 3, r_digits: 2) }
    category { association :category, :expense, :funded }
    basis { :monthly }
    interval_months { 1 }
    anchor_date { nil }

    trait :category_rule do
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

    # A TARGET RULE (computed-claims spec §3.2/§3.3): the target lives on the CATEGORY —
    # `categories.target_amount` — and the rule is what accrues toward it, because every claim comes
    # from a rule and every adjustment targets one. The anchor is deliberately left OPTIONAL and
    # unset here: an anchored target rule accrues by the catch-up formula toward its due date, and an
    # anchorless one accrues at its own rate toward the category's figure until it gets there. Two
    # shapes, one trait, and each example that wants the dated one adds `anchor_date:` itself.
    #
    # `:per_period` BASIS, so the rate is stated in the user's own periods and no example has to
    # divide a monthly figure by a cadence to say what a period accrues. `target_amount` is a
    # transient so an example can plant the figure the formula is about in one line.
    trait :target do
      transient do
        target_amount { 1_200 }
      end

      basis { :per_period }
      interval_months { nil }
      anchor_date { nil }
      category { association :category, :expense, :funded, target_amount: target_amount }
    end
  end
end
