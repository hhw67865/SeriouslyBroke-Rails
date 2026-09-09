# frozen_string_literal: true

class Account < ApplicationRecord
  include ModelSearchable

  belongs_to :user, touch: true
  has_many :transfers_in, class_name: "Transfer", foreign_key: :to_account_id, dependent: :destroy, inverse_of: :to_account
  has_many :transfers_out, class_name: "Transfer", foreign_key: :from_account_id, dependent: :destroy, inverse_of: :from_account
  has_many :entries, dependent: :nullify

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :opening_balance, presence: true, numericality: true

  before_destroy :main_is_not_deletable, prepend: true

  searchable :name, label: "Name"

  # Returns the account, saved or carrying its errors. The first account a user opens is main.
  def self.open(user, name:, balance:)
    account = user.accounts.new(name: name, opening_balance: balance, opened_on: user.opening_day)
    transaction do
      account.save && user.main_account.blank? && user.update!(main_account: account)
    end
    account
  end

  def main? = user.main_account_id == id

  def balance = AccountLedger.new(user).balance_of(self)

  # Moves the opening balance so that the balance today equals the typed figure. Nothing else moves.
  def correct_balance(typed)
    update(opening_balance: opening_balance.to_d + (BigDecimal(typed.to_s) - balance))
  end

  private

  def main_is_not_deletable
    return unless main?
    return if destroyed_by_association

    errors.add(:base, "This is your main account — everything flows through it")
    throw(:abort)
  end
end
