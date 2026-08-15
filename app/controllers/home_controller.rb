# frozen_string_literal: true

class HomeController < ApplicationController
  # No `include DateContext`: it is already inherited from ApplicationController, and
  # ActiveSupport::Concern's `append_features` bails out on an ancestor that already
  # includes it, so a second include here would be a silent no-op — noise, nothing more.
  # The concern stays in the chain because shared/_date_selector calls its
  # `selected_month` / `selected_year` helpers on every page. Home itself is anchored to
  # today rather than to that month scrubber, hence `Date.current` below.
  def index
    @presenter = HomePresenter.new(user: current_user, today: Date.current)
  end
end
