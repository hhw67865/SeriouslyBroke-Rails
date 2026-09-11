# frozen_string_literal: true

# The Savings page: checking with what claims it, and every other account with what it is owed.
# Reads through one ClaimLedger; the row facts cost two queries whatever the row count.
class SavingsPresenter
  attr_reader :user, :today

  def initialize(user:, today: user.today)
    @user = user
    @today = today
  end

  def checking = user.main_account
  def checking_balance = ledger.pot
  delegate :claimed, :budget_claim, :savings_claim, :free, to: :ledger
  def typical_income = ledger.account_ledger.typical_income

  def accounts = @accounts ||= user.accounts.order(:name).to_a
  def savings_accounts = accounts.reject(&:main?)
  def rows = @rows ||= savings_accounts.map { |account| line_for(account) }
  def savings_total = rows.sum(0.to_d, &:balance)
  def owed_total = rows.sum(0.to_d, &:claim)

  private

  def ledger = @ledger ||= ClaimLedger.new(user, today: today)
  def targeted = @targeted ||= ledger.savings_accounts.index_by(&:id)

  def line_for(account)
    calculator = calculator_for_row(account)
    SavingsLine.new(
      account: account,
      balance: ledger.account_ledger.balance_of(account),
      claim: calculator&.claim || 0.to_d,
      accrued: calculator&.accrued_this_period || 0.to_d,
      countable_span: calculator&.countable_span || (today...today),
      targets: calculator&.targets || [],
      moved_words: moved_words(account),
      adjustments: adjustments_this_period.fetch(account.id, [])
    )
  end

  def calculator_for_row(account)
    return nil unless targeted.key?(account.id)

    ledger.calculator_for(targeted.fetch(account.id))
  end

  def moved_words(account)
    touch = latest_transfer[account.id]
    return "—" if touch.blank?

    "#{touch.in? ? "+" : "−"}#{currency(touch.amount)} #{touch.in? ? "in" : "out"} on #{touch.date.strftime("%b %-d")}"
  end

  def latest_transfer = @latest_transfer ||= Transfer.latest_per_account(savings_accounts.map(&:id))

  def adjustments_this_period
    @adjustments_this_period ||= Adjustment.on_accounts(savings_accounts.map(&:id))
      .dated_within(user.period_containing(today)).order(:date, :created_at).group_by(&:source_id)
  end

  def currency(amount) = ActiveSupport::NumberHelper.number_to_currency(amount)
end
