# frozen_string_literal: true

class Entry < ApplicationRecord
  include ModelSearchable

  belongs_to :item, touch: true
  accepts_nested_attributes_for :item

  # An entry may name the pool it actually landed in, overriding its category's.
  # An employer splitting a paycheck across two accounts is two deposits, and each
  # one has to be able to name its own destination.
  belongs_to :pool, optional: true

  has_many :pool_movements, foreign_key: :source_entry_id, dependent: :destroy, inverse_of: :source_entry

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true

  validate :pool_must_belong_to_user
  validate :income_must_land_in_an_account

  delegate :user, to: :item
  delegate :category, to: :item

  scope :expenses, -> { joins(item: :category).where(categories: { category_type: :expense }) }
  scope :incomes, -> { joins(item: :category).where(categories: { category_type: :income }) }
  scope :savings, -> { joins(item: :category).where(categories: { category_type: :savings }) }
  scope :budgetable_expenses, -> { expenses.where(categories: { pool_id: nil }) }
  scope :pool_covered_expenses, -> { expenses.where.not(categories: { pool_id: nil }) }
  scope :tracked, -> { where(categories: { tracked: true }) }

  # Define searchable fields using the DSL
  searchable :description, label: "Description"
  searchable :date, type: :date, label: "Date"
  searchable :item, through: :item, column: :name, label: "Item"
  searchable :category, through: [:item, :category], column: :name, label: "Category"
  searchable :pool, through: [:item, :category, :pool], column: :name, label: "Pool"

  # entry override -> category's pool -> the user's default account
  def effective_pool
    pool || resolved_category&.effective_pool
  end

  private

  # `category` and `user` are delegations through `item`, so on a half-built entry they
  # raise rather than return nil. Everything below reaches the category through here so
  # the guard can never be half-applied to one link and not the other.
  def resolved_category
    item&.category
  end

  # Records, not ids: under `build` an unsaved association leaves `*_id` nil on both
  # sides, and `nil == nil` would wave a foreign pool through.
  def pool_must_belong_to_user
    return if pool.blank? || resolved_category.blank?

    errors.add(:pool, "must belong to the same user") unless pool.user == resolved_category.user
  end

  # The counterpart to Category#income_must_land_in_an_account. The override is a second
  # channel to the same destination, so it carries the same rule: income lands in an
  # account, never directly in an envelope.
  def income_must_land_in_an_account
    return if pool.blank? || !resolved_category&.income?

    errors.add(:pool, "must be an account for income entries") unless pool.pool_type_account?
  end
end
