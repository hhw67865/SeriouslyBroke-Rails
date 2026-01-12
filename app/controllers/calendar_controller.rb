# frozen_string_literal: true

class CalendarController < ApplicationController
  include DateContext

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
    @presenter = WeeklyCalendarPresenter.new(user: current_user, date: Date.current)
  end

  private

  def parse_date_param
    params[:date].present? ? Date.parse(params[:date]) : Date.current
  end
end
