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
               else
                 quiet_state
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

  # What the goal is, for the one state measured against one. Zero where the concept does not
  # apply: an account's target is a buffer marker and a budget envelope's is a display marker,
  # and neither is a thing being saved toward.
  #
  # `.to_d`, not the raw column — `target_amount` is nil on every pool that is not a savings
  # pool, and this is read straight into a currency helper.
  def target = pool.target_amount.to_d

  def needs_attention? = ATTENTION_STATES.include?(state)

  private

  # The tail of the same precedence chain: what a pool with no live problem is doing. Split
  # out only because the seventh state pushed #state past rubocop's complexity limit — the
  # order here is as load-bearing as the order above it, and :saving must stay first.
  def quiet_state
    return :saving if saving?
    return :left_to_spend if anchored_budgets.empty?

    :on_track
  end

  # The seventh state's guard, and the reason it sits immediately above :left_to_spend.
  #
  # A savings pool with no dated rule could previously reach NO state but :left_to_spend —
  # every state above it needs an anchored rule, and that branch is the fall-through for
  # having none — so a vacation fund rendered "$424.00 left". That is a spendable number for
  # money that is not spendable, which inverts the design's second principle on every savings
  # row at once.
  #
  # Placed BELOW the four attention states on purpose: a goal $50 in the red is overdrawn
  # first and saving second. Placed ABOVE :left_to_spend because both guards hold for exactly
  # this pool — after it, this could never fire at all.
  #
  # Dateless only. A savings pool that names an anchor has a deadline, and the anchored maths
  # already spreads it across the periods remaining; that vocabulary keeps winning.
  #
  # Close to PoolCalculator#dateless_goal? but deliberately NOT the same condition: that one
  # adds `target_amount.to_d.positive?`, because it divides toward a target and a goal of zero
  # would have it ask for money forever. This is a display state, and a savings pool with no
  # target set is still saving — it renders "$424.00 saved" instead of progress toward a
  # figure that does not exist. Changing either side does not automatically change the other.
  def saving? = pool.pool_type_savings? && anchored_budgets.empty?

  def pool_calculator = @pool_calculator ||= pool.calculator(today: today)

  # Memoized per rule. BudgetCalculator#due_date re-runs the paid_since_anchor SUM every
  # time it is asked, and a single #state + #due_on asks several times per rule — six
  # identical SELECT SUMs per rule, per pool, on the one screen this class exists to render.
  def calculator_for(budget)
    (@calculators ||= {})[budget] ||= budget.calculator(today: today)
  end

  # Sorted, not raw. `has_many :budgets` carries no ORDER BY, so the "first match" that
  # #overdue_budget and #unreachable_budget take would be whatever order Postgres happened
  # to hand back — a Utilities envelope with water due Feb 1 and electric due Feb 3, both
  # unpaid, reading `overdue $X · Feb 1` or `overdue $Y · Feb 3` at random between page
  # loads with no data change.
  #
  # Same key and same reasoning as PoolCalculator#budgets_by_due_date, which already guards
  # this: earliest due date first, because the most urgent rule is the one worth naming;
  # `-amount` breaks a tie toward the larger obligation; `id` makes even identical rows
  # deterministic. The brief mandates a singular rule, so which one it is has to be stable.
  def anchored_budgets
    @anchored_budgets ||= pool.budgets.select { |b| b.anchor_date.present? }
      .sort_by { |b| [calculator_for(b).due_date, -b.amount, b.id] }
  end

  def overdue_budget
    return @overdue_budget if defined?(@overdue_budget)

    @overdue_budget = anchored_budgets.find { |b| calculator_for(b).overdue? }
  end

  # A rule nothing can save: it still has a shortfall and no period boundary
  # falls between today and its due date, so no future funding can reach it.
  #
  # The window is deliberately asymmetric — `today + 1` on one side, the due date
  # included on the other — because the two sides answer different questions.
  #
  # The `to` side asks *will money arrive in time to pay this?*, so a boundary landing on
  # the due date counts: you distribute that morning and pay the bill that day.
  #
  # The `from` side asks *can any FUTURE period help spread this?*, and today's
  # distribution is the one being looked at right now. If nothing falls between tomorrow
  # and the due date, the bill cannot be smoothed and has to be funded now or not at all
  # — which is the entire signal :wont_make_it exists to give. Using `today` here would
  # collapse that: a $300 bill due Feb 14 with boundaries on Feb 6 and Feb 20 would read
  # as comfortably fundable, hiding that today is the only chance to fund it.
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
  #
  # `target * (cycles_completed + 1)`, never a bare `target`. The two sides have to be
  # on the same basis: #paid_since_anchor is CUMULATIVE across every cycle since the
  # anchor, while #target is ONE cycle's worth, so subtracting them only lines up while
  # cycles_completed is 0. On a $600 six-monthly bill with cycle 1 paid and cycle 2
  # overdue and untouched, `target - paid` is `600 - 600` and reports $0 owed on a bill
  # owed in full — and $0 reads as settled. Total owed through the current cycle against
  # total ever paid is the comparison that holds for every cycle.
  def overdue_amount
    calc = calculator_for(overdue_budget)
    [(calc.target * (calc.cycles_completed + 1)) - calc.paid_since_anchor, 0.to_d].max
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
