# frozen_string_literal: true

# The Budget page: the tiles, every expense category with its rules, and the declaration form.
class BudgetPagePresenter
  CategoryRow = Data.define(:category, :lines, :type_dots, :takes_now, :open) do
    delegate :name, :priority, to: :category
    def open? = open
    def rule_count = lines.size
    def ruled? = lines.any?
    def needs_attention? = lines.any?(&:trouble?)
    def reorderable? = ruled?
  end
  Segment = Data.define(:type, :amount, :percent)
  Tiles = Data.define(:budget, :budget_now, :savings, :segments, :income, :cadence, :leftover, :leftover_now, :declared, :fits) do
    def declared? = declared
    def fits? = fits
    def where = budget + savings
    def where_now = budget_now + savings
    def catching_up? = budget_now != budget
  end

  TYPE_OVERVIEW_ORDER = [:bill, :usage, :choice].freeze

  attr_reader :user, :today

  def initialize(user:, today: user.today, open_category_id: nil)
    @user = user
    @today = today
    @open_category_id = open_category_id.presence&.to_s
  end

  def tiles
    @tiles ||= Tiles.new(
      budget: budget,
      budget_now: budget_now,
      savings: savings,
      segments: segments,
      income: typical_income,
      cadence: user.period_cadence,
      leftover: leftover,
      leftover_now: leftover_now,
      declared: declared?,
      fits: fits?
    )
  end

  def category_rows = @category_rows ||= ruled_rows + unruled_rows
  def reorderable_rows = @reorderable_rows ||= category_rows.select(&:reorderable?)
  def open?(category) = @open_category_id.present? && @open_category_id == category.id.to_s
  def no_categories? = category_rows.empty?

  def type_overview
    @type_overview ||= begin
      asks = claim_ledger.rules.group_by { |rule| rule.rule_type.to_sym }
      TYPE_OVERVIEW_ORDER.filter_map do |type|
        group = asks[type]
        [type, group.sum(0.to_d) { |rule| claim_ledger.calculator_for(rule).ask }] if group
      end
    end
  end

  delegate :budget, :savings, to: :claim_ledger

  # Memoised with defined?, because nil is a real answer and the common one for a new user.
  def typical_income
    return @typical_income if defined?(@typical_income)

    @typical_income = claim_ledger.account_ledger.typical_income
  end

  def leftover = typical_income && (typical_income - savings - budget)
  def budget_now = @budget_now ||= claim_ledger.rules.sum(0.to_d) { |rule| claim_ledger.calculator_for(rule).planned_this_period }
  def leftover_now = typical_income && (typical_income - savings - budget_now)
  def declared? = user.period_cadence.present?
  def history? = typical_income.present?
  def underwater? = declared? && history? && budget + savings > typical_income

  private

  def ruled_rows
    claim_rows.blocks
      .sort_by { |block| [block.category.priority, block.category.name] }
      .map { |block| row_for(block.category, lines: block.rows) }
  end

  def unruled_rows
    ruled = claim_rows.blocks.to_set { |block| block.category.id }
    expense_categories.reject { |category| ruled.include?(category.id) }
      .map { |category| row_for(category, lines: []) }
  end

  def row_for(category, lines:)
    CategoryRow.new(
      category: category,
      lines: lines,
      type_dots: lines.map(&:stripe_type),
      takes_now: lines.sum(0.to_d, &:per_period),
      open: open?(category)
    )
  end

  def expense_categories = @expense_categories ||= user.categories.expenses.order(:name).to_a

  def claim_rows
    @claim_rows ||= ClaimRows.new(
      ledger: claim_ledger,
      today: today,
      categories: user.categories.in_fill_order.to_a
    )
  end

  def segments
    parts = [[:savings, savings]] + type_overview
    total = parts.sum { |(_type, amount)| amount }
    return [] unless total.positive?

    parts.reject { |(_type, amount)| amount.zero? }
      .map { |(type, amount)| Segment.new(type: type, amount: amount, percent: ((amount / total) * 100).round.clamp(0, 100)) }
  end

  def fits? = declared? && history? && !underwater?
  def claim_ledger = @claim_ledger ||= ClaimLedger.new(user, today: today)
end
