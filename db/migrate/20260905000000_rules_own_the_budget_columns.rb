# frozen_string_literal: true

# THE THREE COLUMNS A RULE NEEDS TO SAY WHAT IT IS (rules-own-the-budget spec §2).
#
# SCHEMA ONLY. The data move — copying `categories.target_amount` onto the rule that accrues toward
# it, minting a rule for a goal that has none, typing every existing rule, and dropping the
# category's column — is §6 and lives in its OWN migration, which runs after this one. Two files
# rather than one because they are two different kinds of statement: this one is reversible by
# definition (a column added is a column dropped), while the data half's `down` has to copy a figure
# back the other way and can only be written once the column it copies FROM exists.
#
# `carries_over` — WHAT HAPPENS TO MONEY THE PERIOD DID NOT SPEND. False is today's behaviour and
# therefore the default: a rate rule resets at every boundary (§3.1, use-it-or-lose-it). True is the
# emergency fund — the §3.2 walk with no due date — and it is the column `ClaimCalculator#shape`
# reads to tell the two apart. NOT NULL with a default so every row that exists before this runs is
# a rate rule, which is exactly what it was.
#
# `target_amount` — A CAP ON WHAT BUILDS UP, moved off `categories`. NULL is the honest absence
# rather than a sentinel: a building rule with no target is the "grows without limit" shape (§2.1
# row 2), and `ClaimCalculator#capped?` is that `present?` asked once. The CHECK is
# `categories_target_amount`'s own rule re-stated on the new owner — a goal of zero is already met
# and a negative one is money owed to the user by their own budget.
#
# `rule_type` — bill (0) | usage (1) | choice (2), §3. DEFAULT 1 = `usage`, and the default is a
# ruling rather than a convenience: it is the widest of the three ("a real need whose amount moves
# with how you live"), so a rule typed by nobody claims neither that it must be paid nor that it is
# discretionary. The give-way order reads it and the Budget page shows the label, so the default is
# visible to the user who has to correct it. NOT NULL because §3's overview and the give-way walk
# both partition on it, and a fourth, nameless bucket would be a rule nothing can order.
#
# NO INDEX ON ANY OF THE THREE. Every reader of these columns already has the row in hand — the
# claim formulas read them off a loaded rule, and the Budget page's grouping is a Ruby sort over the
# rules it has already fetched for `ClaimLedger`. An index here would be paid for on every write and
# read by nothing.
class RulesOwnTheBudgetColumns < ActiveRecord::Migration[8.1]
  def up
    add_column :budgets, :carries_over, :boolean, null: false, default: false
    add_column :budgets, :target_amount, :money, scale: 2
    add_column :budgets, :rule_type, :integer, null: false, default: 1

    add_check_constraint :budgets, "target_amount > 0::money", name: "budgets_positive_target_amount"
  end

  # THE CHECK GOES FIRST, and on Postgres dropping the column would take it anyway — stating it is
  # what keeps the `down` a readable inverse of the `up` rather than a fact about the engine.
  def down
    remove_check_constraint :budgets, name: "budgets_positive_target_amount"
    remove_column :budgets, :rule_type
    remove_column :budgets, :target_amount
    remove_column :budgets, :carries_over
  end
end
