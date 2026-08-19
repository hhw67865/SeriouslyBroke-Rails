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
    # The add-account card's form object (see bank_accounts_controller.rb for why the type is
    # fixed). `Pool.new`, not `current_user.pools.new` — the association form would append the
    # unsaved record to any loaded target for the rest of the request.
    @new_bank_account = Pool.new(user: current_user, pool_type: :account)
  end
end
