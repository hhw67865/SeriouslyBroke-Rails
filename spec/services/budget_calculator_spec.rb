# frozen_string_literal: true

require "rails_helper"

RSpec.describe BudgetCalculator, type: :model do
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6)) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:car) { create(:pool, :budget_pool, user: user, account: checking, name: "Car") }
  let(:category) { create(:category, :expense, user: user, name: "Car Spending", pool: car) }
  let(:today) { Date.new(2026, 2, 6) }

  # Spec §4.4's recurring bill: $800 every 6 months, next due Jun 1. Pass an item
  # to give it a fulfillment signal; without one it is assumed paid on time.
  def insurance_rule(item: nil, interval: 6, anchor: Date.new(2026, 6, 1), amount: 800)
    create(
      :pool_budget,
      :recurring,
      pool: car,
      amount: amount,
      interval_months: interval,
      anchor_date: anchor,
      item: item
    )
  end

  # Budget validates amount > 0, so a degenerate rule can no longer be created — but a row
  # can still reach these code paths through a direct write, and the calculator has to
  # answer rather than divide by zero or roll its own schedule backwards. Written past the
  # validation on purpose: the guard being exercised is the calculator's, not the model's.
  def degenerate_insurance_rule(item:, amount:)
    rule = insurance_rule(item: item)
    rule.update_column(:amount, amount) # rubocop:disable Rails/SkipsModelValidations -- the point
    rule.reload
  end

  # A dated obligation with no fulfillment signal — the §4.4 `required` fixtures.
  def dated_rule(amount:, interval:, anchor:)
    create(:pool_budget, pool: car, amount: amount, interval_months: interval, anchor_date: anchor)
  end

  # A dated one-off — a bill or a savings goal that never repeats.
  def one_time_rule(item: nil, amount: 500, anchor: Date.new(2026, 2, 1))
    create(:pool_budget, :one_time, pool: car, amount: amount, anchor_date: anchor, item: item)
  end

  # A user who never declared a period, so User#period_boundaries returns [].
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

    it "is the day before the next period boundary for a per-paycheck rule" do
      budget = create(:pool_budget, :per_paycheck_rate, pool: car, amount: 300)

      expect(budget.calculator(today: today).period_end).to eq(Date.new(2026, 2, 19))
    end

    it "falls back to the end of the month when no period is configured" do
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

    # Month-end anchors lag by a day: Jan 31 + 1 month is Feb 28, so the February
    # occurrence has arguably come due on Feb 28, but the day-of-month backoff does
    # not release it until Mar 1. Pinned deliberately — the lag under-rolls, which
    # keeps an obligation visible a day longer rather than forgetting it early.
    it "lags a day for a month-end anchor, erring toward not rolling" do
      budget = insurance_rule(interval: 1, anchor: Date.new(2026, 1, 31))

      expect(budget.calculator(today: Date.new(2026, 2, 28)).elapsed_cycles).to eq(1)
    end

    it "catches up the day after a month-end anchor's short month" do
      budget = insurance_rule(interval: 1, anchor: Date.new(2026, 1, 31))

      expect(budget.calculator(today: Date.new(2026, 3, 1)).elapsed_cycles).to eq(2)
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

    # The signal is the amount paid, not the number of rows. A $1 entry and a $500
    # entry are not the same event, and treating them alike loses real money.
    it "does not roll on a partial payment" do
      create(:entry, item: item, amount: 400, date: Date.new(2026, 6, 2))

      expect(budget.calculator(today: Date.new(2026, 7, 1)).cycles_completed).to eq(0)
    end

    it "rolls exactly once when the bill is settled in instalments" do
      create(:entry, item: item, amount: 400, date: Date.new(2026, 6, 2))
      create(:entry, item: item, amount: 400, date: Date.new(2026, 6, 9))

      expect(budget.calculator(today: Date.new(2026, 7, 1)).cycles_completed).to eq(1)
    end

    it "rolls once when the bill is overpaid" do
      create(:entry, item: item, amount: 900, date: Date.new(2026, 6, 2))

      expect(budget.calculator(today: Date.new(2026, 7, 1)).cycles_completed).to eq(1)
    end

    # Paying two cycles' worth up front must not roll a cycle that has not yet come
    # due — the same conservative direction #elapsed_cycles already errs in.
    it "never rolls further than the cycles that have actually come due" do
      create(:entry, item: item, amount: 1600, date: Date.new(2026, 6, 2))

      expect(budget.calculator(today: Date.new(2026, 7, 1)).cycles_completed).to eq(1)
    end

    it "is zero for a rule whose amount is zero, rather than dividing by it" do
      free = create(:item, category: category, name: "Free")
      budget = degenerate_insurance_rule(item: free, amount: 0)

      expect(budget.calculator(today: Date.new(2026, 7, 1)).cycles_completed).to eq(1)
    end

    it "falls back to elapsed cycles for a zero-amount rule that has been paid against" do
      free = create(:item, category: category, name: "Free")
      budget = degenerate_insurance_rule(item: free, amount: 0)
      create(:entry, item: free, amount: 50, date: Date.new(2026, 6, 2))

      expect(budget.calculator(today: Date.new(2026, 7, 1)).cycles_completed).to eq(1)
    end

    # Dividing by a negative amount yields a negative quotient — `floor` rounds toward
    # -infinity, and `min` can only clamp downward — which would roll due_date backwards
    # past its anchor. The model now rejects the sign; this pins the calculator's own guard.
    it "falls back to elapsed cycles for a negative-amount rule" do
      refund = create(:item, category: category, name: "Refund")
      budget = degenerate_insurance_rule(item: refund, amount: -800)
      create(:entry, item: refund, amount: 400, date: Date.new(2026, 6, 2))

      expect(budget.calculator(today: Date.new(2026, 7, 1)).cycles_completed).to eq(1)
    end
  end

  describe "#paid_since_anchor" do
    let(:item) { create(:item, category: category, name: "Insurance") }
    let(:budget) { insurance_rule(item: item) }

    it "sums the entries recorded on or after the anchor" do
      create(:entry, item: item, amount: 400, date: Date.new(2026, 6, 2))
      create(:entry, item: item, amount: 250, date: Date.new(2026, 6, 9))

      expect(budget.calculator(today: Date.new(2026, 7, 1)).paid_since_anchor).to eq(650)
    end

    it "excludes entries recorded before the anchor" do
      create(:entry, item: item, amount: 400, date: Date.new(2026, 5, 30))

      expect(budget.calculator(today: Date.new(2026, 7, 1)).paid_since_anchor).to eq(0)
    end

    it "is zero for a rule with no item to read a payment from" do
      expect(insurance_rule.calculator(today: Date.new(2026, 7, 1)).paid_since_anchor).to eq(0)
    end

    # Without an anchor there is no window to sum over, and an unbounded sum would
    # quietly return every entry ever recorded against the item — a wrong answer
    # dressed up as a real one, at a public entry point.
    it "is zero for an anchorless rate rule that has an item" do
      gas = create(:item, category: category, name: "Gas")
      budget = create(:pool_budget, :rate, pool: car, amount: 80, item: gas)
      create(:entry, item: gas, amount: 10, date: Date.new(2026, 2, 3))

      expect(budget.calculator(today: today).paid_since_anchor).to eq(0)
    end

    it "is an exact decimal" do
      create(:entry, item: item, amount: 400, date: Date.new(2026, 6, 2))

      expect(budget.calculator(today: Date.new(2026, 7, 1)).paid_since_anchor).to be_a(BigDecimal)
    end
  end

  describe "#due_date" do
    it "is the end of the calendar month for a monthly rate rule" do
      budget = create(:pool_budget, :rate, pool: car, amount: 80)

      expect(budget.calculator(today: today).due_date).to eq(Date.new(2026, 2, 28))
    end

    it "is the day before the next period boundary for a per-paycheck rate rule" do
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

    # The state the pay-based rolling design exists for: two occurrences have come
    # due, only one was paid, so the rule still points at the one still owed.
    it "stays one cycle behind when only one of two elapsed cycles was paid" do
      item = create(:item, category: category, name: "Insurance")
      budget = insurance_rule(item: item)
      create(:entry, item: item, amount: 800, date: Date.new(2026, 6, 2))

      expect(budget.calculator(today: Date.new(2027, 1, 1)).due_date).to eq(Date.new(2026, 12, 1))
    end

    it "reads as overdue while it is a cycle behind" do
      item = create(:item, category: category, name: "Insurance")
      budget = insurance_rule(item: item)
      create(:entry, item: item, amount: 800, date: Date.new(2026, 6, 2))

      expect(budget.calculator(today: Date.new(2027, 1, 1))).to be_overdue
    end

    # A degenerate amount must never send the schedule backwards in time.
    it "never rolls a zero-amount rule before its own anchor" do
      free = create(:item, category: category, name: "Free")
      budget = degenerate_insurance_rule(item: free, amount: 0)
      create(:entry, item: free, amount: 50, date: Date.new(2026, 6, 2))

      expect(budget.calculator(today: Date.new(2026, 7, 1)).due_date).to eq(Date.new(2026, 12, 1))
    end

    it "never rolls a negative-amount rule backwards past its anchor" do
      refund = create(:item, category: category, name: "Refund")
      budget = degenerate_insurance_rule(item: refund, amount: -800)
      create(:entry, item: refund, amount: 400, date: Date.new(2026, 6, 2))

      expect(budget.calculator(today: Date.new(2026, 7, 1)).due_date).to eq(Date.new(2026, 12, 1))
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

    # The four payment states. A partial payment must NOT fulfil the rule — that
    # would zero the requirement while real money is still owed.
    it "is false for a one-time rule that has only been partly paid" do
      budget = one_time_rule(item: registration)
      create(:entry, item: registration, amount: 100, date: Date.new(2026, 2, 1))

      expect(budget.calculator(today: Date.new(2026, 6, 3))).not_to be_fulfilled
    end

    it "is true for a one-time rule once an entry lands on its item" do
      budget = one_time_rule(item: registration)
      create(:entry, item: registration, amount: 500, date: Date.new(2026, 2, 1))

      expect(budget.calculator(today: Date.new(2026, 6, 3))).to be_fulfilled
    end

    it "is true for a one-time rule settled in instalments" do
      budget = one_time_rule(item: registration)
      create(:entry, item: registration, amount: 200, date: Date.new(2026, 2, 1))
      create(:entry, item: registration, amount: 300, date: Date.new(2026, 2, 8))

      expect(budget.calculator(today: Date.new(2026, 6, 3))).to be_fulfilled
    end

    it "is true for a one-time rule that was overpaid" do
      budget = one_time_rule(item: registration)
      create(:entry, item: registration, amount: 600, date: Date.new(2026, 2, 1))

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

    # A settled rule has no funding gap. Reporting one would let Task 8 render
    # "$500 still needed" next to a bill that was paid months ago.
    it "is zero for a fulfilled rule regardless of what is allocated" do
      registration = create(:item, category: category, name: "Registration")
      settled = one_time_rule(item: registration)
      create(:entry, item: registration, amount: 500, date: Date.new(2026, 2, 1))

      expect(settled.calculator(today: Date.new(2026, 6, 3)).shortfall(0)).to eq(0)
    end

    it "still reports the gap for a rule that was only partly paid" do
      registration = create(:item, category: category, name: "Registration")
      partly = one_time_rule(item: registration)
      create(:entry, item: registration, amount: 100, date: Date.new(2026, 2, 1))

      expect(partly.calculator(today: Date.new(2026, 6, 3)).shortfall(0)).to eq(500)
    end
  end

  describe "#periods_until_due" do
    it "counts every period boundary from today through the due date inclusive" do
      budget = create(:pool_budget, :one_time, pool: car, amount: 500, anchor_date: Date.new(2026, 3, 6))

      # Feb 6, Feb 20, Mar 6 — both endpoints are boundaries and both count.
      expect(budget.calculator(today: today).periods_until_due).to eq(3)
    end

    it "is one when the bill is due today" do
      budget = create(:pool_budget, :one_time, pool: car, amount: 500, anchor_date: today)

      expect(budget.calculator(today: today).periods_until_due).to eq(1)
    end

    it "clamps to one when the bill is already overdue" do
      item = create(:item, category: category, name: "Insurance")
      budget = insurance_rule(item: item)

      # due Jun 1, today Jun 3 — an inverted range yields no boundaries at all.
      expect(budget.calculator(today: Date.new(2026, 6, 3)).periods_until_due).to eq(1)
    end

    it "clamps to one when the user has no period configured" do
      budget = cadence_less_rule(:one_time, amount: 500, anchor_date: Date.new(2026, 8, 1))

      expect(budget.calculator(today: today).periods_until_due).to eq(1)
    end
  end

  describe "#required" do
    # Spec §4.4: Car pool, Feb 6, biweekly. Boundaries Feb 6, Feb 20, Mar 6...
    it "spreads an obligation across the periods before it is due" do
      budget = dated_rule(amount: 600, interval: 6, anchor: Date.new(2026, 3, 1))

      # 2 boundaries in [Feb 6, Mar 1]: Feb 6 and Feb 20. Shortfall 600 - 500 = 100.
      expect(budget.calculator(today: today).required(500)).to eq(50.00)
    end

    it "demands the whole shortfall when the bill lands before the next boundary" do
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

      # 14 boundaries in [Feb 6, Aug 15]
      expect(budget.calculator(today: today).required(0)).to eq(12.86)
    end

    # 180 / 14 truncates to 12 under integer division. The money column hands back
    # an Integer for an in-memory record, so this guards the cents.
    it "returns an exact decimal rather than a truncated integer" do
      budget = dated_rule(amount: 180, interval: 12, anchor: Date.new(2026, 8, 15))

      expect(budget.calculator(today: today).required(0)).to be_a(BigDecimal)
    end

    it "spreads a monthly rate rule over the periods left in the month" do
      budget = create(:pool_budget, :rate, pool: car, amount: 80)

      # due Feb 28; boundaries Feb 6 and Feb 20.
      expect(budget.calculator(today: today).required(0)).to eq(40.00)
    end

    it "demands the full amount of a per-paycheck rate rule every period" do
      budget = create(:pool_budget, :per_paycheck_rate, pool: car, amount: 300)

      # due Feb 19; only Feb 6 falls in [Feb 6, Feb 19].
      expect(budget.calculator(today: today).required(0)).to eq(300.00)
    end

    it "spreads a one-time goal across every boundary before it" do
      budget = create(:pool_budget, :one_time, pool: car, amount: 500, anchor_date: Date.new(2026, 8, 1))

      # 13 boundaries in [Feb 6, Aug 1]. 500 / 13 = 38.4615...
      expect(budget.calculator(today: today).required(0)).to eq(38.46)
    end

    it "demands the whole shortfall at once when the bill is overdue" do
      item = create(:item, category: category, name: "Insurance")
      budget = insurance_rule(item: item)

      expect(budget.calculator(today: Date.new(2026, 6, 3)).required(300)).to eq(500.00)
    end

    it "demands the whole shortfall at once when no period is configured" do
      budget = cadence_less_rule(:one_time, amount: 500, anchor_date: Date.new(2026, 8, 1))

      expect(budget.calculator(today: today).required(0)).to eq(500.00)
    end

    # The four fulfillment cells for the one-time shape. An unfulfilled rule still
    # spreads its shortfall; a fulfilled one must stop asking for money entirely,
    # or a reached savings goal bills the user forever.
    it "still spreads a one-time rule whose item has no entry yet" do
      registration = create(:item, category: category, name: "Registration")
      budget = one_time_rule(item: registration, anchor: Date.new(2026, 8, 1))

      # 13 boundaries in [Feb 6, Aug 1].
      expect(budget.calculator(today: today).required(0)).to eq(38.46)
    end

    it "is zero for a one-time rule once its bill is recorded" do
      registration = create(:item, category: category, name: "Registration")
      budget = one_time_rule(item: registration)
      create(:entry, item: registration, amount: 500, date: Date.new(2026, 2, 1))

      expect(budget.calculator(today: Date.new(2026, 6, 3)).required(0)).to eq(0)
    end

    # The partial-payment trap: a $100 entry against a $500 bill must not silently
    # retire the remaining $400.
    it "keeps demanding the balance of a one-time rule that was only partly paid" do
      registration = create(:item, category: category, name: "Registration")
      budget = one_time_rule(item: registration)
      create(:entry, item: registration, amount: 100, date: Date.new(2026, 2, 1))

      expect(budget.calculator(today: Date.new(2026, 6, 3)).required(400)).to eq(100.00)
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

      # due Feb 28; boundaries Feb 6 and Feb 20.
      expect(budget.calculator(today: today).required(0)).to eq(200.00)
    end
  end
end
