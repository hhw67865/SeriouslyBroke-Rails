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

  def initialize(user:, date:, period: :monthly, show_total: true)
    @user = user
    @date = date
    @period = period
    @show_total = show_total
  end

  def ytd?
    period == :ytd
  end

  # === Expenses Tab ===

  def expenses_chart_data
    @expenses_chart_data ||= compute_expenses_chart_data
  end

  def total_expenses
    @total_expenses ||= expenses_scope.where(date: period_range).sum(:amount)
  end

  def total_tracked_expenses
    @total_tracked_expenses ||= tracked_expenses_scope.where(date: period_range).sum(:amount)
  end

  def expense_categories_breakdown
    @expense_categories_breakdown ||= tracked_expense_categories
      .map { |category| { name: category.name, amount: category.calculator(@date, period: period).total_amount } }
      .reject { |c| c[:amount].zero? }
      .sort_by { |c| -c[:amount] }
  end

  def total_budget
    @total_budget ||= begin
      monthly = tracked_expense_categories.sum { |cat| cat.calculator(@date).monthly_budget_rate.to_f }
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
    [COLORS[:dusty_teal], COLORS[:brand], COLORS[:terracotta]]
  end

  # === Income Tab ===

  def income_chart_data
    @income_chart_data ||= compute_income_chart_data
  end

  def total_income
    @total_income ||= tracked_income_scope.where(date: period_range).sum(:amount)
  end

  def income_categories_breakdown
    @income_categories_breakdown ||= tracked_income_categories
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
    @savings_chart_data ||= compute_savings_chart_data
  end

  def total_savings_contribution
    @total_savings_contribution ||= tracked_savings_scope.where(date: period_range).sum(:amount)
  end

  def total_savings_balance
    @total_savings_balance ||= tracked_savings_scope.sum(:amount)
  end

  def savings_categories_breakdown
    @savings_categories_breakdown ||= build_savings_breakdown
  end

  def savings_chart_colors
    [COLORS[:brand_dark]]
  end

  # === Tracked Filter ===

  def categories_for_filter(type)
    all_categories_by_type[type.to_s] || []
  end

  def tracked_count_for(type)
    categories_for_filter(type).count(&:tracked?)
  end

  private

  def all_categories_by_type
    @all_categories_by_type ||= @user.categories.order(:name).group_by(&:category_type)
  end

  def tracked_expense_categories
    @tracked_expense_categories ||= @user.categories.expenses.tracked.includes(:budget, items: :entries)
  end

  def tracked_income_categories
    @tracked_income_categories ||= @user.categories.incomes.tracked.includes(items: :entries)
  end

  def tracked_savings_categories
    @tracked_savings_categories ||= @user.categories.savings.tracked.includes(items: :entries)
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
    @monthly_budget_rate ||= tracked_expense_categories.sum { |cat| cat.calculator(@date).monthly_budget_rate.to_f }
  end

  def calculate_income_change
    current = total_income
    previous = tracked_income_scope.where(date: previous_month_range).sum(:amount)
    return 0 if previous.zero?

    ((current - previous) / previous.to_f * 100).round
  end

  def compute_expenses_chart_data
    return [] if total_expenses.zero?

    ytd? ? ytd_expenses_data : monthly_expenses_data
  end

  def ytd_expenses_data
    tracked = tracked_expenses_scope.group_by_month(:date, range: period_range, default_value: 0).sum(:amount)
    series = [{ name: "Tracked", data: calculate_running_total(tracked).transform_keys { |d| d.strftime("%b %Y") } }]
    if @show_total
      total = expenses_scope.group_by_month(:date, range: period_range, default_value: 0).sum(:amount)
      series << { name: "Total", data: calculate_running_total(total).transform_keys { |d| d.strftime("%b %Y") } }
    end
    series
  end

  def monthly_expenses_data
    tracked = tracked_expenses_scope.group_by_day(:date, range: period_range, default_value: 0).sum(:amount)
    series = [{ name: "Tracked", data: calculate_running_total(tracked) }]
    if @show_total
      total = expenses_scope.group_by_day(:date, range: period_range, default_value: 0).sum(:amount)
      series << { name: "Total", data: calculate_running_total(total) }
    end
    series
  end

  def expenses_scope
    @user.entries.expenses
  end

  def tracked_expenses_scope
    @user.entries.expenses.tracked
  end

  def tracked_income_scope
    @user.entries.incomes.tracked
  end

  def tracked_savings_scope
    @user.entries.savings.tracked
  end

  def compute_income_chart_data
    range = ytd? ? period_range : six_month_range
    series = tracked_income_categories.map do |category|
      monthly_data = category.entries.group_by_month(:date, range: range, default_value: 0).sum(:amount)
      { name: category.name, data: monthly_data.transform_keys { |d| d.strftime("%b %Y") } }
    end
    series.reject { |s| s[:data].values.all?(&:zero?) }
  end

  def compute_savings_chart_data
    range = savings_chart_range
    initial = savings_scope.where(date: ...range.begin).sum(:amount)
    contributions = savings_scope.where(date: range).sum(:amount)
    return {} if initial.zero? && contributions.zero?

    build_savings_running_total(range, initial)
  end

  def savings_chart_range
    ytd? ? period_range : six_month_range
  end

  def savings_scope
    tracked_savings_scope
  end

  def build_savings_running_total(range, initial_balance)
    monthly_data = savings_scope.group_by_month(:date, range: range, default_value: 0).sum(:amount)
    current_total = initial_balance
    monthly_data.each_with_object({}) do |(d, amount), result|
      current_total += amount
      result[d.strftime("%b %Y")] = current_total
    end
  end

  def build_savings_breakdown
    breakdown = tracked_savings_categories.map do |category|
      {
        name: category.name,
        amount: category.calculator(@date, period: period).total_amount,
        balance: category.entries.sum(:amount)
      }
    end
    breakdown.sort_by { |c| -c[:amount] }
  end
end
