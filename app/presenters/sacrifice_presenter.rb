# frozen_string_literal: true

# What would have to give when the rules and savings need more per period than typical income
# brings in.
class SacrificePresenter
  Row = Data.define(:rule, :claim, :reason) do
    def cuttable? = reason.nil?
    def claim_param = DigitsHelper.digits(claim)
  end

  TargetRow = Data.define(:target, :ask, :income) do
    delegate :share?, to: :target
    def name = "#{target.account.name} · #{target.words}"
    def claim_param = DigitsHelper.digits(ask)
    def percent_param = target.percent.to_d.to_s("F").sub(/\.0+\z/, "")
    def income_param = DigitsHelper.digits(income)
  end

  attr_reader :user, :today

  def initialize(user:, today: user.today)
    @user = user
    @today = today
  end

  delegate :budget, to: :ledger

  def savings = @savings ||= ledger.savings

  # Memoised with defined?, because nil is a real answer and the common one for a new user.
  def typical_income
    return @typical_income if defined?(@typical_income)

    @typical_income = ledger.account_ledger.typical_income
  end

  def gap = @gap ||= budget + savings - typical_income.to_d
  def gap_param = DigitsHelper.digits(gap)
  def declared? = user.period_cadence.present? && typical_income.present?
  def underwater? = declared? && gap.positive?
  def cuttable_rows = rows.select(&:cuttable?)
  def fixed_rows = rows.reject(&:cuttable?)
  def unwinnable? = cuttable_total < gap
  def unclosable = gap - cuttable_total

  def target_rows
    @target_rows ||= ledger.savings_accounts.flat_map(&:savings_targets).map { |target| target_row(target) }
      .sort_by { |row| [-row.ask, row.name] }
  end

  def cuttable_total = @cuttable_total ||= cuttable_rows.sum(0.to_d, &:claim) + target_rows.sum(0.to_d, &:ask)
  def rows_total = rows.sum(0.to_d, &:claim) + target_rows.sum(0.to_d, &:ask)

  private

  # A rolling bill is fixed; an allowance or a one-off can be cut.
  def rows
    @rows ||= ledger.rules
      .map { |rule| Row.new(rule: rule, claim: rule.ask(today: today), reason: reason_for(rule)) }
      .sort_by { |row| [-row.claim, row.rule.category.name, row.rule.id] }
  end

  def target_row(target)
    income = target.share? ? ledger.account_ledger.typical_income_of_item(target.item_id) : 0.to_d
    TargetRow.new(target: target, ask: target.ask(typical_income: income), income: income)
  end

  def reason_for(rule) = rule.cadence == :every_n ? :fixed : nil
  def ledger = @ledger ||= ClaimLedger.new(user, today: today)
end
