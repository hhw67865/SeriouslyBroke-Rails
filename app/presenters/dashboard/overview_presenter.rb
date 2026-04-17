# frozen_string_literal: true

module Dashboard
  class OverviewPresenter
    include CategoriesHelper

    def initialize(parent)
      @parent = parent
      @user = parent.user
    end

    # === Chart: Income vs Expenses with Savings net delta ===

    def overview_chart_data
      @overview_chart_data ||= compute_overview_chart_data
    end

    def overview_chart_colors
      [
        DashboardPresenter::COLORS[:brand_dark],
        DashboardPresenter::COLORS[:terracotta],
        DashboardPresenter::COLORS[:dusty_teal]
      ]
    end

    # === Cash-flow stats ===

    # Pure cash flow: what came in vs what actually left.
    # Savings contributions are tracked separately via savings_delta — they are
    # an allocation of money you still hold, not money spent.
    def net_amount
      @net_amount ||= @parent.total_tracked_income - @parent.total_tracked_expenses
    end

    def expense_ratio
      income = @parent.total_tracked_income
      return 0 if income.zero?

      (@parent.total_tracked_expenses / income.to_f * 100).round(1)
    end

    # === Savings flow (separate from net) ===

    def savings_contributions_total
      @savings_contributions_total ||= @user.entries.savings.tracked.where(date: period_range).sum(:amount)
    end

    def savings_withdrawals_total
      @savings_withdrawals_total ||= @user.entries.pool_covered_expenses.tracked.where(date: period_range).sum(:amount)
    end

    def savings_delta
      savings_contributions_total - savings_withdrawals_total
    end

    # === Month-over-month comparison (monthly mode only) ===

    def income_change
      return nil if @parent.ytd?

      @income_change ||= percentage_change(
        @user.entries.incomes.tracked.where(date: previous_range).sum(:amount),
        @parent.total_tracked_income
      )
    end

    def expenses_change
      return nil if @parent.ytd?

      @expenses_change ||= percentage_change(
        @user.entries.expenses.tracked.where(date: previous_range).sum(:amount),
        @parent.total_tracked_expenses
      )
    end

    # === Budget health (budgetable expenses only) ===

    def budgeted_total
      @budgeted_total ||= all_budgeted_breakdown.sum { |c| c[:amount] }
    end

    def budget_used_percentage
      budget = @parent.total_budget
      return 0 if budget.zero?

      (budgeted_total / budget.to_f * 100).round
    end

    # === Top spending (all expense categories combined — cash flow view) ===

    def top_expense_categories
      @top_expense_categories ||= @parent.expense_categories_breakdown.first(5)
    end

    # === Expense split ===

    def all_budgeted_categories_breakdown
      all_budgeted_breakdown
    end

    def pool_covered_total
      @pool_covered_total ||= pool_covered_categories_breakdown.sum { |c| c[:amount] }
    end

    def pool_covered_categories_breakdown
      @pool_covered_categories_breakdown ||= @parent.build_category_breakdown(@parent.tracked_pool_covered_expense_categories)
    end

    private

    delegate :period_range, :six_month_range, to: :@parent

    def previous_range
      @previous_range ||= @parent.previous_month_range
    end

    def all_budgeted_breakdown
      # Sort by most over-budget first, then by highest spend for non-budgeted
      @all_budgeted_breakdown ||= @parent.build_category_breakdown(@parent.tracked_budgetable_expense_categories)
        .sort_by { |c| [c[:budget] ? -(c[:amount] - c[:budget]) : 1, -c[:amount]] }
    end

    def percentage_change(previous, current)
      return 0 if previous.zero?

      ((current - previous) / previous.to_f * 100).round
    end

    def compute_overview_chart_data
      range = @parent.ytd? ? period_range : six_month_range
      series = build_chart_series(range)
      series.all? { |s| s[:data].values.all?(&:zero?) } ? [] : series
    end

    def build_chart_series(range)
      [
        { name: "Income", data: monthly_totals(@user.entries.incomes.tracked, range) },
        { name: "Expenses", data: monthly_totals(@user.entries.expenses.tracked, range) },
        { name: "Net Savings", data: monthly_savings_delta(range) }
      ]
    end

    def monthly_totals(scope, range)
      scope
        .group_by_month(:date, range: range, default_value: 0)
        .sum(:amount)
        .transform_keys { |d| d.strftime("%b %Y") }
    end

    def monthly_savings_delta(range)
      contributions = monthly_totals(@user.entries.savings.tracked, range)
      withdrawals = monthly_totals(@user.entries.pool_covered_expenses.tracked, range)
      contributions.each_with_object({}) do |(month, amount), result|
        result[month] = amount - withdrawals.fetch(month, 0)
      end
    end
  end
end
