# frozen_string_literal: true

# One promise that a savings account is owed money from checking: a fixed amount a period when it
# names no item, or a share of an income item's entries when it does. Each row counts from its
# own starts_on.
class SavingsTarget < ApplicationRecord
  belongs_to :account, touch: true
  belongs_to :item, optional: true

  before_validation :keep_one_figure

  validates :starts_on, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }, if: :target?
  validates :percent, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, if: :share?
  validates :account_id, uniqueness: { conditions: -> { where(item_id: nil) }, message: "already has a fixed target" }, if: :target?
  validates :item_id, uniqueness: { scope: :account_id, message: "already feeds this account" }, if: :share?
  validate :account_is_savings
  validate :item_is_the_users_income
  validate :item_is_not_over_shared

  delegate :user, to: :account

  scope :fixed, -> { where(item_id: nil) }
  scope :shares, -> { where.not(item_id: nil) }

  def target? = item.nil?
  def share? = !target?

  # What this row costs a period: its amount, or its percent of what the item typically brings in.
  def ask(typical_income: nil)
    return amount.to_d if target?

    (percent.to_d / 100 * typical_income.to_d).round(2)
  end

  def words
    return "#{ActiveSupport::NumberHelper.number_to_currency(amount)} a period" if target?

    "#{percent.to_d.to_s("F").sub(/\.0+\z/, "")}% of #{item.name}"
  end

  private

  def keep_one_figure
    target? ? self.percent = nil : self.amount = nil
  end

  def account_is_savings
    errors.add(:account, "checking never carries a savings target") if account&.main?
  end

  def item_is_the_users_income
    return if item.blank? || account.blank?

    errors.add(:item, "must be one of your income items") unless item.user == account.user && item.category.income?
  end

  def item_is_not_over_shared
    return if item.blank? || percent.blank?

    taken = SavingsTarget.shares.where(item_id: item_id).where.not(id: id).sum(:percent).to_d
    errors.add(:percent, "would take #{item.name} past 100% across your accounts") if taken + percent.to_d > 100
  end
end
