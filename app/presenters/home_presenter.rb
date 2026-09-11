# frozen_string_literal: true

# Everything the home page shows: accounts and balances, free to spend, this period's progress,
# the trouble strip, what is coming up and the give-way list. Reads through one ClaimLedger.
class HomePresenter
  UnbudgetedRow = Data.define(:category, :spent)
  Trouble = Data.define(:kind, :subject)
  Uncovered = Data.define(:claim_row, :amount) do
    delegate :name, :kind, :claim, to: :claim_row
    def whole? = amount >= claim
  end
  Progress = Data.define(:first, :last, :day, :days) do
    def days_left = days - day
    def percent = percent_at(day)
    def percent_at(day_index) = ((day_index.to_f / days) * 100).round.clamp(0, 100)
  end
  Tiles = Data.define(
    :free,
    :checking,
    :spent_this_period,
    :claimed,
    :budget_claim,
    :savings_claim,
    :savings_total,
    :savings_owed,
    :savings_count
  )
  # One dated rule due soon. `state` is :ready (the money is there), :short (due this period and
  # not there) or :building (still accruing toward a later day).
  Upcoming = Data.define(:line, :state) do
    # ClaimLine#name says "Whole category" for an item-less rule — the Budget page's own vocabulary
    # for telling one rule from a sibling in the same category. Coming up never shows two rules from
    # one category side by side, so it names the row by its item, or its category standing in for it.
    def name = line.rule.item&.name || line.category.name
    def due_on = line.next_due_on
    def amount = line.target
    def set_aside = line.built_up
    def ready? = state == :ready
    def short? = state == :short
    def building? = state == :building
  end

  UPCOMING_DAYS = 30

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
  delegate :claimed, :budget_claim, :savings_claim, :budget, :savings, to: :claim_ledger
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

  def short? = free_to_spend.negative?
  def shortfall = -free_to_spend

  def day_words = today.strftime("%A, %B %-d")

  def period_words
    progress = period_progress
    return "No period set yet" if progress.nil?

    "Day #{progress.day} of #{progress.days} in this period · next payday #{(progress.last + 1).strftime("%b %-d")}"
  end

  def tiles
    @tiles ||= Tiles.new(
      free: free_to_spend,
      checking: in_checking,
      spent_this_period: spent_this_period,
      claimed: claimed,
      budget_claim: budget_claim,
      savings_claim: savings_claim,
      savings_total: other_accounts_total,
      savings_owed: savings_claim,
      savings_count: other_accounts.size
    )
  end

  # nil for a user with no cadence: `User#period_containing` falls back to the calendar month, and
  # a spent-this-period figure must not state a period as fact when the header says there is none.
  def spent_this_period
    return nil if period_progress.nil?

    @spent_this_period ||= Entry.expenses.where(categories: { user_id: user.id })
      .where(date: user.period_containing(today)).sum(:amount).to_d
  end

  # Dated rules due from today through UPCOMING_DAYS, soonest first, each with where its money stands.
  def upcoming
    @upcoming ||= upcoming_lines
      .map { |line| Upcoming.new(line: line, state: upcoming_state(line)) }
      .sort_by { |row| [row.due_on, row.name] }
  end

  # Savings accounts with a target, as the Savings page reads them, off this page's own ledger.
  def savings_blocks
    @savings_blocks ||= SavingsPresenter.new(user: user, today: today, ledger: claim_ledger).rows.select(&:targeted?)
  end

  def kinds_legend = ClaimLedger::KIND_RANK.keys.map { |kind| [kind, kind.to_s.capitalize] }

  # Which claims give way to cover the shortfall, in give-way order — savings included, between
  # usage and bills.
  def uncovered_claims
    @uncovered_claims ||= begin
      remaining = short? ? shortfall : 0.to_d
      claim_ledger.claims.each_with_object([]) do |row, list|
        break list unless remaining.positive?
        next unless row.claim.positive?

        taken = [row.claim, remaining].min
        list << Uncovered.new(claim_row: row, amount: taken)
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

  # The budget and savings together ask for more per period than typical income brings in.
  def structurally_underwater?
    return @structurally_underwater if defined?(@structurally_underwater)

    income = typical_income
    @structurally_underwater = user.period_cadence.present? && income.present? && budget + savings > income
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

  # Dated, unpaid, and due somewhere in the next UPCOMING_DAYS.
  def upcoming_lines
    blocks.flat_map(&:rows).select { |line| line.dated? && !line.paid? && due_soon?(line) }
  end

  def due_soon?(line) = line.next_due_on&.between?(today, today + UPCOMING_DAYS) || false

  def upcoming_state(line)
    return :short if line.short?
    return :building if line.fund_short?

    :ready
  end

  # This period's adjustments, so each rule row can list them under its Adjust panel.
  def adjustments_this_period
    @adjustments_this_period ||= Adjustment.on_rules(claim_ledger.rules.map(&:id))
      .dated_within(user.period_containing(today)).order(:date, :created_at).group_by(&:source_id)
  end

  def trouble_lines = @trouble_lines ||= blocks.flat_map(&:rows).select(&:trouble?)
  def claim_ledger = @claim_ledger ||= ClaimLedger.new(user, today: today)
  def claim_rows = @claim_rows ||= ClaimRows.new(ledger: claim_ledger, today: today, categories: categories, adjustments: adjustments_this_period)
  def account_ledger = claim_ledger.account_ledger
end
