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

    # ** UNSPENT MONEY BUILDS UP (rules-own-the-budget spec §2.1, row 2): the emergency fund. ** The
    # §3.2 walk with no due date and NO CAP — `gap` is unbounded, so every period plans its plain
    # rate and the fund grows for as long as the rule lives.
    #
    # `:per_period` BASIS, so the rate is stated in the user's own periods and no example has to
    # divide a monthly figure by a cadence to say what a period accrues. A monthly building rule is
    # legal (row 5) and the two examples that want one say `basis: :monthly, interval_months: 1`
    # themselves rather than earning a trait apiece.
    #
    # ** IT REPLACES `:target`, WHICH PUT THE FIGURE ON THE CATEGORY. ** A goal is not a kind of
    # category any more; it is a building rule with a target (§7), and the trait that spelled the old
    # shape would now build a rule whose claim is computed by a different formula from the one its
    # name promises.
    trait :building do
      basis { :per_period }
      interval_months { nil }
      anchor_date { nil }
      carries_over { true }
    end

    # THE GOAL (§2.1 row 3): a building rule that names the figure it is building TOWARD, so the walk
    # caps there and the last contribution is the remainder rather than the rate.
    trait :capped do
      building
      target_amount { 1_200 }
    end

    # THE GOAL FED BY HAND (§2.1 row 4): a capped building rule with NO standing rate, which is the
    # one shape `Budget#set_aside_only?` exempts from `amount > 0`. It accrues only by positive
    # adjustments (§3.3's "set aside").
    trait :hand_fed do
      capped
      amount { 0 }
    end

    # THE THREE TYPES (§3). `usage` is the column's own default and has a trait all the same, so an
    # example that means "typed usage on purpose" reads differently from one that never said.
    trait :bill do
      rule_type { :bill }
    end

    trait :usage do
      rule_type { :usage }
    end

    trait :choice do
      rule_type { :choice }
    end
  end
end
