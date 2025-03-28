class Category < ApplicationRecord
  belongs_to :user
  belongs_to :savings_pool, optional: true
  has_many :items, dependent: :destroy
  has_many :entries, through: :items
  has_one :budget, dependent: :destroy

  validates :name, presence: true
  validates :category_type, presence: true

  enum category_type: {
    expense: 0,
    income: 1,
    savings: 2
  }

  validate :budget_only_for_expense

  # Basic scopes
  scope :expenses, -> { where(category_type: :expense) }
  scope :incomes, -> { where(category_type: :income) }
  scope :savings, -> { where(category_type: :savings) }

  # Enhanced scopes with includes
  scope :with_type, ->(type) {
    case type.to_s
    when 'expense' then expenses.includes(:budget, :items)
    when 'income' then incomes.includes(:items)
    when 'savings' then savings.includes(:items, :savings_pool)
    else expenses.includes(:budget, :items) # Default to expenses
    end
  }

  # Search scope
  scope :search, ->(query) {
    query.present? ? where('name ILIKE ?', "%#{query}%") : all
  }

  # Calculator for category metrics
  def calculator(date = Date.current)
    @calculator ||= CategoryCalculator.new(self, date)
  end

  private

  def budget_only_for_expense
    errors.add(:budget, "can only be set for expense categories") if budget.present? && !expense?
  end
end
