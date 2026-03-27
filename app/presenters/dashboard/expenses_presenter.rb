# frozen_string_literal: true

module Dashboard
  class ExpensesPresenter
    include CategoriesHelper

    def initialize(parent)
      @parent = parent
      @user = parent.user
    end

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
      @expense_categories_breakdown ||= @parent.build_category_breakdown(@parent.tracked_expense_categories)
    end

    def untracked_expense_categories_breakdown
      @untracked_expense_categories_breakdown ||= @parent.build_category_breakdown(@parent.untracked_expense_categories)
    end

    def total_budget
      @total_budget ||= begin
        monthly = @parent.tracked_expense_categories.sum { |cat| cat.calculator(@parent.date).monthly_budget_rate.to_f }
        @parent.ytd? ? monthly * months_in_range(period_range) : monthly
      end
    end

    def budget_line_data
      return {} if total_budget.zero?

      if @parent.ytd?
        budget_line_series(monthly_budget_rate, period_range, group: :month)
          .transform_keys { |d| d.strftime("%b %Y") }
      else
        budget_line_series(total_budget, period_range)
      end
    end

    def expenses_chart_colors
      [DashboardPresenter::COLORS[:dusty_teal], DashboardPresenter::COLORS[:brand], DashboardPresenter::COLORS[:terracotta]]
    end

    private

    delegate :period_range, :six_month_range, to: :@parent

    def expenses_scope
      @user.entries.expenses
    end

    def tracked_expenses_scope
      @user.entries.expenses.tracked
    end

    def monthly_budget_rate
      @monthly_budget_rate ||= @parent.tracked_expense_categories.sum { |cat| cat.calculator(@parent.date).monthly_budget_rate.to_f }
    end

    def compute_expenses_chart_data
      return [] if total_expenses.zero?

      @parent.ytd? ? ytd_expenses_data : monthly_expenses_data
    end

    def ytd_expenses_data
      series = [{ name: "Tracked", data: monthly_running_total(tracked_expenses_scope) }]
      series << { name: "Total", data: monthly_running_total(expenses_scope) } if @parent.show_total?
      series
    end

    def monthly_running_total(scope)
      data = scope.group_by_month(:date, range: period_range, default_value: 0).sum(:amount)
      calculate_running_total(data).transform_keys { |d| d.strftime("%b %Y") }
    end

    def monthly_expenses_data
      tracked = tracked_expenses_scope.group_by_day(:date, range: period_range, default_value: 0).sum(:amount)
      series = [{ name: "Tracked", data: calculate_running_total(tracked) }]
      if @parent.show_total?
        total = expenses_scope.group_by_day(:date, range: period_range, default_value: 0).sum(:amount)
        series << { name: "Total", data: calculate_running_total(total) }
      end
      series
    end
  end
end
