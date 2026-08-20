# frozen_string_literal: true

class DistributionsController < ApplicationController
  # GET /distributions/new
  #
  # The proposal only. Confirming it is #create.
  def new
    account = distribution_account
    return redirect_to(root_path, alert: "Set up an account before distributing.") if account.nil?

    @presenter = presenter_for(account)
  end

  # POST /distributions
  #
  # THE SPLIT. Everything above this line describes what would happen; this is the line that
  # makes it happen, and it is the only request in the app that moves money between pools.
  #
  # THE PROPOSAL CARRIES THE OVERRIDES AND THE COMMITTER WRITES WHAT IT SAYS. The plan's
  # original wording — "calls AllocationCommitter with the overrides" — describes an
  # AllocationCommitter that no longer exists: it took an `overrides:` keyword and substituted
  # those figures onto an already-finished fill, which decided the split in two places and meant
  # money freed by cutting a high row could never reach the envelope below it. There is one
  # split now, decided inside AllocationCalculator#fill, and #proposal_for is the same
  # construction the screen renders from — so what is written is what was shown.
  #
  # NOTHING WRAPS #call. AllocationCommitter opens `transaction(requires_new: true)` precisely
  # because a caller's own transaction would otherwise swallow its rollback and commit a
  # half-written split under a `success? == false` result. It does not need help here, and
  # anything added around this line would be that shape.
  #
  # A failure re-renders the SAME screen with the errors above it, rather than redirecting: the
  # user's edits are in the query the form submitted, so the boxes come back holding what they
  # typed and the row that was refused is still on screen next to the reason.
  def create
    account = distribution_account
    return redirect_to(root_path, alert: "Set up an account before distributing.") if account.nil?

    committer = AllocationCommitter.new(proposal_for(account))
    result = committer.call
    return redirect_to(root_path, notice: confirmation_for(result, committer, account)) if result.success?

    @errors = result.errors
    @presenter = presenter_for(account)
    render :new, status: :unprocessable_content
  end

  private

  # `account.calculator` is built HERE, after the write, and that is the whole reason the
  # buffer figure in the sentence is trustworthy: PoolCalculator memoises, so the proposal's
  # own calculators have been stale since the first movement saved. A fresh one reads the
  # ledger the user is about to see on Home, so the flash and Home cannot disagree.
  def confirmation_for(result, committer, account)
    helpers.distribution_confirmation(
      result,
      # Amendment D: a redistribution REPLACED the previous split, and the screen said so before
      # confirming. Saying "distributed" afterwards would contradict the banner the user just
      # consented to. #replaced is what the committer actually deleted, not a re-derived guess.
      replaced: committer.replaced.any?,
      buffer: account.calculator.balance
    )
  end

  # One construction, both actions. The screen and the confirm read the same params through the
  # same coercion, so a proposal that renders one split and writes another has nowhere to come
  # from.
  def presenter_for(account)
    DistributionPresenter.new(
      user: current_user,
      account: account,
      today: Date.current,
      overrides: override_params,
      # The user asking for the full table on a period that does not need one. A bare presence
      # check, not a boolean cast: the link either carries the parameter or it does not, and
      # `expand=0` is not a shape anything on this screen produces.
      expanded: params[:expand].present?
    )
  end

  # What the committer writes. `overrides` go on the PROPOSAL (amendment A) — the committer has
  # no override path of its own to disagree with this one.
  def proposal_for(account)
    AllocationCalculator.new(
      user: current_user, account: account, today: Date.current, overrides: override_params
    )
  end

  # The edits the user typed into the waterfall, exactly as AllocationCommitter consumes them:
  # `{pool_id => amount}`, keyed by pool id because a row's position is not stable across a
  # re-derived proposal. Nothing is written here and nothing is cast here — AllocationCalculator
  # owns the coercion, and a second `.to_d` on this side is a second answer to "what did they
  # mean by an empty box".
  #
  # Two guards. `overrides=1` arrives as a String and has no #permit!; `overrides[x][]=1` arrives
  # as an Array, which #to_d does not answer to — either one is a 500 on a GET anyone can link to.
  # Values that are not strings are dropped rather than rescued, so the row simply keeps its
  # proposed figure.
  #
  # THE FIRST OF THOSE WAS PRODUCED BY THIS APP'S OWN UI, not by a hand-built URL, and that is
  # worth knowing before anyone relaxes it. The month scrubber re-emitted every query parameter as
  # `hidden_field key, value: value`, which writes a hash's #to_s into one scalar box — so
  # clicking a month arrow mid-edit submitted `overrides=<inspected hash>` and this guard was the
  # only thing standing between that and a 500. The scrubber now drops non-scalar params
  # deliberately (see shared/_date_selector), and the guard stays, because a hidden field
  # somewhere else is one line away from re-creating the shape.
  #
  # `permit!` is safe precisely because the keys are pool ids and nothing here mass-assigns:
  # every key is looked up against THIS account's own rows (AllocationCalculator#fill, which
  # rejects on the ENVELOPE'S ask before an override is consulted), so an id belonging to
  # someone else names no row and is ignored.
  def override_params
    raw = params[:overrides]
    return {} unless raw.is_a?(ActionController::Parameters)

    raw.permit!.to_h.select { |_pool_id, amount| amount.is_a?(String) }
  end

  # OWNERSHIP LIVES HERE, FOR BOTH ACTIONS. Amendment E: #new only renders another user's
  # balances, while #create would WRITE movements out of their account — so the write path is
  # scoped through exactly the same lookup rather than through one of its own. A second scope
  # here would be a second answer to "whose account is this", and the two would disagree on the
  # one request where it matters.
  #
  # AllocationCalculator takes a `user` and an `account` and never checks
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

  # THE USER'S MAIN ACCOUNT — main-account spec §6, fix round 2 (I6). §4 makes main the only
  # account income legally lands in via a category, so "the account the pay landed in" and "the
  # account the user has nominated as main" are the SAME question now, for anyone who has
  # nominated one; ranking every account by how much income reached it inside this period cannot
  # disagree with that answer, because none of them can legally hold income main didn't also
  # carry a movement out of. Consulting `current_user.default_account` is therefore no longer "a
  # second rule in front of" the income-ranking one — it IS the rule, and the ranking below
  # survives only as `#fallback_account_by_income`.
  def default_account
    current_user.default_account || fallback_account_by_income
  end

  # THE FALLBACK, FOR THE ONE USER THIS RULE CANNOT ANSWER FOR: someone with no main account
  # named at all. `users.default_account_id` is nullable and nothing in this app currently
  # creates one outside `BankAccountsController#create`'s first-account rule, so a user who
  # predates that guard (or reaches this screen some other way) can still be in that state, and
  # this screen has to open on SOMETHING rather than 500.
  #
  # `[priority, name]` alone opened the demo user's screen on Ally Savings, an account holding
  # one envelope, while the paycheck sat in Checking; ranking by income within the period is what
  # used to be this whole method before main became mandatory reading, and it is kept verbatim as
  # the fallback rather than simplified, because a user with no main account is exactly the user
  # for whom "which account did the pay land in" is still the only question this app can ask.
  #
  # `by_priority` is the tie-break, not the rule, and `-index` keeps it: `max_by` gives no
  # guarantee about which of several maxima it returns, so two accounts with no income at all —
  # a brand-new user, and every user before their first paycheck of the period — would otherwise
  # open on whichever one Ruby happened to compare last.
  def fallback_account_by_income
    period = current_user.period_datetimes_containing(Date.current)
    ranked = current_user.pools.accounts.by_priority.to_a

    ranked.each_with_index.max_by do |account, index|
      [account.calculator.income_within(period), -index]
    end&.first
  end
end
