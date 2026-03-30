# frozen_string_literal: true

class Budget < ApplicationRecord
  belongs_to :category, touch: true

  enum :period, { month: 0, year: 1 }

  validates :amount, :period, presence: true
  validate :category_must_be_expense
  validate :category_must_not_have_pool

  delegate :user, to: :category

  private

  def category_must_be_expense
    errors.add(:category, "must be an expense category") unless category&.expense?
  end

  def category_must_not_have_pool
    errors.add(:category, "cannot have a budget when linked to a savings pool") if category&.savings_pool_id?
  end
end
