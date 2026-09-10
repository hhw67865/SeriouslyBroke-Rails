# frozen_string_literal: true

# The card under the entry form: what the category's rules hold now and after this amount.
class EntryImpactPresenter
  TYPED_AMOUNT = /\A\d*\.?\d+\z/

  attr_reader :user, :category, :entry, :today

  def initialize(user:, category:, amount: nil, entry: nil, today: user.today)
    @user = user
    @category = category
    @raw_amount = amount
    @entry = entry
    @today = today
  end

  def render? = category.present? && !category.income?
  def unbudgeted? = category.nil? || calculators.empty?
  def fund? = calculators.any?(&:dated?)

  def fund_target
    return nil unless calculators.one? && calculators.first.dated?

    calculators.first.target
  end

  def noun
    return "rules" unless fund?

    dated_rules.any?(&:bill?) ? "bill" : "target"
  end

  def dated_rules = calculators.select(&:dated?).map(&:rule)

  # The claim as it stands, with an edited entry's own amount given back first.
  def balance
    @balance ||= begin
      given_back = own_contribution
      given_back.zero? ? claim : (pre_clamp_claim + given_back).clamp(0.to_d, most_it_could_claim)
    end
  end

  def amount
    @amount ||= case @raw_amount
                when nil then 0.to_d
                when Numeric, BigDecimal then [@raw_amount.to_d, 0.to_d].max
                else @raw_amount.to_s.strip.match?(TYPED_AMOUNT) ? @raw_amount.to_s.to_d : 0.to_d
                end
  end

  def balance_after = @balance_after ||= (balance - amount).to_d
  def figures? = render? && !unbudgeted?
  def overdrawn? = figures? && balance_after.negative?
  def denominator = @denominator ||= fund_target || steady_claim
  def bar? = figures? && denominator.positive?

  def bar_fraction
    return 0.to_d unless denominator.positive?

    (balance_after / denominator).clamp(0.to_d, 1.to_d)
  end

  def bar_percent = (bar_fraction * 100).round

  def period_ends_on
    return nil if user.period_cadence.blank? || user.period_anchor_date.blank?

    user.period_containing(today).last
  end

  def balance_param = DigitsHelper.digits(balance)
  def denominator_param = DigitsHelper.digits(denominator)

  private

  def steady_claim = calculators.sum(0.to_d, &:standing_ask)
  def claim = @claim ||= calculators.sum(0.to_d, &:claim).to_d

  def calculators
    @calculators ||= category.nil? ? [] : category.rules.includes(:item).map { |rule| rule.claim_calculator(today: today) }
  end

  def pre_clamp_claim
    calculators.sum(0.to_d) { |calculator| calculator.rate? ? calculator.raw_rate : calculator.built_up }
  end

  def most_it_could_claim = calculators.sum(0.to_d) { |calculator| ceiling_for(calculator) }

  def ceiling_for(calculator)
    return [calculator.accrued_this_period, 0.to_d].max if calculator.rate?
    return calculator.built_up + calculator.planned_this_period if calculator.fund?

    calculator.target
  end

  def own_contribution
    counted = counted_entry
    return 0.to_d unless counted && counted.item.category_id == category.id && counted_by_the_claim?(counted)

    counted.amount.to_d
  end

  def counted_by_the_claim?(counted)
    calculators.any? { |calculator| calculator.counts_spending_on?(counted.date) } &&
      calculators.none? { |calculator| !calculator.rate? && calculator.over? }
  end

  def counted_entry
    return nil unless entry&.persisted?

    entry.changed? ? user.entries.find_by(id: entry.id) : entry
  end
end
