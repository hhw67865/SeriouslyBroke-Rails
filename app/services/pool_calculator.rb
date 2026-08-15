# frozen_string_literal: true

class PoolCalculator
  attr_reader :pool

  def initialize(pool, as_of: nil)
    @pool = pool
    @as_of = as_of
  end

  def progress_percentage
    return 0 unless pool.target_amount.to_f.positive?

    progress = (current_balance / pool.target_amount * 100).round
    [progress, 100].min
  end

  def current_balance
    contributions - withdrawals
  end

  def contributions
    scope = pool.contribution_entries
    scope = scope.where(date: ..@as_of) if @as_of
    scope.sum(:amount)
  end

  def withdrawals
    scope = pool.withdrawal_entries
    scope = scope.where(date: ..@as_of) if @as_of
    scope.sum(:amount)
  end

  def remaining_amount
    [pool.target_amount - current_balance, 0].max
  end
end
