# frozen_string_literal: true

# MOVING MONEY BY HAND ON THE PURPOSE LEDGER — spec §5's reallocation, re-anchored: a move is
# `category → category` or `available ↔ category` (two-ledger spec §2, §3).
#
# THE RENAME OF `PoolMovementsController`. That controller is still standing for the one screen Home
# still links to — Home's rows are pools until Task 6 — and it goes with `PoolReallocationPresenter`
# in the same commit.
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
  # THE MOVE. One row, so one `save` IS the whole transaction: there is no second write for a failure
  # to leave half-done, and wrapping a single INSERT in an explicit transaction would be ceremony
  # rather than a guard. A refusal writes nothing and says why, because the validations that refuse it
  # run before the INSERT.
  #
  # `context: :reallocation` CARRIES ONE VALIDATOR NOW, WHERE THE POOL ERA'S CARRIED TWO. The
  # same-account rule died with the concept — nothing crosses anything on the purpose ledger — and
  # `Allocation#source_must_hold_it` survives it: a disabled radio is a rendering, and a hand-edited
  # `from_category_id` or a tab submitted after the source was spent down must be refused at the
  # write. `kind` is left alone: `transfer` is the column default, and that is exactly what keeps
  # this row invisible to `Allocation.distributed` when a period is redistributed.
  def create
    @presenter = presenter
    allocation = @presenter.allocation
    return redirect_to(root_path, notice: confirmation_for(allocation)) if allocation.save(context: :reallocation)

    @errors = allocation.errors.full_messages
    render :new, status: :unprocessable_content
  end

  private

  def presenter
    ReallocationPresenter.new(
      user: current_user,
      to_category: party_from(:to_category_id),
      from_category: party_from(:from_category_id),
      amount: params[:amount],
      today: Date.current
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
