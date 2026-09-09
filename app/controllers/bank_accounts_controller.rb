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
  # GET /bank_accounts/1/edit
  #
  # THE POOL EDIT SCREEN'S ACCOUNT ARM, FOLDED IN (two-ledger spec §5, Task 7). `pools/edit` was
  # one form for three kinds of pool — a type picker, a containing-account select, a target, a
  # priority and a start date — and two of the three kinds are CATEGORIES now. What an account
  # still has is a NAME, and that is the whole form:
  #
  #   * `target-amount` — an account's target was the "buffer marker", a health line the
  #     distribution screen printed as ` · you wanted $2,000.00`. Two-ledger §2 gives accounts no
  #     target semantics at all (the buffer is AVAILABLE, on the other ledger), the plan's T8 drops
  #     the column, and Task 7 deleted the last reader (`DistributionPresenter#buffer_target`).
  #   * `pool_type` and `account` — an account is an account and sits inside nothing.
  #   * `priority` and `start_date` — the fill order and the start-date rule both moved onto the
  #     category (`categories.priority`, `categories.funded_since`), where the categories form
  #     edits them.
  def edit
    @bank_account = scoped_account
  end

  # POST /bank_accounts
  #
  # ** THE ADD ROW CARRIES A BALANCE NOW (account-openings spec §3). ** "+ Add an account" asks for a
  # name and what is in it, in one row, because those are one act for the user — and the balance is
  # NOT a column on `pools`: it is handed straight to `AccountOpening`, which writes the same opening
  # record the card's other rows write. A blank balance is legal and leaves the account awaiting its
  # own row, which is how a user who does not know the figure yet gets past this line.
  def create
    pool = Pool.new(user: current_user, pool_type: :account, name: bank_account_params[:name])
    opening = opening_for(pool)

    if add(pool, opening)
      redirect_to root_path, notice: "#{pool.name} added."
    else
      refuse(pool, opening)
    end
  end

  # PATCH /bank_accounts/1
  def update
    @bank_account = scoped_account

    # `name:` ALONE, NOT THE WHOLE OF `#bank_account_params`: that hash now also carries the add
    # row's `balance`, which is not a column on this record and is not this form's business.
    if @bank_account.update(name: bank_account_params[:name])
      redirect_to root_path, notice: "#{@bank_account.name} updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /bank_accounts/1
  #
  # THE POOL ERA'S THREE REFUSALS ARE GONE (Task 8). `Pool` used to halt its own destroy on
  # `restrict_with_error` over `#child_pools` and `#categories`, and on
  # `#return_holdings_to_the_account`'s two — all three about a layer that no longer exists: nothing
  # nests inside an account and no category points at one.
  #
  # ** ONE REFUSAL REPLACED THEM (final fix wave, C-1): MAIN. ** `Pool#main_account_is_not_deletable`
  # halts the chain with a sentence on `:base`, because main is on one side of every AccountMovement
  # the app writes — deleting it cascades over the whole physical ledger and zeroes `pot + Σ accounts`
  # while the purpose ledger stands, which is two-ledger §2's invariant broken by a button. Home
  # renders no Delete on main's card, and this is the half of the pair a crafted DELETE meets.
  #
  # WHAT DELETING ANY OTHER ACCOUNT DOES: `dependent: :destroy` on `#movements_in` / `#movements_out`
  # takes its transfers with it, and main is on the other side of every one of them, so the money main
  # had moved into it goes back to the pot and `pot + Σ accounts` is unchanged to the penny. There is
  # nothing to strand, which is why there is nothing else left to refuse.
  #
  # THE RETURN VALUE IS CHECKED, and it is now load-bearing rather than defensive. `destroy` answers
  # false for a halted chain or a foreign key the database refuses, and a screen that redirected with
  # "deleted." over a row still sitting in the table would be lying about the one thing the button is
  # for.
  def destroy
    account = scoped_account
    pot_before = AccountLedger.new(current_user).pot

    if account.destroy
      redirect_to root_path, notice: deletion_notice(account, pot_before)
    else
      redirect_to root_path, alert: account.errors[:base].to_sentence
    end
  end

  private

  # ** WHAT HAPPENED TO THE MONEY, MEASURED RATHER THAN ASSERTED (fix round round 2 — item 4). **
  # Deleting an account does two different things to two different kinds of money, and only one of
  # them comes back:
  #
  #   MONEY THE USER REALLY TRANSFERRED HERE returns to main — `dependent: :destroy` takes the
  #   movements and main was on the other end of every one of them, so the pot RISES by what they
  #   moved.
  #   WHATEVER THE ACCOUNT WAS OPENED WITH leaves the ledger with its opening entry (`Pool has_one
  #   :opening_entry`). That money was never main's: the opening's entry and its transfer cancel on
  #   main exactly, which is what made saving an account self-contained in the first place.
  #
  # So an account funded entirely by its own opening returns NOTHING and the pot does not move,
  # while one fed by real transfers returns all of it. A flash that promised "$500 is back in
  # checking" either way would be false half the time — so the figure is the pot's own difference,
  # and the clause is only printed when there is something to print.
  def deletion_notice(account, pot_before)
    returned = (AccountLedger.new(current_user).pot - pot_before).round(2)
    return "#{account.name} deleted." unless returned.positive?

    "#{account.name} deleted — #{helpers.number_to_currency(returned)} is back in checking."
  end

  # `current_user.pools.accounts`, NOT `current_user.pools`. A stranger's id is a 404 through the
  # ownership scope, as everywhere; the `.accounts` half is what keeps this controller's promise
  # that it is about bank accounts — the route no longer has a sibling that edits any other kind
  # of pool, so a non-account id arriving here is a URL nothing in the app produces.
  def scoped_account = current_user.pools.accounts.find(params[:id])

  # ONE TRANSACTION FOR THE PAIR, so a refused balance leaves no half-added account behind: the
  # account and what it holds arrived in one submission, and they land or fail together.
  #
  # `break false` for a refused NAME rather than a rollback, because nothing was written to undo; the
  # rollback is for the other order — an account that saved and an opening that would not.
  def add(pool, opening)
    Pool.transaction do
      break false unless pool.save

      # The FIRST account a user creates is their main account (spec §2) — the place income lands and
      # displaced history reads against. Later accounts never steal the role; changing main is a
      # deliberate future affordance, not a side effect of adding a bank. It is set BEFORE the
      # opening is written, because a non-main opening needs a main to transfer out of.
      current_user.update!(default_account: pool) if current_user.default_account.blank?

      next true if opening.blank? || opening.save

      raise ActiveRecord::Rollback
    end
  end

  # Same shape as BudgetPageController#update, the other inline form on a presenter-heavy screen:
  # re-render the page at 422 — nothing was written — with the rejected record as the form object, so
  # the field keeps its input and the error prints beside it. The presenter re-queries every figure,
  # so the unsaved pool leaks into none of them.
  #
  # THE ROLLED-BACK ACCOUNT IS UNPERSISTED AGAIN BY HAND. `raise ActiveRecord::Rollback` undoes the
  # INSERT but leaves the in-memory record believing it has an id, and a form built on it would post
  # to `PATCH /bank_accounts/:a-row-that-does-not-exist`.
  #
  # `@new_account_balance` is the add row's own half of "keep what was typed": the figure has no
  # record to ride back on, since the opening was never written and the account it named is gone.
  def refuse(pool, opening)
    assign_home_state
    flash.now[:alert] = opening.errors.full_messages.to_sentence if opening&.errors&.any?
    @new_bank_account = pool.persisted? ? Pool.new(user: current_user, pool_type: :account, name: pool.name) : pool
    @new_account_balance = bank_account_params[:balance]
    render "home/index", status: :unprocessable_content
  end

  # A BLANK BALANCE IS NOT AN OPENING OF ZERO. "I don't know yet" and "it holds nothing" are
  # different answers, and only the second one is a record: an account added with the field left
  # empty keeps its row in the "Your accounts" card until the user says.
  def opening_for(pool)
    balance = bank_account_params[:balance]
    return if balance.blank?

    AccountOpening.new(current_user, pool, balance: balance)
  end

  # `balance` IS PERMITTED BUT IS NOT A COLUMN — `#create` hands it to `AccountOpening` and passes
  # only `name` to the record. `#update` (the rename form) never sees one.
  def bank_account_params
    params.expect(bank_account: [:name, :balance])
  end
end
