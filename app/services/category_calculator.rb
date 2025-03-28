# frozen_string_literal: true

class CategoryCalculator
  attr_reader :category, :date_range

  def initialize(category, date = Date.current)
    @category = category
    @date_range = date.all_month
  end

  # Shared methods
  def total_amount
    category.entries.where(date: date_range).sum(:amount)
  end

  # Expense methods
  def budget_percentage
    return 0 unless category.expense? && category.budget&.amount.to_f.positive?
    (total_amount / category.budget.amount * 100).round
  end

  # Income methods
  def previous_month_change_percentage
    return 0 unless category.income? && !previous_month_amount.zero?

    calculate_percentage_change(current_amount, previous_month_amount)
  end

  def previous_month_trend
    percentage = previous_month_change_percentage
    percentage >= 0 ? :up : :down
  end

  # Savings methods
  def monthly_contribution
    return 0 unless category.savings?
    total_amount
  end

  # For all categories
  def top_items(limit = 3)
    items_with_amounts = {}

    category.items.each do |item|
      amount = item.entries.where(date: date_range).sum(:amount)
      items_with_amounts[item] = amount if amount.positive?
    end

    items_with_amounts.sort_by { |_, amount| -amount }.first(limit).to_h
  end

  private

  def current_amount
    total_amount
  end

  def previous_month_amount
    @previous_month_amount ||= begin
      prev_date = 1.month.ago(@date_range.first)
      prev_range = prev_date.all_month
      category.entries.where(date: prev_range).sum(:amount)
    end
  end

  def calculate_percentage_change(current, previous)
    ((current - previous) / previous.to_f * 100).round
  end
end
