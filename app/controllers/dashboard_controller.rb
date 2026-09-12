# frozen_string_literal: true

class DashboardController < ApplicationController
  include PeriodContext

  # `?tab=` is checked against this rather than trusted: index.html.erb renders in a `case` with no
  # `else`, so an unrecognised tab would print the tab strip over an empty panel.
  TABS = [:all, :expenses, :income].freeze

  def index
    @tab = TABS.include?(params[:tab]&.to_sym) ? params[:tab].to_sym : :all
    @presenter = DashboardPresenter.new(user: current_user, date: selected_date, period: current_period, show_total: params[:show_total] == "true")
  end
end
