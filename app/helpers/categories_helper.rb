# frozen_string_literal: true

# WHAT WENT WITH THE CAP ERA (plan 3, task 4, decision 6), each grepped callerless over
# `app lib db/seeds.rb config` after the change:
#
# * `#period_budget_label` — "Monthly Budget" / "YTD Budget", the label on the two stat cards that
#   printed the sum of a user's category caps.
# * `#budget_line_series` — the flat/accumulating "Budget" line drawn across the expenses chart.
# * `#months_in_range` — a monthly cap multiplied out across a YTD range, and nothing else.
# * `#budget_status` / `#budget_status_color` — "On track" / "Over budget" / "Budget exceeded" off
#   a percentage-of-cap. These went callerless one task earlier, when the category page's capped
#   arm was deleted; they are swept up here with the family they belonged to.
module CategoriesHelper
  # Period-aware label helpers to reduce view conditionals
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

  def calculate_running_total(data_hash)
    total = 0
    data_hash.each_with_object({}) do |(date, amount), result|
      total += amount
      result[date] = total
    end
  end

  def savings_evolution_series(category, range)
    # Calculate total savings before the start of the range
    initial_balance = category.entries.where(date: ...range.begin).sum(:amount)

    # Get monthly sums within the range (Groupdate handles ordering with range option)
    monthly_data = category.entries.group_by_month(:date, range: range, default_value: 0).sum(:amount)

    # Accumulate
    current_total = initial_balance
    monthly_data.each_with_object({}) do |(date, amount), result|
      current_total += amount
      result[date] = current_total
    end
  end
end
