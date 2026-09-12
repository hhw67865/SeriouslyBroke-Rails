# frozen_string_literal: true

# The rule form's preview card: the rule said back, and the arithmetic under it, off ONE
# ClaimCalculator so the card cannot pair one rule's figure with another's state.
class RulePreview
  attr_reader :rule_form, :user, :today

  def initialize(rule_form, user:, today: user.today)
    @rule_form = rule_form
    @user = user
    @today = today
  end

  # The unsaved (or in-edit) record the words have already been applied to — RuleForm assigns them
  # in its constructor, so this is the rule these words describe on every path.
  delegate :rule, to: :rule_form

  def ready? = missing.empty?

  # What the card says instead of a figure. A blank is not a refusal: nothing has been submitted,
  # and "Pick a date." is the sentence a preview owes a half-filled form.
  def missing
    @missing ||= [
      missing_owner, missing_amount, missing_item, missing_date, missing_interval, missing_type
    ].compact
  end

  def missing_owner = ("Pick the category this rule is for." if rule.category.blank?)

  def missing_amount = ("Fill in an amount." unless amount.positive?)

  # An item from another category is a rule the save will refuse, and the card must not price it.
  def missing_item
    return nil if rule.item.blank? || rule.item.category_id == rule.category_id

    "Pick an item in #{rule.category&.name}."
  end

  def missing_date = ("Pick a date." if by_date? && rule.anchor_date.blank?)

  def missing_interval
    "Say how many months it comes round in." if rule_form.repeats? && rule.interval_months.blank?
  end

  def missing_type = ("Choose what kind of rule this is." if rule_form.rule_type.blank?)

  # A decimal column casts anything unparseable to 0, which is what "Fill in an amount." is for.
  def amount = rule.amount.to_d

  def by_date? = rule_form.schedule == "by_date"

  delegate :rate?, :fund?, to: :line

  def repeating? = line.dated? && rule.interval_months.present?

  delegate :ask, :periods_left, :built_up, to: :calculator

  delegate :next_due_on, to: :line

  # The row Home will draw, built the way Home builds it.
  def line
    @line ||= ClaimRows.line_for(rule, calculator, period_range: period_range)
  end

  private

  def calculator = @calculator ||= rule.claim_calculator(today: today, spending: lanes, adjustments: lanes)

  # `[]` for a rule that does not exist yet: the spending it would read is the category's, which is
  # a fact about today's receipts. An edit gets `nil` — its own history is what the card is about.
  def lanes = rule.new_record? ? [] : nil

  def period_range = @period_range ||= ClaimRows.period_range_for(user, today)
end
