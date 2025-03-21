class Category < ApplicationRecord
  belongs_to :user
  belongs_to :savings_pool, optional: true
  has_many :items, dependent: :destroy
  has_many :entries, through: :items
  has_one :budget, dependent: :destroy

  enum category_type: { income: 0, expense: 1, savings: 2 }

  validates :name, :category_type, presence: true
  validates :savings_pool, presence: true, if: :savings?
  validate :budget_only_for_expense

  scope :expenses, -> { where(category_type: :expense) }
  scope :incomes, -> { where(category_type: :income) }
  scope :savings, -> { where(category_type: :savings) }

  private

  def budget_only_for_expense
    errors.add(:budget, "can only be set for expense categories") if budget.present? && !expense?
  end
end
