# frozen_string_literal: true

# Presenter for the weekly calendar view.
# Pre-computes entry groupings and weekly breakdown to minimize view complexity.
#
# Usage in controller:
#   @presenter = WeeklyCalendarPresenter.new(user: current_user, date: Date.current)
#
# Usage in view:
#   @presenter.days.each { |day| day[:entries_by_type][:expense] }
#   @presenter.weekly_breakdown[:expense][:total]
#   @presenter.range_label
#
class WeeklyCalendarPresenter
  attr_reader :focused_date, :week_start, :week_end

  def initialize(user:, date:)
    @user = user
    @focused_date = date
    @week_start = date - date.wday
    @week_end = @week_start + 6
    @entries = fetch_entries
    @entries_by_date = group_entries_by_date
  end

  # Returns array of days, each containing:
  # { date:, entries_by_type: { expense: [...], income: [...], savings: [...] } }
  def days
    @days ||= build_days
  end

  # Returns weekly breakdown:
  # { expense: { total:, categories: { "Food" => 100 } }, income: {...}, savings: {...} }
  def weekly_breakdown
    @weekly_breakdown ||= calculate_weekly_breakdown
  end

  def range_label
    if week_start.month == week_end.month
      "#{week_start.strftime("%b %-d")} – #{week_end.strftime("%-d, %Y")}"
    else
      "#{week_start.strftime("%b %-d")} – #{week_end.strftime("%b %-d, %Y")}"
    end
  end

  def prev_week_date
    (focused_date - 7).strftime("%Y-%m-%d")
  end

  def next_week_date
    (focused_date + 7).strftime("%Y-%m-%d")
  end

  def month_path_params
    { month: focused_date.month, year: focused_date.year }
  end

  private

  def fetch_entries
    Entry.joins(item: :category)
      .includes(item: :category)
      .where(categories: { user_id: @user.id })
      .where(date: week_start.beginning_of_day..week_end.end_of_day)
      .order(:date)
  end

  def group_entries_by_date
    @entries.group_by { |e| e.date.to_date }
  end

  def build_days
    (week_start..week_end).map do |date|
      entries = @entries_by_date[date] || []
      {
        date: date,
        entries_by_type: group_by_type(entries)
      }
    end
  end

  def group_by_type(entries)
    CategoryTypeHelper::CATEGORY_TYPES.index_with do |type|
      entries.select { |e| e.category.category_type.to_sym == type }.map do |e|
        {
          id: e.id,
          name: e.item.name,
          amount: e.amount,
          category_name: e.category.name
        }
      end
    end
  end

  def calculate_weekly_breakdown
    breakdown = empty_breakdown
    @entries.each { |entry| add_to_breakdown(breakdown, entry) }
    breakdown
  end

  def empty_breakdown
    CategoryTypeHelper::CATEGORY_TYPES.index_with { { total: 0, categories: Hash.new(0) } }
  end

  def add_to_breakdown(breakdown, entry)
    type = entry.category.category_type.to_sym
    return unless breakdown.key?(type)

    breakdown[type][:total] += entry.amount
    breakdown[type][:categories][entry.category.name] += entry.amount
  end
end
