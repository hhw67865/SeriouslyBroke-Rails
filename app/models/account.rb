# frozen_string_literal: true

class Account < ApplicationRecord
  include ModelSearchable

  belongs_to :user, touch: true
  has_many :transfers_in, class_name: "Transfer", foreign_key: :to_account_id, dependent: :destroy, inverse_of: :to_account
  has_many :transfers_out, class_name: "Transfer", foreign_key: :from_account_id, dependent: :destroy, inverse_of: :from_account
  has_many :savings_targets, dependent: :destroy
  has_many :adjustments, as: :source, dependent: :destroy
  accepts_nested_attributes_for :savings_targets, allow_destroy: true, reject_if: :all_blank

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

  def savings? = !main?

  def claim_calculator(today: user.today, **rows) = SavingsCalculator.new(self, today: today, **rows)

  def balance = AccountLedger.new(user).balance_of(self)

  # The edit form's two answers, applied together or not at all: a rename must not survive a balance
  # the account refuses. Returns true only when both writes landed.
  def revise(name:, balance:)
    self.name = name
    return false unless balance.blank? || numeric?(balance)

    transaction do
      next false unless save
      next true if balance.blank?
      next true if correct_balance(balance)

      raise ActiveRecord::Rollback
    end || false
  end

  # Moves the opening balance so that the balance today equals the typed figure. Nothing else moves.
  def correct_balance(typed)
    corrected = BigDecimal(typed.to_s, exception: false)
    if corrected.nil?
      errors.add(:opening_balance, "is not a number")
      return false
    end

    update(opening_balance: opening_balance.to_d + (corrected - balance))
  end

  private

  # The refusal is raised before anything is written, so a refused figure cannot cost a rollback of
  # a rename that was otherwise fine.
  def numeric?(typed)
    return true if BigDecimal(typed.to_s, exception: false)

    errors.add(:opening_balance, "is not a number")
    false
  end

  def main_is_not_deletable
    return unless main?
    return if destroyed_by_association

    errors.add(:base, "This is your main account — everything flows through it")
    throw(:abort)
  end
end
