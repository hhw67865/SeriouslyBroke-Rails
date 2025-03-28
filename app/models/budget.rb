# frozen_string_literal: true

class Budget < ApplicationRecord
  belongs_to :category

  enum :period, { month: 0, year: 1 }

  validates :amount, :period, presence: true
  validate :category_must_be_expense

  delegate :user, to: :category

  private

  def category_must_be_expense
    errors.add(:category, "must be an expense category") unless category&.expense?
  end
end
