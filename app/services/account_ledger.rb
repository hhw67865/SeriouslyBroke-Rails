# frozen_string_literal: true

# Balances for one user in a fixed number of queries. A balance is the opening balance, plus
# income that landed in the account, minus spending (main only), plus transfers in, minus out.
class AccountLedger
  class NotAnAccount < StandardError; end

  attr_reader :user, :today

  def initialize(user, today: user.today)
    @user = user
    @today = today
  end

  def balance_of(account)
    raise NotAnAccount, "#{account.name} belongs to another user" unless account.user_id == user.id

    account.opening_balance.to_d + income_into(account) - expenses_from(account) +
      transfers_in(account) - transfers_out(account)
  end

  def pot = main.present? ? balance_of(main) : 0.to_d

  def total_money = user.accounts.sum(0.to_d) { |account| balance_of(account) }

  def income_within(range) = user_entries(Entry.incomes).where(date: range).sum(:amount).to_d

  # The mean of regular income over the last complete periods, nil until one period is complete.
  # Memoised with defined?, because nil is a real answer and the common one for a new user.
  def typical_income
    return @typical_income if defined?(@typical_income)

    @typical_income = IncomeMeasure.new(user, category_ids: user.categories.incomes.regular.ids, today: today).typical
  end

  private

  def main = user.main_account

  def main?(account) = main.present? && account.id == main.id

  def income_into(account)
    landed = income_by_account.fetch(account.id, 0.to_d)
    main?(account) ? landed + income_by_account.fetch(nil, 0.to_d) : landed
  end

  def expenses_from(account) = main?(account) ? total_expenses : 0.to_d

  def transfers_in(account) = transfer_totals(:to_account_id).fetch(account.id, 0.to_d)

  def transfers_out(account) = transfer_totals(:from_account_id).fetch(account.id, 0.to_d)

  def income_by_account
    @income_by_account ||= user_entries(Entry.incomes).group("entries.account_id").sum(:amount).transform_values(&:to_d)
  end

  def total_expenses = @total_expenses ||= user_entries(Entry.expenses).sum(:amount).to_d

  def transfer_totals(column)
    @transfer_totals ||= {}
    @transfer_totals[column] ||= Transfer.where(column => user.accounts.select(:id)).group(column).sum(:amount).transform_values(&:to_d)
  end

  def user_entries(scope) = scope.where(categories: { user_id: user.id })
end
