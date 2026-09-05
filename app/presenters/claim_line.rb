# frozen_string_literal: true

# ** ONE RULE'S CLAIM, AS EVERY SCREEN SAYS IT (computed-claims spec §3.4, two-shapes spec §3). **
# Every member comes off ONE `ClaimCalculator`, from one `ClaimLedger`, so a row cannot pair one
# rule's figure with another's state and cannot cost a walk of its own.
#
# ** IT WAS THREE OBJECTS AND IT IS ONE (this task's carry (b)). ** `HomePresenter::ClaimLine`,
# `BudgetPagePresenter::Rule` and `CategoryBudgetPresenter::Line` were three Data types with the
# same members under three names, and each of their files carried a comment saying the other two had
# to be kept in step by hand. They were not: Home said `$450.00 of $1,200.00` where the other two
# said `$450.00 built up of $1,200.00`, off two helpers (`HomeHelper#figure_words` and
# `#claim_figure`) that were the same sentence with a different noun in it. One row type, one set of
# words (`HomeHelper#shape_words` / `#figure_words` / `#when_words`), three screens.
#
# `shape` RATHER THAN A BOOLEAN, because §3.4 gives the two shapes two different sentences and the
# classification lives in exactly one place (`ClaimCalculator#shape`).
#
# ** THE FIVE MEMBERS THAT ARE NOT THE CALCULATOR'S ARE THE CONTEXT IT CANNOT KNOW. ** `category` is
# the rule's owner; `due_this_period` and `resets_on` are read against the PAGE's period window;
# `adjustments` is this period's delta rows, which only the Budget page fetches (`[]` everywhere
# else — an empty array is an answer, not a gap). Each is a member rather than a derivation for one
# reason: a Data object computing them would have to reach for a calendar or a query of its own,
# which is the one thing every reader on these screens is built to avoid.
#
ClaimLine = Data.define(
  :category,
  :rule,
  :shape,
  :claim,
  :spent,
  :accrued,
  :built_up,
  :target,
  :next_due_on,
  :per_period,
  :over,
  :over_by,
  :overdue,
  :paid,
  :paid_on,
  :due_this_period,
  :resets_on,
  :countable_span,
  :adjustments
) do
  def rate? = shape == :rate

  # MONEY SAVED UP TOWARD A DAY (two-shapes spec §2) — a bill or a goal, which are one shape.
  def dated? = shape == :dated

  def anchored? = next_due_on.present?

  # WHICH KIND OF RULE THIS IS — bill, usage or choice (rules-own-the-budget §3). Off the record
  # rather than a member: the dot beside the row and the type bar above the list are two readings of
  # one column.
  delegate :rule_type, to: :rule

  # SPENT PAST WHAT THE RULE HAD — `ClaimCalculator#over?`, which reads the figure BEFORE the clamp
  # at zero and is therefore the only reader that can tell "spent it exactly" from "spent more than
  # there was". Both leave a claim of zero (§3.1/§3.2).
  def over? = over

  # A DATE THAT PASSED WITH THE MONEY STILL MISSING (§3.2) — and never a PAID one-off, whose date
  # never rolls (`ClaimCalculator#overdue?`).
  def overdue? = overdue

  # ** THE ONE-OFF IS FINISHED (`ClaimCalculator#settled?`). ** A bill or a goal that has been paid
  # out is not short of anything and is not late: it is done, and `HomeHelper#when_words` says so
  # with the day it was done on. Only a one-time rule can be here — a repeating one always has a
  # next occurrence to fund.
  def paid? = paid

  def trouble? = over? || overdue?

  # ** IS THE MONEY FOR THIS OCCURRENCE THERE, OR NOT? ** What it is exactly right for is which
  # SENTENCE the strip says about a rule: "the fund is short $200.00 — this needs paying" is a
  # different instruction from "the money is set aside — pay it and the fund starts again".
  #
  # A PAID ONE-OFF IS NEVER SHORT, and the gate is here rather than in the arithmetic below: paying
  # the bill empties the fund, so `built_up < target` is true of every settled one-off there is —
  # the starkest possible reading of a rule that has nothing left to do.
  def fund_short? = dated? && !paid? && built_up < target

  def fund_gap = dated? ? target - built_up : 0.to_d

  # WHAT THE BAR MEASURES: spending against the rate for a rate rule, the running total against the
  # target for a dated one (§3.4). One pair of readers rather than a signed number, because the two
  # halves are read by different parts of the row.
  def filled = rate? ? spent : built_up

  # THIS PERIOD'S ACCRUAL FOR A RATE RULE, THE TARGET FOR A DATED ONE. Never nil since the two
  # shapes: the uncapped fund that had no figure to be a fraction of is retired (§7).
  def denominator = rate? ? accrued : target

  # A BAR NEEDS SOMETHING TO BE A FRACTION OF, and a rate rule skipped to nothing this period has
  # none — the row prints the fact and no track, `EntryImpactPresenter#bar?`'s rule for its reason.
  def bar? = denominator.positive?

  # WHOLE PERCENT, CLAMPED, matching `HomePresenter::Progress#percent` — the app's bars draw alike,
  # every one of them `style="width: <percent>%"`.
  def percent
    return 0 unless bar?

    ((filled / denominator) * 100).round.clamp(0, 100)
  end

  # WHICH COLOUR THE STRIPE (or the Budget list's dot) IS: the RULE's type, never the category's. A
  # category may carry a bill beside a choice, and the stripe is what says so at a glance.
  def stripe_type = rule.rule_type.to_sym

  # WHICH LANE OF THE CATEGORY THIS RULE PAYS FOR (§3.1's partition): the item it names, or
  # everything no other rule claims.
  def name = rule.item&.name || ClaimLine::WHOLE_CATEGORY

  # ** THE MONEY IS NOT ALL THERE AND THE DAY IS HERE OR GONE. ** Two facts, and both are needed:
  # `#fund_short?` alone is true of every goal that has not finished saving — a $5,000 target due in
  # 2027 is not "short", it is accruing — and the date alone is true of a bill whose money is
  # sitting ready. This is the pair the runway's tick colours split on, said once so the tick and
  # the row underneath it cannot disagree about one rule on one afternoon.
  def short? = fund_short? && (due_this_period || overdue?)

  # WHAT THE BAR IS SAYING (§3). `over` is spending past what the rule had; `short` is the state
  # above; `full` is a bar that has arrived — a fund at its target, or a rate rule spent to the
  # penny. `normal` is everything in progress.
  #
  # `over` FIRST, because an over-spent rate rule is also a full one and the news is the excess.
  def bar_state
    return :over if over?
    return :short if short?
    return :full if bar? && filled >= denominator

    :normal
  end

  # ** WHETHER A SKIP IS OFFERABLE, AND IT IS THE ACCRUAL THAT DECIDES (computed-claims fix round
  # MED-2). ** A skip means "accrue nothing this period", so the button has a job only while the
  # period is still accruing SOMETHING — and `#accrued` is the post-adjustment figure while
  # `#per_period` is not. Read off the plan, this offered a second skip on a period already skipped,
  # whose −planned would have been a raid on the rule's prior savings under a flash saying the
  # period was skipped. `AdjustmentForm` is the backstop for a submission that arrives anyway.
  def skippable? = !rate? && accrued.positive?
end

# WHAT AN ITEM-LESS RULE IS CALLED ON A ROW (two-shapes spec §3, and the rule form's own words —
# §5: "the whole category" means "anything in <category> no other rule pays"). It is NOT
# `HomeHelper#pool_rule_label`, which names such a rule by its SHAPE ("Per period", "One-off"): a
# row already prints the shape in its own clause, so the shape said twice would displace the one
# thing the row is missing — which lane of the category this rule is about.
#
# OUTSIDE THE BLOCK, and read through the type — `Lint/ConstantDefinitionInBlock` will not have it
# inside one, and `Style/DataInheritance` forbids the `class X < Data.define(…)` form that would
# have given it a lexical home. `HomePresenter` hoisted the same constant out of the same block for
# the same reason before this class existed.
ClaimLine::WHOLE_CATEGORY = "Whole category"
