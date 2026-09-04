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
  #   funding, on a page organised by calendar month rather than by funding period — the savings
  #   strip four inches below already answers "what do my goals claim", from `ClaimLedger`.
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
    # ** `Category#saving_toward_a_target?` IS THE CLASSIFIER — a funding start and a figure to
    # reach — AND IT REPLACED `#savings?`, WHICH INVERTED UNDER THE COMPUTED MODEL. ** That
    # predicate added `budgets.none?`, and the third clause had a real job while a waterfall
    # existed: a Retirement Supplement a rate rule refilled every period was being SPENT toward a
    # rate rather than SAVED toward a figure, and it belonged with the envelopes on a page organised
    # by where money went.
    #
    # Nothing refills anything now, and every claim comes from a RULE (§3.3) — so `budgets.none?`
    # selected exactly the goals that claim $0.00, and `DropTheDistribution` (§7) mints the
    # zero-amount target rule for every goal in a real database that lacked one. Kept as it was,
    # this strip rendered NOTHING on migrated data and a truthful zero on everything else: two
    # honest answers, neither useful, and a band that silently stops appearing is indistinguishable
    # from one that broke. `#savings?` is deleted with its last caller.
    #
    # COMPOSED IN SQL RATHER THAN SELECTED IN RUBY, which the third clause is what used to prevent:
    # `expenses.where.not(funded_since: nil).where.not(target_amount: nil)` IS
    # `#saving_toward_a_target?`, one row set, no `budgets` preload and no Ruby pass.
    #
    # `ClaimLedger` RATHER THAN `Category#claim`, because this is a strip of many categories and the
    # unbatched door costs a spending query and an adjustment query PER RULE. The two are pinned
    # against each other figure for figure in `claim_ledger_spec`, so the batching cannot make this
    # page disagree with a category's own.
    def savings_summary
      @savings_summary ||= savings_categories.map do |category|
        claim = claim_ledger.claim_of_category(category)
        {
          id: category.id,
          name: category.name,
          balance: claim,
          target_amount: category.target_amount,
          progress_percentage: progress_percentage(claim, category.target_amount)
        }
      end
    end

    def total_savings_balance = savings_summary.sum { |row| row[:balance] }

    private

    # ** `as_of:` HAS NO EQUIVALENT, AND THIS IS THE HONEST NEAREST THING (computed-claims §3). **
    # `HoldingCalculator` could be BOUNDED at a past date because a holding was a signed sum of
    # dated rows: cut the rows at a date and you have the balance on that date. A claim is not a sum
    # of rows, it is a WALK over periods — `ClaimCalculator` takes a `today:` and accrues from
    # `funded_since` up to it — so the only bound the model has is which period the walk stops in.
    #
    # `min(period_range.end, user.today)`, and each half answers a different way the question can be
    # wrong:
    #
    #   * `period_range.end` is the selected month's (or the YTD range's) last day, so a strip
    #     looking at July reports what the rules claimed by the end of July rather than what they
    #     claim this afternoon. A YTD strip and a monthly strip still describe different moments,
    #     which is the property the old bound was chosen for.
    #   * `user.today` is the cap, and it is the half the old reader did not need. `period_range.end`
    #     for the CURRENT month is a day in the FUTURE, and a claim asked at a future date is
    #     perfectly computable — the walk simply runs on and accrues periods that have not happened.
    #     That is a real feature of the model (a fund is knowable on any day, including days that
    #     have not come), and it is exactly the wrong thing on a strip a user reads as a statement of
    #     what they have: it would show a goal already fed by a period nobody has lived through.
    #
    # ** IT IS PERIOD-GRAINED AND NOT DAY-GRAINED, AND THE STRIP'S COPY IS WRITTEN TO SURVIVE THAT.
    # ** `ClaimCalculator` sums a period's spending and adjustments over the WHOLE period
    # (`period.cover?(day)`), so a claim asked on the 31st of a month whose funding period runs to
    # the 10th of the next one counts rows dated after the 31st. "As of the end of July" therefore
    # means "as of the end of the funding period containing July 31", which is a real and small
    # discrepancy that no arithmetic here can remove — the alternative, re-cutting the rows at a day,
    # is a second spelling of `ClaimCalculator`'s own window and the one thing §3 does not allow a
    # screen to do. So the strip states no date and promises no instant; see its own header.
    def as_of = @as_of ||= [@parent.period_range.end, @user.today].min

    def claim_ledger = @claim_ledger ||= ClaimLedger.new(@user, today: as_of)

    # HOW FULL, AS A WHOLE PERCENT, CLAMPED AT BOTH ENDS — `HoldingCalculator#progress_percentage`'s
    # arithmetic to the character, so no figure on this strip moves for a reason nobody asked for.
    #
    # THE FLOOR SURVIVES THOUGH NOTHING CAN REACH IT ANY MORE. It was there because an overdrawn
    # category measured against a target answered a NEGATIVE percentage, and "minus thirty percent
    # complete" is not a reading of anything. §3 clamps every claim at zero, so the negative arm is
    # unreachable now — kept because it costs nothing and because the day a claim is allowed to go
    # negative is the day a bar of negative width would be drawn again.
    #
    # The type is Integer at both bounds by construction — `.round` on the quotient, and two Integer
    # clamp bounds.
    def progress_percentage(claim, target)
      return 0 unless target.to_f.positive?

      (claim / target * 100).round.clamp(0, 100)
    end

    def savings_categories
      @savings_categories ||= @user.categories
        .expenses
        .where.not(funded_since: nil)
        .where.not(target_amount: nil)
        .order(:name)
    end
  end
end
