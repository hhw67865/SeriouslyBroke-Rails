# frozen_string_literal: true

# Computes what a single funding rule needs from the next period.
# See docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md §4.1-4.2
class BudgetCalculator
  attr_reader :budget, :today

  def initialize(budget, today: Date.current)
    @budget = budget
    @today = today
  end

  # `.to_d` is load-bearing. The `money` column casts to BigDecimal when it comes
  # back from Postgres, but an in-memory record assigned `amount: 180` keeps the
  # Integer — and `Integer / Integer` in #required truncates the cents (180/14 was
  # returning 12, not 12.86). A Float assignment is just as unwelcome in money math.
  def target = budget.amount.to_d

  # The cycle rolls when the bill is PAID, not when the date passes. Rolling on
  # the date alone would silently forget an obligation that was never settled.
  def due_date
    return period_end if budget.anchor_date.nil?
    return budget.anchor_date if budget.interval_months.nil?

    budget.anchor_date + (cycles_completed * budget.interval_months).months
  end

  # WHICH RULE COMES FIRST — the one place that key lives, and it decides more than an order.
  #
  # It picks the rule a row NAMES (`overdue $180 · Feb 1` rather than `· Feb 3`), the rule that
  # `allocated_balances` fills first and therefore the one that SLIPS when money leaves, and the
  # rule the reallocation screen calls the holder. It was written out four times over —
  # PoolCalculator#budgets_by_due_date, PoolStatus#anchored_budgets, HomePresenter#dated_rules_for,
  # DistributionPresenter#next_dated_rule and ReallocationPresenter#holder_for — which is the same
  # shape `ReallocationPresenter.source_order` was extracted out of one ruling ago.
  #
  # A TRIPLE, NOT A BARE DUE DATE, and every term earns its place: `sort_by`/`min_by` are not
  # stable and neither owner's `has_many :budgets` carries an ORDER BY, so two rules sharing a due
  # date could swap between page loads — the same holder reporting different #required figures with
  # no data change.
  # `-target` breaks that tie toward the larger obligation, because the bigger bill is the one you
  # can least afford to be short on; `budget.id` makes even identical amounts deterministic.
  #
  # `-target` rather than `-budget.amount`: identical ordering, and it keeps the money hazard out
  # of the key — an in-memory record assigned `amount: 180` holds the Integer, so the raw column
  # mixes Integer and BigDecimal across a comparison depending on where the row came from.
  #
  # `on:` is the due date when the caller has ALREADY computed it. #due_date re-runs
  # #paid_since_anchor's SUM on every call, and HomePresenter#dated_rules_for prints the date it
  # sorted by — asking twice would double that query for every dated rule on the screen.
  def due_order(on = due_date) = [on, -target, budget.id]

  # WHEN THIS RULE'S PERIOD ROLLS. A per-period rule's rolls on the user's own cadence boundaries;
  # a MONTHLY-basis rate rule's rolls on the CALENDAR MONTH, and that is not the frame
  # `Budget#steady_ask` uses for the same rule.
  #
  # TWO FRAMES, DELIBERATELY (plan 2d decision 5, recorded here and in `Budget#steady_ask`). A
  # $260-a-month rule under a biweekly cadence COSTS $120 a period — `steady_ask` divides by
  # `periods_per_year`, because 26 periods a year is what biweekly means and the answer must not
  # depend on which month you ask in. Its LIFECYCLE is a different question: the month is the span
  # the user said the money is for, so the period containing `today` ends when that month does,
  # and `PoolCalculator#period_closed?` may not sweep the envelope's leftover before it.
  #
  # They are different questions — what does it claim per period, versus when is the span it
  # claimed for over — so two answers is right and unifying them would be one wrong answer to
  # both. Normalising the lifecycle by `periods_per_year` would end a monthly rule's period
  # mid-month and sweep money the rule still expects to cover the rest of it; measuring the cost
  # by the calendar month made a standing rate swing 50% between months holding two boundaries and
  # months holding three, which is the defect `steady_ask` exists to close.
  def period_end
    budget.basis_per_period? ? boundary_period_end : today.end_of_month
  end

  # The payment signal is the amount paid, never the number of entries. Counting
  # rows treats a $1 payment and a $500 payment as the same event: a partial
  # payment would retire the whole obligation, and a bill settled in two
  # instalments would roll two cycles instead of one.
  # Without an anchor there is no window to sum over: `where(date: nil..)` imposes
  # no bound at all, so this would report every entry ever recorded against the
  # item as payment toward the current cycle. A wrong answer, not an exception —
  # and this is public API, reachable without going through #cycles_completed.
  def paid_since_anchor
    return 0.to_d if budget.item.nil? || budget.anchor_date.nil?

    budget.item.entries.where(date: budget.anchor_date..).sum(:amount).to_d
  end

  # Zero for an anchorless rule: with no anchor there is no cycle to have
  # completed. This early return is strictly redundant twice over — #elapsed_cycles
  # is already 0 without an anchor so the `min` floors the result at 0, and
  # #paid_since_anchor now guards the nil anchor itself — but it states the rule
  # directly at the point the rule applies.
  #
  # The `min` keeps a prepayment from rolling a cycle that has not yet come due,
  # erring in the same conservative direction as #elapsed_cycles itself.
  def cycles_completed
    return 0 if budget.anchor_date.nil?
    return elapsed_cycles if budget.item.nil?
    # Nothing is owed, so nothing can be outstanding. `positive?`, not `zero?`:
    # Budget now validates amount > 0, but a row written past that validation would
    # divide by zero here, and a negative gives a negative quotient — `floor` rounds
    # toward -infinity and `min` only clamps downward, which would roll due_date back
    # past its anchor. Same reasoning as PoolCalculator's defensive clamp.
    return elapsed_cycles unless target.positive?

    [(paid_since_anchor / target).floor, elapsed_cycles].min
  end

  # How many occurrences of this bill have already come due, regardless of what
  # was recorded. Once today reaches the anchor, one occurrence has passed — so
  # this is (whole intervals elapsed) + 1, never a bare division.
  #
  # Zero where the concept does not apply — no anchor to count from, or no
  # interval to divide by. Both are unreachable through #due_date, which guards
  # on the same nils, but this is public API and must answer rather than raise.
  def elapsed_cycles
    return 0 if budget.anchor_date.nil? || budget.interval_months.nil?
    return 0 if today < budget.anchor_date

    (months_since_anchor / budget.interval_months) + 1
  end

  # A one-time rule is the only shape with no next occurrence to roll into, so
  # being done cannot be read off its schedule the way a recurring rule's can.
  # It needs a separate axis, or a settled bill bills the user forever.
  def one_time? = budget.anchor_date.present? && budget.interval_months.nil?

  # An item is a real fulfillment signal, and the test is the amount paid, not
  # that *something* was paid — a $100 entry against a $500 bill leaves $400 owed.
  # Without an item we fall back to the same "assume paid on time" reading that
  # anchored no-item rules already get.
  def fulfilled?
    return false unless one_time?

    budget.item ? paid_since_anchor >= target : today >= budget.anchor_date
  end

  # The `item.present?` check is belt-and-braces: no reachable shape can now
  # satisfy `due_date < today` without an item. Anchorless rules end at or after
  # today, a recurring rule's due date always rolls past today, and a one-time
  # rule with a past anchor is caught by #fulfilled? above. Kept because "no
  # fulfillment signal means never late" is the rule being expressed, and the
  # alternative is leaning on a non-local invariant three shapes away.
  def overdue?
    return false if fulfilled?

    budget.item.present? && due_date < today
  end

  # A settled rule has no funding gap, so this reports zero rather than a raw
  # `target - allocated`. Both this and #required are public and Home renders
  # either; a paid bill showing "$500 still needed" is the same lie in reverse.
  #
  # `0.to_d` rather than a bare `0`: on the overfunded path `max` returns the
  # literal it was given, and an Integer leaking out here made #required's return
  # type depend on whether the rule happened to be funded.
  def shortfall(allocated)
    return 0.to_d if fulfilled?

    [target - allocated, 0.to_d].max
  end

  def periods_until_due
    [user.period_boundaries(from: today, to: due_date).count, 1].max
  end

  # Fulfillment short-circuits scheduling: #due_date still reports the anchor,
  # because a one-time rule genuinely never rolls, but a settled obligation must
  # stop asking for money regardless of how its date compares to today. That gate
  # lives in #shortfall alone — duplicating it here would leave two guards where
  # neither can be shown to matter.
  def required(allocated)
    (shortfall(allocated) / periods_until_due).round(2)
  end

  private

  # Budget#user resolves in both category and pool mode, so this never nils out.
  def user = budget.user

  # Whole calendar months from the anchor to today, backing off one when today
  # has not yet reached the anchor's day of the month — Dec 1 is not yet a full
  # six months past a Jun 15 anchor, and counting it would roll the bill early.
  def months_since_anchor
    anchor = budget.anchor_date
    months = ((today.year * 12) + today.month) - ((anchor.year * 12) + anchor.month)
    today.day < anchor.day ? months - 1 : months
  end

  # The per-period-basis branch of #period_end: the day before the user's next declared
  # boundary. Named for what it computes, not for its return type — a bare `_date` suffix
  # would only restate that #period_end returns a Date too, and leave the two names
  # indistinguishable at the call site.
  def boundary_period_end
    next_boundary = user.period_boundaries(from: today + 1, to: today + 45).first
    next_boundary ? next_boundary - 1 : today.end_of_month
  end
end
