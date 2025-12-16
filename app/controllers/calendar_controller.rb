# frozen_string_literal: true

class CalendarController < ApplicationController
  include DateContext

  def index
    @month_date = Date.new(selected_year, selected_month, 1)
    calendar_start = @month_date.beginning_of_month.beginning_of_week(:sunday)
    calendar_end = @month_date.end_of_month.end_of_week(:sunday)
    @entries = Entry.joins(item: :category)
      .where(categories: { user_id: current_user.id })
      .where(date: calendar_start..calendar_end)
      .includes(item: :category)
  end

  def week
    date_str = params[:date]
    @focused_date = date_str.present? ? Date.parse(date_str) : Date.current
    @week_start = @focused_date - @focused_date.wday
    @week_end = @week_start + 6
    @week_entries_by_day = build_week_entries(@week_start..@week_end)
    calculate_weekly_totals
  rescue ArgumentError
    @focused_date = Date.current
    @week_start = @focused_date - @focused_date.wday
    @week_end = @week_start + 6
    @week_entries_by_day = build_week_entries(@week_start..@week_end)
    calculate_weekly_totals
  end

  private

  # Real data: entries grouped by day for a week range for current_user
  def build_week_entries(range)
    entries = Entry.joins(item: :category)
      .includes(item: :category)
      .where(categories: { user_id: current_user.id })
      .where(date: range.begin.beginning_of_day..range.end.end_of_day)
      .order(:date)

    by_day = (range.begin..range.end).index_with { |d| [] }

    entries.each do |e|
      by_day[e.date.to_date] << {
        id: e.id,
        name: e.item.name,
        amount: e.amount,
        type: e.category.category_type.to_sym,
        category_name: e.category.name
      }
    end

    by_day
  end

  def calculate_weekly_totals
    @weekly_breakdown = {
      expense: { total: 0, categories: Hash.new(0) },
      income: { total: 0, categories: Hash.new(0) },
      savings: { total: 0, categories: Hash.new(0) }
    }

    @week_entries_by_day.each_value do |day_entries|
      day_entries.each do |entry|
        type = entry[:type]
        next unless @weekly_breakdown.key?(type)

        amount = entry[:amount]
        @weekly_breakdown[type][:total] += amount
        @weekly_breakdown[type][:categories][entry[:category_name]] += amount
      end
    end
  end
end
