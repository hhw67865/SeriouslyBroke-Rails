# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable

  has_many :categories, dependent: :destroy
  has_many :accounts, dependent: :destroy
  has_many :items, through: :categories
  has_many :entries, through: :items
  has_many :rules, through: :categories
  belongs_to :main_account, class_name: "Account", optional: true

  enum :theme, { light: 0, dark: 1 }
  enum :period_cadence, { weekly: 0, biweekly: 1, semimonthly: 2, monthly: 3 }, prefix: :period

  normalizes :timezone, with: ->(value) { value.presence }

  validates :email, confirmation: { case_sensitive: false }, if: :will_save_change_to_email?
  validates :timezone, inclusion: { in: TZInfo::Timezone.all_identifiers }, allow_nil: true
  validates :period_anchor_date, presence: { message: "is required when you set a period" }, if: :period_cadence
  validate :main_account_is_own

  PERIODS_PER_YEAR = { "weekly" => 52, "biweekly" => 26, "semimonthly" => 24, "monthly" => 12 }.freeze
  STRIDE_DAYS = { "weekly" => 7, "biweekly" => 14 }.freeze
  # Wide enough to hold a whole period on either side of any date, on any cadence.
  PERIOD_WINDOW_DAYS = 45

  def periods_per_year = PERIODS_PER_YEAR.fetch(period_cadence, 12)

  def today = Time.current.in_time_zone(timezone.presence || "UTC").to_date

  # The day before the first entry, so an opening balance predates everything that flowed since.
  def opening_day
    first = entries.minimum(:date)
    first ? first.to_date - 1 : today
  end

  def toggle_theme! = update(theme: light? ? :dark : :light)

  # Every period boundary in from..to on the user's grid, ascending. The first of each month
  # without a cadence, so a grid always exists to spread a dated rule over.
  def period_boundaries(from:, to:)
    from = from.to_date
    to = to.to_date
    return [] if to < from
    return monthly_dates([1], from, to) if period_cadence.blank? || period_anchor_date.blank?

    case period_cadence
    when "weekly", "biweekly" then strided_dates(STRIDE_DAYS.fetch(period_cadence), from, to)
    when "monthly" then monthly_dates([period_anchor_date.day], from, to)
    when "semimonthly" then monthly_dates(semimonthly_days, from, to)
    end
  end

  # The period holding the date: from its opening boundary to the day before the next one. The
  # window is wider than any cadence's period, so a boundary is always found on either side.
  def period_containing(date)
    date = date.to_date
    opened_on = period_boundaries(from: date - PERIOD_WINDOW_DAYS, to: date).last
    next_boundary = period_boundaries(from: date + 1, to: date + PERIOD_WINDOW_DAYS).first
    opened_on..(next_boundary - 1)
  end

  # The last `limit` complete periods before today's, oldest first, that begin on or after this
  # user's first entry.
  def complete_periods(limit, today: self.today)
    first = entries.minimum(:date)
    return [] if first.nil?

    walk_periods_back(previous_period(today), limit, first)
  end

  private

  # Walks backward from `cursor`, collecting periods that begin on or after `first`, oldest last.
  def walk_periods_back(cursor, limit, first)
    ranges = []
    while ranges.size < limit && cursor.first >= first
      ranges.unshift(cursor)
      cursor = previous_period(cursor.first)
    end
    ranges
  end

  def previous_period(date) = period_containing(period_containing(date).first - 1)

  def strided_dates(stride, from, to)
    steps = ((from - period_anchor_date).to_i / stride.to_f).ceil
    first = period_anchor_date + (steps * stride)
    return [] if first > to

    (first..to).step(stride).to_a
  end

  def monthly_dates(days, from, to)
    dates = []
    cursor = from.beginning_of_month
    while cursor <= to
      days.each do |day|
        date = cursor.change(day: [day, cursor.end_of_month.day].min)
        dates << date if date.between?(from, to)
      end
      cursor = cursor.next_month
    end
    dates.sort
  end

  def semimonthly_days
    first = period_anchor_date.day
    [first, first <= 15 ? first + 15 : first - 15].sort
  end

  def main_account_is_own
    return if main_account.blank? || main_account.user_id == id

    errors.add(:main_account, "must be an account you own")
  end
end
