class Budget < ApplicationRecord
  belongs_to :category

  enum period: { month: 0, year: 1 }

  validates :amount, :period, presence: true
  validate :category_must_be_expense

  private

  def category_must_be_expense
    errors.add(:category, "must be an expense category") if category && !category.expense?
  end
end
