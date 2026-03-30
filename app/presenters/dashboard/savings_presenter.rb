# frozen_string_literal: true

module Dashboard
  class SavingsPresenter
    def initialize(parent)
      @parent = parent
      @user = parent.user
    end

    # === Chart ===

    def savings_chart_data
      @savings_chart_data ||= compute_savings_chart_data
    end

    def savings_chart_colors
      [DashboardPresenter::COLORS[:brand_dark]]
    end

    def flow_chart_data
      @flow_chart_data ||= compute_flow_chart_data
    end

    def flow_chart_colors
      [DashboardPresenter::COLORS[:brand_dark], DashboardPresenter::COLORS[:terracotta]]
    end

    # === Stats ===

    def total_savings_contribution
      @total_savings_contribution ||= savings_all_scope.where(date: period_range).sum(:amount)
    end

    def total_tracked_savings_contribution
      @total_tracked_savings_contribution ||= tracked_savings_scope.where(date: period_range).sum(:amount)
    end

    def total_savings_balance
      @total_savings_balance ||= savings_all_scope.sum(:amount)
    end

    def total_withdrawals
      @total_withdrawals ||= savings_withdrawal_scope.where(date: period_range).sum(:amount)
    end

    def savings_rate
      @savings_rate ||= begin
        income = @parent.total_tracked_income
        if income.zero?
          0
        else
          (total_tracked_savings_contribution / income.to_f * 100).round(1)
        end
      end
    end

    def total_pools_balance
      pools_summary.sum { |p| p[:balance] }
    end

    # === Pools Summary (period-aware) ===

    def pools_summary
      @pools_summary ||= @user.savings_pools.includes(categories: { items: :entries }).map do |pool|
        calc = pool.calculator(as_of: period_range.end)
        {
          id: pool.id,
          name: pool.name,
          period_contributions: pool_period_contributions(pool),
          period_withdrawals: pool_period_withdrawals(pool),
          balance: calc.current_balance,
          target_amount: pool.target_amount,
          progress_percentage: calc.progress_percentage
        }
      end
    end

    # === Category Breakdowns ===

    def savings_categories_breakdown
      @savings_categories_breakdown ||= build_savings_category_breakdown(@parent.tracked_savings_categories)
    end

    def untracked_savings_categories_breakdown
      @untracked_savings_categories_breakdown ||= build_savings_category_breakdown(@parent.untracked_savings_categories)
    end

    private

    delegate :period_range, :ytd_range, :six_month_range, to: :@parent

    def tracked_savings_scope
      @user.entries.savings.tracked
    end

    def savings_all_scope
      @user.entries.savings
    end

    def savings_withdrawal_scope
      @user.entries.joins(item: :category)
        .joins("INNER JOIN savings_pools ON savings_pools.id = categories.savings_pool_id")
        .where(categories: { category_type: :expense })
    end

    def savings_chart_range
      @parent.ytd? ? period_range : six_month_range
    end

    def savings_scope
      tracked_savings_scope
    end

    def pool_period_contributions(pool)
      pool.contribution_entries.where(date: period_range).sum(:amount)
    end

    def pool_period_withdrawals(pool)
      pool.withdrawal_entries.where(date: period_range).sum(:amount)
    end

    def compute_savings_chart_data
      range = savings_chart_range
      initial = savings_scope.where(date: ...range.begin).sum(:amount)
      contributions = savings_scope.where(date: range).sum(:amount)
      return {} if initial.zero? && contributions.zero?

      build_savings_running_total(range, initial)
    end

    def build_savings_running_total(range, initial_balance)
      monthly_data = savings_scope.group_by_month(:date, range: range, default_value: 0).sum(:amount)
      current_total = initial_balance
      monthly_data.each_with_object({}) do |(d, amount), result|
        current_total += amount
        result[d.strftime("%b %Y")] = current_total
      end
    end

    def build_savings_category_breakdown(categories)
      breakdown = categories.map do |category|
        contributed = category.entries.where(date: ..period_range.end).sum(:amount)
        {
          id: category.id,
          name: category.name,
          amount: category.calculator(@parent.date, period: @parent.period).total_amount,
          total_contributed: contributed
        }
      end
      breakdown.sort_by { |c| -c[:amount] }
    end

    def compute_flow_chart_data
      range = savings_chart_range
      contributions = tracked_savings_scope
        .group_by_month(:date, range: range, default_value: 0).sum(:amount)
        .transform_keys { |d| d.strftime("%b %Y") }
      withdrawals = savings_withdrawal_scope
        .where(date: range)
        .group_by_month(:date, range: range, default_value: 0).sum(:amount)
        .transform_keys { |d| d.strftime("%b %Y") }

      [
        { name: "Contributions", data: contributions },
        { name: "Withdrawals", data: withdrawals }
      ]
    end
  end
end
