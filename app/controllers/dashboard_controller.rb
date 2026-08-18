# frozen_string_literal: true

class DashboardController < ApplicationController
  include PeriodContext

  # THE TABS THIS PAGE HAS, and `?tab=` is checked against them rather than trusted.
  #
  # `?tab=savings` IS NOW A STALE BOOKMARK (plan 3, task 5) — the savings tab is deleted with the
  # category type it summed. `@tab` used to be whatever the query string said, and `index.html.erb`
  # renders in a `case` with no `else`, so an unknown tab printed the tab strip and the period
  # toggle over an EMPTY panel: a page that looks broken rather than a page that says the tab is
  # gone. Anything unrecognised lands on All, which is where this page opens anyway.
  TABS = [:all, :expenses, :income].freeze

  def index
    @tab = TABS.include?(params[:tab]&.to_sym) ? params[:tab].to_sym : :all
    @presenter = DashboardPresenter.new(user: current_user, date: selected_date, period: current_period, show_total: params[:show_total] == "true")
  end
end
