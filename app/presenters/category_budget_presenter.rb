# frozen_string_literal: true

# The holdings card on a category's page and the claim figure on its index card.
class CategoryBudgetPresenter
  attr_reader :category, :today

  def initialize(category:, claims:, rows:, today: category.user.today)
    @category = category
    @claims = claims
    @claim_rows = rows
    @today = today
  end

  def ruled? = lines.any?
  def lines = @claim_rows.lines_for(category)
  def rules = lines.map(&:rule)
  def claim = lines.sum(0.to_d, &:claim)
  def needs_attention? = lines.any?(&:trouble?)
  def fund? = fund_line.present?

  # A goal: a ONE-OFF dated rule that is not a bill, item-backed or not. A rule that repeats is a
  # recurring cost rather than a figure being saved toward, so it gets a plain rule line.
  def fund_line
    return @fund_line if defined?(@fund_line)

    @fund_line = lines.detect { |line| line.dated? && !line.rule.bill? && line.rule.interval_months.nil? }
  end

  def fund_rule = fund_line&.rule
  def fund_is_the_only_rule? = rules.one? && fund?
  def fund_figure = fund_line&.built_up

  def target
    return nil unless fund_is_the_only_rule?

    fund_line.target
  end

  def progress_percentage
    return 0 unless bar?

    (fund_figure / target * 100).round.clamp(0, 100)
  end

  def bar? = target&.positive? || false
end
