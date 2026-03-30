# frozen_string_literal: true

class SavingsPoolCalculator
  attr_reader :savings_pool

  def initialize(savings_pool, as_of: nil)
    @savings_pool = savings_pool
    @as_of = as_of
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
    scope = savings_pool.contribution_entries
    scope = scope.where(date: ..@as_of) if @as_of
    scope.sum(:amount)
  end

  def withdrawals
    scope = savings_pool.withdrawal_entries
    scope = scope.where(date: ..@as_of) if @as_of
    scope.sum(:amount)
  end

  def remaining_amount
    [savings_pool.target_amount - current_balance, 0].max
  end
end
