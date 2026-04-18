# frozen_string_literal: true

class CategoryCalculator
  include CategoriesHelper

  attr_reader :category, :date, :date_range, :period

  def initialize(category, date = Date.current, period: :monthly)
    @category = category
    @date = date
    @period = period
    @date_range = compute_date_range(date)
  end

  def total_amount
    category.entries.where(date: date_range).sum(:amount)
  end

  def budget_percentage
    return 0 unless category.expense? && effective_budget.to_f.positive?
    (total_amount / effective_budget * 100).round
  end

  def budget_pace_percentage
    return 0 unless category.expense? && budget_pace.to_f.positive?
    (total_amount / budget_pace * 100).round
  end

  def monthly_budget_rate
    return nil unless category.expense?
    category.budget&.amount
  end

  def effective_budget
    return nil unless monthly_budget_rate

    period == :ytd ? monthly_budget_rate * months_in_range(date_range) : monthly_budget_rate
  end

  def budget_pace(today: Date.current)
    return nil unless monthly_budget_rate
    return effective_budget unless prorated_active?
    ramp_value(pace_day(today), @date.end_of_month.day)
  end

  def budget_curve
    return {} unless monthly_budget_rate
    period == :ytd ? ytd_budget_curve : monthly_budget_curve
  end

  def previous_month_change_percentage
    return 0 unless category.income? && !previous_month_amount.zero?

    calculate_percentage_change(current_amount, previous_month_amount)
  end

  def previous_month_trend
    percentage = previous_month_change_percentage
    percentage >= 0 ? :up : :down
  end

  def monthly_contribution
    return 0 unless category.savings?
    total_amount
  end

  def top_items(limit = 3)
    items_with_amounts = {}

    category.items.each do |item|
      amount = item.entries.where(date: date_range).sum(:amount)
      items_with_amounts[item] = amount if amount.positive?
    end

    items_with_amounts.sort_by { |_, amount| -amount }.first(limit).to_h
  end

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

  def build_item_data(item)
    month_entries = item.entries.where(date: date_range).order(date: :desc).to_a
    return if month_entries.empty?

    {
      total_amount: month_entries.sum(&:amount),
      latest_entry: month_entries.first,
      entry_count: month_entries.size,
      entries: month_entries
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

  def prorated_active?
    period == :monthly && category.budget&.prorated?
  end

  def pace_day(today)
    return 0 if today < @date.beginning_of_month
    return @date.end_of_month.day if today > @date.end_of_month
    today.day
  end

  def ramp_value(day, days_in_month)
    (monthly_budget_rate * day / days_in_month.to_f).round(2)
  end

  def monthly_budget_curve
    days = @date.end_of_month.day
    return @date.all_month.index_with { effective_budget } unless prorated_active?
    @date.all_month.each_with_index.with_object({}) do |(d, i), h|
      h[d] = ramp_value(i + 1, days)
    end
  end

  def ytd_budget_curve
    current = date_range.begin.beginning_of_month
    acc = 0
    {}.tap do |h|
      while current <= date_range.end
        acc += monthly_budget_rate
        h[current] = acc
        current = current.next_month
      end
    end
  end
end
