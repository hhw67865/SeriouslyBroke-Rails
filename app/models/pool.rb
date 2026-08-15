# frozen_string_literal: true

class Pool < ApplicationRecord
  include ModelSearchable

  belongs_to :user, touch: true
  has_many :categories, dependent: :nullify
  has_many :items, through: :categories
  has_many :entries, through: :items

  belongs_to :account, class_name: "Pool", optional: true
  has_many :child_pools,
           class_name: "Pool",
           foreign_key: :account_id,
           dependent: :restrict_with_error,
           inverse_of: :account

  # Prefixed so `pool_type_account?` ("is an account") can never be misread as the
  # `account` association ("the account this pool sits inside").
  enum :pool_type, { account: 0, budget: 1, savings: 2 }, prefix: true

  scope :accounts, -> { where(pool_type: :account) }
  scope :budgets, -> { where(pool_type: :budget) }
  scope :savings, -> { where(pool_type: :savings) }
  scope :by_priority, -> { order(:priority, :name) }

  attr_accessor :create_expense_category, :create_savings_category

  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :target_amount, presence: true, if: :pool_type_savings?
  validates :start_date, presence: true

  validate :account_matches_pool_type

  after_initialize :set_default_start_date, if: :new_record?
  after_create :create_auto_categories

  # Configure searchable fields
  searchable :name, label: "Name"
  searchable :category, through: :categories, column: :name, label: "Category"

  # Entries scoped to start_date and filtered by category type
  def contribution_entries
    entries.joins(item: :category).where(categories: { category_type: :savings }).where(date: start_date..)
  end

  def withdrawal_entries
    entries.joins(item: :category).where(categories: { category_type: :expense }).where(date: start_date..)
  end

  def timeline_entries
    contribution_entries.or(withdrawal_entries)
  end

  def calculator(as_of: nil)
    PoolCalculator.new(self, as_of: as_of)
  end

  # What the bank actually says: unallocated cash plus every pool inside it.
  def total
    calculator.current_balance + child_pools.sum { |pool| pool.calculator.current_balance }
  end

  private

  def account_matches_pool_type
    return errors.add(:account, "cannot be set on an account") if pool_type_account? && account_id.present?
    return if pool_type_account?

    return require_account_for_budget_pools if account.blank?

    errors.add(:account, "must be an account") unless account.pool_type_account?
    errors.add(:account, "must belong to the same user") unless account.user_id == user_id
  end

  # Savings pools may stay account-less until Plan 3's data migration backfills them;
  # budget pools are new in this plan and must name an account from day one.
  # TODO(plan-3): tighten to include savings pools once the account backfill lands
  def require_account_for_budget_pools
    errors.add(:account, "must be set for budget pools") if pool_type_budget?
  end

  def set_default_start_date
    self.start_date ||= Date.current
  end

  def create_auto_categories
    create_linked_category(:expense) if boolean_cast(create_expense_category)
    create_linked_category(:savings) if boolean_cast(create_savings_category)
  end

  def create_linked_category(type)
    base_name = "#{name} #{type.to_s.capitalize}"
    categories.create!(
      user: user,
      name: unique_category_name(base_name),
      category_type: type
    )
  end

  def unique_category_name(base_name)
    candidate = base_name
    suffix = 2
    while user.categories.exists?(["LOWER(name) = ?", candidate.downcase])
      candidate = "#{base_name} #{suffix}"
      suffix += 1
    end
    candidate
  end

  def boolean_cast(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end
end
