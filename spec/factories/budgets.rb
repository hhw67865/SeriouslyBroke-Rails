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

    # ** AN ALLOWANCE THAT KEEPS WHAT IT DOESN'T SPEND (two-shapes spec §12) — `$X a period, keeps`.
    # ** It is `:per_period_rate` plus one column, and that is the whole of the shape: no anchor (a
    # dated rule never keeps — `Budget#keeps_unspent_never_dates`), no interval, and no target. The
    # three fund traits §7 deleted wrote `carries_over` and a `target_amount` beside it; this one
    # writes neither, because what came back is the keeping and not the ceiling.
    trait :keeps_unspent do
      basis { :per_period }
      interval_months { nil }
      anchor_date { nil }
      keeps_unspent { true }
    end

    # a savings goal or one-off bill — never rolls
    trait :one_time do
      basis { :monthly }
      interval_months { nil }
      anchor_date { Date.new(2026, 8, 1) }
    end

    # ** A GOAL, WHICH IS A ONE-OFF DATED RULE (two-shapes spec §2 row 5). ** `:one_time` is the same
    # three columns and this is the same shape said in the user's words — "$X by a date" — with a
    # date far enough out that a walk over it spans many periods. Both are kept because an example
    # about a BILL and an example about a GOAL want different names for one shape, which is exactly
    # what §2 says they are.
    #
    # ** IT REPLACES THE THREE FUND TRAITS (§7). ** They wrote the retired carry-over column and the
    # target beside it, and the hand-fed one wrote an amount of zero — a shape `Budget` refuses
    # outright now. A trait for a shape the model rejects is a fixture that cannot be constructed,
    # which is what `claim_calculator_spec` asserts rather than leaves implied.
    # ** THE DATE IS RELATIVE, AND THE REASON IS CLAUDE.md's THIRD FLAKE CAUSE (fix round 1 —
    # LOW-9). ** It was `Date.new(2027, 6, 1)`, a fixed day: every fortnight the suite is not run,
    # that day is one period closer, and `ClaimCalculator#standing_ask` — `target ÷ periods to fund`
    # — moves with it. A trait every accruing example in the suite reaches for must not carry a
    # figure that drifts on the wall clock.
    #
    # NINE MONTHS, WHICH IS FAR ENOUGH TO READ AS A GOAL and near enough that the walk over it is
    # cheap. `due:` is a transient so an example that needs a particular horizon says so rather than
    # overriding the column and losing the reason.
    transient { due { Date.current + 9.months } }

    trait :by_date do
      basis { :monthly }
      interval_months { nil }
      anchor_date { due }
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
