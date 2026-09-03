# frozen_string_literal: true

# ONE DISTRIBUTION PER PERIOD PER USER (two-ledger spec §2). The purpose ledger has a single root —
# AVAILABLE — so there is nothing here to choose between and nothing to look up: this controller
# used to carry `#distribution_account`, `#default_account` and `#fallback_account_by_income`,
# forty lines whose whole job was deciding WHICH account's buffer was being handed out. They are
# gone with the second root, and with them the ownership question they existed to answer safely:
# `AllocationCalculator` now takes a `user` and nothing else, so there is no id from the request for
# a stranger's money to arrive in.
class DistributionsController < ApplicationController
  # GET /distributions/new
  #
  # The proposal only. Confirming it is #create.
  def new
    @presenter = presenter
  end

  # POST /distributions
  #
  # THE SPLIT. Everything above this line describes what would happen; this is the line that makes
  # it happen, and it is the only request in the app that moves money on the purpose ledger.
  #
  # THE PROPOSAL CARRIES THE OVERRIDES AND THE COMMITTER WRITES WHAT IT SAYS. The plan's original
  # wording — "calls AllocationCommitter with the overrides" — describes an AllocationCommitter that
  # no longer exists: it took an `overrides:` keyword and substituted those figures onto an
  # already-finished fill, which decided the split in two places and meant money freed by cutting a
  # high row could never reach the category below it. There is one split now, decided inside
  # AllocationCalculator#fill, and #proposal is the same construction the screen renders from — so
  # what is written is what was shown.
  #
  # NOTHING WRAPS #call. AllocationCommitter opens `transaction(requires_new: true)` precisely
  # because a caller's own transaction would otherwise swallow its rollback and commit a half-written
  # split under a `success? == false` result. It does not need help here, and anything added around
  # this line would be that shape.
  #
  # A failure re-renders the SAME screen with the errors above it, rather than redirecting: the
  # user's edits are in the query the form submitted, so the boxes come back holding what they typed
  # and the row that was refused is still on screen next to the reason.
  def create
    committer = AllocationCommitter.new(proposal)
    result = committer.call
    return redirect_to(root_path, notice: confirmation_for(result, committer)) if result.success?

    @errors = result.errors
    @presenter = presenter
    render :new, status: :unprocessable_content
  end

  private

  # The available figure is read HERE, after the write, and that is the whole reason it is
  # trustworthy: `CategoryLedger` is a snapshot memoised at first read, so the proposal's own ledger
  # has been stale since the first allocation saved. A fresh one reads the ledger the user is about
  # to see on Home, so the flash and Home cannot disagree.
  def confirmation_for(result, committer)
    helpers.distribution_confirmation(
      result,
      # A redistribution REPLACED the previous split, and the screen said so before confirming.
      # Saying "distributed" afterwards would contradict the banner the user just consented to.
      # #replaced is what the committer actually deleted, not a re-derived guess.
      replaced: committer.replaced.any?,
      available: CategoryLedger.new(current_user.categories.expenses.to_a, user: current_user).available
    )
  end

  # One construction, both actions. The screen and the confirm read the same params through the same
  # coercion, so a proposal that renders one split and writes another has nowhere to come from.
  def presenter
    DistributionPresenter.new(
      user: current_user,
      today: Date.current,
      overrides: override_params,
      # The user asking for the full table on a period that does not need one. A bare presence check,
      # not a boolean cast: the link either carries the parameter or it does not, and `expand=0` is
      # not a shape anything on this screen produces.
      expanded: params[:expand].present?
    )
  end

  # What the committer writes. `overrides` go on the PROPOSAL — the committer has no override path of
  # its own to disagree with this one.
  def proposal
    AllocationCalculator.new(user: current_user, today: Date.current, overrides: override_params)
  end

  # The edits the user typed into the waterfall, exactly as AllocationCalculator consumes them:
  # `{category_id => amount}`, keyed by category id because a row's position is not stable across a
  # re-derived proposal. Nothing is written here and nothing is cast here — AllocationCalculator owns
  # the coercion, and a second `.to_d` on this side is a second answer to "what did they mean by an
  # empty box".
  #
  # Two guards. `overrides=1` arrives as a String and has no #permit!; `overrides[x][]=1` arrives as
  # an Array, which #to_d does not answer to — either one is a 500 on a GET anyone can link to.
  # Values that are not strings are dropped rather than rescued, so the row simply keeps its proposed
  # figure.
  #
  # THE FIRST OF THOSE WAS PRODUCED BY THIS APP'S OWN UI, not by a hand-built URL, and that is worth
  # knowing before anyone relaxes it. The month scrubber re-emitted every query parameter as
  # `hidden_field key, value: value`, which writes a hash's #to_s into one scalar box — so clicking a
  # month arrow mid-edit submitted `overrides=<inspected hash>` and this guard was the only thing
  # standing between that and a 500. The scrubber now drops non-scalar params deliberately (see
  # shared/_date_selector), and the guard stays, because a hidden field somewhere else is one line
  # away from re-creating the shape.
  #
  # `permit!` is safe precisely because the keys are category ids and nothing here mass-assigns:
  # every key is looked up against THIS user's own rows (AllocationCalculator#fill, which rejects on
  # the CATEGORY'S ask before an override is consulted), so an id belonging to someone else names no
  # row and is ignored.
  def override_params
    raw = params[:overrides]
    return {} unless raw.is_a?(ActionController::Parameters)

    raw.permit!.to_h.select { |_category_id, amount| amount.is_a?(String) }
  end
end
