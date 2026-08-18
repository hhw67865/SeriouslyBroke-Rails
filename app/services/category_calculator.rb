# frozen_string_literal: true

# WHAT A CATEGORY SPENT, AND NOTHING ABOUT WHAT IT WAS ALLOWED TO SPEND.
#
# The cap family is deleted with the cap era (plan 3, task 4, decision 6): `#budget_percentage`,
# `#monthly_budget_rate`, `#effective_budget`, `#budget_curve` and the two private curve builders
# all resolved `category.budget&.amount`, and `budgets.category_id` is nil on every row — so each
# answered its empty form for every category the app can hold. `#budget_pace`,
# `#budget_pace_percentage` and the prorated ramp went one task earlier with `budgets.prorated`.
#
# HOW MUCH A CATEGORY MAY SPEND IS A POOL QUESTION NOW, and the pool answers it: an envelope holds
# what a rule put in it, and `PoolCalculator#balance` is the one reader for that. A category-level
# second opinion is exactly what the cutover abolished.
#
# `#monthly_contribution` goes with them for a different reason: it was `#total_amount` behind a
# `category.savings?` gate, so it was one reader wearing two names. Its two call sites (the
# category summary card and the category index card) read `#total_amount` directly, and the savings
# ARMS around them are DELETED in plan 3 task 5 with the category type — so the gate has no
# predicate to be, either.
class CategoryCalculator
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
