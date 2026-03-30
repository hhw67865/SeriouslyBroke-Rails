# frozen_string_literal: true

require "rails_helper"

RSpec.describe SavingsPoolCalculator, type: :model do
  let(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }
  let!(:pool) { create(:savings_pool, user: user, name: "Emergency Fund", target_amount: 10_000, start_date: base_date - 6.months) }

  # Savings category (contributions)
  let!(:savings_cat) { create(:category, :savings, user: user, name: "Emergency Savings", savings_pool: pool) }
  let!(:savings_item) { create(:item, category: savings_cat, name: "Monthly Transfer") }

  # Expense category linked to pool (withdrawals)
  let!(:expense_cat) { create(:category, :expense, user: user, name: "Emergency Expense", savings_pool: pool) }
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

  describe "entries before pool start_date are excluded", :aggregate_failures do
    it "ignores contributions dated before the pool start_date" do
      create(:entry, item: savings_item, amount: 999.00, date: pool.start_date - 1.day)

      calc = pool.calculator
      expect(calc.contributions).to eq(1400.00) # unchanged, pre-start entry excluded
    end

    it "ignores withdrawals dated before the pool start_date" do
      create(:entry, item: expense_item, amount: 999.00, date: pool.start_date - 1.day)

      calc = pool.calculator
      expect(calc.withdrawals).to eq(250.00) # unchanged
    end
  end
end
