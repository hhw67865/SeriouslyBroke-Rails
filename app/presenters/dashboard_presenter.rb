# frozen_string_literal: true

# Presenter for the dashboard view.
# Delegates tab-specific logic to focused sub-presenters while keeping shared
# date/period helpers, category loaders, and tracked filter methods here.
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
    sage_light: "#DCD9B4", # Lighter sage
    positive: "#a9a76b", # Brand dark olive (positive)
    negative: "#C4977A" # Terracotta (negative)
  }.freeze

  attr_reader :user, :date, :period

  def initialize(user:, date:, period: :monthly, show_total: true)
    @user = user
    @date = date
    @period = period
    @show_total = show_total
  end

  def show_total?
    @show_total
  end

  def ytd?
    period == :ytd
  end

  # === Sub-presenters ===

  def expenses
    @expenses ||= Dashboard::ExpensesPresenter.new(self)
  end

  def income
    @income ||= Dashboard::IncomePresenter.new(self)
  end

  def savings
    @savings ||= Dashboard::SavingsPresenter.new(self)
  end

  def overview
    @overview ||= Dashboard::OverviewPresenter.new(self)
  end

  # === Expenses Tab (delegated) ===

  delegate :expenses_chart_data,
           :total_expenses,
           :total_tracked_expenses,
           :total_budgetable_expenses,
           :total_tracked_budgetable_expenses,
           :total_pool_covered_expenses,
           :total_tracked_pool_covered_expenses,
           :expense_categories_breakdown,
           :untracked_expense_categories_breakdown,
           :total_budget,
           :budget_line_data,
           :expenses_chart_colors,
           to: :expenses

  # === Income Tab (delegated) ===

  delegate :income_chart_data,
           :total_income,
           :total_tracked_income,
           :income_categories_breakdown,
           :untracked_income_categories_breakdown,
           :income_change_percentage,
           :income_chart_colors,
           to: :income

  # === Savings Tab (delegated) ===

  delegate :savings_chart_data,
           :total_savings_contribution,
           :total_tracked_savings_contribution,
           :total_savings_balance,
           :savings_categories_breakdown,
           :untracked_savings_categories_breakdown,
           :savings_chart_colors,
           :flow_chart_data,
           :flow_chart_colors,
           :total_withdrawals,
           :pools_summary,
           :total_pools_balance,
           :savings_rate,
           to: :savings

  # === All/Overview Tab (delegated) ===

  delegate :overview_chart_data,
           :overview_chart_colors,
           :net_amount,
           :expense_ratio,
           :income_change,
           :expenses_change,
           :savings_contributions_total,
           :savings_withdrawals_total,
           :net_savings,
           :income_remaining,
           :budgeted_total,
           :budget_used_percentage,
           :top_expense_categories,
           :pool_covered_total,
           :all_budgeted_categories_breakdown,
           :pool_covered_categories_breakdown,
           to: :overview

  # === Tracked Filter ===

  def categories_for_filter(type)
    all_categories_by_type[type.to_s] || []
  end

  def tracked_count_for(type)
    categories_for_filter(type).count(&:tracked?)
  end

  # Shared date range helpers — accessible by sub-presenters

  def period_range
    @period_range ||= ytd? ? ytd_range : month_range
  end

  def six_month_range
    @six_month_range ||= (@date.beginning_of_month - 5.months)..@date.end_of_month
  end

  def ytd_range
    @ytd_range ||= @date.beginning_of_year..@date.end_of_month
  end

  # === Shared helpers for sub-presenters ===

  def all_categories_by_type
    @all_categories_by_type ||= @user.categories.order(:name).group_by(&:category_type)
  end

  def tracked_expense_categories
    @tracked_expense_categories ||= @user.categories.expenses.tracked.includes(:budget, :savings_pool, items: :entries)
  end

  def tracked_budgetable_expense_categories
    @tracked_budgetable_expense_categories ||= tracked_expense_categories.select(&:budgetable?)
  end

  def tracked_pool_covered_expense_categories
    @tracked_pool_covered_expense_categories ||= tracked_expense_categories.select(&:pool_covered?)
  end

  def tracked_income_categories
    @tracked_income_categories ||= @user.categories.incomes.tracked.includes(items: :entries)
  end

  def tracked_savings_categories
    @tracked_savings_categories ||= @user.categories.savings.tracked.includes(items: :entries)
  end

  def untracked_expense_categories
    @untracked_expense_categories ||= @user.categories.expenses.untracked.includes(:budget, items: :entries)
  end

  def untracked_income_categories
    @untracked_income_categories ||= @user.categories.incomes.untracked.includes(items: :entries)
  end

  def untracked_savings_categories
    @untracked_savings_categories ||= @user.categories.savings.untracked.includes(items: :entries)
  end

  def month_range
    @month_range ||= @date.all_month
  end

  def previous_month_range
    @previous_month_range ||= (@date - 1.month).all_month
  end

  def build_category_breakdown(categories)
    results = categories.map { |category| build_category_entry(category) }
    results.reject { |c| c[:amount].zero? }.sort_by { |c| -c[:amount] }
  end

  private

  def build_category_entry(category)
    calc = category.calculator(@date, period: period)
    entry = { id: category.id, name: category.name, amount: calc.total_amount }
    enrich_with_budget(entry, category, calc)
    entry
  end

  def enrich_with_budget(entry, category, calc)
    return unless category.budgetable? && calc.effective_budget.to_f.positive?

    pace = calc.budget_pace
    spent = calc.total_amount
    entry[:budget] = calc.effective_budget
    entry[:prorated] = category.budget.prorated?
    entry[:budget_percentage] = calc.budget_percentage
    entry[:budget_pace] = pace
    entry[:over_budget] = spent > pace
    entry[:budget_diff] = (spent - pace).abs
  end
end
