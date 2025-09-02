# frozen_string_literal: true

class SavingsPoolCalculator
  attr_reader :savings_pool

  def initialize(savings_pool, _date = nil)
    @savings_pool = savings_pool
    # We don't need date_range as we're calculating all-time totals
  end

  # Get the current progress as a percentage of the target amount
  def progress_percentage
    return 0 unless savings_pool.target_amount.to_f.positive?

    progress = (current_balance / savings_pool.target_amount * 100).round
    # Cap positive progress at 100%, but allow negative percentages
    [progress, 100].min
  end

  # Calculate the current balance based on contributions minus withdrawals
  def current_balance
    contributions - withdrawals
  end

  # Get all contributions from savings categories (all time)
  def contributions
    savings_pool.entries
      .joins(item: :category)
      .where(categories: { category_type: :savings })
      .sum(:amount)
  end

  # Get all withdrawals from expense categories attached to this pool (all time)
  def withdrawals
    savings_pool.entries
      .joins(item: :category)
      .where(categories: { category_type: :expense })
      .sum(:amount)
  end

  # Calculate remaining amount needed to reach target
  def remaining_amount
    [savings_pool.target_amount - current_balance, 0].max
  end
end
