# frozen_string_literal: true

module Dashboard
  # SPENDING, BY THE LANE IT CAME OUT OF. See DashboardPresenter#tracked_buffer_funded_categories
  # for the one predicate all six figures below are built on.
  #
  # WHAT LEFT WITH THE CAP (plan 3, task 4, decision 6): `#total_budget`, `#budget_line_data`,
  # `#monthly_budget_rate` and `#sum_curves` — the "Budget" series drawn across the chart and the
  # stat card beside it. Every one of them resolved `CategoryCalculator#monthly_budget_rate`, which
  # read a category's cap, so all four answered $0.00 / `{}` for every user the app can now hold.
  class ExpensesPresenter
    include CategoriesHelper

    def initialize(parent)
      @parent = parent
      @user = parent.user
    end

    # === Chart: buffer spending, running total ===

    def expenses_chart_data
      @expenses_chart_data ||= compute_expenses_chart_data
    end

    # Two series, not three: the first colour used to be the Budget line's.
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

    # === Totals (buffer lane — spending nothing reserved money for) ===

    def total_buffer_expenses
      @total_buffer_expenses ||= buffer_expenses_scope.where(date: period_range).sum(:amount)
    end

    def total_tracked_buffer_expenses
      @total_tracked_buffer_expenses ||= tracked_buffer_expenses_scope.where(date: period_range).sum(:amount)
    end

    # === Totals (envelope lane — spending funded before it happened) ===

    def total_envelope_expenses
      @total_envelope_expenses ||= envelope_expenses_scope.where(date: period_range).sum(:amount)
    end

    def total_tracked_envelope_expenses
      @total_tracked_envelope_expenses ||= tracked_envelope_expenses_scope.where(date: period_range).sum(:amount)
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

    # `Entry.spendable` — every expense the household actually spent, which is every expense but an
    # account's opening record (fix round round 2 — item 3). These are the two scopes behind "Total
    # Unbudgeted Spending" and "Tracked Unbudgeted Spending", and the band of rows below them is
    # narrowed by `Category.spendable`: a total that counted a row the list could not show is a
    # total nobody can check.
    def expenses_scope
      @user.entries.spendable
    end

    def tracked_expenses_scope
      @user.entries.spendable.tracked
    end

    def buffer_expenses_scope
      @parent.buffer_funded_expenses
    end

    def tracked_buffer_expenses_scope
      @parent.buffer_funded_expenses.tracked
    end

    def envelope_expenses_scope
      @parent.enveloped_expenses
    end

    def tracked_envelope_expenses_scope
      @parent.enveloped_expenses.tracked
    end

    def compute_expenses_chart_data
      return [] if total_buffer_expenses.zero?

      @parent.ytd? ? ytd_expenses_data : monthly_expenses_data
    end

    def ytd_expenses_data
      series = [{ name: "Tracked", data: monthly_running_total(tracked_buffer_expenses_scope) }]
      series << { name: "Total", data: monthly_running_total(buffer_expenses_scope) } if @parent.show_total?
      series
    end

    def monthly_running_total(scope)
      data = scope.group_by_month(:date, range: period_range, default_value: 0).sum(:amount)
      calculate_running_total(data).transform_keys { |d| d.strftime("%b %Y") }
    end

    def monthly_expenses_data
      tracked = tracked_buffer_expenses_scope.group_by_day(:date, range: period_range, default_value: 0).sum(:amount)
      series = [{ name: "Tracked", data: calculate_running_total(tracked) }]
      if @parent.show_total?
        total = buffer_expenses_scope.group_by_day(:date, range: period_range, default_value: 0).sum(:amount)
        series << { name: "Total", data: calculate_running_total(total) }
      end
      series
    end
  end
end
