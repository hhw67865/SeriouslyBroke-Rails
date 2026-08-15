# frozen_string_literal: true

# Computes a pool's balance and how that balance is spoken for by its rules.
# See docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md §2.2, §4.3
class PoolCalculator
  attr_reader :pool, :today

  def initialize(pool, as_of: nil, today: Date.current)
    @pool = pool
    @as_of = as_of
    @today = today
  end

  # Deliberately start-date-agnostic. The balance this replaces filtered entries to
  # `pool.start_date..`; a pool's balance is all the money in it, with no cutoff — the
  # movement ledger simply starts empty. `start_date` survives as a savings-goal display
  # attribute, not a balance filter. See the spec example that pins this.
  def balance
    income_entries_total + savings_entries_total +
      movements_in_total - movements_out_total - expense_entries_total
  end

  # Retained for the savings-pool views; identical to #balance.
  alias current_balance balance

  # Earliest due date fills first: the money you need soonest must actually be there.
  def allocated_balances
    @allocated_balances ||= begin
      remaining = balance
      budgets_by_due_date.index_with do |budget|
        taken = remaining.clamp(0, budget.amount)
        remaining -= taken
        taken
      end
    end
  end

  def reserve = allocated_balances.values.sum

  def free_amount = [balance - reserve, 0].max

  def required
    budgets_by_due_date.sum { |budget| budget.calculator(today: today).required(allocated_balances[budget]) }
  end

  def progress_percentage
    return 0 unless pool.target_amount.to_f.positive?

    [(balance / pool.target_amount * 100).round, 100].min
  end

  def remaining_amount
    [pool.target_amount.to_f - balance, 0].max
  end

  def contributions = movements_in_total + savings_entries_total

  def withdrawals = movements_out_total + expense_entries_total

  private

  # The sort key is a triple, not a bare due date. `sort_by` is not stable and `pool.budgets`
  # carries no ORDER BY, so two rules sharing a due date could swap fill order between calls —
  # the same pool reporting different #required figures on consecutive loads with no data
  # change. `-amount` breaks the tie toward the larger obligation (the bigger bill is the one
  # you can least afford to be short on); `id` makes even identical amounts deterministic.
  def budgets_by_due_date
    @budgets_by_due_date ||= pool.budgets.includes(:item, :pool).sort_by do |budget|
      [budget.calculator(today: today).due_date, -budget.amount, budget.id]
    end
  end

  # Entry.incomes / .expenses already join item: :category, so do not join again.
  # An entry's own pool_id overrides its category's, so both must be honoured —
  # otherwise Entry#pool is a column nothing reads.
  def income_entries_total
    scoped(Entry.incomes.merge(entries_for_pool)).sum(:amount)
  end

  def expense_entries_total
    scoped(Entry.expenses.merge(entries_for_pool)).sum(:amount)
  end

  # TODO(plan-3): delete once §6.1 step 5 converts savings-category entries to movements.
  # Becomes a no-op the moment that migration runs (Entry.savings is then empty), so the
  # removal is mechanical and cannot double-count during the cutover.
  def savings_entries_total
    scoped(Entry.savings.merge(entries_for_pool)).sum(:amount)
  end

  # One predicate rather than .or — Entry.incomes already carries the categories
  # join, and .or rejects relations whose joins differ structurally.
  def entries_for_pool
    Entry.where(
      "entries.pool_id = :id OR (entries.pool_id IS NULL AND categories.pool_id = :id)",
      id: pool.id
    )
  end

  def movements_in_total = scoped(pool.movements_in).sum(:amount)

  def movements_out_total = scoped(pool.movements_out).sum(:amount)

  def scoped(relation)
    @as_of ? relation.where(date: ..@as_of) : relation
  end
end
