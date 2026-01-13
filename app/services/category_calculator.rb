# frozen_string_literal: true

class CategoryCalculator
  attr_reader :category, :date_range, :period

  def initialize(category, date = Date.current, period: :monthly)
    @category = category
    @period = period
    @date_range = compute_date_range(date)
  end

  # Shared methods
  def total_amount
    category.entries.where(date: date_range).sum(:amount)
  end

  # Expense methods
  def budget_percentage
    return 0 unless category.expense? && effective_budget.to_f.positive?
    (total_amount / effective_budget * 100).round
  end

  # Returns the monthly budget rate (yearly budgets are converted to monthly)
  def monthly_budget_rate
    return nil unless category.expense? && category.budget&.amount

    if category.budget.year?
      (category.budget.amount / 12.0).round(2)
    else
      category.budget.amount
    end
  end

  # Returns true if budget is yearly (for display purposes)
  def yearly_budget?
    category.budget&.year?
  end

  # Returns the effective budget for the current period
  def effective_budget
    return nil unless monthly_budget_rate

    period == :ytd ? monthly_budget_rate * months_in_range : monthly_budget_rate
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

  # Items for current month with detailed information
  def current_month_items
    result = {}

    category.items.each do |item|
      item_data = build_item_data(item)
      result[item] = item_data if item_data
    end

    sort_items_by_amount(result)
  end

  private

  def compute_date_range(date)
    case period
    when :ytd
      date.beginning_of_year..date.end_of_month
    else
      date.all_month
    end
  end

  def months_in_range
    first_date = date_range.first
    last_date = date_range.last
    ((last_date.year - first_date.year) * 12) + (last_date.month - first_date.month) + 1
  end

  def build_item_data(item)
    month_entries = item.entries.where(date: date_range)
    return unless month_entries.any?

    {
      total_amount: month_entries.sum(:amount),
      latest_entry: month_entries.order(date: :desc).first,
      entry_count: month_entries.count
    }
  end

  def sort_items_by_amount(items_hash)
    items_hash.sort_by { |_, data| -data[:total_amount] }.to_h
  end

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
