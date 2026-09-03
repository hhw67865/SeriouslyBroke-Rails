# frozen_string_literal: true

# A DATED, SIGNED DELTA ON ONE RULE'S ACCRUAL (computed-claims spec §3.3) — the purpose side's only
# writer besides the rules themselves.
#
# `accrued(P) = planned(P) + Σ adjustments dated inside P`. It is a DELTA and never an override:
# skipping a period is an adjustment of −planned dated today, reducing one is a smaller negative,
# topping up is a positive, and setting money aside in a goal is a positive on the goal's rule. One
# row, one verb, both signs.
#
# NOTHING PHYSICAL MOVES. There is no association from here to `account_movements` or to `pools`, and
# there must never be one: the physical invariant `pot + Σ accounts == income − expenses` is blind to
# this table, which is what makes an adjustment free to be written, edited and deleted without ever
# putting the two ledgers out of step.
class Adjustment < ApplicationRecord
  # `class_name: "Budget"` is the one place the table's name and the app's word for a row in it meet
  # — see the migration's header. `touch: true` matches `Budget belongs_to :category`: writing an
  # adjustment changes what the rule claims, and every claim reader is a snapshot.
  belongs_to :rule, class_name: "Budget", touch: true

  # ZERO IS THE ONE AMOUNT THAT SAYS NOTHING, and it is refused in Ruby as well as at the database:
  # `adjustments_non_zero_amount` catches a row written past this model, and this catches the form.
  # BOTH SIGNS ARE LEGAL — `numericality` with no bound at all beside `other_than` is deliberate, not
  # an omission, and it is the only money column in this app that reads that way (§3.3).
  validates :amount, presence: true, numericality: { other_than: 0 }
  validates :date, presence: true

  # THE PERIODS A WALK VISITS, as one bound. The claim formulas ask for every adjustment from the
  # accrual start onward and never for a single row, so this is the shape every reader wants;
  # `ClaimLedger` uses the same scope over a whole user's rules at once.
  scope :dated_within, ->(range) { where(date: range) }

  # WHOSE ADJUSTMENT — through the rule, because this table carries no user column and inventing one
  # would give ownership two places to be wrong. `Budget#user` walks the category, and it is nil-safe
  # for an unsaved rule, so this is too.
  def user = rule&.user

  # THE CALENDAR DAY THIS ADJUSTMENT FALLS ON, IN THE OWNER'S ZONE (§3.3: it lands in the period
  # CONTAINING its date). `date` is a datetime, so a Tokyo user's Sep 12 top-up is stored
  # `2026-09-11 15:00` UTC and `.to_date` under an ambient UTC zone would file it in the period
  # before. `User#local_day` is the one re-zoning in the app — the same one
  # `CategoryLedger::ENTRY_LOCAL_DAY` performs in SQL for an entry.
  def local_day = user ? user.local_day(date) : date.to_date
end
