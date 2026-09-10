# frozen_string_literal: true

# Every rule's ClaimLine, and the two orders the screens read them in. Nothing here queries: the
# rules, their calculators and their spending come off the ClaimLedger the caller already holds.
class ClaimRows
  # One category and its rules, in give-way order.
  CategoryBlock = Data.define(:category, :rows, :claimed) do
    delegate :name, to: :category

    def rule_count = rows.size

    # Wider than ClaimLine#trouble? by `short?`: a bill still saving is not strip-worthy, but it is
    # worth a tinted header.
    def trouble? = rows.any? { |row| row.trouble? || row.short? }
  end

  # One rule's row off one calculator, with no ledger — the door the rule form's preview comes in by.
  def self.line_for(rule, calculator, period_range: nil, adjustments: [])
    ClaimLine.new(
      **figures(calculator),
      **context(rule, calculator, period_range: period_range, adjustments: adjustments)
    )
  end

  # Which period rows are read against, for a caller with no ClaimRows. Gated on the declaration:
  # User#period_containing falls back to the calendar month, which a card must not state as a fact.
  def self.period_range_for(user, today)
    return nil if user.period_cadence.blank? || user.period_anchor_date.blank?

    user.period_containing(today)
  end

  attr_reader :ledger, :today

  # `categories:` is the caller's Category.in_fill_order list, required only by #give_way_order.
  # `adjustments:` is { rule_id => [Adjustment] }; every caller but the Budget page passes nothing.
  def initialize(ledger:, today: ledger.today, categories: nil, adjustments: {})
    @ledger = ledger
    @today = today
    @categories = categories
    @adjustments = adjustments
  end

  delegate :user, to: :ledger

  # Every rule's claim, by category. Sorted on the date the row PRINTS (ClaimCalculator#next_due_on,
  # which rolls on payment) rather than on the anchor_date column, so the lines are built first.
  def lines_by_category
    @lines_by_category ||= lines
      .sort_by { |line| Rule.sort_key(next_due_on: line.next_due_on, amount: line.rule.amount, id: line.rule.id) }
      .group_by { |line| line.category.id }
  end

  def lines_for(category) = lines_by_category.fetch(category.id, [])

  # The order claims give way in: the rule's type first (a choice goes before a bill), then the
  # category in reverse fill order, then the app's one within-category key.
  def give_way_order
    @give_way_order ||= lines_by_category.values.flatten.sort_by { |line| give_way_key(line) }
  end

  # The blocks are #give_way_order grouped back — group_by keeps first-appearance order, so a
  # category sits where its soonest-giving-way rule sits and no second sort can disagree.
  def blocks
    @blocks ||= give_way_order.group_by { |line| line.category.id }.map do |_id, rows|
      CategoryBlock.new(category: rows.first.category, rows: rows, claimed: rows.sum(0.to_d, &:claim))
    end
  end

  # Memoised with defined?, because nil is a real answer and the common one for an undeclared user.
  def period_range
    return @period_range if defined?(@period_range)

    @period_range = self.class.period_range_for(user, today)
  end

  # Every category a claim line can belong to, in Category.in_fill_order's own key. The rules' own
  # categories are added because ClaimLedger counts every rule's claim into `free`.
  def ranked_categories
    @ranked_categories ||= (categories + ledger.rules.filter_map(&:category))
      .uniq.sort_by { |category| [category.priority, category.name] }
  end

  private

  def categories = @categories ||= user.categories.in_fill_order.to_a

  def lines = @lines ||= ledger.rules.map { |rule| build_line(rule) }

  def build_line(rule)
    self.class.line_for(
      rule,
      ledger.calculator_for(rule),
      period_range: period_range,
      adjustments: @adjustments.fetch(rule.id, [])
    )
  end

  # The calculator's own answers, in one read of one object, so a row cannot pair one rule's figure
  # with another's state.
  def self.figures(calculator)
    {
      shape: calculator.shape,
      claim: calculator.claim,
      spent: calculator.spent_this_period,
      accrued: calculator.accrued_this_period,
      built_up: calculator.built_up,
      target: calculator.target,
      next_due_on: calculator.next_due_on,
      per_period: calculator.planned_this_period,
      over: calculator.over?,
      over_by: calculator.over_by,
      overdue: calculator.overdue?,
      paid: calculator.settled?,
      paid_on: calculator.settled_on,
      countable_span: calculator.countable_span
    }
  end

  # What the calculator cannot know: the rule's owner, the page's period window, and the deltas only
  # the Budget page fetches.
  def self.context(rule, calculator, period_range:, adjustments:)
    {
      category: rule.category,
      rule: rule,
      due_this_period: due_this_period?(calculator.next_due_on, period_range),
      resets_on: calculator.rate? ? next_period_opens_on(period_range) : nil,
      adjustments: adjustments
    }
  end

  def self.next_period_opens_on(period_range) = period_range.nil? ? nil : period_range.last + 1

  def self.due_this_period?(due, period_range)
    due.present? && period_range.present? && period_range.cover?(due)
  end

  private_class_method :figures, :context, :next_period_opens_on, :due_this_period?

  def give_way_key(line)
    [
      line.rule.type_rank,
      give_way_rank.fetch(line.category.id),
      Rule.sort_key(next_due_on: line.next_due_on, amount: line.rule.amount, id: line.rule.id)
    ]
  end

  # The category half of the key: #ranked_categories read backwards, as an index, so reverse fill
  # order arrives as one comparable number.
  def give_way_rank
    @give_way_rank ||= ranked_categories.each_with_index.to_h { |category, index| [category.id, -index] }
  end
end
