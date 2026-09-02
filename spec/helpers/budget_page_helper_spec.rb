# frozen_string_literal: true

require "rails_helper"

RSpec.describe BudgetPageHelper, type: :helper do
  # Real Budget records rather than doubles: every branch below reads a combination of `basis`,
  # `interval_months` and `anchor_date` that Budget's own validations decide is legal, and a
  # double is free to claim a shape the model would refuse.
  def rule(*traits, **attrs) = build(:budget, *traits, pool: nil, **attrs)

  describe "#budget_rule_name" do
    it "names the item it pays" do
      budget = rule(category: build(:category, :expense, :funded), item: build(:item, name: "Rent Bill"))

      expect(helper.budget_rule_name(budget)).to eq("Rent Bill")
    end

    it "falls back to the category for an item-less rule" do
      budget = rule(category: build(:category, :expense, :funded, name: "Groceries"))

      expect(helper.budget_rule_name(budget)).to eq("Groceries")
    end

    # THE POOL ARM IS TRANSITIONAL AND IS PINNED AS SUCH (Task 8 deletes it with
    # `budgets.pool_id`). `Budget.for_user` spans both owner lanes, so the sacrifice view lists
    # rules written before the cutover, and a row that could not say its own name would print a
    # blank label beside a real figure. This example is deleted with the column, not before.
    it "falls back to the pool for a rule written before the cutover" do
      budget = build(:pool_budget, pool: build(:pool, :budget_pool, name: "Legacy"))

      expect(helper.budget_rule_name(budget)).to eq("Legacy")
    end
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

  # ALL SEVEN STATES, IN BOTH DIRECTIONS. Three were asserted in neither, and :overdue and
  # :wont_make_it are the dangerous pair: their labels print a DATE and no money figure at all,
  # so if either fell out of the balance side the pool's balance would vanish from the page and
  # every example here would stay green.
  describe "#pool_balance_clause" do
    # A REAL PoolStatus with only its state and balance stubbed, never an `instance_double`
    # answering `amount_is_balance?` itself: the helper is a lookup on that method now, and a
    # double told what to answer would assert nothing about which states print their own money.
    # This way the mapping under test is PoolStatus's real one.
    #
    # A BARE STATUS, which is what the helper now takes — the Categories page's budget block
    # (spec §8.1) renders the same clause off a pool it holds no Group for, and wrapping one here
    # would test a shape only one of the two callers has.
    def status_for(state, balance: 250)
      PoolStatus.new(build(:pool)).tap do |status|
        allow(status).to receive_messages(state: state, balance: balance)
      end
    end

    # :overdue and :wont_make_it print `overdue · was Aug 6` and `won't make it · Aug 19` — no
    # figure whatsoever — so the clause is the only thing putting the balance on screen for them.
    it "states the balance where the label named a bill instead", :aggregate_failures do
      expect(helper.pool_balance_clause(status_for(:behind))).to eq("· holds $250.00")
      expect(helper.pool_balance_clause(status_for(:overdue))).to eq("· holds $250.00")
      expect(helper.pool_balance_clause(status_for(:wont_make_it))).to eq("· holds $250.00")
    end

    # `pool_status_label` prints PoolStatus#amount, which IS the balance here — printed again
    # the row read "$250.00 left · holds $250.00". :overdrawn is included because its label
    # prints the balance NEGATED, which read "overdrawn $80.00 · holds -$80.00".
    it "stays silent where the label has already said it", :aggregate_failures do
      expect(helper.pool_balance_clause(status_for(:left_to_spend))).to eq("")
      expect(helper.pool_balance_clause(status_for(:on_track))).to eq("")
      expect(helper.pool_balance_clause(status_for(:overdrawn))).to eq("")
      expect(helper.pool_balance_clause(status_for(:saving))).to eq("")
    end
  end

  # `#budget_rule_reason` AND ITS ONE SURVIVING EXAMPLE ARE DELETED (two-ledger spec §5, Task 5).
  # It gave an account-less pool Home's own wording, which was the last reason a rule could be
  # outside the fill order; a rule belongs to a category and every category is in the waterfall, so
  # `BudgetPagePresenter::Rule` no longer carries a `reason` for the helper to word.
end
