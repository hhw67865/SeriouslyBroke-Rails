# frozen_string_literal: true

# The Reports page. Tab-specific work belongs to the sub-presenters; the date and period helpers,
# the category loaders and the tracked filter are shared and live here.
class DashboardPresenter
  # Chart palette, harmonious with the brand olive/sage (#C9C78B).
  COLORS = {
    brand: "#C9C78B",
    brand_dark: "#a9a76b",
    terracotta: "#C4977A",
    dusty_teal: "#7BA3A8",
    warm_sand: "#D4B896",
    dusty_rose: "#C9A9A9",
    slate: "#8B9A9C",
    sage_light: "#DCD9B4",
    positive: "#a9a76b",
    negative: "#C4977A"
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

  def overview
    @overview ||= Dashboard::OverviewPresenter.new(self)
  end

  # === Expenses Tab (delegated) ===

  delegate :expenses_chart_data,
           :total_expenses,
           :total_tracked_expenses,
           :total_buffer_expenses,
           :total_tracked_buffer_expenses,
           :total_envelope_expenses,
           :total_tracked_envelope_expenses,
           :expense_categories_breakdown,
           :untracked_expense_categories_breakdown,
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

  # === All/Overview Tab (delegated) ===

  delegate :net_amount,
           :expense_ratio,
           :top_expense_categories,
           :buffer_categories_breakdown,
           :envelope_categories_breakdown,
           :savings_summary,
           :savings_target,
           :savings_progress,
           :total_savings_balance,
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

  # `includes(:rules)` because the two lanes below ask every row `#ruled?`.
  def tracked_expense_categories
    @tracked_expense_categories ||= @user.categories.expenses.tracked.includes(:rules, items: :entries)
  end

  # Which lane a category spends from, and the only split this page draws. The two entry scopes
  # below are `Category#ruled?` said in SQL, so the totals and the rows beneath them agree.

  def tracked_unruled_categories
    @tracked_unruled_categories ||= tracked_expense_categories.reject(&:ruled?)
  end

  def tracked_ruled_categories
    @tracked_ruled_categories ||= tracked_expense_categories.select(&:ruled?)
  end

  def unruled_expenses
    @unruled_expenses ||= @user.entries.expenses.where.not(categories: { id: Category.with_a_rule.select(:id) })
  end

  def ruled_expenses
    @ruled_expenses ||= @user.entries.expenses.where(categories: { id: Category.with_a_rule.select(:id) })
  end

  def tracked_income_categories
    @tracked_income_categories ||= @user.categories.incomes.tracked.includes(items: :entries)
  end

  def untracked_expense_categories
    @untracked_expense_categories ||= @user.categories.expenses.untracked.includes(items: :entries)
  end

  def untracked_income_categories
    @untracked_income_categories ||= @user.categories.incomes.untracked.includes(items: :entries)
  end

  def month_range
    @month_range ||= @date.all_month
  end

  def previous_month_range
    @previous_month_range ||= (@date - 1.month).all_month
  end

  # A name and a figure, and that is the whole row.
  def build_category_breakdown(categories)
    results = categories.map do |category|
      { id: category.id, name: category.name, amount: category.stats(@date, period: period).total_amount }
    end
    results.reject { |c| c[:amount].zero? }.sort_by { |c| -c[:amount] }
  end
end
