# frozen_string_literal: true

# The Your income page: the period declaration and which categories count toward typical income.
class BudgetIncomePresenter
  Period = Data.define(:range, :income)

  attr_reader :user, :declaration

  def initialize(user:, declaration: nil)
    @user = user
    @declaration = declaration || user
  end

  def income_categories
    @income_categories ||= user.categories.incomes.order(:name).to_a
  end

  delegate :typical_income, to: :ledger

  def declared? = user.period_cadence.present?
  def cadence = user.period_cadence&.humanize
  def history? = typical_income.present?

  def periods
    @periods ||= ledger.complete_periods(AccountLedger::TYPICAL_PERIODS)
      .map { |range| Period.new(range: range, income: ledger.regular_income_within(range)) }
  end

  private

  def ledger = @ledger ||= AccountLedger.new(user)
end
