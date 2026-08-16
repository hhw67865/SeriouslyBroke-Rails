# frozen_string_literal: true

# Moving money between two envelopes in one account — spec §5's reallocation.
class PoolMovementsController < ApplicationController
  # OWNERSHIP, ONCE, FOR BOTH ACTIONS. #new only renders another user's balances; #create would
  # WRITE a movement out of their envelope — so the two are scoped through the same lookup rather
  # than through one each, which is the shape that lets them disagree on the request where it
  # matters. Amendment B: a stranger's pool can be neither end.
  #
  # A redirect rather than a 404, and the difference is that both of these ids arrive in LINKS —
  # Task 8 puts them in Home's fix buttons — so a stale one is an ordinary thing to hold, not an
  # attack. The message is the same whether the pool never existed or belongs to somebody else,
  # which is the only answer that does not confirm the difference.
  before_action :require_own_pools

  # GET /pool_movements/new
  #
  # The proposal and its damage. Writes nothing.
  def new
    @presenter = presenter
  end

  # POST /pool_movements
  #
  # THE MOVE. One row, so one `save` IS the whole transaction: there is no second write for a
  # failure to leave half-done, and wrapping a single INSERT in an explicit transaction would be
  # ceremony rather than a guard. A refusal writes nothing and says why, because the validations
  # that refuse it run before the INSERT.
  #
  # `context: :reallocation` is what adds spec §5's same-account rule to the model's own
  # validations. `kind` is left alone: `transfer` is the column default, and that is exactly what
  # keeps this row invisible to `PoolMovement.distributed` when a period is redistributed.
  def create
    @presenter = presenter
    movement = @presenter.movement
    return redirect_to(root_path, notice: confirmation_for(movement)) if movement.save(context: :reallocation)

    @errors = movement.errors.full_messages
    render :new, status: :unprocessable_content
  end

  private

  def presenter
    ReallocationPresenter.new(
      user: current_user,
      to_pool: pool_from(:to_pool_id),
      from_pool: pool_from(:from_pool_id),
      amount: params[:amount],
      today: Date.current
    )
  end

  # BUILT AFTER THE WRITE, and that is the whole reason these two figures can be trusted:
  # PoolCalculator memoises and is stale-after-write by construction, so the presenter's own
  # calculators have been answering from before the save since the moment it landed. These are
  # fresh, so the sentence and the screen the user lands on cannot disagree.
  def confirmation_for(movement)
    helpers.reallocation_confirmation(
      movement,
      source_balance: movement.from_pool.calculator.balance,
      destination_balance: movement.to_pool.calculator.balance
    )
  end

  # Scoped through `current_user.pools`, so an id that is not theirs is indistinguishable from an
  # id that does not exist — which is correct, since neither is a resource this user has.
  def pool_from(key) = params[key].presence && current_user.pools.find_by(id: params[key])

  def require_own_pools
    return if [:to_pool_id, :from_pool_id].all? { |key| params[key].blank? || pool_from(key) }

    redirect_to root_path, alert: "We couldn't find that envelope."
  end
end
