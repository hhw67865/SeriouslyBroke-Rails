# frozen_string_literal: true

# ONBOARDING STEP 2 (main-account spec §5): give a fresh account its real balance, as the
# ONE movement from main that mirrors the transfers that really happened over the years.
# A movement, not an entry: this money is not income — it already existed; it is being told
# where it lives. Inherits HomeController for the same reason BankAccountsController does:
# failure re-renders home/index.
#
# NOT `PoolMovementsController#create`: that action saves on the `:reallocation` context, and
# `PoolMovement#must_not_cross_accounts` runs on exactly that context — it would refuse the
# main → account move this door exists to write. This is a separate door because it is a
# separate legality, not because the two are unrelated.
class AccountFundingsController < HomeController
  # POST /account_fundings
  def create
    account = current_user.pools.pool_type_account.find(funding_params[:account_id])
    movement = fund(account)

    if movement.persisted?
      redirect_to root_path, notice: "#{account.name} funded with #{helpers.number_to_currency(movement.amount)}."
    else
      render_refused(movement)
    end
  end

  private

  # LOCKED, so two submits for the same account — a double-click, a resubmit before the redirect
  # lands — cannot both read "not yet funded" and both write. The second request's own
  # `account.lock!` blocks until the first transaction commits, exactly the idiom
  # Pool.apply_fill_order and AllocationCommitter#call already use for the same reason: a row
  # lock serialises the second writer behind the first rather than letting both act on a balance
  # that was only true for an instant.
  #
  # THE SAME PREDICATE THE CARD'S OWN RENDER GATE ASKS (fix round 2 — MED-1/2/3 in one ruling):
  # `HomePresenter#awaiting_funding?`, not a second spelling of "already funded" invented here —
  # the controller used to ask `child_pools.exists? || balance != 0`, which disagreed with the
  # view's own `pools.empty?` and left an envelope-first account 422ing on a balance that was, in
  # fact, zero. Asked again inside the lock rather than trusted from whatever the view answered
  # before this request, because that answer is a snapshot and this one has to be current.
  #
  # THE ONE CARVE-OUT: funding main FROM itself is refused by `PoolMovement#pools_must_differ`,
  # not by this guard — `awaiting_funding?(main)` is false for the unrelated reason that `main`
  # IS the user's default account, and reporting "already holds money" there would say something
  # false about an account that may hold none. Only a target that genuinely differs from main
  # gets the money-based refusal; main itself is left to the model's own truthful validation.
  def fund(account)
    PoolMovement.transaction do
      account.lock!
      movement = build_movement(account)
      presenter = HomePresenter.new(user: current_user, today: Date.current)

      if !presenter.awaiting_funding?(account) && account != current_user.default_account
        movement.errors.add(:to_pool, "already holds money")
      else
        movement.save
      end
      movement
    end
  end

  def build_movement(account)
    PoolMovement.new(
      from_pool: current_user.default_account,
      to_pool: account,
      amount: funding_params[:amount],
      date: Date.current,
      kind: :transfer
    )
  end

  # Same shape as BankAccountsController's own 422 branch: re-render Home with the rejected
  # record as the form object (HomePresenter#funding_movement_for is how it finds its way back
  # to the one card it belongs to), so the typed amount and the error survive the re-render.
  def render_refused(movement)
    assign_home_state(rejected_movement: movement)
    flash.now[:alert] = movement.errors.full_messages.to_sentence
    render "home/index", status: :unprocessable_content
  end

  def funding_params
    @funding_params ||= params.expect(account_funding: [:account_id, :amount])
  end
end
