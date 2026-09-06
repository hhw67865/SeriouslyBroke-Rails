# frozen_string_literal: true

# ** SAYING WHAT AN ACCOUNT HOLDS (account-openings spec §3). ** One door, two verbs, and the same
# act behind both: `create` is the "Your accounts" card's row for an account that has not answered
# yet, `update` is the **Edit balance** row on a finished account's card. The spec calls the second
# one a correction and the model calls it a rewrite of the first — see `AccountOpening`, which is
# where the whole of the arithmetic lives. Nothing here computes anything.
#
# NESTED UNDER THE ACCOUNT, AND SINGULAR, because that is exactly the shape of the thing: an account
# has ONE opening record (`pools.opened_on` plus at most one entry), so there is no id to name and no
# collection to index. The account in the path is scoped through `current_user.pools.accounts`, so a
# stranger's id is a 404 the way it is at every other door in this app.
#
# INHERITS HomeController, NOT ApplicationController, for the reason `BankAccountsController` states:
# the failure path re-renders `home/index`, whose bare partial renders resolve against the rendering
# controller's view prefixes. This action IS a Home-screen door.
class AccountOpeningsController < HomeController
  # POST /bank_accounts/:bank_account_id/opening
  def create = save_opening

  # PATCH /bank_accounts/:bank_account_id/opening
  def update = save_opening

  private

  def save_opening
    account = scoped_account
    opening = AccountOpening.new(current_user, account, balance: opening_params[:balance])
    return refuse(opening) unless opening.save

    redirect_to root_path, notice: "#{account.name} holds #{helpers.number_to_currency(opening.balance)}."
  end

  # The same shape as `BankAccountsController`'s own 422 branch: re-render the page — nothing was
  # written — with the refused object threaded back through `HomePresenter#rejected_opening_for`, so
  # the typed figure and the sentence that refused it survive beside the row they belong to.
  def refuse(opening)
    assign_home_state(rejected_opening: opening)
    flash.now[:alert] = opening.errors.full_messages.to_sentence
    render "home/index", status: :unprocessable_content
  end

  def scoped_account = current_user.pools.accounts.find(params[:bank_account_id])

  def opening_params = params.expect(account_opening: [:balance])
end
