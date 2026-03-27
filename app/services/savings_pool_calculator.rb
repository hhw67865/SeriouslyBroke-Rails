# frozen_string_literal: true

class SavingsPoolCalculator
  attr_reader :savings_pool

  def initialize(savings_pool, _date = nil)
    @savings_pool = savings_pool
  end

  def progress_percentage
    return 0 unless savings_pool.target_amount.to_f.positive?

    progress = (current_balance / savings_pool.target_amount * 100).round
    [progress, 100].min
  end

  def current_balance
    contributions - withdrawals
  end

  def contributions
    savings_pool.contribution_entries.sum(:amount)
  end

  def withdrawals
    savings_pool.withdrawal_entries.sum(:amount)
  end

  def remaining_amount
    [savings_pool.target_amount - current_balance, 0].max
  end
end
