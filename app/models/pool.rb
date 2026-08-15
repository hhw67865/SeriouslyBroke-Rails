# frozen_string_literal: true

class Pool < ApplicationRecord
  include ModelSearchable

  belongs_to :user, touch: true
  has_many :categories, dependent: :nullify
  has_many :budgets, dependent: :destroy
  has_many :items, through: :categories
  has_many :entries, through: :items

  # Entries that named this pool directly, overriding their category's. Nullified on
  # destroy for the same reason categories are: the entry falls back down the chain
  # rather than blocking the delete on a foreign key.
  has_many :override_entries, class_name: "Entry", dependent: :nullify, inverse_of: :pool

  belongs_to :account, class_name: "Pool", optional: true
  has_many :child_pools,
           class_name: "Pool",
           foreign_key: :account_id,
           dependent: :restrict_with_error,
           inverse_of: :account

  has_many :movements_in,
           class_name: "PoolMovement",
           foreign_key: :to_pool_id,
           dependent: :destroy,
           inverse_of: :to_pool
  has_many :movements_out,
           class_name: "PoolMovement",
           foreign_key: :from_pool_id,
           dependent: :destroy,
           inverse_of: :from_pool

  # Prefixed so `pool_type_account?` ("is an account") can never be misread as the
  # `account` association ("the account this pool sits inside").
  enum :pool_type, { account: 0, budget: 1, savings: 2 }, prefix: true

  # Named `*_pools` so they can never be misread as the `budgets` association
  # (`pool.budgets` holds Budget records; `Pool.budget_pools` holds Pool records).
  scope :accounts, -> { where(pool_type: :account) }
  scope :budget_pools, -> { where(pool_type: :budget) }
  scope :savings_pools, -> { where(pool_type: :savings) }
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

  # Entries scoped to start_date and filtered by category type.
  #
  # The `start_date..` filter is a deliberate divergence from PoolCalculator#balance, which
  # dropped it: these three feed the savings-goal *timeline*, which is a story about a goal
  # and rightly begins when the goal did, while the balance is all the money in the pool
  # regardless of when it arrived. PoolsController#show therefore renders a timeline and a
  # balance computed on different rules, on purpose — a pre-start entry counts toward the
  # balance without appearing in the list above it.
  # TODO(plan-3): revisit once savings-category entries become movements; the timeline will
  # need a movement-aware source and this is the moment to decide if the cutoff survives.
  def contribution_entries
    entries.joins(item: :category).where(categories: { category_type: :savings }).where(date: start_date..)
  end

  def withdrawal_entries
    entries.joins(item: :category).where(categories: { category_type: :expense }).where(date: start_date..)
  end

  def timeline_entries
    contribution_entries.or(withdrawal_entries)
  end

  def calculator(as_of: nil, today: Date.current)
    PoolCalculator.new(self, as_of: as_of, today: today)
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
    # Records, not ids: with neither the pool nor its parent saved both `user_id`s are nil,
    # and `nil == nil` waves another user's account through.
    errors.add(:account, "must belong to the same user") unless account.user == user
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
