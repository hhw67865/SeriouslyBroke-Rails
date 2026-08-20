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

      # THE FAMILY TOTAL, NOT MAIN'S BARE BUFFER (main-account spec §5, fix round 1 — MED-4). A
      # bank statement for a physical account counts every dollar sitting in it, and money an
      # envelope inside main is holding has not LEFT the bank account — it is still main's money,
      # earmarked. `PoolCalculator.new(main).balance` answers only the unallocated remainder,
      # which undercounts main whenever an envelope inside it holds anything: a user who read
      # $1,200 off their bank statement while $150 of it sat in a Groceries envelope inside that
      # same account would have typed the true figure and watched the app "correct" main to
      # $1,050, silently losing the $150 from Σ pools. `Pool#total` is the existing reader for
      # exactly this question — "what the bank actually says: unallocated cash plus every pool
      # inside it" — already used by the distributions screen for the same account-level figure,
      # so this reuses it rather than re-deriving a second reader of the same rule.
      #
      # IDENTICAL TO THE BARE BALANCE WHEN MAIN HOLDS NO POOLS (`Pool#total`'s own spec pins this),
      # which is why every example that predates this ruling still holds: none of them plants an
      # envelope inside main, so `main.total == main.calculator.current_balance` on every one of
      # them and nothing about their assertions moves.
      difference = actual - main.total
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
    item.entries.create!(amount: difference.abs, date: Date.current)
  end

  def opening_balance_params
    params.expect(opening_balance: [:actual])
  end
end
