# frozen_string_literal: true

# MOVING MONEY BY HAND ON THE PURPOSE LEDGER — spec §5's reallocation, re-anchored: a move is
# `category → category` or `available ↔ category` (two-ledger spec §2, §3).
#
# THE RENAME OF `PoolMovementsController`, which is DELETED (Task 6) along with
# `PoolReallocationPresenter`, `PoolMovementsHelper` and `app/views/pool_movements/`. It outlived
# this controller by one task only because Home's fix buttons were its last links, and Home's rows
# were pools.
class AllocationsController < ApplicationController
  # OWNERSHIP, ONCE, FOR BOTH ACTIONS. #new only renders another user's figures; #create would WRITE
  # a row out of their category — so the two are scoped through the same lookup rather than through
  # one each, which is the shape that lets them disagree on the request where it matters.
  #
  # A redirect rather than a 404, and the difference is that both of these ids arrive in LINKS, so a
  # stale one is an ordinary thing to hold rather than an attack. The message is the same whether the
  # category never existed or belongs to somebody else, which is the only answer that does not
  # confirm the difference.
  before_action :require_own_categories

  # GET /allocations/new
  #
  # The proposal and its damage. Writes nothing.
  def new
    @presenter = presenter
  end

  # POST /allocations
  #
  # THE MOVE. TWO WRITES AND ONE ACT since the final fix wave (I-1) — the row, and the `funded_since`
  # stamp on a destination that was not holding money yet — which is `BudgetProposal`'s shape for
  # `BudgetProposal`'s reason. See #commit.
  #
  # `context: :reallocation` CARRIES ONE VALIDATOR NOW, WHERE THE POOL ERA'S CARRIED TWO. The
  # same-account rule died with the concept — nothing crosses anything on the purpose ledger — and
  # `Allocation#source_must_hold_it` survives it: a disabled radio is a rendering, and a hand-edited
  # `from_category_id` or a tab submitted after the source was spent down must be refused at the
  # write. `kind` is left alone: `transfer` is the column default, and that is exactly what keeps
  # this row invisible to `Allocation.distributed` when a period is redistributed.
  def create
    @presenter = presenter
    return refuse(missing_side_errors) if missing_side_errors.any?

    allocation = @presenter.allocation
    return redirect_to(root_path, notice: confirmation_for(allocation)) if commit(allocation)

    refuse(allocation.errors.full_messages)
  end

  private

  # ** ALLOCATING INTO A CATEGORY STARTS IT HOLDING (§4, final fix wave I-1). ** The spec's own
  # sentence is "the date it first got a rule OR AN ALLOCATION", and only the rule half was ever
  # written. The screen cannot reach the other half — the destination select is built from holders —
  # but `#party_from` resolves against `current_user.categories`, not against holders, so a crafted
  # POST (or a stale tab, or the next screen that widens the picker) wrote money INTO a category with
  # a NULL `funded_since`: money in a category that every reader in the app calls empty, with no
  # screen offering to move it back out. Stamped rather than refused, because the spec says an
  # allocation is one of the two things that make a category start holding — refusing it would be a
  # different rule from the one §4 states.
  #
  # THE DESTINATION ONLY. A move OUT of a category does not make it start holding — §4's "got" is
  # arriving money — and a non-holder cannot be a source anyway: `Allocation#source_must_hold_it`
  # refuses one that does not hold the amount, and the pair of guards in this wave is what keeps a
  # non-holder's balance at zero.
  #
  # ONE TRANSACTION OVER THE TWO, and `requires_new: true` for `BudgetProposal#save`'s own reason: a
  # nested `transaction` opens no savepoint by default, so `Rollback` would be swallowed and the
  # outer transaction would commit the half it did write. The dangerous half-state here is the
  # MIRROR of that class's — a row of money in a category whose clock never started — and it is the
  # very state this method exists to prevent, so it must not be reachable through a failed stamp
  # either.
  #
  # THE ROW IS WRITTEN FIRST so a refused move never touches the category: `save(context:
  # :reallocation)` is where affordability and ownership are decided, and a stamp landing ahead of it
  # would be a visible change (the category enters the fill order) on a request that moved nothing.
  def commit(allocation)
    written = false

    ActiveRecord::Base.transaction(requires_new: true) do
      written = allocation.save(context: :reallocation) && start_holding(allocation).present?
      raise ActiveRecord::Rollback unless written
    end

    written
  end

  # `Category#start_holding` — the app's ONE spelling of the stamp, shared with `BudgetProposal`. The
  # root has no clock to start, which is what the first arm is: `to_category` is NULL for a move back
  # to AVAILABLE (§2), and AVAILABLE holds money for no rule and has no `funded_since` of its own.
  #
  # ANSWERS THE RECORD IT WROTE RATHER THAN A BOOLEAN, on `BudgetProposal#write_all`'s rule: a caller
  # reading `&&` must not be able to mistake "there was nothing to do" for "it worked". The
  # root's arm hands back the allocation, which is the thing that was written on that path.
  #
  # The refusal is carried onto the allocation, the record this controller renders errors from, in
  # `BudgetProposal#carry_errors`' words: the failing attribute belongs to the category, and
  # `allocation.errors[:funded_since]` would name a field this form does not have.
  def start_holding(allocation)
    category = allocation.to_category
    return allocation if category.nil?
    return category if category.start_holding

    category.errors.full_messages.each { |message| allocation.errors.add(:base, "Envelope: #{message}") }
    nil
  end

  # A MISSING SIDE IS NOT THE ROOT, AND THIS IS THE ONLY PLACE THAT DIFFERENCE CAN BE ENFORCED.
  # `ReallocationPresenter` carries `nil` for "the user has not chosen yet" and `ROOT` for AVAILABLE;
  # `Allocation` cannot tell them apart, because both are the same NULL column (two-ledger spec §2).
  # So a POST carrying a source and no destination wrote a real `category → available` withdrawal —
  # MEASURED: `from_category_id=<Cushion>&amount=300` with no `to_category_id` saved the row and
  # reported "Moved $300.00 from Cushion to Available", money the user never asked to move, out of
  # the envelope they had just selected. The other direction is the same shape with the ends swapped.
  #
  # THE `"available"` STRING IS THE ONLY WAY TO NAME THE ROOT, which is what makes the refusal safe
  # rather than a restriction: it is a value the select and the radio both submit, so every move a
  # user can actually make on the screen names both of its ends explicitly.
  #
  # ABOVE THE MODEL RATHER THAN IN IT, because the model is right: a NULL side IS available, and a
  # validation refusing one would refuse every sweep the committer writes.
  def missing_side_errors
    @missing_side_errors ||= [
      [@presenter.to_category, "Envelope can't be blank"],
      [@presenter.from_category, "Source can't be blank"]
    ].filter_map { |side, message| message if side.nil? }
  end

  def refuse(errors)
    @errors = errors
    render :new, status: :unprocessable_content
  end

  def presenter
    ReallocationPresenter.new(
      user: current_user,
      to_category: party_from(:to_category_id),
      from_category: party_from(:from_category_id),
      amount: params[:amount],
      today: current_user.today
    )
  end

  # BUILT AFTER THE WRITE, and that is the whole reason these two figures can be trusted:
  # `CategoryLedger` and `HoldingCalculator` both memoise and are stale-after-write by construction,
  # so the presenter's own readers have been answering from before the save since the moment it
  # landed. These are fresh, so the sentence and the screen the user lands on cannot disagree.
  def confirmation_for(allocation)
    ledger = CategoryLedger.new(current_user.categories.expenses.to_a, user: current_user)

    helpers.allocation_confirmation(
      allocation,
      source_balance: balance_of(allocation.from_category, ledger),
      destination_balance: balance_of(allocation.to_category, ledger)
    )
  end

  # A NULL SIDE IS AVAILABLE (§2), so the figure to read back for it is the root's rather than a
  # category's. One ledger answers for both, which is what keeps the two halves of the sentence
  # describing one moment.
  def balance_of(category, ledger)
    category.nil? ? ledger.available : ledger.holding_of(category)
  end

  # `"available"` IS THE ROOT and it is not a uuid, so it can never collide with a category id. Any
  # other value is looked up through `current_user.categories`, so an id that is not theirs is
  # indistinguishable from an id that does not exist — which is correct, since neither is a resource
  # this user has.
  def party_from(key)
    raw = params[key]
    return nil if raw.blank?
    return ReallocationPresenter::ROOT if raw == ReallocationPresenter::ROOT.id

    current_user.categories.find_by(id: raw)
  end

  def require_own_categories
    return if [:to_category_id, :from_category_id].all? { |key| params[key].blank? || party_from(key) }

    redirect_to root_path, alert: "We couldn't find that envelope."
  end
end
