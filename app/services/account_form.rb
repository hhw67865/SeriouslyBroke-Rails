# frozen_string_literal: true

# The account form's params onto an account: name, mode, target rows and a balance correction, all
# landing together or not at all. A refused figure costs no rename.
class AccountForm
  attr_reader :account

  def initialize(account, params)
    @account = account
    @params = params.to_h.deep_symbolize_keys
  end

  delegate :errors, to: :account

  def save
    assign
    return false unless balance.blank? || numeric?(balance)

    Account.transaction do
      next false unless account.save
      next true if balance.blank?
      next true if account.correct_balance(balance)

      raise ActiveRecord::Rollback
    end || false
  end

  private

  def balance = @params[:balance]

  def assign
    account.name = @params[:name] if @params.key?(:name)
    account.keeps_extra = @params[:keeps_extra] if @params.key?(:keeps_extra)
    account.savings_targets_attributes = @params[:savings_targets_attributes] if @params.key?(:savings_targets_attributes)
  end

  def numeric?(typed)
    return true if BigDecimal(typed.to_s, exception: false)

    account.errors.add(:opening_balance, "is not a number")
    false
  end
end
