# frozen_string_literal: true

# Reduces a pool to exactly one display state. Every row's wording, colour and
# auto-expand behaviour on Home derives from here, so the precedence order below
# is the single place that decision lives.
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §4.4
class PoolStatus
  ATTENTION_STATES = [:overdrawn, :overdue, :wont_make_it, :behind].freeze

  attr_reader :pool, :today

  def initialize(pool, today: Date.current)
    @pool = pool
    @today = today
  end

  def state
    @state ||= if balance.negative? then :overdrawn
               elsif overdue_budget then :overdue
               elsif unreachable_budget then :wont_make_it
               elsif behind_amount.positive? then :behind
               elsif anchored_budgets.empty? then :left_to_spend
               else
                 :on_track
               end
  end

  def amount
    case state
    when :overdrawn then -balance
    when :overdue then overdue_amount
    when :wont_make_it then shortfall_for(unreachable_budget)
    when :behind then behind_amount
    else balance
    end
  end

  def due_on
    case state
    when :overdue then calculator_for(overdue_budget).due_date
    when :wont_make_it then calculator_for(unreachable_budget).due_date
    when :behind then lagging_due_date
    else next_due_date
    end
  end

  # Through #pool_calculator, not a second `pool.calculator` — the brief's draft built
  # one calculator here and another for the allocation maths, so a single #state call
  # ran the five balance queries twice and the two objects could in principle disagree.
  def balance = @balance ||= pool_calculator.balance

  def needs_attention? = ATTENTION_STATES.include?(state)

  private

  def pool_calculator = @pool_calculator ||= pool.calculator(today: today)

  def calculator_for(budget) = budget.calculator(today: today)

  def anchored_budgets
    @anchored_budgets ||= pool.budgets.select { |b| b.anchor_date.present? }
  end

  def overdue_budget
    return @overdue_budget if defined?(@overdue_budget)

    @overdue_budget = anchored_budgets.find { |b| calculator_for(b).overdue? }
  end

  # A rule nothing can save: it still has a shortfall and no period boundary
  # falls between today and its due date, so no future funding can reach it.
  def unreachable_budget
    return @unreachable_budget if defined?(@unreachable_budget)

    @unreachable_budget = anchored_budgets.find do |budget|
      calc = calculator_for(budget)
      next false unless shortfall_for(budget).positive?

      pool.user.period_boundaries(from: today + 1, to: calc.due_date).empty?
    end
  end

  def shortfall_for(budget)
    calculator_for(budget).shortfall(pool_calculator.allocated_balances[budget] || 0.to_d)
  end

  # The unpaid remainder, not the rule's face value: a $600 bill with $400 already
  # recorded against its item is $200 outstanding, and reporting $600 overstates by
  # exactly what the user has paid. Reuses BudgetCalculator's own payment signal
  # rather than re-querying the item's entries here.
  def overdue_amount
    calc = calculator_for(overdue_budget)
    [calc.target - calc.paid_since_anchor, 0.to_d].max
  end

  # How far below a steady schedule this pool is. A rule with N periods in its
  # full cycle and R remaining should hold amount * (N - R) / N by now.
  # Summed over anchored rules only, which is what makes the :behind branch and the
  # :left_to_spend branch below it mutually exclusive: with no anchored rules there is
  # nothing to sum and this is the seed, 0.
  def behind_amount
    @behind_amount ||= anchored_budgets.sum(0.to_d) { |budget| behind_amount_for(budget) }
  end

  # Zero where a steady schedule is not a concept: a one-time rule has no interval to
  # spread over, and a user with no cadence declared has no boundaries in the window.
  # Both make #periods_in_cycle zero, and both reach the division below without this.
  def behind_amount_for(budget)
    total = periods_in_cycle(budget)
    return 0.to_d unless total.positive?

    remaining = calculator_for(budget).periods_until_due
    expected = budget.amount.to_d * [total - remaining, 0].max / total
    allocated = pool_calculator.allocated_balances[budget] || 0.to_d
    [expected - allocated, 0.to_d].max
  end

  def periods_in_cycle(budget)
    return 0 if budget.interval_months.blank?

    calc = calculator_for(budget)
    pool.user.period_boundaries(from: calc.due_date - budget.interval_months.months, to: calc.due_date).count
  end

  def next_due_date
    anchored_budgets.map { |b| calculator_for(b).due_date }.min
  end

  # The earliest due date among the rules that actually own part of the lag. #amount
  # stays the pool-wide sum — the total is what the user has to make up — but the date
  # has to name a rule that contributed to it. Drawn from every anchored rule instead,
  # a pool behind on its March insurance would read "behind $385 · Feb 28" and send the
  # user to look at the gas envelope, which is perfectly on schedule.
  def lagging_due_date
    anchored_budgets.select { |b| behind_amount_for(b).positive? }
      .map { |b| calculator_for(b).due_date }
      .min
  end
end
