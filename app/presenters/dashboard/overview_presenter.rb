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
  #
  # ARRIVED, from `Dashboard::SavingsPresenter` when the savings TAB was deleted (task 5):
  # `#pools_summary` and `#total_pools_balance`, the goals strip this tab renders. See below.
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

    # === The goals strip ===
    #
    # SAVINGS ARE CATEGORIES (two-ledger spec §3, Task 7). This read `pools.savings_pools` through
    # `PoolCalculator`, and both are gone with the screens: a savings goal is now just a category
    # with a target and no refill rule, holding its own money. `#pools_summary` and
    # `#total_pools_balance` are renamed with the thing they describe, and the strip they feed
    # (`dashboard/_pools_strip` → `dashboard/_savings_strip`) went with them.
    #
    # `Category#savings?` IS THE CLASSIFIER, and it is the app's DISPLAY question — holder, with a
    # target, carrying no rule — which is exactly the shape Task 1's migration mints out of each
    # savings pool. It is deliberately NOT `HoldingCalculator#saving_toward_a_target?`, the
    # rendering predicate the impact card, Home and the categories page's holdings card now share:
    # this strip is an INDEX of the user's savings, and a Retirement Supplement the waterfall
    # refills every period belongs with the envelopes on a page organised by where money went, not
    # in a band headed "Savings".
    #
    # SELECTED IN RUBY rather than composed in SQL, because `savings?` reads `budgets.none?` and
    # the rows are already loaded for the entry sums beneath them; the scope narrows to holders
    # with a target first, so the `budgets` question is asked of a handful of rows at most.
    #
    # `as_of: period_range.end` is what makes the figures period-aware — a YTD strip and a monthly
    # strip describe different moments — and it is `HoldingCalculator`'s own bound, not a second
    # one.
    def savings_summary
      @savings_summary ||= savings_categories.map do |category|
        calculator = category.holding_calculator(as_of: @parent.period_range.end)
        {
          id: category.id,
          name: category.name,
          balance: calculator.balance,
          target_amount: category.target_amount,
          progress_percentage: calculator.progress_percentage
        }
      end
    end

    def total_savings_balance = savings_summary.sum { |row| row[:balance] }

    private

    def savings_categories
      @savings_categories ||= @user.categories
        .expenses
        .where.not(funded_since: nil)
        .where.not(target_amount: nil)
        .includes(:budgets)
        .order(:name)
        .select(&:savings?)
    end
  end
end
