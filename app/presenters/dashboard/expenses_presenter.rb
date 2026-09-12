# frozen_string_literal: true

module Dashboard
  # Spending, by the lane it came out of. See DashboardPresenter#tracked_unruled_categories for the
  # one predicate all six figures below are built on.
  class ExpensesPresenter
    include CategoriesHelper

    def initialize(parent)
      @parent = parent
      @user = parent.user
    end

    # === Chart: unruled spending, running total ===

    def expenses_chart_data
      @expenses_chart_data ||= compute_expenses_chart_data
    end

    def expenses_chart_colors
      [DashboardPresenter::COLORS[:brand], DashboardPresenter::COLORS[:terracotta]]
    end

    # === Totals (all expenses — used by cash-flow views) ===

    def total_expenses
      @total_expenses ||= expenses_scope.where(date: period_range).sum(:amount)
    end

    def total_tracked_expenses
      @total_tracked_expenses ||= tracked_expenses_scope.where(date: period_range).sum(:amount)
    end

    # === Totals (unruled lane — spending no rule claims money for) ===

    def total_unruled_expenses
      @total_unruled_expenses ||= unruled_expenses_scope.where(date: period_range).sum(:amount)
    end

    def total_tracked_unruled_expenses
      @total_tracked_unruled_expenses ||= tracked_unruled_expenses_scope.where(date: period_range).sum(:amount)
    end

    # === Totals (ruled lane — spending a rule claimed before it happened) ===

    def total_ruled_expenses
      @total_ruled_expenses ||= ruled_expenses_scope.where(date: period_range).sum(:amount)
    end

    def total_tracked_ruled_expenses
      @total_tracked_ruled_expenses ||= tracked_ruled_expenses_scope.where(date: period_range).sum(:amount)
    end

    # === Category breakdowns ===

    def expense_categories_breakdown
      @expense_categories_breakdown ||= @parent.build_category_breakdown(@parent.tracked_expense_categories)
    end

    def untracked_expense_categories_breakdown
      @untracked_expense_categories_breakdown ||= @parent.build_category_breakdown(@parent.untracked_expense_categories)
    end

    private

    delegate :period_range, :six_month_range, to: :@parent

    def expenses_scope
      @user.entries.expenses
    end

    def tracked_expenses_scope
      @user.entries.expenses.tracked
    end

    def unruled_expenses_scope
      @parent.unruled_expenses
    end

    def tracked_unruled_expenses_scope
      @parent.unruled_expenses.tracked
    end

    def ruled_expenses_scope
      @parent.ruled_expenses
    end

    def tracked_ruled_expenses_scope
      @parent.ruled_expenses.tracked
    end

    def compute_expenses_chart_data
      return [] if total_unruled_expenses.zero?

      @parent.ytd? ? ytd_expenses_data : monthly_expenses_data
    end

    def ytd_expenses_data
      series = [{ name: "Tracked", data: monthly_running_total(tracked_unruled_expenses_scope) }]
      series << { name: "Total", data: monthly_running_total(unruled_expenses_scope) } if @parent.show_total?
      series
    end

    def monthly_running_total(scope)
      data = scope.group_by_month(:date, range: period_range, default_value: 0).sum(:amount)
      calculate_running_total(data).transform_keys { |d| d.strftime("%b %Y") }
    end

    def monthly_expenses_data
      tracked = tracked_unruled_expenses_scope.group_by_day(:date, range: period_range, default_value: 0).sum(:amount)
      series = [{ name: "Tracked", data: calculate_running_total(tracked) }]
      if @parent.show_total?
        total = unruled_expenses_scope.group_by_day(:date, range: period_range, default_value: 0).sum(:amount)
        series << { name: "Total", data: calculate_running_total(total) }
      end
      series
    end
  end
end
