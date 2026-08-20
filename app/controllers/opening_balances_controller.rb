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
# ONE-TIME BY CONSTRUCTION: `Category.opening_balance`'s own existence IS the latch (see
# Category::OPENING_BALANCE_NAME) — nothing has to remember that onboarding ran, and a second
# attempt is refused before anything is computed.
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
    actual = BigDecimal(opening_balance_params[:actual], exception: false)
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
  def record_correction(main, actual)
    Category.transaction do
      main.lock!
      presenter = HomePresenter.new(user: current_user, today: Date.current)
      next { alert: "Opening balance was already recorded." } unless presenter.awaiting_opening_balance?(main)

      difference = actual - PoolCalculator.new(main).balance
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
