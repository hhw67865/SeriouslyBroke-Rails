# frozen_string_literal: true

class DistributionsController < ApplicationController
  # GET /distributions/new
  #
  # The proposal only. Confirming it is `create`, which Task 6 owns.
  def new
    account = distribution_account
    return redirect_to(root_path, alert: "Set up an account before distributing.") if account.nil?

    @presenter = DistributionPresenter.new(user: current_user, account: account, today: Date.current)
  end

  private

  # OWNERSHIP LIVES HERE. AllocationCalculator takes a `user` and an `account` and never checks
  # that the two belong together — it is arithmetic over whatever account it is handed — so a
  # bare `Pool.find(params[:account_id])` would hand a signed-in user another user's balances,
  # envelope names and buffer. Scoped through `current_user.pools`, an id that is not theirs
  # raises RecordNotFound and the request 404s, which is the same answer as an id that does not
  # exist — the correct one, since neither is a resource this user has.
  #
  # `.accounts` as well as the user scope: an envelope's id is a valid pool id belonging to the
  # right user, and AllocationCalculator over an envelope would fill its CHILDREN, of which it
  # has none, and report the envelope's own balance as a buffer to hand out. A screen with no
  # rows and a real number on it is worse than a 404.
  def distribution_account
    accounts = current_user.pools.accounts
    return accounts.find(params[:account_id]) if params[:account_id].present?

    # `by_priority` — `[priority, name]` — rather than whatever Postgres hands back: heap order
    # moves a row on any plain UPDATE, so the screen would open on a different account after an
    # unrelated edit. Priority first because the user has already ranked their pools, and it
    # gives them a way to choose without a setting; name only breaks the tie.
    current_user.default_account || accounts.by_priority.first
  end
end
