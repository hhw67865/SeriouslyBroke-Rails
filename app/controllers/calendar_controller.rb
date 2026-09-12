# frozen_string_literal: true

class CalendarController < ApplicationController
  def index
    @presenter = MonthlyCalendarPresenter.new(
      user: current_user,
      month_date: Date.new(selected_year, selected_month, 1)
    )
  end

  def week
    @presenter = WeeklyCalendarPresenter.new(
      user: current_user,
      date: parse_date_param
    )
  rescue ArgumentError
    @presenter = WeeklyCalendarPresenter.new(user: current_user, date: current_user.today)
  end

  private

  def parse_date_param
    params[:date].present? ? Date.parse(params[:date]) : current_user.today
  end
end
