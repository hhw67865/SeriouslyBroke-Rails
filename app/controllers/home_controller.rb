# frozen_string_literal: true

class HomeController < ApplicationController
  # No `include DateContext`: it is already inherited from ApplicationController, and
  # ActiveSupport::Concern's `append_features` bails out on an ancestor that already
  # includes it, so a second include here would be a silent no-op — noise, nothing more.
  # The concern stays in the chain because shared/_date_selector calls its
  # `selected_month` / `selected_year` helpers on every page. Home itself is anchored to
  # today rather than to that month scrubber, hence the `today:` below — and it is the OWNER's day
  # (`User#today`, fix round 2 — LOW-1), not the ambient clock's.
  def index
    assign_home_state
  end

  protected

  # SHARED BY EVERY HOME-SCREEN DOOR'S 422 BRANCH (BankAccountsController, AccountOpeningsController)
  # and by #index itself, so the two never drift the way a hand-rebuilt copy in each controller
  # eventually would. Both halves this method assigns are read by `home/index` no matter which
  # controller rendered it.
  #
  # `rejected_opening:` reaches #index too, always nil there — HomePresenter's own default — so
  # this stays the one place `HomePresenter.new` is called for a Home render rather than a second
  # constructor call free to forget the keyword. It was `rejected_movement:` while onboarding asked
  # about funding movements; nothing on this screen asks the user about a movement now.
  #
  # `Pool.new`, not `current_user.pools.new` — the association form would append the unsaved
  # record to any loaded target for the rest of the request.
  def assign_home_state(rejected_opening: nil)
    @presenter = HomePresenter.new(user: current_user, today: current_user.today, rejected_opening: rejected_opening)
    @new_bank_account = Pool.new(user: current_user, pool_type: :account)
  end
end
