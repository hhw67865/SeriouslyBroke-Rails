# frozen_string_literal: true

# The mean of chosen income categories over a user's last complete periods. `user` may be an
# unsaved probe carrying a typed cadence and anchor, so the grid it walks is whichever one is set.
class IncomeMeasure
  PERIODS = 2
  Period = Data.define(:range, :income)

  attr_reader :user, :category_ids, :today

  def initialize(user, category_ids:, today: user.today)
    @user = user
    @category_ids = category_ids
    @today = today
  end

  # The last PERIODS complete periods before today's, oldest first, that begin on or after the
  # user's first entry.
  def periods
    @periods ||= complete_periods(PERIODS).map { |range| Period.new(range: range, income: income_within(range)) }
  end

  def typical
    return nil if periods.empty?

    (periods.sum(0.to_d, &:income) / periods.size).round(2)
  end

  private

  def complete_periods(limit)
    first = user.entries.minimum(:date)
    return [] if first.nil?

    walk_periods_back(previous_period(today), limit, first)
  end

  # Walks backward from `cursor`, collecting periods that begin on or after `first`, oldest last.
  def walk_periods_back(cursor, limit, first)
    ranges = []
    while ranges.size < limit && cursor.first >= first
      ranges.unshift(cursor)
      cursor = previous_period(cursor.first)
    end
    ranges
  end

  def previous_period(date) = user.period_containing(user.period_containing(date).first - 1)

  def income_within(range)
    Entry.incomes.where(categories: { id: category_ids, user_id: user.id }, date: range).sum(:amount).to_d
  end
end
