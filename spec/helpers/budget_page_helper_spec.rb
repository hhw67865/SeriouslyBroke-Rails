# frozen_string_literal: true

require "rails_helper"

RSpec.describe BudgetPageHelper, type: :helper do
  # Real Budget records rather than doubles: every branch below reads a combination of `basis`,
  # `interval_months` and `anchor_date` that Budget's own validations decide is legal, and a
  # double is free to claim a shape the model would refuse.
  def rule(*traits, **attrs) = build(:budget, *traits, **attrs)

  describe "#budget_rule_name" do
    it "names the item it pays" do
      budget = rule(category: build(:category, :expense, :funded), item: build(:item, name: "Rent Bill"))

      expect(helper.budget_rule_name(budget)).to eq("Rent Bill")
    end

    it "falls back to the category for an item-less rule" do
      budget = rule(category: build(:category, :expense, :funded, name: "Groceries"))

      expect(helper.budget_rule_name(budget)).to eq("Groceries")
    end

    # THE POOL ARM AND ITS EXAMPLE ARE DELETED WITH `budgets.pool_id` (two-ledger spec §5,
    # Task 8). It read "falls back to the pool for a rule written before the cutover"; there is one
    # owner lane now and the category arm above is it.
  end

  # THE FIGURE AND WHAT IT IS A FIGURE PER. $600 a period and $600 every six months are the same
  # digits and a twelvefold difference in what the user owes.
  describe "#budget_rule_amount" do
    it "says a rate rule's period" do
      expect(helper.budget_rule_amount(rule(:per_period_rate, category: build(:category, :expense, :funded), amount: 400))).to eq("$400.00 / period")
    end

    it "says a recurring rule's interval" do
      budget = rule(category: build(:category, :expense, :funded), amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))

      expect(helper.budget_rule_amount(budget)).to eq("$600.00 every 6 months")
    end

    it "says a monthly rule is monthly" do
      expect(helper.budget_rule_amount(rule(:rate, category: build(:category, :expense, :funded), amount: 120))).to eq("$120.00 a month")
    end

    it "says a one-off rule happens once" do
      expect(helper.budget_rule_amount(rule(:one_time, category: build(:category, :expense, :funded), amount: 300))).to eq("$300.00 once")
    end
  end

  # ** `#pool_balance_clause` AND ITS TWO EXAMPLES ARE DELETED (computed-claims spec §6). ** They
  # asserted, over all seven `HoldingStatus` states, that a group said its BALANCE exactly once:
  # the clause `· holds $250.00` printed for the three states whose label named a bill's shortfall
  # instead, and stayed silent for the four whose label was the balance already. Every one of those
  # states is a reading of money MOVED into a category, and nothing moves on the purpose side any
  # more (§5) — `HoldingStatus` is deleted, and so is the helper that read it.
  #
  # WHAT REPLACED THE SENTENCE, and where it is pinned: §3.4's row prints ONE figure per rule,
  # named — `spent of rate` for an envelope, `built up of target` for a fund — so there is no
  # second clause to fill in a figure the first one left out. `HomeHelper#claim_figure` is that
  # reader and `spec/helpers/home_helper_spec.rb` pins it; the row is pinned on the page in
  # `spec/system/budget_page/rules_spec.rb`.

  # `#budget_rule_reason` AND ITS ONE SURVIVING EXAMPLE ARE DELETED (two-ledger spec §5, Task 5).
  # It gave an account-less pool Home's own wording, which was the last reason a rule could be
  # outside the fill order; a rule belongs to a category and every category is in the waterfall, so
  # `BudgetPagePresenter::Rule` no longer carries a `reason` for the helper to word.
end
