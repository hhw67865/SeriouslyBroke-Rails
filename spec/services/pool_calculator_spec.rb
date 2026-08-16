# frozen_string_literal: true

require "rails_helper"

RSpec.describe PoolCalculator, type: :model do
  let(:user) { create(:user) }

  # These fixtures build a pool balance out of savings-category entries — the pre-envelope
  # shape #balance still has to answer for until Plan 3 converts those entries to movements.
  # Scoped to this group so they do not leak into the envelope examples below.
  describe "savings-pool balances" do
    let(:base_date) { Date.current.beginning_of_month }
    let!(:pool) { create(:pool, user: user, name: "Emergency Fund", target_amount: 10_000, start_date: base_date - 6.months) }

    # Savings category (contributions)
    let!(:savings_cat) { create(:category, :savings, user: user, name: "Emergency Savings", pool: pool) }
    let!(:savings_item) { create(:item, category: savings_cat, name: "Monthly Transfer") }

    # Expense category linked to pool (withdrawals)
    let!(:expense_cat) { create(:category, :expense, user: user, name: "Emergency Expense", pool: pool) }
    let!(:expense_item) { create(:item, category: expense_cat, name: "Withdrawal") }

    before do
      # Contributions: $200 month-3, $300 month-2, $500 month-1, $400 this month
      create(:entry, item: savings_item, amount: 200.00, date: base_date - 3.months + 1.day)
      create(:entry, item: savings_item, amount: 300.00, date: base_date - 2.months + 1.day)
      create(:entry, item: savings_item, amount: 500.00, date: base_date - 1.month + 1.day)
      create(:entry, item: savings_item, amount: 400.00, date: base_date + 1.day)

      # Withdrawals: $100 month-2, $150 this month
      create(:entry, item: expense_item, amount: 100.00, date: base_date - 2.months + 5.days)
      create(:entry, item: expense_item, amount: 150.00, date: base_date + 5.days)
    end

    describe "date-scoped balance", :aggregate_failures do
      it "returns correct balance as_of 2 months ago" do
        calc = pool.calculator(as_of: (base_date - 2.months).end_of_month)

        expect(calc.contributions).to eq(500.00) # 200 + 300
        expect(calc.withdrawals).to eq(100.00)
        expect(calc.current_balance).to eq(400.00) # 500 - 100
        expect(calc.progress_percentage).to eq(4) # 400/10000 * 100
      end

      it "returns correct balance as_of 1 month ago" do
        calc = pool.calculator(as_of: (base_date - 1.month).end_of_month)

        expect(calc.contributions).to eq(1000.00) # 200 + 300 + 500
        expect(calc.withdrawals).to eq(100.00)
        expect(calc.current_balance).to eq(900.00) # 1000 - 100
        expect(calc.progress_percentage).to eq(9) # 900/10000 * 100
      end

      it "returns correct balance as_of current month end" do
        calc = pool.calculator(as_of: base_date.end_of_month)

        expect(calc.contributions).to eq(1400.00) # 200 + 300 + 500 + 400
        expect(calc.withdrawals).to eq(250.00) # 100 + 150
        expect(calc.current_balance).to eq(1150.00) # 1400 - 250
        expect(calc.progress_percentage).to eq(12) # 1150/10000 * 100 = 11.5, rounded to 12
      end

      it "returns all-time balance with no as_of date" do
        calc = pool.calculator

        expect(calc.current_balance).to eq(1150.00)
        expect(calc.remaining_amount).to eq(8850.00) # 10000 - 1150
      end
    end

    # The two "entries before pool start_date are excluded" examples that lived here were
    # deleted, not un-pended: #balance deliberately stopped filtering on start_date, and the
    # "counts entries and movements dated before the pool's start_date" example below pins
    # the opposite semantic. They asserted a rule this branch permanently reversed.
  end

  # Regression: account and budget pools legitimately have a nil target_amount (only
  # savings pools validate its presence), which made remaining_amount raise
  # NoMethodError and took the pools index down with it.
  describe "pools with no target_amount", :aggregate_failures do
    it "returns zero instead of raising" do
      account = create(:pool, :account, user: user)

      expect(account.target_amount).to be_nil
      expect(account.calculator.remaining_amount).to eq(0)
      # `nil.to_d` is 0, which is what makes the nil target safe without a guard.
      expect(account.calculator.remaining_amount).to be_a(BigDecimal)
      expect(account.calculator.progress_percentage).to eq(0)
    end
  end

  describe "envelope behaviour" do
    let(:envelope_user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6)) }
    let(:checking) { create(:pool, :account, user: envelope_user, name: "Checking") }
    let(:car) { create(:pool, :budget_pool, user: envelope_user, account: checking, name: "Car") }
    let(:car_category) { create(:category, :expense, user: envelope_user, name: "Car Spending", pool: car) }

    # A method rather than a `let`: Date is immutable, so there is nothing to memoize.
    def today = Date.new(2026, 2, 6)

    describe "#balance" do
      it "counts movements in, movements out, and expense entries" do
        create(:pool_movement, from_pool: checking, to_pool: car, amount: 700)
        create(:pool_movement, from_pool: car, to_pool: checking, amount: 50)
        create(:entry, item: create(:item, category: car_category), amount: 70, date: today)

        expect(car.calculator(today: today).balance).to eq(580.00)
      end

      it "counts income entries into an account" do
        income_category = create(:category, :income, user: envelope_user, pool: checking)
        create(:entry, item: create(:item, category: income_category), amount: 2_400, date: today)
        create(:pool_movement, from_pool: checking, to_pool: car, amount: 400)

        expect(checking.calculator(today: today).balance).to eq(2_000.00)
      end

      # The balance is deliberately start-date-agnostic. The old #contributions scoped to
      # `start_date..`; #balance does not, and must not — a pool's balance is all the money
      # in it, full stop. Pinned as a semantic rather than left as an incidental omission,
      # so re-adding the filter is a test failure and not a silent "fix".
      it "counts entries and movements dated before the pool's start_date", :aggregate_failures do
        car.update!(start_date: Date.new(2026, 6, 1))
        create(:pool_movement, from_pool: checking, to_pool: car, amount: 100, date: Date.new(2026, 1, 20))
        create(:entry, item: create(:item, category: car_category), amount: 40, date: Date.new(2026, 1, 15))

        expect(car.start_date).to be > Date.new(2026, 1, 20)
        expect(car.calculator(today: today).balance).to eq(60.00)
      end

      it "goes negative when a pool is overspent" do
        create(:pool_movement, from_pool: checking, to_pool: car, amount: 100)
        create(:entry, item: create(:item, category: car_category), amount: 150, date: today)

        expect(car.calculator(today: today).balance).to eq(-50.00)
      end

      # Dashboard::SavingsPresenter calls pool.calculator(as_of:), so the date cutoff
      # has to reach the movements too, not only the entries it used to filter.
      it "applies as_of to movements", :aggregate_failures do
        create(:pool_movement, from_pool: checking, to_pool: car, amount: 500, date: Date.new(2026, 1, 10))
        create(:pool_movement, from_pool: car, to_pool: checking, amount: 100, date: Date.new(2026, 2, 10))

        expect(car.calculator(as_of: Date.new(2026, 1, 31), today: today).balance).to eq(500.00)
        expect(car.calculator(today: today).balance).to eq(400.00)
      end

      # Entry#pool_id overrides its category's pool. Asserted in both directions on
      # purpose: the override pool must gain the entry AND the category's pool must
      # lose it. Reading only the category's pool_id passes the first half.
      it "honours a per-entry pool override in both directions", :aggregate_failures do
        maintenance = create(:pool, :budget_pool, user: envelope_user, account: checking, name: "Maintenance")
        create(:pool_movement, from_pool: checking, to_pool: car, amount: 300)
        create(:pool_movement, from_pool: checking, to_pool: maintenance, amount: 300)
        create(:entry, item: create(:item, category: car_category), amount: 100, date: today, pool: maintenance)

        expect(car.calculator(today: today).balance).to eq(300.00)
        expect(maintenance.calculator(today: today).balance).to eq(200.00)
      end
    end

    describe "#allocated_balances" do
      # Spec §4.4 — earliest due date fills first.
      let!(:gas) { create(:pool_budget, :rate, pool: car, amount: 80) }
      let!(:insurance) do
        create(:pool_budget, pool: car, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      end
      let!(:registration) do
        create(:pool_budget, pool: car, amount: 180, interval_months: 12, anchor_date: Date.new(2026, 8, 15))
      end

      it "fills by due date and leaves nothing free", :aggregate_failures do
        create(:pool_movement, from_pool: checking, to_pool: car, amount: 580)
        calc = car.calculator(today: today)

        expect(calc.allocated_balances[gas]).to eq(80.00)
        expect(calc.allocated_balances[insurance]).to eq(500.00)
        expect(calc.allocated_balances[registration]).to eq(0)
        expect(calc.free_amount).to eq(0)
      end

      it "reports the surplus beyond every rule as free" do
        create(:pool_movement, from_pool: checking, to_pool: car, amount: 1_000)

        expect(car.calculator(today: today).free_amount).to eq(140.00)
      end

      it "gives every rule zero when the pool is negative", :aggregate_failures do
        create(:entry, item: create(:item, category: car_category), amount: 50, date: today)
        calc = car.calculator(today: today)

        expect(calc.allocated_balances.values).to all(eq(0))
        expect(calc.free_amount).to eq(0)
      end

      it "totals the pool's requirement across its rules" do
        create(:pool_movement, from_pool: checking, to_pool: car, amount: 580)

        # gas $0 + insurance $50.00 + registration $12.86
        expect(car.calculator(today: today).required).to eq(62.86)
      end

      it "raises the requirement after an unexpected expense" do
        create(:pool_movement, from_pool: checking, to_pool: car, amount: 580)
        create(:entry, item: create(:item, category: car_category, name: "New tires"), amount: 420, date: today)

        # gas $0 + insurance $260.00 + registration $12.86
        expect(car.calculator(today: today).required).to eq(272.86)
      end
    end

    # `[BigDecimal, 0].max` returns the bare Integer literal on the negative branch, so the
    # return type of both methods depended on whether the pool happened to be in the black.
    # Plan 2's sweep step divides by #free_amount; money math must not change type under it.
    describe "money types on the negative branch", :aggregate_failures do
      it "returns a BigDecimal zero from #free_amount when the pool is overdrawn" do
        create(:pool_budget, :rate, pool: car, amount: 80)
        create(:entry, item: create(:item, category: car_category), amount: 50, date: today)
        calc = car.calculator(today: today)

        expect(calc.free_amount).to eq(0)
        expect(calc.free_amount).to be_a(BigDecimal)
      end

      it "returns a BigDecimal zero from #remaining_amount when the goal is exceeded" do
        goal = create(:pool, :savings_pool, user: envelope_user, account: checking, target_amount: 100)
        create(:pool_movement, from_pool: checking, to_pool: goal, amount: 250)
        calc = goal.calculator(today: today)

        expect(calc.remaining_amount).to eq(0)
        expect(calc.remaining_amount).to be_a(BigDecimal)
      end

      # The positive branch, pinned alongside the negative one so the pair proves the type
      # no longer depends on which way the subtraction went.
      it "returns a BigDecimal from #remaining_amount when the goal is unmet" do
        goal = create(:pool, :savings_pool, user: envelope_user, account: checking, target_amount: 100)
        create(:pool_movement, from_pool: checking, to_pool: goal, amount: 30.10)
        calc = goal.calculator(today: today)

        expect(calc.remaining_amount).to eq(69.90)
        expect(calc.remaining_amount).to be_a(BigDecimal)
      end
    end

    # The shape the `[x, 0.to_d].max` idiom above never covered: `max` only coerces when
    # the clamp FIRES, and `[0, BigDecimal("0")].max` returns the Integer. An empty
    # `sum(:amount)` over a `money` column returns Integer 0 too, so a pool holding
    # nothing at all — a fresh envelope, the first thing Plan 2b's sweep will meet —
    # answered every money question in the wrong type. Value AND type on each reader:
    # `eq(0)` passes against the Integer that caused this.
    describe "money types on a pool with no entries at all", :aggregate_failures do
      it "answers in BigDecimal from an empty ledger" do
        create(:pool_budget, :rate, pool: car, amount: 80)
        calc = car.calculator(today: today)

        expect(calc.balance).to eq(0)
        expect(calc.balance).to be_a(BigDecimal)
        expect(calc.reserve).to eq(0)
        expect(calc.reserve).to be_a(BigDecimal)
        expect(calc.free_amount).to eq(0)
        expect(calc.free_amount).to be_a(BigDecimal)
      end

      # And with no rules either, so #reserve sums an empty hash rather than a hash of
      # clamped zeroes. Two different Integer sources, one per example.
      it "answers in BigDecimal with no rules to reserve against" do
        calc = car.calculator(today: today)

        expect(calc.allocated_balances).to be_empty
        expect(calc.reserve).to be_a(BigDecimal)
        expect(calc.free_amount).to be_a(BigDecimal)
      end
    end

    # `remaining.clamp(0, budget.amount)` raises ArgumentError whenever amount is negative,
    # taking down allocated_balances, reserve, free_amount and required — the whole pool
    # page. Budget now validates the sign, so this writes past the validation to prove the
    # rendering path survives a degenerate row however it got there.
    describe "#allocated_balances with a degenerate rule amount" do
      it "gives the bad rule nothing and keeps the waterfall intact", :aggregate_failures do
        gas = create(:pool_budget, :rate, pool: car, amount: 80)
        broken = create(:pool_budget, pool: car, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
        broken.update_column(:amount, -100) # rubocop:disable Rails/SkipsModelValidations -- the point
        create(:pool_movement, from_pool: checking, to_pool: car, amount: 500)
        calc = car.calculator(today: today)

        expect(broken.reload.amount).to be_negative
        expect(calc.allocated_balances[broken]).to eq(0)
        expect(calc.allocated_balances[gas]).to eq(80.00)
        expect(calc.free_amount).to eq(420.00)
      end
    end

    # `sort_by` is not stable in Ruby, so a bare due-date sort let two rules sharing a due
    # date swap fill order between calls — the same pool reporting different `required`
    # figures on consecutive page loads with no data change. Money must not be a coin flip.
    describe "#allocated_balances when two rules share a due date" do
      let!(:big) do
        create(:pool_budget, pool: car, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      end
      let!(:small) do
        create(:pool_budget, pool: car, amount: 200, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      end

      it "fills the larger obligation first", :aggregate_failures do
        create(:pool_movement, from_pool: checking, to_pool: car, amount: 500)
        calc = car.calculator(today: today)

        expect(big.calculator(today: today).due_date).to eq(small.calculator(today: today).due_date)
        expect(calc.allocated_balances[big]).to eq(500.00)
        expect(calc.allocated_balances[small]).to eq(0)
      end
    end

    # An account holds no rules at all (Budget rejects an account owner), so its whole
    # balance sweeps back as free. This is the value a later plan's sweep step reads.
    describe "#free_amount for a pool with no rules" do
      it "reports the entire balance as free", :aggregate_failures do
        income_category = create(:category, :income, user: envelope_user, pool: checking)
        create(:entry, item: create(:item, category: income_category), amount: 1_200, date: today)
        calc = checking.calculator(today: today)

        expect(calc.allocated_balances).to be_empty
        expect(calc.reserve).to eq(0)
        expect(calc.free_amount).to eq(1_200.00)
        expect(calc.required).to eq(0)
        # An unseeded `sum` over an empty rule set returns the Integer literal 0, making
        # #required's type depend on whether the pool happens to hold any rules.
        expect(calc.required).to be_a(BigDecimal)
      end
    end
  end

  describe "dateless savings goals" do
    let(:goal_user) { create(:user, :biweekly) }
    let(:account) { create(:pool, :account, user: goal_user) }
    let(:vacation) do
      create(:pool, :savings_pool, user: goal_user, account: account, target_amount: 2_400)
    end
    let(:today) { Date.new(2026, 2, 6) }

    before { create(:pool_budget, :per_paycheck_rate, pool: vacation, amount: 150) }

    # The whole progression, in order, because "a dateless goal is just a rate rule plus a
    # pool target" is the reading this group exists to disprove. An ordinary rate rule is
    # satisfied at its OWN amount — correct for a budget envelope, which is swept and topped
    # back up every period, and wrong for a savings pool, which never sweeps: under that
    # reading the second example below returned 0 and a $2,400 goal reported itself funded
    # forever at $150. Each example is one period further along the same goal.
    it "asks for its rate while below the target" do
      expect(vacation.calculator(today: today).required).to eq(150)
    end

    # $600 of $2,400 saved. The rule's amount is a contribution rate, not a per-period
    # ceiling, so a part-funded goal keeps asking for the whole rate.
    it "still asks for the full rate when partly funded" do
      create(:pool_movement, from_pool: account, to_pool: vacation, amount: 600)

      expect(vacation.calculator(today: today).required).to eq(150)
    end

    # $100 short with a $150 rate: asking for the rate would overshoot the target the user
    # set, so the final contribution is the remainder.
    it "asks only for the remainder when less than a rate is left" do
      create(:pool_movement, from_pool: account, to_pool: vacation, amount: 2_300)

      expect(vacation.calculator(today: today).required).to eq(100)
    end

    it "stops asking once the balance reaches the target" do
      create(:pool_movement, from_pool: account, to_pool: vacation, amount: 2_400)

      expect(vacation.calculator(today: today).required).to eq(0)
    end

    it "stops asking when overfunded" do
      create(:pool_movement, from_pool: account, to_pool: vacation, amount: 2_500)

      expect(vacation.calculator(today: today).required).to eq(0)
    end

    # `0.to_d`, not a bare `0`: #required feeds a summing caller, so a reached goal must not
    # make the return type depend on how well funded the pool is.
    it "returns a BigDecimal zero from the reached branch" do
      create(:pool_movement, from_pool: account, to_pool: vacation, amount: 2_400)

      expect(vacation.calculator(today: today).required).to be_a(BigDecimal)
    end

    # Budget blesses two dateless shapes and their amounts are in different units: a
    # per_paycheck rule's amount IS the per-period rate, while a monthly rule's is a
    # per-month figure. $600 a month is $300 a period for this biweekly user in a
    # two-boundary February; summing the two bases raw would ask $600 a fortnight.
    it "converts a monthly rate to a per-period figure" do
      monthly_goal = create(:pool, :savings_pool, user: goal_user, account: account, target_amount: 2_400)
      create(:pool_budget, :rate, pool: monthly_goal, amount: 600)

      expect(monthly_goal.calculator(today: today).required).to eq(300)
    end

    # The whole month, not what is left of it. Asked on Feb 20 — the month's second and last
    # boundary — the goal still contributes $300, not the $600 that dividing by the periods
    # REMAINING would give. A goal wants a steady rate; the lumpier catch-up reading belongs
    # to a dated bill.
    it "divides a monthly rate by the whole month, not the periods left in it" do
      monthly_goal = create(:pool, :savings_pool, user: goal_user, account: account, target_amount: 2_400)
      create(:pool_budget, :rate, pool: monthly_goal, amount: 600)

      expect(monthly_goal.calculator(today: Date.new(2026, 2, 20)).required).to eq(300)
    end

    # Both bases on one goal, each normalised before adding: $150 a period plus $600 a month.
    it "adds rules of different bases in the same unit" do
      create(:pool_budget, :rate, pool: vacation, amount: 600)

      expect(vacation.calculator(today: today).required).to eq(450)
    end

    # A user with no cadence has no boundaries at all, so the monthly amount cannot be
    # divided into periods. Falling back to the full amount is a wrong-but-safe answer;
    # dividing by zero takes down every page that renders a requirement.
    it "falls back to the full monthly amount for a user with no cadence configured" do
      cadence_less = create(:user)
      bank = create(:pool, :account, user: cadence_less)
      goal = create(:pool, :savings_pool, user: cadence_less, account: bank, target_amount: 2_400)
      create(:pool_budget, :rate, pool: goal, amount: 600)

      expect(goal.calculator(today: today).required).to eq(600)
    end

    # A savings pool with a deadline is not a dateless goal. The anchored maths spreads the
    # $600 across the 13 pay periods between today and Aug 1 — $46.15 a period — and must
    # keep winning; the dateless path would ask for the whole $600 now.
    it "leaves an anchored savings goal to the scheduled maths" do
      deadline_goal = create(:pool, :savings_pool, user: goal_user, account: account, target_amount: 2_400)
      create(:pool_budget, :one_time, pool: deadline_goal, amount: 600)

      expect(deadline_goal.calculator(today: today).required).to eq(46.15)
    end

    it "does not apply the cutoff to budget pools" do
      envelope = create(:pool, :budget_pool, user: goal_user, account: account, target_amount: nil)
      create(:pool_budget, :per_paycheck_rate, pool: envelope, amount: 150)

      expect(envelope.calculator(today: today).required).to eq(150)
    end

    # The pair below is the pool-type discrimination, held at one identical balance so the
    # only difference between the two answers is the pool's type. The nil-target envelope
    # example above cannot do that job: with no target, #dateless_goal? is false for it
    # whether or not the `pool_type_savings?` guard is there, so it fails zero mutations.
    it "stops asking, in BigDecimal, once a target below the rate is reached", :aggregate_failures do
      calc = pool_at_a_target_below_its_rate(:savings_pool).calculator(today: today)

      expect(calc.required).to eq(0)
      expect(calc.required).to be_a(BigDecimal)
    end

    # An envelope's target is a display marker, not a goal: at the identical balance it
    # keeps asking for the $50 still missing from this period's $150.
    it "keeps a budget pool asking for the rest of its rate at the same balance" do
      calc = pool_at_a_target_below_its_rate(:budget_pool).calculator(today: today)

      expect(calc.required).to eq(50)
    end

    # $100 target, $150 a period, $100 in the pool.
    def pool_at_a_target_below_its_rate(trait)
      create(:pool, trait, user: goal_user, account: account, target_amount: 100).tap do |pool|
        create(:pool_budget, :per_paycheck_rate, pool: pool, amount: 150)
        create(:pool_movement, from_pool: account, to_pool: pool, amount: 100)
      end
    end
  end

  # Plan 2b decision 1: a rate envelope whose period has ended still HOLDS its leftover
  # until a distribution moves it, so the question these answer is "is that money spoken
  # for by a period that is over" — never "should the screen pretend the money is gone".
  #
  # `today` is Thu 20 Aug 2026, the last day of a biweekly period anchored Fri 6 Feb 2026:
  # boundaries fall on Aug 7 and Aug 21, so a payment dated Aug 15 is inside the live
  # period and one dated Jul 12 is two periods back. Fixed rather than relative because
  # every expectation here turns on which side of a boundary a date sits.
  describe "closed periods and sweeping" do
    let(:sweep_user) { create(:user, :biweekly) }
    let(:account) { create(:pool, :account, user: sweep_user) }
    let(:today) { Date.new(2026, 8, 20) }
    let(:last_period) { Date.new(2026, 7, 12) }
    let(:this_period) { Date.new(2026, 8, 15) }

    def envelope(trait = :budget_pool, **attrs)
      create(:pool, trait, user: sweep_user, account: account, **attrs)
    end

    def fund(pool, amount, on:)
      create(:pool_movement, from_pool: account, to_pool: pool, amount: amount, date: on)
    end

    def spend(pool, amount, on:)
      category = create(:category, :expense, user: sweep_user, pool: pool)
      create(:entry, item: create(:item, category: category), amount: amount, date: on)
    end

    def calc(pool) = pool.calculator(today: today)

    # The positive direction. $60 left in Groceries from a period that ended a month ago:
    # the money is still in the envelope, and the next distribution takes it back.
    it "sweeps a rate envelope's leftover once its period has ended", :aggregate_failures do
      groceries = envelope(name: "Groceries")
      create(:pool_budget, :per_paycheck_rate, pool: groceries, amount: 400)
      fund(groceries, 60, on: last_period)

      expect(calc(groceries).period_closed?).to be(true)
      expect(calc(groceries).sweepable_amount).to eq(60)
      expect(calc(groceries).sweepable_amount).to be_a(BigDecimal)
    end

    # The negative direction at the same shape and the same balance: the only difference is
    # which side of Aug 7 the money arrived on. Without this the example above passes against
    # a #period_closed? hard-coded to true.
    it "leaves a rate envelope funded inside the live period alone", :aggregate_failures do
      groceries = envelope(name: "Groceries")
      create(:pool_budget, :per_paycheck_rate, pool: groceries, amount: 400)
      fund(groceries, 60, on: this_period)

      expect(calc(groceries).period_closed?).to be(false)
      expect(calc(groceries).sweepable_amount).to eq(0)
      expect(calc(groceries).sweepable_amount).to be_a(BigDecimal)
    end

    # THE trap (plan decision 2). A dateless savings goal IS a rate rule on a savings pool,
    # so eligibility written as "has a rate rule whose period ended" drains every goal the
    # user has. #free_amount is asserted alongside because it is the number a naive sweep
    # would reach for: `required` reads the $150 as a contribution rate while
    # `allocated_balances` still clamps the reserve to the rule's own $150, so this goal
    # reports $450 free. Sweeping is gated on the pool's TYPE, never on its rule shape.
    it "never sweeps a savings goal, whatever its rate rule's period says", :aggregate_failures do
      vacation = envelope(:savings_pool, name: "Vacation", target_amount: 2_400)
      create(:pool_budget, :per_paycheck_rate, pool: vacation, amount: 150)
      fund(vacation, 600, on: last_period)

      expect(calc(vacation).free_amount).to eq(450)
      expect(calc(vacation).period_closed?).to be(false)
      expect(calc(vacation).sweepable_amount).to eq(0)
      expect(calc(vacation).sweepable_amount).to be_a(BigDecimal)
    end

    # Fix round 1, the behaviour change. An anchored rule is money already spoken for by a
    # bill nobody has paid yet, so the sweep must not take it — but a RECURRING dated rule is
    # never `fulfilled?` (there is always a next occurrence), so gating the whole envelope on
    # it stranded the rate rule's genuine leftover in every period, permanently. The sweep is
    # partial instead: the bill keeps what it holds, the rest goes back.
    #
    # All three numbers are pinned and all three differ, so the example cannot pass on a
    # fixture where balance, reserve and sweepable happen to coincide: $900 in, the bill is
    # holding $500 of it, $400 comes back.
    it "sweeps a mixed envelope down to what its live bill is holding", :aggregate_failures do
      car = envelope(name: "Car")
      rate = create(:pool_budget, :per_paycheck_rate, pool: car, amount: 100)
      rent = create(:pool_budget, pool: car, amount: 500, interval_months: 1, anchor_date: Date.new(2026, 9, 1))
      fund(car, 900, on: last_period)

      expect(calc(car).balance).to eq(900)
      expect(calc(car).allocated_balances[rent]).to eq(500)
      expect(calc(car).allocated_balances[rate]).to eq(100)
      expect(calc(car).period_closed?).to be(true)
      expect(calc(car).sweepable_amount).to eq(400)
      expect(calc(car).sweepable_amount).to be_a(BigDecimal)
    end

    # Under-funded, at the shape the fix brief named: $300 against a $500 bill. The reserve is
    # by ALLOCATION, not by the rule's amount, and #allocated_balances fills earliest-due
    # first — the rate rule is due at this period's end (Aug 20) and the bill not until Sep 1,
    # so the rate rule takes its $100 and the bill reserves only the $200 left. $100 therefore
    # still comes back, and it should: that is last period's unspent grocery money, not rent.
    #
    # Pinned as the reserve MOVING (500 -> 200) at the same rule, which is the whole point of
    # reserving by allocation; a reserve read off `budget.amount` would answer 500 here and
    # sweep nothing.
    it "reserves what an under-funded bill actually holds, not what it wants", :aggregate_failures do
      car = envelope(name: "Car")
      rent = create(:pool_budget, pool: car, amount: 500, interval_months: 1, anchor_date: Date.new(2026, 9, 1))
      create(:pool_budget, :per_paycheck_rate, pool: car, amount: 100)
      fund(car, 300, on: last_period)

      expect(calc(car).balance).to eq(300)
      expect(calc(car).allocated_balances[rent]).to eq(200)
      expect(calc(car).period_closed?).to be(true)
      expect(calc(car).sweepable_amount).to eq(100)
      expect(calc(car).sweepable_amount).to be_a(BigDecimal)
    end

    # The other direction of the same idea, and the one that reaches zero: when the bill is
    # the earlier claim it fills FIRST and swallows the whole under-funded balance, leaving
    # the rate rule nothing to give back. A monthly rate rule ends Aug 31 while this bill,
    # anchored Jul 25, comes round again on Aug 25 — so the bill sorts ahead of it.
    #
    # Without this half the example above passes against a sweep that simply never returns
    # zero for a live bill.
    it "sweeps nothing when the live bill's allocation takes the whole balance", :aggregate_failures do
      car = envelope(name: "Car")
      rent = create(:pool_budget, pool: car, amount: 500, interval_months: 1, anchor_date: Date.new(2026, 7, 25))
      create(:pool_budget, :rate, pool: car, amount: 100)
      fund(car, 400, on: last_period)

      expect(calc(car).balance).to eq(400)
      expect(calc(car).allocated_balances[rent]).to eq(400)
      expect(calc(car).period_closed?).to be(true)
      expect(calc(car).sweepable_amount).to eq(0)
      expect(calc(car).sweepable_amount).to be_a(BigDecimal)
    end

    # The same shape with the anchored rule settled — a one-off dated Aug 1, now behind us.
    # A fulfilled bill reserves nothing, so the whole balance sweeps. Without this the
    # examples above pass against "any anchored rule reserves forever".
    #
    # #free_amount is pinned alongside deliberately, and it DISAGREES: #allocated_balances
    # still fills a fulfilled rule, so the pool reports $300 free while $900 sweeps. That is
    # the measured behaviour of the two readers today, and this assertion is here so a later
    # change to either one has to face the divergence rather than discover it in a ledger.
    it "sweeps the whole balance once the anchored rule beside the rate rule is fulfilled", :aggregate_failures do
      car = envelope(name: "Car")
      create(:pool_budget, :per_paycheck_rate, pool: car, amount: 100)
      create(:pool_budget, :one_time, pool: car, amount: 500, anchor_date: Date.new(2026, 8, 1))
      fund(car, 900, on: last_period)

      expect(calc(car).free_amount).to eq(300)
      expect(calc(car).period_closed?).to be(true)
      expect(calc(car).sweepable_amount).to eq(900)
      expect(calc(car).sweepable_amount).to be_a(BigDecimal)
    end

    # Mixed bases on one envelope: the per-paycheck rule's period ended Aug 6, the monthly
    # rule's does not end until Aug 31. `all?` means the LATEST period governs, so the money
    # stays put while any rule still has a live claim on it.
    it "waits for the later period when an envelope mixes bases", :aggregate_failures do
      utilities = envelope(name: "Utilities")
      create(:pool_budget, :per_paycheck_rate, pool: utilities, amount: 100)
      create(:pool_budget, :rate, pool: utilities, amount: 600)
      fund(utilities, 75, on: Date.new(2026, 8, 5))

      expect(utilities.budgets.map { |b| b.calculator(today: Date.new(2026, 8, 5)).period_end })
        .to contain_exactly(Date.new(2026, 8, 6), Date.new(2026, 8, 31))
      expect(calc(utilities).period_closed?).to be(false)
      expect(calc(utilities).sweepable_amount).to eq(0)
    end

    # The other direction of the same mixed-basis envelope: money from July is past both
    # period ends, so both rules agree and it sweeps.
    it "sweeps a mixed-basis envelope once every basis has rolled" do
      utilities = envelope(name: "Utilities")
      create(:pool_budget, :per_paycheck_rate, pool: utilities, amount: 100)
      create(:pool_budget, :rate, pool: utilities, amount: 600)
      fund(utilities, 75, on: last_period)

      expect(calc(utilities).period_closed?).to be(true)
    end

    # No rate rule means no period to close. An envelope funded only against a dated bill
    # accumulates toward it; "use it or lose it" is a rate envelope's policy, not every
    # envelope's, and applying it here would empty the bill fund every month.
    #
    # The `rate_budgets.empty?` guard is now the ONLY thing holding this line — the anchored
    # gate that used to shadow it is gone — so the fixture is funded $600 against a $500 bill
    # rather than exactly $500. At an exact match the reserve would eat the balance and
    # #sweepable_amount would read 0 either way; the extra $100 makes both assertions bite,
    # because a lost guard turns `[].all?` into `true` and hands that $100 to the buffer.
    it "does not sweep an envelope with only anchored rules", :aggregate_failures do
      rent = envelope(name: "Rent")
      create(:pool_budget, pool: rent, amount: 500, interval_months: 1, anchor_date: Date.new(2026, 9, 1))
      fund(rent, 600, on: last_period)

      expect(calc(rent).balance).to eq(600)
      expect(calc(rent).period_closed?).to be(false)
      expect(calc(rent).sweepable_amount).to eq(0)
    end

    it "does not sweep an envelope with no rules at all", :aggregate_failures do
      mystery = envelope(name: "Mystery")
      fund(mystery, 80, on: last_period)

      expect(calc(mystery).period_closed?).to be(false)
      expect(calc(mystery).sweepable_amount).to eq(0)
    end

    # The emptiest shape in the app, and the one every money reader here has changed type on
    # before: no movements and no entries, so every `sum(:amount)` behind #balance returns the
    # Integer literal 0. A sweep divides and sums these, so the guarantee is asserted as a
    # TYPE, not only as a value.
    #
    # #period_closed? is asserted directly because the $0 balance cannot distinguish the
    # `last_funded_on.nil?` guard from the clamp: with nothing in the envelope, sweepable
    # reads 0 whether the period is judged closed or not. This envelope has never been funded,
    # so there is no period for it to be past — the marker has to say so on its own.
    it "returns a BigDecimal zero for an entry-less envelope", :aggregate_failures do
      fresh = envelope(name: "Fresh")
      create(:pool_budget, :per_paycheck_rate, pool: fresh, amount: 400)

      expect(calc(fresh).period_closed?).to be(false)
      expect(calc(fresh).sweepable_amount).to eq(0)
      expect(calc(fresh).sweepable_amount).to be_a(BigDecimal)
    end

    # A closed envelope that was overspent has nothing to give back. The deficit is the
    # buffer's problem (spec §7.2), and a negative sweep would be the buffer paying the
    # envelope on the way OUT — money moving the wrong way through the ledger.
    it "sweeps nothing from a closed envelope that went negative", :aggregate_failures do
      dining = envelope(name: "Dining")
      create(:pool_budget, :per_paycheck_rate, pool: dining, amount: 150)
      fund(dining, 100, on: last_period)
      spend(dining, 180, on: last_period)

      expect(calc(dining).balance).to eq(-80)
      expect(calc(dining).period_closed?).to be(true)
      expect(calc(dining).sweepable_amount).to eq(0)
      expect(calc(dining).sweepable_amount).to be_a(BigDecimal)
    end
  end
end
