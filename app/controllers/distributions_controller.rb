# frozen_string_literal: true

class DistributionsController < ApplicationController
  # GET /distributions/new
  #
  # The proposal only. Confirming it is `create`, which Task 6 owns.
  def new
    account = distribution_account
    return redirect_to(root_path, alert: "Set up an account before distributing.") if account.nil?

    @presenter = DistributionPresenter.new(
      user: current_user,
      account: account,
      today: Date.current,
      overrides: override_params
    )
  end

  private

  # The edits the user typed into the waterfall, exactly as AllocationCommitter consumes them:
  # `{pool_id => amount}`, keyed by pool id because a row's position is not stable across a
  # re-derived proposal. Nothing is written here and nothing is cast here — the committer owns
  # the coercion, and a second `.to_d` on this side is a second answer to "what did they mean by
  # an empty box".
  #
  # Two guards, both against shapes only a hand-built URL produces: `overrides=1` arrives as a
  # String and has no #permit!, and `overrides[x][]=1` arrives as an Array, which #to_d does not
  # answer to — either one is a 500 on a GET anyone can link to. Values that are not strings are
  # dropped rather than rescued, so the row simply keeps its proposed figure.
  #
  # `permit!` is safe precisely because the keys are pool ids and nothing here mass-assigns:
  # every key is looked up against THIS account's own rows (AllocationCommitter#amount_for), so
  # an id belonging to someone else names no row and is ignored.
  def override_params
    raw = params[:overrides]
    return {} unless raw.is_a?(ActionController::Parameters)

    raw.permit!.to_h.select { |_pool_id, amount| amount.is_a?(String) }
  end

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
    return current_user.pools.accounts.find(params[:account_id]) if params[:account_id].present?

    default_account
  end

  # THE ACCOUNT THE PAY LANDED IN — the plan's ruling, and it is a real choice as soon as a user
  # has two accounts. `[priority, name]` alone opened the demo user's screen on Ally Savings, an
  # account holding one envelope, while the paycheck sat in Checking; you distribute the account
  # your income arrived in.
  #
  # `by_priority` is the tie-break, not the rule, and `-index` keeps it: `max_by` gives no
  # guarantee about which of several maxima it returns, so two accounts with no income at all —
  # a brand-new user, and every user before their first paycheck of the period — would otherwise
  # open on whichever one Ruby happened to compare last.
  #
  # `current_user.default_account` is deliberately NOT consulted. It is one question, and the
  # plan answers it; a second rule in front of this one is a second answer, and the two disagree
  # exactly when the user's pay lands somewhere other than their nominated account — which is
  # the case this rule exists for.
  def default_account
    period = current_user.period_datetimes_containing(Date.current)
    ranked = current_user.pools.accounts.by_priority.to_a

    ranked.each_with_index.max_by do |account, index|
      [account.calculator.income_within(period), -index]
    end&.first
  end
end
