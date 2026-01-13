# frozen_string_literal: true

module CategoriesHelper
  # Period-aware label helpers to reduce view conditionals
  def period_budget_label
    current_period == :ytd ? "YTD Budget" : "Monthly Budget"
  end

  def period_amount_label(category_type)
    prefix = current_period == :ytd ? "YTD" : "Monthly"
    case category_type.to_sym
    when :expense then "#{prefix} Budget"
    when :income then "#{prefix} Income"
    when :savings then "#{prefix} Contribution"
    end
  end

  def period_items_label
    current_period == :ytd ? "Items This Year" : "Items This Month"
  end

  def period_trend_label
    current_period == :ytd ? "YTD" : "Monthly"
  end

  def period_time_label
    current_period == :ytd ? "this year" : "this month"
  end

  def budget_status(percentage)
    case percentage
    when (101..) then "Budget exceeded"
    when (91..100) then "Almost depleted"
    when (76..90) then "Warning zone"
    when (51..75) then "On track"
    else "Well under budget"
    end
  end

  def budget_status_color(percentage)
    case percentage
    when (91..) then "bg-status-danger"
    when (76..90) then "bg-status-warning"
    else "bg-brand"
    end
  end

  def calculate_running_total(data_hash)
    total = 0
    data_hash.each_with_object({}) do |(date, amount), result|
      total += amount
      result[date] = total
    end
  end

  def budget_line_series(amount, range, group: :day)
    if group == :month
      # For YTD view, show accumulated budget per month
      current_date = range.begin.beginning_of_month
      end_date = range.end
      accumulated = 0
      result = {}

      while current_date <= end_date
        accumulated += amount
        result[current_date] = accumulated
        current_date = current_date.next_month
      end

      result
    else
      # Daily view - flat line at budget amount
      range.index_with { amount }
    end
  end

  def savings_evolution_series(category, range)
    # Calculate total savings before the start of the range
    initial_balance = category.entries.where(date: ...range.begin).sum(:amount)

    # Get monthly sums within the range
    monthly_data = category.entries.group_by_month(:date, range: range).sum(:amount)

    # Accumulate
    current_total = initial_balance
    monthly_data.each_with_object({}) do |(date, amount), result|
      current_total += amount
      result[date] = current_total
    end
  end
end
