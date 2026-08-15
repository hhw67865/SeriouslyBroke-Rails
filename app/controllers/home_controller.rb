# frozen_string_literal: true

class HomeController < ApplicationController
  # No `include DateContext`: ApplicationController already includes it, so re-including
  # here would re-run the concern's `included do` block and register
  # `before_action :set_selected_month_year` a second time on this controller. Home is
  # anchored to today rather than to the sidebar's month scrubber, so it needs nothing
  # from the concern beyond the helper methods shared/_date_selector calls.
  def index
    @presenter = HomePresenter.new(user: current_user, today: Date.current)
  end
end
