# frozen_string_literal: true

# Writes one adjustment on a rule from the adjust panel: a signed amount on a date, or a skip,
# which is minus whatever accrued this period. Dates outside what the rule counts are refused.
class AdjustmentForm
  DAY = "%b %-d"

  attr_reader :rule, :name, :today, :calculator, :adjustment

  def initialize(rule:, params:, name:, today: rule.today)
    @rule = rule
    @params = params
    @name = name
    @today = today
    @calculator = rule.claim_calculator(today: today)
    @adjustment = rule.adjustments.new(amount: amount, date: chosen_date)
  end

  def save
    return false unless acceptable?

    adjustment.save
  end

  def error_sentence = adjustment.errors.full_messages.to_sentence
  def skip? = @params[:skip].present?

  delegate :rate?, :allowance?, to: :calculator

  private

  def acceptable?
    add_refusal
    adjustment.errors.empty?
  end

  def add_refusal
    return adjustment.errors.add(:base, nothing_to_skip_sentence) if nothing_to_skip?
    return unless adjustment.valid?

    refusal = date_refusal
    adjustment.errors.add(:base, refusal) if refusal
  end

  def date_refusal
    return not_counting_yet if countable_span.none?
    return if countable_span.cover?(adjustment.date)

    out_of_reach
  end

  def nothing_to_skip_sentence = "#{name} isn't accruing anything this period, so there's nothing to skip."
  def not_counting_yet = "#{name} hasn't started counting yet, so there's nothing to adjust."
  def nothing_to_skip? = skip? && !calculator.accrued_this_period.positive?
  def countable_span = @countable_span ||= calculator.countable_span

  def out_of_reach
    "#{name} #{reach_clause} — pick a date between " \
      "#{countable_span.first.strftime(DAY)} and #{countable_span.last.strftime(DAY)}."
  end

  def reach_clause
    return "counts this period only, up to today" if rate?

    "counts dates from when it started building, up to today"
  end

  def amount
    return -calculator.accrued_this_period if skip?
    return -@params[:amount].to_s.to_d.abs if @params[:amount_sign].to_i.negative?

    @params[:amount]
  end

  def chosen_date
    return today if skip?

    @params[:date].presence || today
  end
end
