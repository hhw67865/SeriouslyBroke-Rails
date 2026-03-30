# frozen_string_literal: true

class DashboardController < ApplicationController
  include PeriodContext

  def index
    @tab = (params[:tab] || :all).to_sym
    @presenter = DashboardPresenter.new(user: current_user, date: selected_date, period: current_period, show_total: params[:show_total] == "true")
  end
end
