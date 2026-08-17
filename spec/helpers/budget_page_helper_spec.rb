# frozen_string_literal: true

require "rails_helper"

RSpec.describe BudgetPageHelper, type: :helper do
  # Real Budget records rather than doubles: every branch below reads a combination of `basis`,
  # `interval_months` and `anchor_date` that Budget's own validations decide is legal, and a
  # double is free to claim a shape the model would refuse.
  def pool_rule(*traits, **attrs) = build(:pool_budget, *traits, category: nil, **attrs)

  describe "#budget_rule_name" do
    it "names the item it pays" do
      budget = pool_rule(item: build(:item, name: "Rent Bill"))

      expect(helper.budget_rule_name(budget)).to eq("Rent Bill")
    end

    it "falls back to the pool for an item-less pool rule" do
      budget = pool_rule(pool: build(:pool, :budget_pool, name: "Groceries"))

      expect(helper.budget_rule_name(budget)).to eq("Groceries")
    end

    it "falls back to the category for a category-mode rule" do
      budget = build(:budget, category: build(:category, :expense, name: "Shopping"))

      expect(helper.budget_rule_name(budget)).to eq("Shopping")
    end
  end

  # THE FIGURE AND WHAT IT IS A FIGURE PER. $600 a period and $600 every six months are the same
  # digits and a twelvefold difference in what the user owes.
  describe "#budget_rule_amount" do
    it "says a rate rule's period" do
      expect(helper.budget_rule_amount(pool_rule(:per_period_rate, amount: 400))).to eq("$400.00 / period")
    end

    it "says a recurring rule's interval" do
      budget = pool_rule(amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))

      expect(helper.budget_rule_amount(budget)).to eq("$600.00 every 6 months")
    end

    it "says a monthly rule is monthly" do
      expect(helper.budget_rule_amount(pool_rule(:rate, amount: 120))).to eq("$120.00 a month")
    end

    it "says a one-off rule happens once" do
      expect(helper.budget_rule_amount(pool_rule(:one_time, amount: 300))).to eq("$300.00 once")
    end

    # A category-mode rule is a monthly spending cap and carries no interval at all —
    # Budget#shape_must_be_valid only runs in pool mode — so the interval branches would call
    # every one of them a one-off.
    it "calls a category-mode rule monthly rather than one-off" do
      budget = build(:budget, category: build(:category, :expense), amount: 200)

      expect(helper.budget_rule_amount(budget)).to eq("$200.00 a month")
    end
  end

  # ALL SEVEN STATES, IN BOTH DIRECTIONS. Three were asserted in neither, and :overdue and
  # :wont_make_it are the dangerous pair: their labels print a DATE and no money figure at all,
  # so if either fell out of the balance side the pool's balance would vanish from the page and
  # every example here would stay green.
  describe "#budget_group_balance" do
    # A REAL PoolStatus with only its state and balance stubbed, never an `instance_double`
    # answering `amount_is_balance?` itself: the helper is a lookup on that method now, and a
    # double told what to answer would assert nothing about which states print their own money.
    # This way the mapping under test is PoolStatus's real one.
    def group(state, balance: 250)
      status = PoolStatus.new(build(:pool))
      allow(status).to receive_messages(state: state, balance: balance)
      BudgetPagePresenter::Group.new(
        pool: build(:pool),
        rules: [],
        status: status,
        changed_after_distributing: false
      )
    end

    # :overdue and :wont_make_it print `overdue · was Aug 6` and `won't make it · Aug 19` — no
    # figure whatsoever — so the clause is the only thing putting the balance on screen for them.
    it "states the balance where the label named a bill instead", :aggregate_failures do
      expect(helper.budget_group_balance(group(:behind))).to eq("· holds $250.00")
      expect(helper.budget_group_balance(group(:overdue))).to eq("· holds $250.00")
      expect(helper.budget_group_balance(group(:wont_make_it))).to eq("· holds $250.00")
    end

    # `pool_status_label` prints PoolStatus#amount, which IS the balance here — printed again
    # the row read "$250.00 left · holds $250.00". :overdrawn is included because its label
    # prints the balance NEGATED, which read "overdrawn $80.00 · holds -$80.00".
    it "stays silent where the label has already said it", :aggregate_failures do
      expect(helper.budget_group_balance(group(:left_to_spend))).to eq("")
      expect(helper.budget_group_balance(group(:on_track))).to eq("")
      expect(helper.budget_group_balance(group(:overdrawn))).to eq("")
      expect(helper.budget_group_balance(group(:saving))).to eq("")
    end
  end

  describe "#budget_rule_reason" do
    def rule(reason) = BudgetPagePresenter::Rule.new(budget: build(:budget), due_on: nil, reason: reason)

    # Home's own row phrasing, verbatim — the same fact about the same pool, said once.
    it "gives an account-less pool Home's own wording" do
      expect(helper.budget_rule_reason(rule(:no_account))).to eq("no account — nothing can fund it")
    end

    it "says a category rule caps rather than fills" do
      expect(helper.budget_rule_reason(rule(:category))).to eq("caps a category — no envelope to fill")
    end
  end
end
