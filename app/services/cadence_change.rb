# frozen_string_literal: true

# A change of period cadence. Per-period rules may be scaled so they cost the same per year.
class CadenceChange
  Line = Data.define(:rule, :amount, :scaled_amount)

  SMALLEST_RATE = BigDecimal("0.01")

  attr_reader :user, :declaration, :periods_per_year_before

  def initialize(user:, declaration:)
    @user = user
    @declaration = declaration.to_h.symbolize_keys
    @periods_per_year_before = user.periods_per_year
  end

  def offered? = changing? && acceptable? && lines.any?
  def changing? = cadence.present? && user.period_cadence.present? && cadence != user.period_cadence
  def cadence = declaration[:period_cadence].presence
  def periods_per_year = User::PERIODS_PER_YEAR.fetch(cadence, 12)

  def lines
    @lines ||= user.rules.per_period.includes(:category).map do |rule|
      Line.new(rule: rule, amount: rule.amount.to_d, scaled_amount: scaled(rule.amount.to_d))
    end
  end

  def apply(scale: nil)
    scaling = scale && offered?
    saved = false
    ActiveRecord::Base.transaction do
      saved = user.update(declaration)
      raise ActiveRecord::Rollback unless saved

      lines.each { |line| line.rule.update!(amount: line.scaled_amount) } if scaling
    end
    @scaled = scaling && saved
    saved
  end

  def scaled? = @scaled.present?

  private

  def acceptable?
    probe = User.find(user.id)
    probe.assign_attributes(declaration)
    probe.valid?
  end

  def scaled(amount) = [(amount * periods_per_year_before / periods_per_year).round(2), SMALLEST_RATE].max
end
