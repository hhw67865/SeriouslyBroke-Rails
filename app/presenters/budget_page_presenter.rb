# frozen_string_literal: true

# The Budget page: the tiles, every expense category with its rules, and the declaration form.
class BudgetPagePresenter
  CategoryRow = Data.define(:category, :lines, :type_dots, :claimed, :open) do
    delegate :name, :priority, to: :category
    def open? = open
    def rule_count = lines.size
    def ruled? = lines.any?
    def needs_attention? = lines.any?(&:trouble?)
    def reorderable? = ruled?
  end
  Segment = Data.define(:type, :amount, :percent)
  Tiles = Data.define(:need, :segments, :income, :cadence, :leftover, :declared, :fits) do
    def declared? = declared
    def fits? = fits
  end

  TYPE_OVERVIEW_ORDER = [:bill, :usage, :choice].freeze

  attr_reader :user, :today, :declaration

  def initialize(user:, today: user.today, declaration: nil, open_category_id: nil, declaring: false)
    @user = user
    @today = today
    @declaration = declaration || user
    @open_category_id = open_category_id.presence&.to_s
    @declaring = declaring
  end

  def tiles
    @tiles ||= Tiles.new(
      need: rules_need,
      segments: segments,
      income: typical_income,
      cadence: user.period_cadence,
      leftover: leftover,
      declared: declared?,
      fits: fits?
    )
  end

  def category_rows = @category_rows ||= ruled_rows + unruled_rows
  def reorderable_rows = @reorderable_rows ||= category_rows.select(&:reorderable?)
  def open?(category) = @open_category_id.present? && @open_category_id == category.id.to_s
  def declaring? = @declaring || declaration.errors.any?
  def no_categories? = category_rows.empty?

  def type_overview
    @type_overview ||= begin
      asks = claim_ledger.rules.group_by { |rule| rule.rule_type.to_sym }
      TYPE_OVERVIEW_ORDER.filter_map do |type|
        group = asks[type]
        [type, group.sum(0.to_d) { |rule| claim_ledger.calculator_for(rule).standing_ask }] if group
      end
    end
  end

  def rules_need = @rules_need ||= Rule.steady_need(user, today: today, ledger: claim_ledger)

  # Memoised with defined?, because nil is a real answer and the common one for a new user.
  def typical_income
    return @typical_income if defined?(@typical_income)

    @typical_income = claim_ledger.account_ledger.typical_income
  end

  def income_categories
    return @income_categories if defined?(@income_categories)

    @income_categories = user.categories.incomes.order(:name).to_a
  end

  def leftover = typical_income && (typical_income - rules_need)
  def declared? = user.period_cadence.present?
  def history? = typical_income.present?
  def underwater? = declared? && history? && rules_need > typical_income

  private

  def ruled_rows
    claim_rows.blocks
      .sort_by { |block| [block.category.priority, block.category.name] }
      .map { |block| row_for(block.category, lines: block.rows, claimed: block.claimed) }
  end

  def unruled_rows
    ruled = claim_rows.blocks.to_set { |block| block.category.id }
    expense_categories.reject { |category| ruled.include?(category.id) }
      .map { |category| row_for(category, lines: [], claimed: 0.to_d) }
  end

  def row_for(category, lines:, claimed:)
    CategoryRow.new(category: category, lines: lines, type_dots: lines.map(&:stripe_type), claimed: claimed, open: open?(category))
  end

  def expense_categories = @expense_categories ||= user.categories.expenses.order(:name).to_a

  def claim_rows
    @claim_rows ||= ClaimRows.new(
      ledger: claim_ledger,
      today: today,
      categories: user.categories.in_fill_order.to_a,
      adjustments: adjustments_this_period
    )
  end

  def segments
    total = type_overview.sum { |(_type, amount)| amount }
    return [] unless total.positive?

    type_overview.map { |(type, amount)| Segment.new(type: type, amount: amount, percent: ((amount / total) * 100).round.clamp(0, 100)) }
  end

  def fits? = declared? && history? && !underwater?
  def claim_ledger = @claim_ledger ||= ClaimLedger.new(user, today: today)

  def adjustments_this_period
    @adjustments_this_period ||= Adjustment.where(rule_id: claim_ledger.rules.map(&:id))
      .dated_within(user.period_containing(today)).order(:date, :created_at).group_by(&:rule_id)
  end
end
