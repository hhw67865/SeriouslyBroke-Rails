# frozen_string_literal: true

# Accounts, in two lots: the one you spend from, whose figures are Home's own (read through one
# HomePresenter, never recomputed), and everything set aside, whose transfer facts cost one query
# total, whatever the row count.
class AccountsPresenter
  Row = Data.define(:account, :balance, :opened_words, :moved_words)

  attr_reader :user, :today

  def initialize(user:, today: user.today)
    @user = user
    @today = today
  end

  delegate :accounts, to: :home
  def spending = user.main_account
  def spending_balance = home.in_checking
  def claimed = home.total_claims
  def free = home.free_to_spend

  def set_aside = @set_aside ||= other_accounts.map { |account| row_for(account) }
  def set_aside_total = home.other_accounts_total

  private

  def home = @home ||= HomePresenter.new(user: user, today: today)
  def other_accounts = home.other_accounts
  def other_account_ids = @other_account_ids ||= other_accounts.map(&:id)

  def row_for(account)
    Row.new(
      account: account,
      balance: home.balance_of(account),
      opened_words: opened_words(account),
      moved_words: moved_words(account)
    )
  end

  def opened_words(account)
    return nil if account.opened_on.blank?

    "opened #{account.opened_on.strftime("%b %Y")}"
  end

  def moved_words(account)
    touch = latest_transfer[account.id]
    return "—" if touch.blank?

    "#{touch.in? ? "+" : "−"}#{currency(touch.amount)} #{touch.in? ? "in" : "out"} on #{touch.date.strftime("%b %-d")}"
  end

  def latest_transfer
    @latest_transfer ||= Transfer.latest_per_account(other_account_ids)
  end

  def currency(amount) = ActiveSupport::NumberHelper.number_to_currency(amount)
end
