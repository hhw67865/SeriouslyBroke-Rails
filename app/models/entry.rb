# frozen_string_literal: true

class Entry < ApplicationRecord
  include ModelSearchable

  belongs_to :item, touch: true
  belongs_to :account, optional: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true
  validate :account_is_the_users
  validate :only_income_lands_in_an_account

  delegate :user, :category, to: :item

  scope :expenses, -> { joins(item: :category).where(categories: { category_type: :expense }) }
  scope :incomes, -> { joins(item: :category).where(categories: { category_type: :income }) }
  scope :tracked, -> { where(categories: { tracked: true }) }
  scope :on_unruled_items, -> { where.not(item_id: Rule.where.not(item_id: nil).select(:item_id)) }
  # A rule's lane: its item's entries, or the whole category's entries on items with no rule of their own.
  scope :in_lane_of,
        lambda { |rule|
          next where(item_id: rule.item_id) if rule.item_id.present?

          expenses.where(items: { category_id: rule.category_id }).on_unruled_items
        }
  scope :since, ->(day) { where(date: day..) }

  searchable :description, label: "Description"
  searchable :date, type: :date, label: "Date"
  searchable :item, through: :item, column: :name, label: "Item"
  searchable :category, through: [:item, :category], column: :name, label: "Category"

  # No account means main.
  def landing_account = account || user.main_account

  private

  def account_is_the_users
    return if account.blank? || item.blank?

    errors.add(:account, "must be one of your accounts") unless account.user_id == user.id
  end

  def only_income_lands_in_an_account
    return if account.blank? || item.blank? || category.income?

    errors.add(:account, "only income lands in an account — spending leaves your main account")
  end
end
