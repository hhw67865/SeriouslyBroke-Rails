# frozen_string_literal: true

class Category < ApplicationRecord
  include ModelSearchable

  belongs_to :user, touch: true
  belongs_to :savings_pool, optional: true, touch: true
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

  # Basic scopes
  scope :expenses, -> { where(category_type: :expense) }
  scope :incomes, -> { where(category_type: :income) }
  scope :savings, -> { where(category_type: :savings) }
  scope :tracked, -> { where(tracked: true) }
  scope :untracked, -> { where(tracked: false) }
  scope :budgetable, -> { expenses.where(savings_pool_id: nil) }
  scope :pool_covered, -> { expenses.where.not(savings_pool_id: nil) }

  scope :with_type,
        lambda { |type|
          case (type || :expense).to_sym
          when :expense then expenses.includes(:budget, :savings_pool, :items)
          when :income then incomes.includes(:items)
          when :savings then savings.includes(:items, :savings_pool)
          end
        }

  # Configure searchable fields
  searchable :name, label: "Name"

  def budgetable?
    expense? && savings_pool_id.nil?
  end

  def pool_covered?
    expense? && savings_pool_id.present?
  end

  def calculator(date = Date.current, period: :monthly)
    CategoryCalculator.new(self, date, period: period)
  end

  private

  def destroy_budget_if_not_expense
    return unless category_type_changed? && !expense? && budget

    budget.destroy
    self.budget = nil
  end

  def destroy_budget_if_pool_linked
    return unless savings_pool_id_changed? && savings_pool_id.present? && budget

    budget.destroy
    self.budget = nil
  end

  def budget_only_for_expense
    errors.add(:budget, "can only be set for expense categories") if budget.present? && !expense?
  end
end
