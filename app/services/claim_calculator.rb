# frozen_string_literal: true

# One rule's claim on main, computed from its shape, the user's period grid, its lane's spending
# and its adjustments. Spending and adjustment rows are [day, amount] pairs, queried unless handed in.
class ClaimCalculator
  PERIOD_WALK_LIMIT = 520

  Walk = Struct.new(:built_up, :raw, :planned, :paid) do
    def self.start = new(0.to_d, 0.to_d, 0.to_d, 0.to_d)
  end

  attr_reader :rule, :today

  def initialize(rule, today: rule.today, spending: nil, adjustments: nil)
    @rule = rule
    @today = today
    @spending = spending
    @adjustments = adjustments
  end

  delegate :shape, to: :rule
  def rate? = shape == :rate
  def dated? = shape == :dated
  def fund? = shape == :fund
  def allowance? = rate? || fund?

  def claim
    return 0.to_d if periods.empty?

    rate? ? rate_claim : built_up
  end

  def built_up = rate? ? 0.to_d : walk.built_up

  def planned_this_period
    return 0.to_d if periods.empty?

    rate? ? rate_per_period : walk.planned
  end

  # What the rule costs a period: its amount, a one-off target spread to its date, or, for a
  # rolling rule, the rule's own share of an interval. Rule only calls back for the one-off arm.
  def ask
    return rate_per_period if allowance?
    return (target / periods_to_fund).round(2) if one_time?

    rule.ask(today: today)
  end

  def accrued_this_period = planned_this_period + adjustments_within(current_period)
  def spent_this_period = spent_within(current_period)
  def over? = rate? ? raw_rate.negative? : walk.raw.negative?
  def raw_rate = accrued_this_period - spent_this_period
  def over_by = rate? ? -raw_rate : -walk.raw
  def next_due_on = dated? ? due_on(walk.paid) : nil
  def overdue? = next_due_on.present? && next_due_on < today && !settled?
  def settled? = one_time? && settled_by?(walk.paid)

  def settled_on
    return nil unless settled?

    running = 0.to_d
    countable_spending.each do |day, amount|
      running += amount
      return day if running >= target
    end
    nil
  end

  def periods_left
    due = next_due_on
    due ? periods_left_from(current_period.first, due) : nil
  end

  def target
    return @target if defined?(@target)

    @target = if dated?
                rule.amount.to_d
              else
                (fund? ? nil : 0.to_d)
              end
  end

  def window_start = periods.first&.first || current_period.first

  def counts_spending_on?(day) = day >= rule.starts_on && periods.any? { |period| period.cover?(day) }

  # Every entry `spent` sums, as a relation rather than a second copy of the lane logic: the
  # periods this calculator walks are contiguous, so their span is one date range.
  def counted_entries
    return Entry.none if periods.empty?

    Entry.in_lane_of(rule)
      .since([window_start, rule.starts_on].max)
      .where(date: ..periods.last.last)
      .includes(:item)
      .order(date: :desc, created_at: :desc)
  end

  # The dates an adjustment may carry: from the rule's start (or the first counted period) to today.
  def countable_span
    return (today...today) if periods.empty?

    [window_start, rule.starts_on].max..[today, periods.last.last].min
  end

  private

  def user = rule.user
  def rate_claim = [raw_rate, 0.to_d].max
  def rate_per_period = rule.amount.to_d

  def walk
    @walk ||= Walk.start.tap { |state| periods.each { |period| step(state, period) } }
  end

  def step(state, period)
    state.planned = planned_for(period, state, due_on(state.paid))
    settle(state, accrued_in(state, period), spent_within(period))
  end

  def accrued_in(state, period)
    accrued = state.built_up + state.planned + adjustments_within(period)
    return accrued if fund?

    [accrued, target].min
  end

  def settle(state, accrued, spent)
    state.paid += spent
    state.raw = accrued - spent
    state.built_up = [state.raw, 0.to_d].max
  end

  def planned_for(period, state, due)
    return rate_per_period if fund?
    return 0.to_d if settled_by?(state.paid)

    gap = target - state.built_up
    return 0.to_d unless gap.positive?

    [(gap / periods_left_from(period.first, due)).round(2), gap].min
  end

  def settled_by?(paid) = one_time? && paid >= target
  def one_time? = anchor.present? && rule.interval_months.nil?
  def anchor = rule.anchor_date

  def countable_spending
    spending_rows.select { |day, _amount| counts_spending_on?(day) }.sort_by(&:first)
  end

  # A one-off is due on its date. A rolling rule's due dates are a series — the anchor stepped by
  # the interval, forward and back — and each target paid settles the earliest open one, so the
  # next due date is the first not yet covered. Paying ahead settles further dates; no cap.
  def due_on(paid)
    return nil if anchor.blank?
    return anchor if rule.interval_months.nil? || !target.positive?

    due_at(first_due_index + (paid / target).floor)
  end

  def due_at(index) = anchor + (index * rule.interval_months).months

  # The series index of the first due date on or after the rule's start.
  def first_due_index
    @first_due_index ||= begin
      index = 0
      index -= 1 while due_at(index - 1) >= rule.starts_on
      index += 1 while due_at(index) < rule.starts_on
      index
    end
  end

  def periods
    @periods ||= if rule.starts_on > today
                   []
                 elsif rate?
                   [current_period]
                 else
                   walk_periods
                 end
  end

  def current_period = @current_period ||= user.period_containing(today)

  def walk_periods
    visited = []
    cursor = user.period_containing(rule.starts_on)
    while cursor.first <= today && visited.size < PERIOD_WALK_LIMIT
      visited << cursor
      cursor = user.period_containing(cursor.last + 1)
    end
    visited
  end

  def periods_left_from(from, due) = [user.period_boundaries(from: from, to: due).count, 1].max
  def periods_to_fund = periods_left_from(user.period_containing(rule.starts_on).first, anchor)

  def spent_within(period)
    spending_rows.sum(0.to_d) { |day, amount| period.cover?(day) && day >= rule.starts_on ? amount : 0.to_d }
  end

  def adjustments_within(period)
    adjustment_rows.sum(0.to_d) { |day, amount| period.cover?(day) ? amount : 0.to_d }
  end

  def spending_rows = @spending_rows ||= @spending.nil? ? query_spending : @spending
  def adjustment_rows = @adjustment_rows ||= @adjustments.nil? ? query_adjustments : @adjustments

  def query_spending
    Entry.in_lane_of(rule).since([window_start, rule.starts_on].max).pluck(:date, :amount).map { |day, amount| [day, amount.to_d] }
  end

  def query_adjustments
    rule.adjustments.pluck(:date, :amount).map { |day, amount| [day, amount.to_d] }
  end
end
