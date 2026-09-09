# frozen_string_literal: true

# ONE DATED, SIGNED DELTA ON A RULE'S ACCRUAL (computed-claims spec §3.3).
#
# "On Sep 12, −$158 from the car fund"; "on Sep 20, +$100 into groceries"; "+$500 into Vacation".
# Skip a period, reduce it, top it up, raid it, set money aside, take it back — every one of those
# is this row with a different sign, and there is no second table and no second verb. It REPLACES
# the purpose side's `allocations` transfers, which Task 4 converts and drops.
#
# IT TARGETS A RULE AND NOT A CATEGORY, and that is §3.3's own sentence: "every claim comes from a
# rule and every adjustment targets a rule". A category's money is the sum of its rules' claims, so
# an adjustment aimed at the category would have no arm to land on — a savings goal is a rule with a
# target, and the migration that lands the old transfers mints one where a goal has none.
#
# `rule_id` RATHER THAN `budget_id`, and the mismatch with the table name is deliberate: the app's
# whole vocabulary for a `budgets` row is "rule" (`Budget.for_user`, `#rules_need`, the Budget page's
# rule rows), and this column is read in the claim formulas where the word is always "rule". The
# foreign key still names `budgets` because that is the table; `Adjustment belongs_to :rule,
# class_name: "Budget"` is the one place the two spellings meet.
#
# `date` IS A DATETIME, matching `entries.date` and `allocations.date` — the two columns an
# adjustment sits beside in the same period arithmetic. §3.3's whole point is that an adjustment
# lands in the period CONTAINING its date, on whatever cadence grid exists, so the column has to
# carry an instant the owner's timezone can be applied to exactly as `CategoryLedger`'s day boundary
# applies it to an entry. A bare `date` would fix the day in UTC and put a Tokyo user's evening
# top-up in yesterday's period.
#
# `amount <> 0` AT THE DATABASE, and no sign constraint of any kind. A zero adjustment is a row that
# says nothing — the thing deleting it is for — while both signs are the whole point: `+$100` tops a
# period up and `−$158` releases money the fund had already built. Every other money column in this
# schema carries `amount > 0` and states its direction in a second column; this one states it in the
# sign, because §3.3's arithmetic is a SUM of signed deltas (`accrued(P) = planned(P) + Σ
# adjustments dated inside P`) and a direction column would make that sum a case statement.
#
# NO FK TO `entries`, NO PATH TO `account_movements`. An adjustment is an act of intention and moves
# nothing physical (§5): the physical invariant `pot + Σ accounts == income − expenses` cannot see
# this table at all.
class CreateAdjustments < ActiveRecord::Migration[8.1]
  def change
    create_table :adjustments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :rule, type: :uuid, null: false, foreign_key: { to_table: :budgets }
      t.datetime :date, null: false
      t.money :amount, scale: 2, null: false
      t.timestamps
    end

    # The date index is `allocations`' and `account_movements`': every reader of this table asks for
    # a window (the periods a walk visits), never for a single row.
    add_index :adjustments, :date

    add_check_constraint :adjustments, "amount <> 0::money", name: "adjustments_non_zero_amount"
  end
end
