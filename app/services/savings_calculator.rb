# frozen_string_literal: true

# One savings account's claim on checking: what its targets owe over the periods since the earliest
# start, less what arrived by transfer, floored the way keeps_extra says. Rows are [day, amount]
# pairs (income keyed by item id), queried unless handed in.
class SavingsCalculator
  PERIOD_WALK_LIMIT = 520
  ROW_KEYS = [:targets, :transfers, :income, :adjustments, :typical_income_by_item].freeze

  attr_reader :account, :today

  def initialize(account, today: account.user.today, **rows)
    @account = account
    @today = today
    assign_rows(rows)
  end

  def targets = @targets ||= account.savings_targets.includes(:item).to_a
  def start = @start ||= targets.map(&:starts_on).min

  def claim
    return 0.to_d if periods.empty?

    account.keeps_extra? ? [accrued_total - arrived_total, 0.to_d].max : carried
  end

  # What the account costs a period: every target's ask, a share's against its item's typical income.
  def ask = targets.sum(0.to_d) { |target| target.ask(typical_income: typical_income_of(target.item_id)) }

  def owed_this_period = periods.empty? ? 0.to_d : owed_in(current_period)
  def accrued_this_period = periods.empty? ? 0.to_d : accrued_in(current_period)
  def arrived_this_period = periods.empty? ? 0.to_d : arrived_in(current_period)

  # The dates an adjustment may carry: from the earliest start to today.
  def countable_span
    return (today...today) if periods.empty?

    start..today
  end

  def periods
    @periods ||= start.nil? || start > today ? [] : walk_periods
  end

  private

  def assign_rows(rows)
    rows.each_key { |key| raise ArgumentError, "unknown keyword: #{key}" unless ROW_KEYS.include?(key) }

    @targets = rows[:targets]
    @transfers = rows[:transfers]
    @income = rows[:income]
    @adjustments = rows[:adjustments]
    @typical_income_by_item = (rows[:typical_income_by_item] || {}).dup
  end

  def user = account.user
  def current_period = @current_period ||= user.period_containing(today)

  def walk_periods
    visited = []
    cursor = user.period_containing(start)
    while cursor.first <= today && visited.size < PERIOD_WALK_LIMIT
      visited << cursor
      cursor = user.period_containing(cursor.last + 1)
    end
    visited
  end

  def accrued_total = periods.sum(0.to_d) { |period| accrued_in(period) }
  def arrived_total = periods.sum(0.to_d) { |period| arrived_in(period) }

  def carried
    periods.reduce(0.to_d) { |carry, period| [carry + accrued_in(period) - arrived_in(period), 0.to_d].max }
  end

  def owed_in(period)
    targets.sum(0.to_d) do |target|
      next 0.to_d if target.starts_on > period.last

      target.target? ? target.amount.to_d : share_owed(target, period)
    end
  end

  def share_owed(target, period)
    landed = sum_within(income_rows.fetch(target.item_id, []), period, from: target.starts_on)
    (landed * target.percent.to_d / 100).round(2)
  end

  def accrued_in(period) = owed_in(period) + sum_within(adjustment_rows, period)
  def arrived_in(period) = sum_within(transfer_rows, period, from: start)

  def sum_within(rows, period, from: nil)
    rows.sum(0.to_d) { |day, amount| period.cover?(day) && (from.nil? || day >= from) ? amount : 0.to_d }
  end

  def typical_income_of(item_id)
    return nil if item_id.nil?

    @typical_income_by_item[item_id] ||= AccountLedger.new(user, today: today).typical_income_of_item(item_id)
  end

  def transfer_rows = @transfer_rows ||= @transfers.nil? ? query_transfers : @transfers
  def income_rows = @income_rows ||= @income.nil? ? query_income : @income
  def adjustment_rows = @adjustment_rows ||= @adjustments.nil? ? query_adjustments : @adjustments

  def query_transfers
    return [] if start.nil?

    account.transfers_in.where(date: start..).pluck(:date, :amount).map { |day, amount| [day, amount.to_d] }
  end

  def query_income
    ids = targets.filter_map(&:item_id)
    return {} if ids.empty? || start.nil?

    Entry.where(item_id: ids, date: start..).pluck(:item_id, :date, :amount)
      .group_by(&:first)
      .transform_values { |rows| rows.map { |_id, day, amount| [day, amount.to_d] } }
  end

  def query_adjustments = account.adjustments.pluck(:date, :amount).map { |day, amount| [day, amount.to_d] }
end
