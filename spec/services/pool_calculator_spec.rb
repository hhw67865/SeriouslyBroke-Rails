# frozen_string_literal: true

require "rails_helper"

RSpec.describe PoolCalculator, type: :model do
  let(:user) { create(:user) }

  # These fixtures build a pool balance out of savings-category entries, which is
  # exactly what PoolCalculator#balance stopped counting. Scoped to this group so
  # they no longer leak into the envelope examples below.
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
      it "returns correct balance as_of 2 months ago", pending: "savings-category contributions become movements in Plan 3" do
        calc = pool.calculator(as_of: (base_date - 2.months).end_of_month)

        expect(calc.contributions).to eq(500.00) # 200 + 300
        expect(calc.withdrawals).to eq(100.00)
        expect(calc.current_balance).to eq(400.00) # 500 - 100
        expect(calc.progress_percentage).to eq(4) # 400/10000 * 100
      end

      it "returns correct balance as_of 1 month ago", pending: "savings-category contributions become movements in Plan 3" do
        calc = pool.calculator(as_of: (base_date - 1.month).end_of_month)

        expect(calc.contributions).to eq(1000.00) # 200 + 300 + 500
        expect(calc.withdrawals).to eq(100.00)
        expect(calc.current_balance).to eq(900.00) # 1000 - 100
        expect(calc.progress_percentage).to eq(9) # 900/10000 * 100
      end

      it "returns correct balance as_of current month end", pending: "savings-category contributions become movements in Plan 3" do
        calc = pool.calculator(as_of: base_date.end_of_month)

        expect(calc.contributions).to eq(1400.00) # 200 + 300 + 500 + 400
        expect(calc.withdrawals).to eq(250.00) # 100 + 150
        expect(calc.current_balance).to eq(1150.00) # 1400 - 250
        expect(calc.progress_percentage).to eq(12) # 1150/10000 * 100 = 11.5, rounded to 12
      end

      it "returns all-time balance with no as_of date", pending: "savings-category contributions become movements in Plan 3" do
        calc = pool.calculator

        expect(calc.current_balance).to eq(1150.00)
        expect(calc.remaining_amount).to eq(8850.00) # 10000 - 1150
      end
    end

    describe "entries before pool start_date are excluded", :aggregate_failures do
      it "ignores contributions dated before the pool start_date", pending: "savings-category contributions become movements in Plan 3" do
        create(:entry, item: savings_item, amount: 999.00, date: pool.start_date - 1.day)

        calc = pool.calculator
        expect(calc.contributions).to eq(1400.00) # unchanged, pre-start entry excluded
      end

      it "ignores withdrawals dated before the pool start_date", pending: "savings-category contributions become movements in Plan 3" do
        create(:entry, item: expense_item, amount: 999.00, date: pool.start_date - 1.day)

        calc = pool.calculator
        expect(calc.withdrawals).to eq(250.00) # unchanged
      end
    end
  end

  # Regression: account and budget pools legitimately have a nil target_amount (only
  # savings pools validate its presence), which made remaining_amount raise
  # NoMethodError and took the pools index down with it.
  describe "pools with no target_amount", :aggregate_failures do
    it "returns zero instead of raising" do
      account = create(:pool, :account, user: user)

      expect(account.target_amount).to be_nil
      expect(account.calculator.remaining_amount).to eq(0)
      expect(account.calculator.progress_percentage).to eq(0)
    end
  end

  describe "envelope behaviour" do
    let(:envelope_user) { create(:user, pay_cadence: :biweekly, pay_anchor_date: Date.new(2026, 2, 6)) }
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
      end
    end
  end
end
