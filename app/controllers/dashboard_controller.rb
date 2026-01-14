# frozen_string_literal: true

class DashboardController < ApplicationController
  include PeriodContext

  def index
    @tab = (params[:tab] || :expenses).to_sym
    @presenter = DashboardPresenter.new(user: current_user, date: selected_date, period: current_period)
  end
end
