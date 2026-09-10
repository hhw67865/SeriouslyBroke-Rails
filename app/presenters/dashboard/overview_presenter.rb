# frozen_string_literal: true

module Dashboard
  # The All tab: the cash-flow figures, the two lanes' breakdowns and the savings strip.
  class OverviewPresenter
    def initialize(parent)
      @parent = parent
      @user = parent.user
    end

    # === Cash-flow stats ===

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
      @buffer_categories_breakdown ||= @parent.build_category_breakdown(@parent.tracked_unruled_categories)
    end

    def envelope_categories_breakdown
      @envelope_categories_breakdown ||= @parent.build_category_breakdown(@parent.tracked_ruled_categories)
    end

    # The savings strip. Money being saved toward a day is a shape rather than a kind of category,
    # and a rule that REPEATS is a recurring bill: `Rule.saving_toward_a_date` draws both clauses.
    def savings_summary
      @savings_summary ||= savings_categories.map { |category| savings_line(category) }
    end

    # `#sole` is deliberate: the scope's `item_id IS NULL` clause is single-valued per category, and
    # a `#first` would silently name one of two where a raise says so.
    def savings_line(category)
      rule = category.rules.select(&:saving_toward_a_date?).sole

      ClaimRows.line_for(rule, claim_ledger.calculator_for(rule))
    end

    # The target is a ceiling on the FUND's own money, so beside a figure that also holds a sibling
    # bill's accrual it would be a fraction of the wrong number.
    def whole_category_fund?(line) = sole_rule_category_ids.include?(line.rule.category_id)

    def savings_target(line) = whole_category_fund?(line) ? line.target : nil

    def savings_progress(line) = progress_percentage(line.built_up, savings_target(line))

    def total_savings_balance = savings_summary.sum(0.to_d, &:built_up)

    private

    # A claim is a walk over periods, so the only bound is which period it stops in: the selected
    # range's last day, capped at today so no card counts a period nobody has lived through.
    def as_of = @as_of ||= [@parent.period_range.end, @user.today].min

    def claim_ledger = @claim_ledger ||= ClaimLedger.new(@user, today: as_of)

    # How full, as a whole percent. The floor survives though a clamped claim cannot reach it: a
    # bar of negative width is what it is there to refuse.
    def progress_percentage(claim, target)
      return 0 unless target.to_f.positive?

      (claim / target * 100).round.clamp(0, 100)
    end

    # The categories whose only rule is the fund, counted once for the whole strip rather than per
    # card.
    def sole_rule_category_ids
      @sole_rule_category_ids ||= savings_categories.select { |category| category.rules.size == 1 }.to_set(&:id)
    end

    def savings_categories
      @savings_categories ||= @user.categories
        .expenses
        .where(id: Rule.saving_toward_a_date.select(:category_id))
        .includes(:rules)
        .order(:name)
    end
  end
end
