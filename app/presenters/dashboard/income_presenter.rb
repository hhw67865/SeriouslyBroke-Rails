# frozen_string_literal: true

module Dashboard
  class IncomePresenter
    def initialize(parent)
      @parent = parent
      @user = parent.user
    end

    def income_chart_data
      @income_chart_data ||= compute_income_chart_data
    end

    def total_income
      @total_income ||= income_scope.where(date: period_range).sum(:amount)
    end

    def total_tracked_income
      @total_tracked_income ||= tracked_income_scope.where(date: period_range).sum(:amount)
    end

    def income_categories_breakdown
      @income_categories_breakdown ||= @parent.build_category_breakdown(@parent.tracked_income_categories)
    end

    def untracked_income_categories_breakdown
      @untracked_income_categories_breakdown ||= @parent.build_category_breakdown(@parent.untracked_income_categories)
    end

    def income_change_percentage
      return nil if @parent.ytd?

      @income_change_percentage ||= calculate_income_change
    end

    def income_chart_colors
      [
        DashboardPresenter::COLORS[:brand],
        DashboardPresenter::COLORS[:dusty_teal],
        DashboardPresenter::COLORS[:terracotta],
        DashboardPresenter::COLORS[:warm_sand],
        DashboardPresenter::COLORS[:dusty_rose],
        DashboardPresenter::COLORS[:slate]
      ]
    end

    private

    delegate :period_range, :six_month_range, to: :@parent

    def income_scope
      @user.entries.incomes
    end

    def tracked_income_scope
      @user.entries.incomes.tracked
    end

    def calculate_income_change
      current = total_tracked_income
      previous = tracked_income_scope.where(date: @parent.previous_month_range).sum(:amount)
      return 0 if previous.zero?

      ((current - previous) / previous.to_f * 100).round
    end

    def compute_income_chart_data
      range = @parent.ytd? ? period_range : six_month_range
      series = @parent.tracked_income_categories.map do |category|
        monthly_data = category.entries.group_by_month(:date, range: range, default_value: 0).sum(:amount)
        { name: category.name, data: monthly_data.transform_keys { |d| d.strftime("%b %Y") } }
      end
      series.reject { |s| s[:data].values.all?(&:zero?) }
    end
  end
end
