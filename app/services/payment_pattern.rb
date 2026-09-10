# frozen_string_literal: true

# What an item's payment history says about it: when it last cost money, how often that comes
# round, and what that comes to per period. `payments` is `[date, amount]`, newest first.
class PaymentPattern
  CADENCE_BUCKETS = [
    [20, "several a month"],
    [46, "monthly"],
    [111, "every 3 months"],
    [221, "every 6 months"],
    [451, "every 12 months"]
  ].freeze

  YEAR_DAYS = BigDecimal("365.25")

  attr_reader :payments, :today, :periods_per_year

  def initialize(payments, today:, periods_per_year:)
    @payments = payments
    @today = today
    @periods_per_year = periods_per_year
  end

  def count = recent.size
  def last_paid = recent.first
  def typical = median(last_three.map { |(_date, amount)| amount })
  def low = last_three.map { |(_date, amount)| amount }.min
  def high = last_three.map { |(_date, amount)| amount }.max
  def range? = typical.present? && (low < typical * BigDecimal("0.8") || high > typical * BigDecimal("1.2"))

  def cadence_words
    return nil unless median_gap

    CADENCE_BUCKETS.each { |ceiling, words| return words if median_gap < ceiling }
    "now and then"
  end

  def lapsed?
    return false unless median_gap && last_paid

    days_since = (today - last_paid.first).to_i
    days_since > 2 * median_gap && days_since >= 60
  end

  def usually_words
    return "—" if count.zero?
    return "once so far" if count == 1

    amount_words = range? ? "#{fmt(low)}–#{fmt(high)}" : fmt(typical)
    words = "#{amount_words} #{cadence_words}"
    lapsed? ? "was #{words}" : words
  end

  def per_period
    return nil if count < 2 || lapsed?

    (typical * payments_a_year / periods_per_year).round(2)
  end

  private

  def recent = @recent ||= payments.first(6)
  def last_three = recent.first(3)

  def median_gap
    return @median_gap if defined?(@median_gap)

    gaps = recent.each_cons(2).map { |(newer, _), (older, _)| (newer - older).to_i }
    @median_gap = median(gaps)
  end

  # Extrapolating from the median gap overcounts a "several a month" item, so that bucket counts
  # what actually landed in the trailing year instead.
  def payments_a_year
    return payments.count { |(date, _amount)| date > today - 365 } if median_gap < 20

    YEAR_DAYS / median_gap
  end

  def median(values)
    return nil if values.empty?

    sorted = values.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / BigDecimal(2)
  end

  def fmt(amount) = ActiveSupport::NumberHelper.number_to_currency(amount)
end
