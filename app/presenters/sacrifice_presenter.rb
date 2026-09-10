# frozen_string_literal: true

# What would have to give when the rules need more per period than typical income brings in.
class SacrificePresenter
  Row = Data.define(:rule, :claim, :reason) do
    def cuttable? = reason.nil?
    def claim_param = DigitsHelper.digits(claim)
  end

  attr_reader :user, :today

  def initialize(user:, today: user.today)
    @user = user
    @today = today
  end

  def rules_need = @rules_need ||= Rule.steady_need(user, today: today, ledger: ledger)

  # Memoised with defined?, because nil is a real answer and the common one for a new user.
  def typical_income
    return @typical_income if defined?(@typical_income)

    @typical_income = ledger.account_ledger.typical_income
  end

  def gap = @gap ||= rules_need - typical_income.to_d
  def gap_param = DigitsHelper.digits(gap)
  def declared? = user.period_cadence.present? && typical_income.present?
  def underwater? = declared? && gap.positive?
  def cuttable_rows = rows.select(&:cuttable?)
  def fixed_rows = rows.reject(&:cuttable?)
  def cuttable_total = @cuttable_total ||= cuttable_rows.sum(0.to_d, &:claim)
  def unwinnable? = cuttable_total < gap
  def unclosable = gap - cuttable_total
  def rows_total = rows.sum(0.to_d, &:claim)

  private

  # A rolling bill is fixed; an allowance or a one-off can be cut.
  def rows
    @rows ||= ledger.rules
      .map { |rule| Row.new(rule: rule, claim: rule.steady_ask(today: today), reason: reason_for(rule)) }
      .sort_by { |row| [-row.claim, row.rule.category.name, row.rule.id] }
  end

  def reason_for(rule) = rule.cadence == :every_n ? :fixed : nil
  def ledger = @ledger ||= ClaimLedger.new(user, today: today)
end
