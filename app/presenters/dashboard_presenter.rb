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
  #
  # THE SAVINGS TAB'S THIRTEEN DELEGATIONS ARE GONE (plan 3, task 5) — the chart, the flow chart,
  # the two contribution totals, the balance, the two breakdowns, the withdrawals and
  # `#savings_rate`, all of them summing entries in a savings CATEGORY. `#pools_summary` and
  # `#total_pools_balance` are the two that survived the tab, because the ALL tab renders the goals
  # strip they feed; they moved to `Dashboard::OverviewPresenter` rather than dying with the class.
  delegate :net_amount,
           :expense_ratio,
           :top_expense_categories,
           :buffer_categories_breakdown,
           :envelope_categories_breakdown,
           :pools_summary,
           :total_pools_balance,
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

  # `includes(:budget)` IS GONE WITH ITS READER (plan 3, task 4). Task 3 measured the preload at
  # 5 statements against 18 without it and kept it on that number — but the 18 were 18 queries for
  # an answer that was nil every time, and what justified paying for them was `#total_budget`,
  # which this task deletes. `Category has_one :budget` goes with it.
  def tracked_expense_categories
    @tracked_expense_categories ||= @user.categories.expenses.tracked.includes(:pool, items: :entries)
  end

  # ---------------------------------------------------------------------------------------------
  # WHICH LANE A CATEGORY SPENDS FROM — the split this page is built on, and the only split it
  # draws. Task 3 landed these four as a mechanical bridge with the semantics deferred here;
  # decision 6 keeps the line and drops the cap-era names that sat on top of it.
  #
  # BUFFER: an expense category pointing at an ACCOUNT. Nothing reserves this money — it is spent
  # straight out of the account it lands in.
  # ENVELOPE: a category pointing at a budget envelope or a savings goal. The money was moved
  # there before it was spent.
  #
  # ONE PREDICATE, and it is `Category#buffer_funded?`'s — the same line the suggestion engine's
  # rate detector, the Categories page's `account_pointed` arm and the entry form's impact card
  # all draw. The four readers below are its SQL twin (`categories.pool_id IN (accounts)`) so the
  # entry sums and the category breakdowns beside them cannot describe different money.
  #
  # THE CATEGORY'S POOL, NOT `PoolBalanceLedger::ENTRY_POOL_ID`. The ledger resolves an entry
  # through `COALESCE(entries.pool_id, categories.pool_id)` because an entry may name the pool it
  # actually landed in; this page groups BY CATEGORY, so its rows and its totals have to answer
  # the same question or the breakdown would not sum to the stat card above it. Nothing writes
  # `entries.pool_id` today (it is not permitted by EntriesController and is nil on every row), so
  # the two readers agree — but they are answers to different questions and the day an override
  # can be written this page still wants the category's lane.
  # ---------------------------------------------------------------------------------------------
  def tracked_buffer_funded_categories
    @tracked_buffer_funded_categories ||= tracked_expense_categories.select(&:buffer_funded?)
  end

  def tracked_enveloped_categories
    @tracked_enveloped_categories ||= tracked_expense_categories.reject(&:buffer_funded?)
  end

  # The entry-level half of the same line. `account_pool_ids` is a sub-SELECT rather than a loaded
  # array so these compose into the `group_by_day`/`group_by_month` scopes the charts build on
  # without a second round trip.
  def buffer_funded_expenses = @user.entries.expenses.where(categories: { pool_id: account_pool_ids })

  def enveloped_expenses = @user.entries.expenses.where.not(categories: { pool_id: account_pool_ids })

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

  # A NAME AND A FIGURE, and that is the whole row now. `#enrich_with_budget` used to add
  # `:budget`, `:budget_percentage`, `:over_budget` and `:budget_diff` off the category's cap;
  # the cap is gone and so are the four keys and every view arm that read them (decision 6).
  def build_category_breakdown(categories)
    results = categories.map do |category|
      { id: category.id, name: category.name, amount: category.calculator(@date, period: period).total_amount }
    end
    results.reject { |c| c[:amount].zero? }.sort_by { |c| -c[:amount] }
  end

  private

  def account_pool_ids = @user.pools.accounts.select(:id)
end
