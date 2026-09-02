# frozen_string_literal: true

# Reduces a category to exactly one display state. Every row's wording, colour and auto-expand
# behaviour derives from here, so the precedence order below is the single place that decision
# lives.
#
# THE PORT OF `PoolStatus` (two-ledger Task 3): the same six-state vocabulary in the same order,
# reading a category's holdings where it read an envelope's balance.
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §4.4
class HoldingStatus
  ATTENTION_STATES = [:overdrawn, :overdue, :wont_make_it, :behind].freeze

  # THE STATES WHOSE #amount IS ABOUT A BILL RATHER THAN ABOUT THIS CATEGORY'S OWN MONEY — exactly
  # the three arms of #amount that do not read #balance. Here beside ATTENTION_STATES, and for the
  # same reason it is: a caller that has to know which states print the category's money is asking a
  # question about this class's #amount, and a hand copy of the case statement below would be a
  # second reader free to drift from it.
  BILL_STATES = [:overdue, :wont_make_it, :behind].freeze

  attr_reader :category, :today

  # `pending:` is HoldingProjection's, passed straight down and never read here — see #calculator.
  # Every state this class decides is a reading of the balance or of what the balance leaves a rule
  # holding, so adjusting the balance is the whole of what "how would this category be doing if the
  # distribution on screen went through" means. :wont_make_it in particular is exactly that
  # question: a rule with a shortfall and no boundary left before its due date, where the shortfall
  # is what the funding did or did not close.
  #
  # `terms:` is HoldingCalculator's, passed straight down and never read here either — a status is a
  # reading of a balance, and this only changes who ran the queries that balance is made of. It
  # defaults to nothing, so a status built anywhere else is untouched.
  #
  # IT IS HERE BECAUSE THE MEASUREMENT PUT IT HERE on the pool side: a screen renders a status for
  # every holder it lists, each building a calculator of its own, and leaving this class out of the
  # batching would have batched only the cheaper half of every screen.
  def initialize(category, today: Date.current, pending: HoldingProjection::Pending.none, terms: nil)
    @category = category
    @today = today
    @pending = pending
    @terms = terms
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

  # Through #calculator, not a second `category.holding_calculator` — one object per status, so a
  # single #state call runs the balance queries once and the two figures cannot disagree.
  def balance = @balance ||= calculator.balance

  # What the goal is, for the one state measured against one. Zero where the concept does not apply:
  # an envelope names no target, and a target is not a thing being saved toward unless somebody set
  # one.
  #
  # `.to_d`, not the raw column — `target_amount` is nil on every category that is not a goal, and
  # this is read straight into a currency helper.
  def target = category.target_amount.to_d

  def needs_attention? = ATTENTION_STATES.include?(state)

  # IS #amount A READING OF THIS CATEGORY'S BALANCE? True in four of the seven states — the balance
  # itself in three and its negation on :overdrawn — and false in the three whose figure is a bill's
  # shortfall. A row that prints the label AND the balance needs this to know whether it is about to
  # print one number twice; that is a question about #amount, so it is answered here.
  def amount_is_balance? = BILL_STATES.exclude?(state)

  # WHICH PERIOD THE FIGURE BELONGS TO, off the calculator this class already holds — never a second
  # calculator, which would run #last_funded_on's aggregate against an object free to disagree with
  # the one #balance came from.
  #
  # Here rather than on each presenter because the ` · last period` suffix rides on a status, and
  # every screen that prints a status owes the reader the same suffix: a swept rate-rule envelope
  # reading `$400.00 left · last period` on one screen and `$400.00 left` on another is two screens
  # describing one category differently on the same afternoon.
  delegate :period_closed?, to: :calculator

  # WHAT MOVING MONEY IN WOULD ACTUALLY CLOSE, which is not always #amount.
  #
  # #amount is the figure the STATE is about — the number the row prints. This is the figure an
  # ACTION is about, and the two differ on exactly one state, because :overdue is the one state that
  # is not a reading of the balance at all. It fires on a DATE and a missing payment, so its amount
  # is the bill's unpaid remainder: a category holding every penny of a $180 premium that simply has
  # not been paid yet reads `overdue · was Aug 10` and reports `amount` $180, while the money is
  # sitting right there. Offering to move $180 into it would invite a real mistake to fix an
  # imaginary problem. What that bill needs is paying, not funding, and #shortfall_for says so by
  # returning zero.
  #
  # The other three attention states coincide with #amount by construction and are NOT re-derived
  # here: :overdrawn is `-balance`, :wont_make_it is already `shortfall_for(unreachable_budget)`,
  # and :behind is `expected - allocated`. Only the divergence is written down.
  #
  # Zero for every quiet state, so a caller cannot mistake a healthy category's BALANCE (which
  # #amount returns there) for a gap.
  def funding_gap
    return 0.to_d unless needs_attention?
    return shortfall_for(overdue_budget) if state == :overdue

    amount
  end

  private

  # The tail of the same precedence chain: what a category with no live problem is doing. Split out
  # only because the seventh state pushed #state past rubocop's complexity limit — the order here is
  # as load-bearing as the order above it, and :saving must stay first.
  def quiet_state
    return :saving if saving?
    return :left_to_spend if anchored_budgets.empty?

    :on_track
  end

  # The seventh state's guard, and the reason it sits immediately above :left_to_spend.
  #
  # A goal with no dated rule could otherwise reach NO state but :left_to_spend — every state above
  # it needs an anchored rule, and that branch is the fall-through for having none — so a vacation
  # fund rendered "$424.00 left". That is a spendable number for money that is not spendable, which
  # inverts the design's second principle on every savings row at once.
  #
  # Placed BELOW the four attention states on purpose: a goal $50 in the red is overdrawn first and
  # saving second. Placed ABOVE :left_to_spend because both guards hold for exactly this category —
  # after it, this could never fire at all.
  #
  # THE TARGET IS THE QUESTION, NOT `Category#savings?`, and for HoldingCalculator#dateless_goal?'s
  # reason (its comment carries the whole argument): `savings?` additionally requires the category
  # to carry NO RULE, so a goal refilled at a rate — the demo's Retirement Supplement — would fall
  # through to :left_to_spend and render its retirement balance as money to spend, which is the very
  # defect this state was carved out to fix.
  #
  # IT IS THE CALCULATOR'S OWN CONDITION, ASKED RATHER THAN RESTATED (fix round 1, LOW-2). This read
  # `target_amount.to_d.positive? && anchored_budgets.empty?`, which is #dateless_goal? with the
  # `holder?` leg missing — a second spelling of one question, and one that answered differently for
  # a target-bearing category that has never been funded. Its pool-era ancestor was allowed to
  # differ because it asked a TYPE while the calculator asked a target; with the type gone both ask
  # the target, so the honest thing is one predicate with one reader of it.
  #
  # The two legs still mean what they meant here: a goal with a deadline keeps the anchored
  # vocabulary (that is #dateless_goal?'s dateless leg), and a category holding nothing is not
  # saving (its `holder?` leg). Asked off the memoised calculator this class already holds, so it
  # costs no query of its own.
  def saving? = calculator.dateless_goal?

  def calculator
    @calculator ||= category.holding_calculator(today: today, pending: @pending, terms: @terms)
  end

  # Memoized per rule. BudgetCalculator#due_date re-runs the paid_since_anchor SUM every time it is
  # asked, and a single #state + #due_on asks several times per rule — six identical SELECT SUMs per
  # rule, per category, on the screens this class exists to render.
  def calculator_for(budget)
    (@calculators ||= {})[budget] ||= budget.calculator(today: today)
  end

  # Sorted, not raw. `has_many :budgets` carries no ORDER BY, so the "first match" that
  # #overdue_budget and #unreachable_budget take would be whatever order Postgres happened to hand
  # back — a Utilities category with water due Feb 1 and electric due Feb 3, both unpaid, reading
  # `overdue $X · Feb 1` or `overdue $Y · Feb 3` at random between page loads with no data change.
  #
  # Same key as HoldingCalculator#budgets_by_due_date, because it IS that key:
  # BudgetCalculator#due_order, asked of the memoised calculator this class already holds. Earliest
  # due date first, because the most urgent rule is the one worth naming.
  def anchored_budgets
    @anchored_budgets ||= category.budgets.select { |b| b.anchor_date.present? }
      .sort_by { |b| calculator_for(b).due_order }
  end

  def overdue_budget
    return @overdue_budget if defined?(@overdue_budget)

    @overdue_budget = anchored_budgets.find { |b| calculator_for(b).overdue? }
  end

  # A rule nothing can save: it still has a shortfall and no period boundary falls between today and
  # its due date, so no future funding can reach it.
  #
  # The window is deliberately asymmetric — `today + 1` on one side, the due date included on the
  # other — because the two sides answer different questions.
  #
  # The `to` side asks *will money arrive in time to pay this?*, so a boundary landing on the due
  # date counts: you distribute that morning and pay the bill that day.
  #
  # The `from` side asks *can any FUTURE period help spread this?*, and today's distribution is the
  # one being looked at right now. If nothing falls between tomorrow and the due date, the bill
  # cannot be smoothed and has to be funded now or not at all — which is the entire signal
  # :wont_make_it exists to give.
  def unreachable_budget
    return @unreachable_budget if defined?(@unreachable_budget)

    @unreachable_budget = anchored_budgets.find do |budget|
      calc = calculator_for(budget)
      next false unless shortfall_for(budget).positive?

      category.user.period_boundaries(from: today + 1, to: calc.due_date).empty?
    end
  end

  def shortfall_for(budget)
    calculator_for(budget).shortfall(calculator.allocated_balances[budget] || 0.to_d)
  end

  # The unpaid remainder, not the rule's face value: a $600 bill with $400 already recorded against
  # its item is $200 outstanding, and reporting $600 overstates by exactly what the user has paid.
  # Reuses BudgetCalculator's own payment signal rather than re-querying the item's entries here.
  #
  # `target * (cycles_completed + 1)`, never a bare `target`. The two sides have to be on the same
  # basis: #paid_since_anchor is CUMULATIVE across every cycle since the anchor, while #target is
  # ONE cycle's worth, so subtracting them only lines up while cycles_completed is 0. On a $600
  # six-monthly bill with cycle 1 paid and cycle 2 overdue and untouched, `target - paid` is `600 -
  # 600` and reports $0 owed on a bill owed in full — and $0 reads as settled.
  def overdue_amount
    calc = calculator_for(overdue_budget)
    [(calc.target * (calc.cycles_completed + 1)) - calc.paid_since_anchor, 0.to_d].max
  end

  # How far below a steady schedule this category is. A rule with N periods in its full cycle and R
  # remaining should hold amount * (N - R) / N by now. Summed over anchored rules only, which is
  # what makes the :behind branch and the :left_to_spend branch below it mutually exclusive: with no
  # anchored rules there is nothing to sum and this is the seed, 0.
  def behind_amount
    @behind_amount ||= anchored_budgets.sum(0.to_d) { |budget| behind_amount_for(budget) }
  end

  # Zero where a steady schedule is not a concept: a one-time rule has no interval to spread over,
  # and a user with no cadence declared has no boundaries in the window. Both make #periods_in_cycle
  # zero, and both reach the division below without this.
  def behind_amount_for(budget)
    total = periods_in_cycle(budget)
    return 0.to_d unless total.positive?

    remaining = calculator_for(budget).periods_until_due
    expected = budget.amount.to_d * [total - remaining, 0].max / total
    allocated = calculator.allocated_balances[budget] || 0.to_d
    [expected - allocated, 0.to_d].max
  end

  def periods_in_cycle(budget)
    return 0 if budget.interval_months.blank?

    calc = calculator_for(budget)
    category.user.period_boundaries(from: calc.due_date - budget.interval_months.months, to: calc.due_date).count
  end

  def next_due_date
    anchored_budgets.map { |b| calculator_for(b).due_date }.min
  end

  # The earliest due date among the rules that actually own part of the lag. #amount stays the
  # category-wide sum — the total is what the user has to make up — but the date has to name a rule
  # that contributed to it. Drawn from every anchored rule instead, a category behind on its March
  # insurance would read "behind $385 · Feb 28" and send the user to look at the gas rule, which is
  # perfectly on schedule.
  def lagging_due_date
    anchored_budgets.select { |b| behind_amount_for(b).positive? }
      .map { |b| calculator_for(b).due_date }
      .min
  end
end
