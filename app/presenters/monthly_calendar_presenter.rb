# frozen_string_literal: true

# The month grid: six weeks of days, each with the day's expense and income totals.
class MonthlyCalendarPresenter
  attr_reader :month_date

  def initialize(user:, month_date:)
    @user = user
    @month_date = month_date
    @entries = fetch_entries
    @entries_by_date = group_entries_by_date
  end

  # { date:, in_month:, totals: { expense:, income: } } per day.
  def weeks
    @weeks ||= build_weeks
  end

  def data?
    @entries.any? { |e| e.date.month == month_date.month && e.date.year == month_date.year }
  end

  def month_label
    month_date.strftime("%B %Y")
  end

  def calendar_start
    @calendar_start ||= month_date.beginning_of_month.beginning_of_week(:sunday)
  end

  def calendar_end
    @calendar_end ||= month_date.end_of_month.end_of_week(:sunday)
  end

  private

  def fetch_entries
    Entry.joins(item: :category)
      .where(categories: { user_id: @user.id })
      .where(date: calendar_start..calendar_end)
      .includes(item: :category)
  end

  def group_entries_by_date
    @entries.group_by(&:date)
  end

  def build_weeks
    weeks = []
    week = []

    (calendar_start..calendar_end).each do |date|
      week << build_day(date)
      if week.size == 7
        weeks << week
        week = []
      end
    end

    weeks
  end

  def build_day(date)
    entries = @entries_by_date[date] || []

    {
      date: date,
      in_month: date.month == month_date.month,
      totals: calculate_totals(entries)
    }
  end

  def calculate_totals(entries)
    CategoryTypeHelper::CATEGORY_TYPES.index_with do |type|
      entries.select { |e| e.category.category_type.to_sym == type }.sum(&:amount)
    end
  end
end
