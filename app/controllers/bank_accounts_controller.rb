# frozen_string_literal: true

# WHERE BANK ACCOUNTS ARE BORN (onboarding step 1). Accounts render on Home, so Home is where
# they are created — the Pools page is the savings-goals index and says so in its subtitle.
#
# NAMED `bank_accounts`, NOT `accounts`: `resource :account` (singular) is already the
# user-settings page, so the bare plural would give one word two meanings a click apart. The
# UI already says "bank account" everywhere it explains the type.
#
# `pool_type` is SET HERE, not permitted: the one thing this door creates is an account, and a
# form that could be talked into `pool_type: savings` via a crafted param would skip that pool's
# required target. It must be set in Ruby — `pools.pool_type` DEFAULTS TO 1 (budget), so without
# this line every "bank account" would be an envelope refused by the database's
# `pools_account_matches_pool_type` CHECK. `start_date` needs nothing: the model's
# `set_default_start_date` fills today (in the user's timezone) on every new record.
# INHERITS HomeController, NOT ApplicationController: the failure path re-renders `home/index`,
# whose bare partial renders (`render "standing"`) resolve against the rendering controller's
# view prefixes. Subclassing puts `home/` in that chain — this action IS a Home-screen door,
# and the alternative is qualifying every partial name inside Home's own views for a foreign
# controller's benefit.
class BankAccountsController < HomeController
  # POST /bank_accounts
  def create
    pool = Pool.new(user: current_user, pool_type: :account, **bank_account_params)

    if pool.save
      redirect_to root_path, notice: "#{pool.name} added."
    else
      # Same shape as BudgetPageController#update, the other inline form on a presenter-heavy
      # screen: re-render the page at 422 — nothing was written — with the rejected record as
      # the form object, so the field keeps its input and the error prints beside it. The
      # presenter re-queries every figure, so the unsaved pool leaks into none of them.
      @presenter = HomePresenter.new(user: current_user, today: Date.current)
      @new_bank_account = pool
      render "home/index", status: :unprocessable_content
    end
  end

  private

  def bank_account_params
    params.expect(bank_account: [:name])
  end
end
