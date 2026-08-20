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
  def fund(account)
    PoolMovement.transaction do
      account.lock!
      movement = build_movement(account)
      if account_already_funded?(account)
        movement.errors.add(:to_pool, "already has a balance — an account can only be funded once")
      else
        movement.save
      end
      movement
    end
  end

  # THE SAME QUESTION THE CARD'S OWN RENDER GATE ASKS (home/_account.html.erb): an account with
  # a pool inside it or a nonzero buffer has already moved past the onboarding state this door is
  # for. Asked again here, inside the lock, because the view's answer is a snapshot from before
  # this request and cannot be trusted to still be true.
  def account_already_funded?(account)
    account.child_pools.exists? || !account.calculator(today: Date.current).balance.zero?
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
