# frozen_string_literal: true

# One rule's claim, as every screen says it. Every member comes off ONE ClaimCalculator, from one
# ClaimLedger, so a row cannot pair one rule's figure with another's state.
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

  # Money saved up toward a day — a bill or a goal, which are one shape.
  def dated? = shape == :dated

  # An allowance that keeps what it doesn't spend: it walks like a dated rule and asks like a rate
  # one, and it aims at nothing, so #target is nil and there is no bar.
  def fund? = shape == :fund

  def anchored? = next_due_on.present?

  # Which vocabulary the adjust panel speaks. A fund takes the per-period words even though it walks
  # like a dated rule, because it arrives and is spent every period.
  def allowance? = rate? || fund?

  delegate :rule_type, to: :rule

  # Spent past what the rule had — the figure read BEFORE the clamp at zero, so this can tell "spent
  # it exactly" from "spent more than there was".
  def over? = over

  def overdue? = overdue

  def paid? = paid

  # A paid one-off is never short and never overdue, but an overspend survives the payment: the
  # excess left checking and no rule reserved it.
  def trouble? = over? || overdue?

  # Is the money for this occurrence there, or not? A paid one-off is never short — paying empties
  # the fund, so built_up < target is true of every settled one.
  def fund_short? = dated? && !paid? && built_up < target

  def fund_gap = dated? ? target - built_up : 0.to_d

  # What the bar measures: spending against the rate for a rate rule, the running total against the
  # target for a dated one.
  def filled = rate? ? spent : built_up

  # This period's accrual for a rate rule, the target for a dated one, and nothing at all for a
  # fund, which is aiming at no figure.
  def denominator = rate? ? accrued : target

  # A bar needs something to be a fraction of. Every caller of #percent and #bar_state is gated here.
  def bar? = denominator.present? && denominator.positive?

  def percent
    return 0 unless bar?

    ((filled / denominator) * 100).round.clamp(0, 100)
  end

  # Which colour the stripe is: the RULE's type, never the category's.
  def stripe_type = rule.rule_type.to_sym

  # Which lane of the category this rule pays for: the item it names, or everything no other rule
  # claims.
  def name = rule.item&.name || ClaimLine::WHOLE_CATEGORY

  # The money is not all there and the day is here or gone — two facts, and both are needed: a goal
  # due in 2027 is accruing rather than short.
  def short? = fund_short? && (due_this_period || overdue?)

  # What the bar is saying. `over` first, because an over-spent rate rule is also a full one and the
  # news is the excess.
  def bar_state
    return :over if over?
    return :short if short?
    return :full if bar? && filled >= denominator

    :normal
  end

  # A skip means "accrue nothing this period", so the button has a job only while the period is
  # still accruing something — and #accrued is the post-adjustment figure while #per_period is not.
  def skippable? = !rate? && accrued.positive?
end

# What an item-less rule is called on a row. Outside the block, because Lint/ConstantDefinitionInBlock
# will not have it inside one.
ClaimLine::WHOLE_CATEGORY = "Whole category"
