# frozen_string_literal: true

module CategoriesHelper
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

  def budget_line_series(amount, range)
    range.index_with do |_|
      amount
    end
  end

  def savings_evolution_series(category, range)
    # Calculate total savings before the start of the range
    initial_balance = category.entries.where("date < ?", range.begin).sum(:amount)

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
