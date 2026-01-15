# frozen_string_literal: true

# Presenter for the dashboard view.
# Pre-computes chart data and category breakdowns for expenses, income, and savings tabs.
#
# Usage in controller:
#   @presenter = DashboardPresenter.new(user: current_user, date: selected_date, period: current_period)
#
# Usage in view:
#   @presenter.expenses_chart_data
#   @presenter.expense_categories_breakdown
#
class DashboardPresenter
  include CategoriesHelper

  # Chart color palette - harmonious with brand color (#C9C78B olive/sage)
  COLORS = {
    brand: "#C9C78B", # Primary olive/sage
    brand_dark: "#a9a76b", # Darker olive
    terracotta: "#C4977A", # Warm muted coral (expenses)
    dusty_teal: "#7BA3A8", # Muted teal (budget line)
    warm_sand: "#D4B896", # Light warm neutral
    dusty_rose: "#C9A9A9", # Muted pink
    slate: "#8B9A9C", # Muted blue-gray
    sage_light: "#DCD9B4" # Lighter sage
  }.freeze

  attr_reader :date, :period

  def initialize(user:, date:, period: :monthly)
    @user = user
    @date = date
    @period = period
  end

  def ytd?
    period == :ytd
  end

  # === Expenses Tab ===

  def expenses_chart_data
    @expenses_chart_data ||= begin
      return {} if total_expenses.zero?

      if ytd?
        monthly_totals = expense_entries.group_by_month(:date, range: period_range, default_value: 0).sum(:amount)
        data = calculate_running_total(monthly_totals)
        data.transform_keys { |d| d.strftime("%b %Y") }
      else
        daily_totals = expense_entries.group_by_day(:date, range: period_range, default_value: 0).sum(:amount)
        calculate_running_total(daily_totals)
      end
    end
  end

  def total_expenses
    @total_expenses ||= expense_entries.where(date: period_range).sum(:amount)
  end

  def expense_categories_breakdown
    @expense_categories_breakdown ||= expense_categories
      .map { |category| { name: category.name, amount: category.calculator(@date, period: period).total_amount } }
      .reject { |c| c[:amount].zero? }
      .sort_by { |c| -c[:amount] }
  end

  def total_budget
    @total_budget ||= begin
      monthly = expense_categories.sum { |cat| cat.calculator(@date).monthly_budget_rate.to_f }
      ytd? ? monthly * months_in_range(period_range) : monthly
    end
  end

  def budget_line_data
    return {} if total_budget.zero?

    if ytd?
      budget_line_series(monthly_budget_rate, period_range, group: :month)
        .transform_keys { |d| d.strftime("%b %Y") }
    else
      budget_line_series(total_budget, period_range)
    end
  end

  def expenses_chart_colors
    [COLORS[:terracotta], COLORS[:dusty_teal]]
  end

  # === Income Tab ===

  def income_chart_data
    @income_chart_data ||= begin
      range = ytd? ? period_range : six_month_range
      income_categories.map do |category|
        monthly_data = category.entries.group_by_month(:date, range: range, default_value: 0).sum(:amount)
        formatted_data = monthly_data.transform_keys { |d| d.strftime("%b %Y") }
        { name: category.name, data: formatted_data }
      end.reject { |series| series[:data].values.all?(&:zero?) }
    end
  end

  def total_income
    @total_income ||= income_entries.where(date: period_range).sum(:amount)
  end

  def income_categories_breakdown
    @income_categories_breakdown ||= income_categories
      .map { |category| { name: category.name, amount: category.calculator(@date, period: period).total_amount } }
      .reject { |c| c[:amount].zero? }
      .sort_by { |c| -c[:amount] }
  end

  def income_change_percentage
    return nil if ytd?

    @income_change_percentage ||= calculate_income_change
  end

  def income_chart_colors
    [COLORS[:brand], COLORS[:dusty_teal], COLORS[:terracotta], COLORS[:warm_sand], COLORS[:dusty_rose], COLORS[:slate]]
  end

  # === Savings Tab ===

  def savings_chart_data
    @savings_chart_data ||= begin
      range = ytd? ? period_range : six_month_range
      initial_balance = savings_entries.where(date: ...range.begin).sum(:amount)
      period_contributions = savings_entries.where(date: range).sum(:amount)

      # Return empty if no balance and no contributions
      return {} if initial_balance.zero? && period_contributions.zero?

      monthly_data = savings_entries.group_by_month(:date, range: range, default_value: 0).sum(:amount)

      current_total = initial_balance
      monthly_data.each_with_object({}) do |(d, amount), result|
        current_total += amount
        result[d.strftime("%b %Y")] = current_total
      end
    end
  end

  def total_savings_contribution
    @total_savings_contribution ||= savings_entries.where(date: period_range).sum(:amount)
  end

  def total_savings_balance
    @total_savings_balance ||= savings_entries.sum(:amount)
  end

  def savings_categories_breakdown
    @savings_categories_breakdown ||= savings_categories.map do |category|
      {
        name: category.name,
        amount: category.calculator(@date, period: period).total_amount,
        balance: category.entries.sum(:amount)
      }
    end.sort_by { |c| -c[:amount] }
  end

  def savings_chart_colors
    [COLORS[:brand_dark]]
  end

  private

  def expense_categories
    @expense_categories ||= @user.categories.expenses.includes(:budget, items: :entries)
  end

  def income_categories
    @income_categories ||= @user.categories.incomes.includes(items: :entries)
  end

  def savings_categories
    @savings_categories ||= @user.categories.savings.includes(items: :entries)
  end

  def expense_entries
    Entry.joins(item: :category).where(categories: { user_id: @user.id, category_type: :expense })
  end

  def income_entries
    Entry.joins(item: :category).where(categories: { user_id: @user.id, category_type: :income })
  end

  def savings_entries
    Entry.joins(item: :category).where(categories: { user_id: @user.id, category_type: :savings })
  end

  def period_range
    @period_range ||= ytd? ? ytd_range : month_range
  end

  def month_range
    @month_range ||= @date.all_month
  end

  def ytd_range
    @ytd_range ||= @date.beginning_of_year..@date.end_of_month
  end

  def six_month_range
    @six_month_range ||= (@date.beginning_of_month - 5.months)..@date.end_of_month
  end

  def previous_month_range
    @previous_month_range ||= (@date - 1.month).all_month
  end

  def monthly_budget_rate
    @monthly_budget_rate ||= expense_categories.sum { |cat| cat.calculator(@date).monthly_budget_rate.to_f }
  end

  def calculate_income_change
    current = total_income
    previous = income_entries.where(date: previous_month_range).sum(:amount)
    return 0 if previous.zero?

    ((current - previous) / previous.to_f * 100).round
  end
end
