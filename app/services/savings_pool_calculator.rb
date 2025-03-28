# frozen_string_literal: true

class SavingsPoolCalculator
  attr_reader :savings_pool

  def initialize(savings_pool)
    @savings_pool = savings_pool
  end

  def total_saved
    # Add up contributions from savings categories
    savings_contributions = savings_pool.categories.savings.joins(:entries)
      .sum("entries.amount")

    # Subtract expenses
    expense_withdrawals = savings_pool.categories.expenses.joins(:entries)
      .sum("entries.amount")

    savings_contributions - expense_withdrawals
  end

  def progress_percentage
    return 0 unless savings_pool.target_amount.to_f.positive?
    [(total_saved / savings_pool.target_amount.to_f * 100).round, 100].min
  end

  def monthly_contribution(date = Date.current)
    date_range = date.all_month

    # Net contributions this month
    savings_month = savings_pool.categories.savings.joins(:entries)
      .where(entries: { date: date_range })
      .sum("entries.amount")

    expense_month = savings_pool.categories.expenses.joins(:entries)
      .where(entries: { date: date_range })
      .sum("entries.amount")

    savings_month - expense_month
  end
end
