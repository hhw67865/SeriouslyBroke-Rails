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
#
# AND WHAT WENT WITH THE SAVINGS CATEGORY (task 5): `#savings_evolution_series`, the running-total
# line on the category page's savings arm — one reader, deleted with that arm — and
# `#period_amount_label`'s `:savings` case, which returned "Monthly Contribution".
module CategoriesHelper
  # Period-aware label helpers to reduce view conditionals
  def period_amount_label(category_type)
    prefix = current_period == :ytd ? "YTD" : "Monthly"
    case category_type.to_sym
    when :expense then "#{prefix} Budget"
    when :income then "#{prefix} Income"
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
end
