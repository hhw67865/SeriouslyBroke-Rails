# frozen_string_literal: true

module CalendarHelper
  include ActionView::Helpers::NumberHelper

  def month_weeks(month_date)
    start = month_date.beginning_of_month.beginning_of_week(:sunday)
    finish = month_date.end_of_month.end_of_week(:sunday)
    weeks = []
    week = []
    (start..finish).each do |date|
      week << { date: date, in_month: date.month == month_date.month }
      if week.size == 7
        weeks << week
        week = []
      end
    end
    weeks
  end

  def entries_for_date(date)
    @entries.select { |e| e.date.to_date == date }
  end

  def muted_day_class(in_month)
    in_month ? "" : "calendar-adjacent"
  end

  def week_nav_date(date, direction)
    offset = direction == :prev ? -7 : 7
    (date + offset).strftime("%Y-%m-%d")
  end

  def compact_currency(amount)
    "$" + number_to_human(
      amount,
      format: "%n%u",
      precision: 3,
      significant: true,
      strip_insignificant_zeros: true,
      units: {
        unit: "",
        thousand: "k",
        million: "m",
        billion: "b",
        trillion: "t"
      }
    )
  end

  def month_has_data?(month_date)
    @entries.any?
  end
end
