# frozen_string_literal: true

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
