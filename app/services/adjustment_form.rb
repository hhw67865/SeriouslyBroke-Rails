# frozen_string_literal: true

# Writes one adjustment on a claim source — a rule or a savings account — from its adjust panel: a
# signed amount on a date, or a skip, which is minus whatever accrued this period. Dates outside
# what the source counts are refused; an account only ever reduces.
class AdjustmentForm
  DAY = "%b %-d"

  attr_reader :source, :name, :today, :calculator, :adjustment

  def initialize(source:, params:, name:, today: source.user.today)
    @source = source
    @params = params
    @name = name
    @today = today
    @calculator = source.claim_calculator(today: today)
    @adjustment = source.adjustments.new(amount: amount, date: chosen_date)
  end

  def save
    return false unless acceptable?

    adjustment.save
  end

  def error_sentence = adjustment.errors.full_messages.to_sentence
  def skip? = @params[:skip].present?
  def savings? = source.is_a?(Account)
  def rate? = !savings? && calculator.rate?
  def allowance? = !savings? && calculator.allowance?

  private

  def acceptable?
    add_refusal
    adjustment.errors.empty?
  end

  def add_refusal
    return if add_amount_refusal
    return unless adjustment.valid?

    refusal = date_refusal
    adjustment.errors.add(:base, refusal) if refusal
  end

  def add_amount_refusal
    return adjustment.errors.add(:base, nothing_to_skip_sentence) if nothing_to_skip?
    return adjustment.errors.add(:base, nothing_to_top_up_sentence) if savings? && adjustment.amount.to_d.positive?

    false
  end

  def date_refusal
    return not_counting_yet if countable_span.none?
    return if countable_span.cover?(adjustment.date)

    out_of_reach
  end

  def nothing_to_skip_sentence = "#{name} isn't accruing anything this period, so there's nothing to skip."
  def nothing_to_top_up_sentence = "#{name} can take more any time — there's nothing to top up."
  def not_counting_yet = "#{name} hasn't started counting yet, so there's nothing to adjust."
  def nothing_to_skip? = skip? && !calculator.accrued_this_period.positive?
  def countable_span = @countable_span ||= calculator.countable_span

  def out_of_reach
    "#{name} #{reach_clause} — pick a date between " \
      "#{countable_span.first.strftime(DAY)} and #{countable_span.last.strftime(DAY)}."
  end

  def reach_clause
    return "counts from when its first target started, up to today" if savings?
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
