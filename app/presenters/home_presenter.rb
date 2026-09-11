# frozen_string_literal: true

# Everything the home page shows: accounts and balances, free to spend, this period's progress,
# the trouble strip, the give-way list and the runway. Reads through one ClaimLedger.
class HomePresenter
  UnbudgetedRow = Data.define(:category, :spent)
  Trouble = Data.define(:kind, :subject)
  Uncovered = Data.define(:line, :amount) do
    delegate :category, :claim, to: :line
    def whole? = amount >= claim
  end
  Progress = Data.define(:first, :last, :day, :days) do
    def days_left = days - day
    def percent = percent_at(day)
    def percent_at(day_index) = ((day_index.to_f / days) * 100).round.clamp(0, 100)
  end
  RunwayTick = Data.define(:line, :day_index, :percent, :label, :amount, :state, :gap) do
    def ready? = state == :ready
    def short? = state == :short
  end
  Runway = Data.define(:progress, :ticks, :due_total, :short) do
    delegate :first, :last, :day, :days, :days_left, :percent, to: :progress
    def any_due? = ticks.any?
  end
  Pace = Data.define(:amount, :fine) do
    def fine? = fine
  end

  attr_reader :user, :today

  def initialize(user:, today: user.today)
    @user = user
    @today = today
  end

  def accounts = @accounts ||= user.accounts.order(:name).to_a
  delegate :balance_of, to: :account_ledger
  def main?(account) = account.main?
  def other_accounts = accounts.reject { |account| main?(account) }
  def other_accounts_total = other_accounts.sum(0.to_d) { |account| balance_of(account) }
  def overdrawn_other_accounts = other_accounts.select { |account| balance_of(account).negative? }
  def overdraft_for(account) = -balance_of(account)

  def in_checking = claim_ledger.pot
  def free_to_spend = claim_ledger.free
  delegate :claimed, :budget, to: :claim_ledger
  def money_parked_elsewhere? = other_accounts_total.positive?
  def anything_claimed? = claimed.positive?

  def claimed_percent
    return nil unless in_checking.positive?

    ((claimed / in_checking) * 100).round.clamp(0, 100)
  end

  def categories = @categories ||= user.categories.in_fill_order.includes(:rules).to_a
  delegate :ranked_categories, :blocks, :period_range, :give_way_order, to: :claim_rows

  def period_progress
    range = period_range
    return nil if range.nil?

    Progress.new(first: range.first, last: range.last, day: (today - range.first).to_i + 1, days: range.count)
  end

  def runway
    return @runway if defined?(@runway)

    @runway = build_runway
  end

  def pace_line
    progress = period_progress
    return nil if progress.nil?
    return Pace.new(amount: per_day_pace, fine: false) if short?

    Pace.new(amount: (free_to_spend / [progress.days_left, 1].max).round(2), fine: true)
  end

  def short? = free_to_spend.negative?
  def shortfall = -free_to_spend

  def per_day_pace
    progress = period_progress
    return nil if progress.nil? || !short?

    (shortfall / [progress.days_left, 1].max).round(2)
  end

  # Which claims give way to cover the shortfall, in give-way order.
  def uncovered_claims
    @uncovered_claims ||= begin
      remaining = short? ? shortfall : 0.to_d
      give_way_order.each_with_object([]) do |line, list|
        break list unless remaining.positive?
        next unless line.claim.positive?

        taken = [line.claim, remaining].min
        list << Uncovered.new(line: line, amount: taken)
        remaining -= taken
      end
    end
  end

  def uncovered_remainder
    return 0.to_d if uncovered_claims.empty?

    shortfall - uncovered_claims.sum(0.to_d, &:amount)
  end

  def troubles
    @troubles ||= [
      *overdrawn_other_accounts.map { |account| Trouble.new(kind: :overdraft, subject: account) },
      *(short? ? [Trouble.new(kind: :shortfall, subject: nil)] : []),
      *trouble_lines.map { |line| Trouble.new(kind: line.over? ? :over : :overdue, subject: line) },
      *(structurally_underwater? ? [Trouble.new(kind: :structural, subject: nil)] : [])
    ]
  end

  def trouble? = troubles.any?

  # Rules ask for more per period than typical income brings in.
  def structurally_underwater?
    return @structurally_underwater if defined?(@structurally_underwater)

    income = typical_income
    @structurally_underwater = user.period_cadence.present? && income.present? && budget > income
  end

  def typical_income = @typical_income ||= account_ledger.typical_income

  # Spending this period in expense categories no rule claims.
  def unbudgeted_rows
    @unbudgeted_rows ||= unbudgeted_spending
      .filter_map { |category_id, spent| unbudgeted_row(category_id, spent) }
      .sort_by { |row| row.category.name }
  end

  private

  def unbudgeted_spending
    @unbudgeted_spending ||= begin
      claimed = user.categories.with_a_rule.select(:id)
      Entry.expenses.where(categories: { user_id: user.id }).where.not(categories: { id: claimed })
        .where(date: user.period_containing(today)).group("categories.id").sum(:amount)
    end
  end

  def unbudgeted_row(category_id, spent)
    UnbudgetedRow.new(category: unbudgeted_categories.fetch(category_id), spent: spent.to_d) if spent.positive?
  end

  # One query for every row's category, rather than one per row.
  def unbudgeted_categories
    @unbudgeted_categories ||= Category.where(id: unbudgeted_spending.keys).index_by(&:id)
  end

  def build_runway
    progress = period_progress
    return nil if progress.nil?

    ticks = runway_ticks(progress)
    Runway.new(progress: progress, ticks: ticks, due_total: ticks.sum(0.to_d, &:amount), short: ticks.select(&:short?))
  end

  def runway_ticks(progress)
    give_way_order
      .select { |line| line.dated? && line.due_this_period && !line.paid? }
      .sort_by { |line| [line.next_due_on, line.name] }
      .map { |line| runway_tick(line, progress) }
  end

  def runway_tick(line, progress)
    day_index = (line.next_due_on - progress.first).to_i + 1
    RunwayTick.new(
      line: line,
      day_index: day_index,
      percent: progress.percent_at(day_index),
      label: line.rule.item&.name || line.category.name,
      amount: line.target,
      state: line.fund_short? ? :short : :ready,
      gap: line.fund_gap
    )
  end

  def trouble_lines = @trouble_lines ||= blocks.flat_map(&:rows).select(&:trouble?)
  def claim_ledger = @claim_ledger ||= ClaimLedger.new(user, today: today)
  def claim_rows = @claim_rows ||= ClaimRows.new(ledger: claim_ledger, today: today, categories: categories)
  def account_ledger = claim_ledger.account_ledger
end
