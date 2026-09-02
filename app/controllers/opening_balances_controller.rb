# frozen_string_literal: true

# ONBOARDING STEP 3 (main-account spec §5): the one-time correction that sets MAIN to its real
# bank number. After every other account has been given its real balance (step 2), main is wrong
# by exactly the untracked history — years of income and spending this app never saw. The fix is
# ONE ordinary entry, in an auto-created "Opening Balance" category, for the difference between
# what the user types and what the app currently shows.
#
# THE SIGN TRAVELS VIA THE CATEGORY'S TYPE, NOT A SIGNED AMOUNT: entries validate `amount >
# 0` (Entry), so a raise (main was too low) has to be recorded as income and a lowering (main
# was too high) as an expense — the difference's magnitude is the entry, its sign is which
# category it landed in.
#
# ONE-TIME BY CONSTRUCTION, AND DELIBERATELY REOPENABLE: `Category.opening_balance`'s own
# existence IS the latch (see `Category::OPENING_BALANCE_NAME`) — nothing has to remember that
# onboarding ran, and a second attempt is refused before anything is computed. Renaming or
# deleting that category reopens the door, and that is ACCEPTED rather than guarded against: it
# is the user's own escape hatch for a mistyped figure (there is no `destroy` action here), and
# closing it would mean building one. See `Category::OPENING_BALANCE_NAME`'s own comment for the
# same ruling stated where the latch is defined.
#
# INHERITS HomeController, NOT ApplicationController, for the same reason as its two onboarding
# siblings (BankAccountsController, AccountFundingsController): this door lives on Home.
class OpeningBalancesController < HomeController
  # POST /opening_balance
  def create
    main = current_user.default_account
    if main.blank?
      redirect_to root_path, alert: "Add a main account before recording its opening balance."
      return
    end

    # `exception: false`: a blank submit, a comma-formatted figure ("1,000") or any other
    # unparsable string returns nil instead of raising ArgumentError. HTML5 `type="number"`
    # cannot be trusted alone — `config.browser_validations` is off app-wide, and a bare `POST`
    # bypasses the browser entirely — so the server has to survive input a form would normally
    # have blocked.
    #
    # `.round(2)` ON THE PARSED FIGURE, IMMEDIATELY: money has no sub-cent unit anywhere else in
    # this app, and leaving a figure like `0.001` unrounded lets it survive the zero-difference
    # check below (it is not exactly zero) and reach `Entry#amount`'s `decimal` column, whose
    # scale rounds it DOWN TO ZERO on write — failing `greater_than: 0` inside the transaction as
    # an unhandled `RecordInvalid`. Rounding here first means the comparison and the write agree:
    # a sub-cent `actual` against a zero balance takes the zero-difference redirect instead.
    actual = BigDecimal(opening_balance_params[:actual], exception: false)&.round(2)
    if actual.nil?
      redirect_to root_path, alert: "Enter a real balance to record."
      return
    end

    redirect_to root_path, **record_correction(main, actual)
  end

  private

  # LOCKED, the same idiom `AccountFundingsController#fund` uses for the same reason: two submits
  # for the same user — a double-click, a resubmit before the redirect lands — cannot both read
  # "not yet recorded" and both write. The latch is re-asked INSIDE the lock, through a FRESH
  # `HomePresenter` — `#awaiting_opening_balance?`, the SAME predicate the card's own render gate
  # asks — rather than trusted from whatever the page looked like when it rendered.
  #
  # DELIBERATELY UNPINNED BY A SPEC: what the lock guards is a race between two requests reading
  # the latch at the same instant, which is not a shape a single-threaded request spec can
  # produce — `spec/requests/opening_balances_spec.rb`'s "refuses a second correction" example
  # posts twice SEQUENTIALLY and pins the latch itself, not the lock. A genuine regression test
  # here needs two real threads racing one transaction, which is disproportionate machinery for
  # the one line it would be checking; `AccountFundingsController#fund`'s own lock carries the
  # same gap for the same reason.
  def record_correction(main, actual)
    Category.transaction do
      main.lock!
      presenter = HomePresenter.new(user: current_user, today: Date.current)
      next { alert: "Opening balance was already recorded." } unless presenter.awaiting_opening_balance?(main)

      # THE POT (two-ledger spec §2, Task 6) — `AccountLedger#pot`, which is main's balance and is
      # therefore what the bank says about it.
      #
      # IT WAS `Pool#total`, "unallocated cash plus every pool inside it", and that reader existed
      # for a hazard this model does not have: money an envelope inside main was holding had not
      # LEFT the bank account, so a bare buffer undercounted main whenever an envelope held
      # anything — a user who read $1,200 off their statement while $150 of it sat in a Groceries
      # envelope would have typed the true figure and watched the app "correct" main to $1,050.
      # Nothing is housed inside an account now (a category holds its own money and lives nowhere),
      # so the family total and the balance are the same figure, and `AccountLedger` is the one
      # reader of it. `Pool#total` is envelope-era and dies in Task 8.
      difference = actual - AccountLedger.new(current_user).pot
      # A ZERO DIFFERENCE LEAVES THE LATCH OPEN, BY CHOICE (main-account spec §5, fix round 1 —
      # MED-2/LOW-2/MED-3 doc ruling). Nothing is written here — no category, no item, no entry —
      # so `Category.opening_balance` still answers false afterward and the card renders again on
      # the next Home load. This is deliberate, not an oversight: the latch is the CATEGORY's
      # existence, and writing a category to close a door with nothing behind it would be the
      # empty-category defect `#write_correction`'s own comment warns against, applied to the
      # zero case specifically. A user who types the exact figure the app already shows is free to
      # submit again later if that ever stops being true — the door was never meant to shut on a
      # correction that corrected nothing.
      next { notice: "Main already matches your real balance — nothing to record." } if difference.zero?

      write_correction(main, difference)
      { notice: "Main set to your real bank balance." }
    end
  end

  # The category, its one item and the one entry that carries the correction either all land or
  # none do — a category with no entry behind it would sit on Home forever with no balance to
  # show for it, and the latch would already be shut. Runs inside #record_correction's own
  # transaction rather than opening a second one.
  #
  # `tracked: false`: this entry is bookkeeping, not a fact about this period's income or
  # spending. `categories.tracked` defaults to true, and the dashboard's tracked-income and
  # tracked-expense totals both sum by it (`Dashboard::IncomePresenter#total_tracked_income` and
  # its expense twin) — a $1,000 raise recorded today would otherwise inflate THIS period's
  # figures by years of history the app never saw, on the one screen whose whole job is showing
  # what actually happened this period.
  def write_correction(main, difference)
    category = current_user.categories.create!(
      name: Category::OPENING_BALANCE_NAME,
      category_type: difference.positive? ? :income : :expense,
      pool: main,
      tracked: false
    )
    item = category.items.create!(name: "Initial balance")
    item.entries.create!(amount: difference.abs, date: correction_date)
  end

  # THE DAY BEFORE THE USER'S EARLIEST ENTRY (Henry's ruling of 2026-08-20, from real use), and
  # `Date.current` only for the user who has no entries at all.
  #
  # `tracked: false` WAS NOT ENOUGH, AND THE REASON IS THAT IT ANSWERS A DIFFERENT SCREEN. The flag
  # keeps the correction out of the DASHBOARD's tracked-income and tracked-expense totals, which is
  # what #write_correction's own note is about and is still true. The DISTRIBUTE screen reads
  # something else entirely: `DistributionPresenter#income_this_period_from` is
  # `PoolCalculator#income_within`, which sums income entries in the account BY DATE and does not
  # look at `categories.tracked` at all. So a correction stamped today — years of untracked history
  # — arrived on the one screen whose job is "what came in this period, split it" as money to
  # split. Real pollution, not cosmetics: it changes the figure the user distributes from.
  #
  # BEFORE ALL HISTORY, so it is inside no period anyone will ever distribute. Not merely "before
  # this period": a user who reads their Distribute screen for an earlier period would find it
  # there instead, which is the same defect one screen back.
  #
  # Σ IS UNTOUCHED BY THE MOVE. The correction lands in MAIN, an account, and an account has no
  # `start_date` gate on the categories pointing at it (that rule is the ENVELOPE's — see
  # `BudgetProposal`), so the entry counts against main from whatever date it carries. The balance
  # examples in spec/requests/opening_balances_spec.rb read the same corrected figure before and
  # after this change, which is what says the date moved and the money did not.
  #
  # `minimum(:date)` OVER `user.entries`, which is `has_many through: :items` through the
  # categories — every entry the user owns, whichever pool it reaches. Asked BEFORE the correction
  # entry is written (the category and item created above carry none yet), so it cannot find its
  # own answer.
  def correction_date
    earliest = current_user.entries.minimum(:date)

    earliest ? earliest.to_date - 1 : Date.current
  end

  def opening_balance_params
    params.expect(opening_balance: [:actual])
  end
end
