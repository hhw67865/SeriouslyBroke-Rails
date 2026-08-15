# frozen_string_literal: true

require "rails_helper"

RSpec.describe BudgetCalculator, type: :model do
  let(:user) { create(:user, pay_cadence: :biweekly, pay_anchor_date: Date.new(2026, 2, 6)) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:car) { create(:pool, :budget_pool, user: user, account: checking, name: "Car") }
  let(:category) { create(:category, :expense, user: user, name: "Car Spending", pool: car) }
  let(:today) { Date.new(2026, 2, 6) }

  # Spec §4.4's recurring bill: $800 every 6 months, next due Jun 1. Pass an item
  # to give it a fulfillment signal; without one it is assumed paid on time.
  def insurance_rule(item: nil, interval: 6, anchor: Date.new(2026, 6, 1))
    create(
      :pool_budget,
      :recurring,
      pool: car,
      amount: 800,
      interval_months: interval,
      anchor_date: anchor,
      item: item
    )
  end

  # A dated obligation with no fulfillment signal — the §4.4 `required` fixtures.
  def dated_rule(amount:, interval:, anchor:)
    create(:pool_budget, pool: car, amount: amount, interval_months: interval, anchor_date: anchor)
  end

  # A dated one-off — a bill or a savings goal that never repeats.
  def one_time_rule(item: nil, amount: 500, anchor: Date.new(2026, 2, 1))
    create(:pool_budget, :one_time, pool: car, amount: amount, anchor_date: anchor, item: item)
  end

  # A user who never told us when they get paid, so User#pay_dates returns [].
  def cadence_less_rule(*traits, **attrs)
    other = create(:user)
    pool = create(:pool, :budget_pool, user: other, name: "Car")
    create(:pool_budget, *traits, pool: pool, **attrs)
  end

  describe "#target" do
    it "is the rule's amount" do
      budget = create(:pool_budget, :rate, pool: car, amount: 80)

      expect(budget.calculator(today: today).target).to eq(80)
    end

    it "is an exact decimal even when the amount was assigned as an integer" do
      budget = create(:pool_budget, :rate, pool: car, amount: 80)

      expect(budget.calculator(today: today).target).to be_a(BigDecimal)
    end
  end

  describe "#period_end" do
    it "is the end of the calendar month for a monthly rule" do
      budget = create(:pool_budget, :rate, pool: car, amount: 80)

      expect(budget.calculator(today: today).period_end).to eq(Date.new(2026, 2, 28))
    end

    it "is the day before the next paycheck for a per-paycheck rule" do
      budget = create(:pool_budget, :per_paycheck_rate, pool: car, amount: 300)

      expect(budget.calculator(today: today).period_end).to eq(Date.new(2026, 2, 19))
    end

    it "falls back to the end of the month when no pay cadence is configured" do
      budget = cadence_less_rule(:per_paycheck_rate, amount: 300)

      expect(budget.calculator(today: today).period_end).to eq(Date.new(2026, 2, 28))
    end
  end

  describe "#elapsed_cycles" do
    it "is zero before the anchor has arrived" do
      budget = insurance_rule

      expect(budget.calculator(today: Date.new(2026, 5, 31)).elapsed_cycles).to eq(0)
    end

    it "is one on the anchor date itself, because that occurrence has come due" do
      budget = insurance_rule

      expect(budget.calculator(today: Date.new(2026, 6, 1)).elapsed_cycles).to eq(1)
    end

    it "does not advance until the day of the month is reached" do
      budget = insurance_rule(anchor: Date.new(2026, 6, 15))

      expect(budget.calculator(today: Date.new(2026, 12, 1)).elapsed_cycles).to eq(1)
    end

    it "advances once the day of the month is reached" do
      budget = insurance_rule(anchor: Date.new(2026, 6, 15))

      expect(budget.calculator(today: Date.new(2026, 12, 20)).elapsed_cycles).to eq(2)
    end

    it "counts every occurrence that has come due across several intervals" do
      budget = insurance_rule

      expect(budget.calculator(today: Date.new(2027, 6, 1)).elapsed_cycles).to eq(3)
    end

    # These two shapes have no cycle to elapse. They are unreachable through
    # #due_date, which guards on the same nils first, but the method is public
    # so it must answer rather than raise on a perfectly valid record.
    it "is zero for a rate rule, which has no anchor to count from" do
      budget = create(:pool_budget, :rate, pool: car, amount: 80)

      expect(budget.calculator(today: today).elapsed_cycles).to eq(0)
    end

    it "is zero for a one-time rule, which has no interval to divide by" do
      budget = create(:pool_budget, :one_time, pool: car, amount: 500, anchor_date: Date.new(2026, 2, 1))

      expect(budget.calculator(today: Date.new(2026, 6, 3)).elapsed_cycles).to eq(0)
    end
  end

  describe "#cycles_completed" do
    let(:item) { create(:item, category: category, name: "Insurance") }
    let(:budget) { insurance_rule(item: item) }

    it "ignores entries recorded before the anchor" do
      create(:entry, item: item, amount: 800, date: Date.new(2026, 5, 30))

      expect(budget.calculator(today: Date.new(2026, 7, 1)).cycles_completed).to eq(0)
    end

    it "is zero for an anchorless rate rule even when it has an item" do
      gas = create(:item, category: category, name: "Gas")
      budget = create(:pool_budget, :rate, pool: car, amount: 80, item: gas)
      create(:entry, item: gas, amount: 10, date: Date.new(2026, 2, 3))

      expect(budget.calculator(today: today).cycles_completed).to eq(0)
    end

    it "is zero for an anchorless rate rule with no item" do
      budget = create(:pool_budget, :rate, pool: car, amount: 80)

      expect(budget.calculator(today: today).cycles_completed).to eq(0)
    end

    it "counts entries recorded on or after the anchor" do
      create(:entry, item: item, amount: 800, date: Date.new(2026, 6, 1))
      create(:entry, item: item, amount: 800, date: Date.new(2026, 12, 5))

      expect(budget.calculator(today: Date.new(2027, 1, 1)).cycles_completed).to eq(2)
    end
  end

  describe "#due_date" do
    it "is the end of the calendar month for a monthly rate rule" do
      budget = create(:pool_budget, :rate, pool: car, amount: 80)

      expect(budget.calculator(today: today).due_date).to eq(Date.new(2026, 2, 28))
    end

    it "is the day before the next paycheck for a per-paycheck rate rule" do
      budget = create(:pool_budget, :per_paycheck_rate, pool: car, amount: 300)

      expect(budget.calculator(today: today).due_date).to eq(Date.new(2026, 2, 19))
    end

    it "is the anchor itself for a one-time rule" do
      budget = create(:pool_budget, :one_time, pool: car, amount: 500, anchor_date: Date.new(2026, 8, 1))

      expect(budget.calculator(today: today).due_date).to eq(Date.new(2026, 8, 1))
    end

    it "is the anchor itself for a recurring rule that has not come due yet" do
      budget = insurance_rule

      expect(budget.calculator(today: Date.new(2026, 5, 31)).due_date).to eq(Date.new(2026, 6, 1))
    end

    it "rolls on the anchor date itself when the rule has no item" do
      budget = insurance_rule

      expect(budget.calculator(today: Date.new(2026, 6, 1)).due_date).to eq(Date.new(2026, 12, 1))
    end

    it "rolls by elapsed intervals when the rule has no item" do
      budget = insurance_rule

      expect(budget.calculator(today: Date.new(2026, 7, 1)).due_date).to eq(Date.new(2026, 12, 1))
    end

    it "does NOT roll on the date alone when the rule has an item" do
      item = create(:item, category: category, name: "Insurance")
      budget = insurance_rule(item: item)

      expect(budget.calculator(today: Date.new(2026, 7, 1)).due_date).to eq(Date.new(2026, 6, 1))
    end

    it "rolls once the bill is actually recorded on the item" do
      item = create(:item, category: category, name: "Insurance")
      budget = insurance_rule(item: item)
      create(:entry, item: item, amount: 800, date: Date.new(2026, 6, 2))

      expect(budget.calculator(today: Date.new(2026, 7, 1)).due_date).to eq(Date.new(2026, 12, 1))
    end
  end

  describe "#overdue?" do
    let(:item) { create(:item, category: category, name: "Insurance") }
    let(:budget) { insurance_rule(item: item) }

    it "is true when the due date has passed with no entry" do
      expect(budget.calculator(today: Date.new(2026, 6, 3))).to be_overdue
    end

    it "is false on the due date itself" do
      expect(budget.calculator(today: Date.new(2026, 6, 1))).not_to be_overdue
    end

    it "is false once the entry is recorded" do
      create(:entry, item: item, amount: 800, date: Date.new(2026, 6, 2))

      expect(budget.calculator(today: Date.new(2026, 6, 3))).not_to be_overdue
    end

    it "is never true for a rule with no item" do
      expect(insurance_rule.calculator(today: Date.new(2026, 12, 3))).not_to be_overdue
    end

    # A recurring rule rolls its own due date forward, so it can never look late
    # without an item. A one-time rule cannot roll — its anchor is fixed forever —
    # so this is the only shape where the `item.present?` guard does real work.
    # No item means no fulfillment signal, which the design reads as "assume paid".
    it "is not true for a one-time rule with no item whose date has long passed" do
      budget = create(:pool_budget, :one_time, pool: car, amount: 500, anchor_date: Date.new(2026, 2, 1))

      expect(budget.calculator(today: Date.new(2026, 6, 3))).not_to be_overdue
    end

    it "is true for a one-time rule with an item whose date has passed" do
      registration = create(:item, category: category, name: "Registration")

      expect(one_time_rule(item: registration).calculator(today: Date.new(2026, 6, 3))).to be_overdue
    end

    # A one-time rule never rolls its due date, so without a fulfillment axis it
    # would read as late forever — even years after the bill was actually settled.
    it "stops being true for a one-time rule once its bill is recorded" do
      registration = create(:item, category: category, name: "Registration")
      budget = one_time_rule(item: registration)
      create(:entry, item: registration, amount: 500, date: Date.new(2026, 2, 1))

      expect(budget.calculator(today: Date.new(2026, 6, 3))).not_to be_overdue
    end
  end

  # A one-time rule has no next occurrence to roll into, so "done" cannot be read
  # off the schedule the way it is for a recurring rule. It needs its own axis.
  describe "#fulfilled?" do
    let(:registration) { create(:item, category: category, name: "Registration") }

    it "is false for a one-time rule with an item and no entry against it" do
      expect(one_time_rule(item: registration).calculator(today: Date.new(2026, 6, 3))).not_to be_fulfilled
    end

    it "is true for a one-time rule once an entry lands on its item" do
      budget = one_time_rule(item: registration)
      create(:entry, item: registration, amount: 500, date: Date.new(2026, 2, 1))

      expect(budget.calculator(today: Date.new(2026, 6, 3))).to be_fulfilled
    end

    it "is false for a one-time rule with no item before its date arrives" do
      expect(one_time_rule.calculator(today: Date.new(2026, 1, 31))).not_to be_fulfilled
    end

    # Same "assume paid on time" reading that anchored no-item rules already get.
    it "is true for a one-time rule with no item once its date has passed" do
      expect(one_time_rule.calculator(today: Date.new(2026, 6, 3))).to be_fulfilled
    end

    it "is true for a one-time rule with no item on the date itself" do
      expect(one_time_rule.calculator(today: Date.new(2026, 2, 1))).to be_fulfilled
    end

    # Fulfillment is a one-time concept only: a recurring rule expresses the same
    # idea by rolling its due date, and a rate rule never finishes at all.
    it "is false for a recurring rule whose occurrence was recorded" do
      item = create(:item, category: category, name: "Insurance")
      budget = insurance_rule(item: item)
      create(:entry, item: item, amount: 800, date: Date.new(2026, 6, 2))

      expect(budget.calculator(today: Date.new(2026, 7, 1))).not_to be_fulfilled
    end

    it "is false for a rate rule, which never finishes" do
      expect(create(:pool_budget, :rate, pool: car, amount: 80).calculator(today: today)).not_to be_fulfilled
    end
  end

  describe "#shortfall" do
    let(:budget) { dated_rule(amount: 600, interval: 6, anchor: Date.new(2026, 3, 1)) }

    it "is what is still missing from the target" do
      expect(budget.calculator(today: today).shortfall(500)).to eq(100)
    end

    it "is zero when the target is exactly met" do
      expect(budget.calculator(today: today).shortfall(600)).to eq(0)
    end

    it "clamps to zero when overfunded rather than going negative" do
      expect(budget.calculator(today: today).shortfall(750)).to eq(0)
    end

    it "stays an exact decimal even on the clamped path" do
      expect(budget.calculator(today: today).shortfall(750)).to be_a(BigDecimal)
    end
  end

  describe "#periods_until_due" do
    it "counts every payday from today through the due date inclusive" do
      budget = create(:pool_budget, :one_time, pool: car, amount: 500, anchor_date: Date.new(2026, 3, 6))

      # Feb 6, Feb 20, Mar 6 — both endpoints are paydays and both count.
      expect(budget.calculator(today: today).periods_until_due).to eq(3)
    end

    it "is one when the bill is due today" do
      budget = create(:pool_budget, :one_time, pool: car, amount: 500, anchor_date: today)

      expect(budget.calculator(today: today).periods_until_due).to eq(1)
    end

    it "clamps to one when the bill is already overdue" do
      item = create(:item, category: category, name: "Insurance")
      budget = insurance_rule(item: item)

      # due Jun 1, today Jun 3 — an inverted range yields no paydays at all.
      expect(budget.calculator(today: Date.new(2026, 6, 3)).periods_until_due).to eq(1)
    end

    it "clamps to one when the user has no pay cadence configured" do
      budget = cadence_less_rule(:one_time, amount: 500, anchor_date: Date.new(2026, 8, 1))

      expect(budget.calculator(today: today).periods_until_due).to eq(1)
    end
  end

  describe "#required" do
    # Spec §4.4: Car pool, Feb 6, biweekly. Paydays Feb 6, Feb 20, Mar 6...
    it "spreads an obligation across the paychecks before it is due" do
      budget = dated_rule(amount: 600, interval: 6, anchor: Date.new(2026, 3, 1))

      # 2 paydays in [Feb 6, Mar 1]: Feb 6 and Feb 20. Shortfall 600 - 500 = 100.
      expect(budget.calculator(today: today).required(500)).to eq(50.00)
    end

    it "demands the whole shortfall when the bill lands before the next paycheck" do
      budget = dated_rule(amount: 600, interval: 6, anchor: Date.new(2026, 2, 7))

      expect(budget.calculator(today: today).required(0)).to eq(600.00)
    end

    it "is zero when the rule is already funded" do
      budget = dated_rule(amount: 600, interval: 6, anchor: Date.new(2026, 3, 1))

      expect(budget.calculator(today: today).required(600)).to eq(0)
    end

    it "is zero when the rule is overfunded" do
      budget = dated_rule(amount: 600, interval: 6, anchor: Date.new(2026, 3, 1))

      expect(budget.calculator(today: today).required(750)).to eq(0)
    end

    it "rises sharply after an unexpected expense drains the reserve" do
      budget = dated_rule(amount: 600, interval: 6, anchor: Date.new(2026, 3, 1))

      # spec §4.4: after $420 of tires, insurance is left with only $80 allocated
      expect(budget.calculator(today: today).required(80)).to eq(260.00)
    end

    it "spreads a distant obligation thinly" do
      budget = dated_rule(amount: 180, interval: 12, anchor: Date.new(2026, 8, 15))

      # 14 paydays in [Feb 6, Aug 15]
      expect(budget.calculator(today: today).required(0)).to eq(12.86)
    end

    # 180 / 14 truncates to 12 under integer division. The money column hands back
    # an Integer for an in-memory record, so this guards the cents.
    it "returns an exact decimal rather than a truncated integer" do
      budget = dated_rule(amount: 180, interval: 12, anchor: Date.new(2026, 8, 15))

      expect(budget.calculator(today: today).required(0)).to be_a(BigDecimal)
    end

    it "spreads a monthly rate rule over the paychecks left in the month" do
      budget = create(:pool_budget, :rate, pool: car, amount: 80)

      # due Feb 28; paydays Feb 6 and Feb 20.
      expect(budget.calculator(today: today).required(0)).to eq(40.00)
    end

    it "demands the full amount of a per-paycheck rate rule every period" do
      budget = create(:pool_budget, :per_paycheck_rate, pool: car, amount: 300)

      # due Feb 19; only Feb 6 falls in [Feb 6, Feb 19].
      expect(budget.calculator(today: today).required(0)).to eq(300.00)
    end

    it "spreads a one-time goal across every payday before it" do
      budget = create(:pool_budget, :one_time, pool: car, amount: 500, anchor_date: Date.new(2026, 8, 1))

      # 13 paydays in [Feb 6, Aug 1]. 500 / 13 = 38.4615...
      expect(budget.calculator(today: today).required(0)).to eq(38.46)
    end

    it "demands the whole shortfall at once when the bill is overdue" do
      item = create(:item, category: category, name: "Insurance")
      budget = insurance_rule(item: item)

      expect(budget.calculator(today: Date.new(2026, 6, 3)).required(300)).to eq(500.00)
    end

    it "demands the whole shortfall at once when no pay cadence is configured" do
      budget = cadence_less_rule(:one_time, amount: 500, anchor_date: Date.new(2026, 8, 1))

      expect(budget.calculator(today: today).required(0)).to eq(500.00)
    end

    # The four fulfillment cells for the one-time shape. An unfulfilled rule still
    # spreads its shortfall; a fulfilled one must stop asking for money entirely,
    # or a reached savings goal bills the user forever.
    it "still spreads a one-time rule whose item has no entry yet" do
      registration = create(:item, category: category, name: "Registration")
      budget = one_time_rule(item: registration, anchor: Date.new(2026, 8, 1))

      # 13 paydays in [Feb 6, Aug 1].
      expect(budget.calculator(today: today).required(0)).to eq(38.46)
    end

    it "is zero for a one-time rule once its bill is recorded" do
      registration = create(:item, category: category, name: "Registration")
      budget = one_time_rule(item: registration)
      create(:entry, item: registration, amount: 500, date: Date.new(2026, 2, 1))

      expect(budget.calculator(today: Date.new(2026, 6, 3)).required(0)).to eq(0)
    end

    it "still spreads a one-time rule with no item before its date arrives" do
      budget = one_time_rule(anchor: Date.new(2026, 8, 1))

      expect(budget.calculator(today: today).required(0)).to eq(38.46)
    end

    it "is zero for a one-time rule with no item once its date has passed" do
      budget = one_time_rule

      expect(budget.calculator(today: Date.new(2026, 6, 3)).required(0)).to eq(0)
    end

    it "returns an exact decimal on the fulfilled path too" do
      budget = one_time_rule

      expect(budget.calculator(today: Date.new(2026, 6, 3)).required(0)).to be_a(BigDecimal)
    end

    # Budget#calculator is defined on every budget, and a category-mode one has no
    # anchor or interval at all — it must still read as a plain monthly rate rule.
    it "treats a category-mode budget as a monthly rate rule" do
      groceries = create(:category, :expense, user: user, name: "Groceries")
      budget = create(:budget, category: groceries, amount: 400)

      # due Feb 28; paydays Feb 6 and Feb 20.
      expect(budget.calculator(today: today).required(0)).to eq(200.00)
    end
  end
end
