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
    @tracked_expense_categories ||= @user.categories.expenses.tracked.includes(:budget, :pool, items: :entries)
  end

  # ---------------------------------------------------------------------------------------------
  # THE FINDING-1 BRIDGE (plan 3, task 3). TASK 4 OWNS THE SEMANTICS OF THIS PAGE; THIS TASK OWES
  # IT ONLY THAT IT COMPILES AND RENDERS.
  #
  # The four readers below used to split expense spending by `Category#budgetable?` ("no pool at
  # all") against `#pool_covered?` ("any pool"). Both predicates and both `Entry` scopes are gone
  # with the cap: a category with no pool is not a shape this app can hold any more, so the first
  # set would be empty and the second everything, and every figure built on the pair would read
  # $0.00 / 100% without saying why.
  #
  # Re-pointed MECHANICALLY to the nearest post-cutover truth: the buffer-funded set (an expense
  # category pointing at an ACCOUNT — money nothing reserves) where "budgetable" stood, and the
  # enveloped set (pointing at a budget envelope or a savings goal) where "pool-covered" stood.
  # That is the same line `Category#buffer_funded?` draws for the suggestion engine and the
  # Categories page, so this page at least agrees with the two screens beside it.
  #
  # IT IS NOT THE RIGHT ANSWER AND IS NOT MEANT TO BE. "Budgeted" on this page still means "against
  # a category CAP", and there are no caps — so `total_budget` is $0.00 and the budget-health block
  # says nothing useful whatever set it is fed. Task 4 replaces or deletes each chart with a
  # pool-level reader; the report for this task says exactly what these figures read in the
  # meantime.
  # ---------------------------------------------------------------------------------------------
  def tracked_budgetable_expense_categories
    @tracked_budgetable_expense_categories ||= tracked_expense_categories.select(&:buffer_funded?)
  end

  def tracked_pool_covered_expense_categories
    @tracked_pool_covered_expense_categories ||= tracked_expense_categories.reject(&:buffer_funded?)
  end

  # The entry-level half of the same bridge, over the same line. `account_pool_ids` is a sub-SELECT
  # rather than a loaded array so these compose into the `group_by_day`/`group_by_month` scopes the
  # charts build on without a second round trip.
  def buffer_funded_expenses = @user.entries.expenses.where(categories: { pool_id: account_pool_ids })

  def enveloped_expenses = @user.entries.expenses.where.not(categories: { pool_id: account_pool_ids })

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

  def account_pool_ids = @user.pools.accounts.select(:id)

  def build_category_entry(category)
    calc = category.calculator(@date, period: period)
    entry = { id: category.id, name: category.name, amount: calc.total_amount }
    enrich_with_budget(entry, calc)
    entry
  end

  # `category` is no longer consulted: the gate was `category.budgetable? && effective_budget
  # positive`, and with the cap deleted `CategoryCalculator#effective_budget` is nil for every
  # category — so the positive test is the whole gate and this block never fires. The `prorated`
  # and `budget_pace` keys went with it (a pace is a cap spread across the days of a month), and
  # `over_budget` is measured against the budget itself, which is what it always was for a rule
  # that did not prorate.
  def enrich_with_budget(entry, calc)
    return unless calc.effective_budget.to_f.positive?

    spent = calc.total_amount
    entry[:budget] = calc.effective_budget
    entry[:budget_percentage] = calc.budget_percentage
    entry[:over_budget] = spent > calc.effective_budget
    entry[:budget_diff] = (spent - calc.effective_budget).abs
  end
end
