# frozen_string_literal: true

module Dashboard
  # THE ALL TAB, AFTER THE SAVINGS-ENTRY ERA (plan 3, task 4, decision 6).
  #
  # DELETED, each because the question it answered is not a question this app's data can answer any
  # more:
  #
  # * `#savings_contributions_total` — savings-typed ENTRIES. A contribution is a `PoolMovement`
  #   now, so this summed an empty set for every user: the "Savings Contrib $0.00" segment.
  # * `#savings_withdrawals_total` and `#net_savings` — enveloped spending, called a savings
  #   WITHDRAWAL. Spending an envelope you funded is not a raid on savings, and the figure was the
  #   page's loudest untruth ("100.0% From Savings" before Task 3's bridge, 23.7% after). The
  #   movement-based equivalent is not a conversion of this reader but a second reader of pool
  #   funding, on a page organised by calendar month rather than by funding period — the pools
  #   strip four inches below already answers "what do my goals hold", from `PoolCalculator`.
  # * `#income_remaining` — income minus buffer spending minus contributions. With contributions
  #   gone it is `#net_amount` under a second name, and one of them had to go.
  # * `#budgeted_total` and `#budget_used_percentage` — the Budget Used card. `#total_budget` is
  #   the sum of the user's category caps; there are none.
  # * `#overview_chart_data`/`#overview_chart_colors` and `#income_change`/`#expenses_change` —
  #   grepped callerless across `app lib spec`. The chart's third series was the same net-savings
  #   delta, so the one unrendered thing on this page was also carrying the lie.
  class OverviewPresenter
    def initialize(parent)
      @parent = parent
      @user = parent.user
    end

    # === Cash-flow stats ===

    # What came in against what actually left, and after the cutover that is the whole of it:
    # money moved into an envelope has not left, and money spent OUT of an envelope is counted
    # here like any other spending, because it is.
    def net_amount
      @net_amount ||= @parent.total_tracked_income - @parent.total_tracked_expenses
    end

    def expense_ratio
      income = @parent.total_tracked_income
      return 0 if income.zero?

      (@parent.total_tracked_expenses / income.to_f * 100).round(1)
    end

    # === Top spending (all expense categories combined — cash flow view) ===

    def top_expense_categories
      @top_expense_categories ||= @parent.expense_categories_breakdown.first(5)
    end

    # === Expense split, by the lane the money came out of ===

    def buffer_categories_breakdown
      @buffer_categories_breakdown ||= @parent.build_category_breakdown(@parent.tracked_buffer_funded_categories)
    end

    def envelope_categories_breakdown
      @envelope_categories_breakdown ||= @parent.build_category_breakdown(@parent.tracked_enveloped_categories)
    end
  end
end
