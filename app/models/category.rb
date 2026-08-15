# frozen_string_literal: true

class Category < ApplicationRecord
  include ModelSearchable

  belongs_to :user, touch: true
  belongs_to :pool, optional: true, touch: true
  has_many :items, dependent: :destroy
  has_many :entries, through: :items
  has_one :budget, dependent: :destroy

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true
  validates :category_type, presence: true
  validates :name, uniqueness: { scope: :user_id, case_sensitive: false }

  enum :category_type,
       {
         expense: 0,
         income: 1,
         savings: 2
       }

  before_validation :destroy_budget_if_not_expense
  before_validation :destroy_budget_if_pool_linked

  validate :budget_only_for_expense
  validate :income_must_land_in_an_account

  # Basic scopes
  scope :expenses, -> { where(category_type: :expense) }
  scope :incomes, -> { where(category_type: :income) }
  scope :savings, -> { where(category_type: :savings) }
  scope :tracked, -> { where(tracked: true) }
  scope :untracked, -> { where(tracked: false) }
  scope :budgetable, -> { expenses.where(pool_id: nil) }
  scope :pool_covered, -> { expenses.where.not(pool_id: nil) }

  scope :with_type,
        lambda { |type|
          case (type || :expense).to_sym
          when :expense then expenses.includes(:budget, :pool, :items)
          when :income then incomes.includes(:items)
          when :savings then savings.includes(:items, :pool)
          end
        }

  # Configure searchable fields
  searchable :name, label: "Name"

  def budgetable?
    expense? && pool_id.nil?
  end

  def pool_covered?
    expense? && pool_id.present?
  end

  def calculator(date = Date.current, period: :monthly)
    CategoryCalculator.new(self, date, period: period)
  end

  # Public on purpose: Entry#effective_pool and PoolCalculator both call it.
  # category's pool -> the user's default account
  def effective_pool
    pool || user.default_account
  end

  private

  def destroy_budget_if_not_expense
    return unless category_type_changed? && !expense? && budget

    budget.destroy
    self.budget = nil
  end

  def destroy_budget_if_pool_linked
    return unless pool_id_changed? && pool_id.present? && budget

    budget.destroy
    self.budget = nil
  end

  def budget_only_for_expense
    errors.add(:budget, "can only be set for expense categories") if budget.present? && !expense?
  end

  # Income lands in an account, never directly in an envelope: the allocation rules
  # move it out of the account afterwards.
  def income_must_land_in_an_account
    return if pool.blank? || !income?

    errors.add(:pool, "must be an account for income categories") unless pool.pool_type_account?
  end
end
