# frozen_string_literal: true

# What a category spent over a month or a year to date, and what it spent it on. How much it MAY
# spend is a rule question, and ClaimCalculator answers that one.
class CategoryStats
  attr_reader :category, :date, :date_range, :period

  def initialize(category, date = category.user.today, period: :monthly)
    @category = category
    @date = date
    @period = period
    @date_range = compute_date_range(date)
  end

  def total_amount
    category.entries.where(date: date_range).sum(:amount)
  end

  def previous_month_change_percentage
    return 0 unless category.income? && !previous_month_amount.zero?

    calculate_percentage_change(current_amount, previous_month_amount)
  end

  def previous_month_trend
    percentage = previous_month_change_percentage
    percentage >= 0 ? :up : :down
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
end
