# frozen_string_literal: true

require "rails_helper"

# THE HERO CARD — Home's first two answers and its third (answers-first spec §§2-3): how much is in
# checking, how much of that is FREE, and where we are in the period. It replaces the standing band,
# and this file is `spec/system/home/standing_spec.rb`'s successor.
#
# ── CARRIED FROM standing_spec.rb, because they are still true of the card that replaced it:
#
#   * "names the period beside the standing sentence"      → "draws the period as a bar"
#   * "shows no period range before a period is declared"   → unchanged in substance
#   * "names an overdrawn account beside the figures that exclude it" → split in two: the POT's own
#     overdraft is the red "In Checking" figure (§2) and stays here; the NON-MAIN half moved on to
#     the trouble strip in Task 2, with its copy verbatim (see the marker below).
#   * all six sacrifice-link examples were carried here by Task 1 and MOVED ON in Task 2, to the
#     strip that did not exist when Task 1 ran. See the marker at the foot of this file.
#
# Nine carried titles in all; Task 2 took seven of them onward to `trouble_spec.rb`, leaving the two
# period-bar ones and the card's own figures.
#
# EVERY COPY ASSERTION IN THIS FILE GOES THROUGH A DATA HOOK — `[data-in-checking]`,
# `[data-free-to-spend]`, `[data-free-subline]`, `[data-checking-overdrawn]`, `[data-period-range]`,
# `[data-period-progress]`, `[data-overdrawn-account]`. The hooks exist to be asserted through, and
# a file that names half of them and matches the other half on page text leaves the unasserted ones
# looking load-bearing when nothing holds them. Page-wide `have_content` survives only where the
# assertion is deliberately about the WHOLE page rather than the card.
#
# ── DELETED WITH THE STANDING BAND (answers-first spec §2: "this REPLACES the old 'You're covered /
# Nothing is set aside yet' branch question entirely"). Every one of these asserted a branch that no
# longer exists — the card is the same card in every state:
#
#   * "says you're covered when the money is there" — the headline is gone. Its figures survive
#     here as the mid-period budgeter's: $1,000 in, $400 asked for, $600 free.
#   * "states the gap when you're short" — "$250.00 short this period" over "You need … You have …"
#     is the system talking about itself. The same fixture is now "-$250.00 free" with the honest
#     sentence, in "is honest when the plan asks for more than there is".
#   * "does not call a deficit unclaimed money on a covered period" — the MED-1 fixture. The reader
#     it was about (`projected_buffer`) is deleted; "unclaimed" is a dead word (spec §3). The
#     fixture is carried into "is honest when spending has drained the root", which asserts the
#     same $100 the same way round.
#   * "still states what is left over on a covered period in the black" — the other direction of the
#     same branch, and the same "$600.00 unclaimed" figure. Carried as free money, once.
#   * "explains the arithmetic when available itself is in the red" — `[data-available-in-the-red]`
#     and its whole paragraph are gone with the word "available", which Home no longer says (§3).
#     Its fixture (in $100, spent $500 unbudgeted, a $400 rule) is carried into the negative-free
#     example so the state is still measured; only the machinery sentence dies.
RSpec.describe "Home Hero", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  # `checking` FIRST, so it is the account the `:account` trait makes default — every category the
  # helpers below mint would otherwise pull the factory's own account into being and claim the
  # nomination, leaving `checking` a second account nothing points at.
  before do
    checking
    sign_in user, scope: :user
  end

  # A CATEGORY THAT HOLDS MONEY, filled at a rate every period (two-ledger spec §3).
  def envelope(name, amount, priority: 1)
    category = create(
      :category,
      :expense,
      user: user,
      name: name,
      priority: priority,
      funded_since: Date.current - 1.year
    )
    create(:budget, :per_period_rate, category: category, amount: amount)
    category
  end

  # INCOME RAISES BOTH LEDGERS AT ONCE (§2): the pot, and available. It lands in main, which is the
  # only account income may land in.
  def deposit(amount)
    category = create(:category, :income, user: user)
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  # SPENDING THAT DRAINS AVAILABLE: an expense category that has never been funded holds nothing, so
  # its receipts come out of the root (§4's start-date rule). It lowers the pot either way.
  def spend_unbudgeted(amount)
    category = create(:category, :expense, user: user, name: "Unbudgeted")
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  # ── THE TWO FIGURES ────────────────────────────────────────────────────────────────────────────

  # THE MID-PERIOD BUDGETER (spec §9). $1,000 in the bank, $400 the rules still ask for, $600 free —
  # and the subline says where the difference went in the user's own words. The three figures are
  # planted rather than derived so a card that stopped subtracting would fail rather than agree with
  # itself.
  it "answers what is in checking and what of it is free", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(1_000)

    visit root_path

    expect(page).to have_css("[data-in-checking]", text: "$1,000.00")
    expect(page).to have_css("[data-free-to-spend]", text: "$600.00")
    expect(page).to have_css("[data-free-subline]", text: "the rest is set aside or spoken for")
    # THE WORDS THIS CARD NO LONGER SAYS (spec §3), asserted rather than assumed: the band it
    # replaced printed all three. STILL SCOPED TO THE CARD after Task 2, and for a NEW reason: the
    # bands that printed "available now" are gone (`this_period_spec.rb` asserts the section says
    # none of the machinery words), but the trouble strip's fix button names AVAILABLE as a SOURCE
    # ("Take $300.00 from Available") — which is `ReallocationPresenter::Root#name`, the mechanic's
    # term on the screen that button opens, and deliberately not Home describing the user's money.
    # "You're covered" is asserted absent in the drained-root example below, where it is the
    # headline that was actually wrong — not repeated here, which would only cost this example a
    # line without measuring a second thing.
    within("[data-hero]") do
      # CASE-INSENSITIVE: `have_no_content("available")` is a substring match, so it passes over a
      # card printing "Available" — which is the app's own spelling of the word
      # (`ReallocationPresenter::Root#name`) and therefore the spelling that could slip in.
      expect(page).to have_no_content(/available/i)
      expect(page).to have_no_content(/unclaimed/i)
    end
  end

  # THE CAP AT THE POT, WHICH IS RULED (spec §3): money you would have to move out of another
  # account before you could spend it is not free in the moment. THE SAME FIXTURE with $700 walked
  # over to Ally — the purpose ledger has not moved at all, so a card that had dropped the `min`
  # would still read $600 and this is the example that catches it.
  it "caps free at the pot and says where the rest is", :aggregate_failures do
    ally = create(:pool, :account, user: user, name: "Ally")
    envelope("Groceries", 400)
    deposit(1_000)
    create(:account_movement, from_pool: checking, to_pool: ally, amount: 700, date: Date.current, kind: :transfer)

    visit root_path

    expect(page).to have_css("[data-in-checking]", text: "$300.00")
    expect(page).to have_css("[data-free-to-spend]", text: "$300.00")
    expect(page).to have_css("[data-free-subline]", text: "more is parked in other accounts")
  end

  # The other direction on the subline, so the gate cannot be satisfied by a card that simply always
  # prints it: with every dollar in checking there is no other account for anything to be parked in.
  it "says nothing about other accounts when the money is all in checking" do
    envelope("Groceries", 400)
    deposit(1_000)

    visit root_path

    expect(page).to have_no_css("[data-free-subline]", text: "more is parked in other accounts")
  end

  # ── THE NEGATIVE STATES, WHICH ARE THE SAME CARD (spec §2) ─────────────────────────────────────

  # THE FIXTURE THAT KILLED "You're covered" — $250 more asked for than exists. The old band called
  # this "$250.00 short this period"; the card says the same thing in the user's words and never
  # clamps the figure to zero.
  it "is honest when the plan asks for more than there is", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(150)

    visit root_path

    expect(page).to have_css("[data-free-to-spend]", text: "-$250.00")
    expect(page).to have_css("[data-free-to-spend].text-status-danger")
    expect(page).to have_css("[data-free-subline]", text: "More is set aside or spoken for than you have")
    expect(page).to have_no_css("[data-free-subline]", text: "sitting outside checking")
  end

  # ** THE REVIEWER'S MEASURED FIXTURE (fix round 1 — MED-1), AND THE OTHER KIND OF NEGATIVE. **
  # $1,000 of income, $1,200 walked over to Ally, and NOT ONE RULE. The pot is -$200 so free is
  # -$200, and every word the card used to say about that was false: "More is set aside or spoken
  # for than you have" ($0 is set aside, $0 is spoken for) and "nothing is free until money comes
  # in" (a transfer away from $1,000). Nothing about this user's budget is wrong; their money is in
  # the wrong account.
  #
  # BOTH SENTENCES ARE ASSERTED ABSENT as well as the right one present, because the failure this
  # example exists for was a card printing a TRUE-sounding sentence, not a missing one.
  it "says the money is elsewhere rather than gone when the pot is what capped free", :aggregate_failures do
    ally = create(:pool, :account, user: user, name: "Ally")
    deposit(1_000)
    create(:account_movement, from_pool: checking, to_pool: ally, amount: 1_200, date: Date.current, kind: :transfer)

    visit root_path

    expect(page).to have_css("[data-in-checking].text-status-danger", text: "-$200.00")
    expect(page).to have_css("[data-free-to-spend]", text: "-$200.00")
    expect(page).to have_css("[data-free-subline]", text: "sitting outside checking")
    expect(page).to have_no_css("[data-free-subline]", text: "More is set aside or spoken for than you have")
    # The overdraft line states the fact and stops: the clause that used to follow it ("nothing is
    # free until money comes in") is what this user's transfer disproves.
    expect(page).to have_css("[data-checking-overdrawn]", text: "Your checking account is already spent past zero.")
    expect(page).to have_no_css("[data-checking-overdrawn]", text: "until money comes in")
  end

  # ** THE STATE THE OLD BAND GOT WRONG (fix round 1 — MED-1). ** No rules at all, so nothing is
  # short and the band said "You're covered this period" over "-$100.00 is still unclaimed after
  # this period" — a deficit called unclaimed money. There is no branch left to get wrong: the card
  # renders the same three lines and the free figure is simply -$100.00.
  it "is honest when spending has drained the root", :aggregate_failures do
    spend_unbudgeted(100)

    visit root_path

    expect(page).to have_css("[data-free-to-spend]", text: "-$100.00")
    within("[data-hero]") do
      expect(page).to have_no_content(/unclaimed/i)
      expect(page).to have_no_content("You're covered")
    end
  end

  # A PHYSICAL OVERDRAFT (spec §2): the "In Checking" figure itself goes red, with one plain
  # sentence. It takes SPENDING to reach — money a category has claimed has not left the bank.
  #
  # THE OTHER DIRECTION OF THE MED-1 PAIR: an overdrawn pot where the money really is gone. Nothing
  # was moved anywhere, so there is no other account for the "sitting outside checking" sentence to
  # be about, and the card must say the plain thing instead.
  it "turns the checking figure red when the account is overdrawn", :aggregate_failures do
    groceries = envelope("Groceries", 400)
    create(:entry, item: create(:item, category: groceries), amount: 400, date: Date.current)

    visit root_path

    expect(page).to have_css("[data-in-checking].text-status-danger", text: "-$400.00")
    expect(page).to have_css("[data-checking-overdrawn]", text: "already spent past zero")
    expect(page).to have_css("[data-free-subline]", text: "More is set aside or spoken for than you have")
    expect(page).to have_no_css("[data-free-subline]", text: "sitting outside checking")
  end

  # ── MOVED TO THE TROUBLE STRIP (answers-first Task 2): "names a non-main account that has gone
  # below zero". It is spec §5's "physical overdraft" trigger, and Task 1 only kept it here because
  # the strip did not exist yet. Its copy is verbatim in `trouble_spec.rb`, which also pins the other
  # direction — main's own overdraft staying on THIS card and not being repeated there.

  # ── THE PERIOD AS A BAR (spec §2) ──────────────────────────────────────────────────────────────

  # CARRIED FROM "names the period beside the standing sentence". `travel_to` wraps only the visit —
  # HomeController reads `Date.current` at request time — and every date is a planted literal, never
  # a lazy `Date.current` resolved inside the travelled block (CLAUDE.md's third flake cause).
  #
  # Aug 14 – Aug 27 is fourteen days; Aug 20 is day 7 of it, so seven remain.
  it "draws the period as a bar with the days that are left", :aggregate_failures do
    user.update!(period_cadence: :biweekly, period_anchor_date: Date.new(2026, 8, 14))
    envelope("Groceries", 400)
    deposit(1_000)

    travel_to(Date.new(2026, 8, 20)) { visit root_path }

    expect(page).to have_css("[data-period-range]", text: "Aug 14")
    expect(page).to have_css("[data-period-range]", text: "Aug 27")
    expect(page).to have_content("7 days left")
    expect(page).to have_css("[data-period-progress='50']")
  end

  # The singular, because "1 days left" is the kind of thing a reader stops trusting a screen over.
  it "says one day rather than 1 days on the closing eve" do
    user.update!(period_cadence: :biweekly, period_anchor_date: Date.new(2026, 8, 14))
    deposit(1_000)

    travel_to(Date.new(2026, 8, 26)) { visit root_path }

    expect(page).to have_content("1 day left")
  end

  # CARRIED UNCHANGED: no declared period, no invented bar. `User#period_containing` falls back to
  # the calendar month, which is right for a normaliser and a lie on a card that would print a
  # boundary nobody set.
  it "shows no period bar before a period is declared", :aggregate_failures do
    user.update!(period_cadence: nil, period_anchor_date: nil)
    envelope("Groceries", 400)
    deposit(1_000)

    visit root_path

    expect(page).to have_no_css("[data-period-range]")
    expect(page).to have_no_css("[data-period-progress]")
    # The rest of the card is unconditional, and this is where that matters most: a user who has
    # declared nothing still gets both answers.
    expect(page).to have_css("[data-free-to-spend]")
  end

  # ── THE NARROW BREAKPOINT ──────────────────────────────────────────────────────────────────────

  # THE CARD AT 375px (spec §9: "hero and bars at 375px").
  #
  # ** NO `evaluate_script`, AND THAT IS A DIAGNOSIS RATHER THAN A STYLE CHOICE. ** This example was
  # first written as three `have_css`es and a JS `scrollWidth <= clientWidth` check, and it failed
  # intermittently with `InvalidSessionIdError: session deleted as the browser has closed the
  # connection`, raised out of Capybara's own `reset_sessions!` with ZERO assertion failures — on
  # this example and no other in the file, which passed around it as its own control.
  #
  # FIVE MEASUREMENTS, EACH ON A QUIET MACHINE (`pgrep -f "[r]spec"`), AND THE FIRST THREE WERE
  # WRONG DIAGNOSES. The narrowing looked guilty because it was the new thing: `resize_to` +
  # `maximize` failed 3 of 3; `resize_to` + `resize_to(1400, 1400)` failed 1 of 2 (killing "maximize
  # is the problem"); `resize_to` with no restore failed 2 of 3 (killing "the restore is the
  # problem"); a purpose-built 375-wide DRIVER, never resized at all, failed 3 of 5 (killing "the
  # resize is the problem"). The measurement that located it was removing the narrowing ENTIRELY and
  # keeping the body — still 3 of 5. The window was never involved. A trailing `evaluate_script`
  # leaves the session in a state Capybara's teardown navigation does not survive here, which is
  # CLAUDE.md's first cause wearing a different last statement than `click_*`. Without it: 5 of 5.
  #
  # WHAT REPLACES IT IS A BETTER ASSERTION ANYWAY. `scrollWidth <= clientWidth` is a fact about the
  # document; what this example is about is the CARD, and Selenium's own geometry says it directly
  # and without running a line of JS: the hero's right edge inside the viewport, and the free figure
  # — the widest thing on it — inside the hero. Both figures being merely "visible" would be
  # satisfied by a card that had pushed the page sideways, which is exactly what a label-and-amount
  # row does when it cannot wrap.
  describe "on a narrow screen" do
    # A TRUE 375px LAYOUT VIEWPORT, AND CDP IS THE ONLY WAY TO GET ONE. Chrome refuses to make a
    # headless window narrower than 500px — `--window-size=375,667` and
    # `resize_to(375, 667)` alike report `width=500`, measured — so every window-based spelling of
    # this test is really a 500px test wearing a 375 label. `Emulation.setDeviceMetricsOverride`
    # sets the LAYOUT viewport instead of the window, which is what CSS media queries read, so this
    # is the width the spec asked for rather than the nearest width Chrome would allow.
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride", width: 375, height: 667, deviceScaleFactor: 1, mobile: false
      )
    end

    it "fits the card and its figures inside a 375px viewport", :aggregate_failures do
      envelope("Groceries", 400)
      deposit(1_000)

      visit root_path

      expect(page).to have_css("[data-in-checking]", text: "$1,000.00")
      expect(page).to have_css("[data-free-to-spend]", text: "$600.00")
      expect(page).to have_css("[data-period-progress]")

      hero = page.find("[data-hero]").native.rect
      figure = page.find("[data-free-to-spend]").native.rect

      expect(hero.x + hero.width).to be <= 375
      expect(figure.x + figure.width).to be <= hero.x + hero.width
    end
  end

  # ── §9'S PERMANENT BUTTON MOVED TO THE TROUBLE STRIP (answers-first Task 2), and all six of its
  # examples went with it: "shows the structural warning only when rules exceed typical income",
  # "hides the structural warning when the budget fits", "opens the sacrifice view when followed",
  # "keeps the button up on a period whose cash is comfortable", "shows no structural warning before
  # an income is declared" and "shows no structural warning before a period is declared".
  #
  # Task 1 parked the button here because §5's trigger list did not name it and there was no strip to
  # put it on. There is one now, and a strip that renders ONLY when something is true is the right
  # home for a verdict that is only shown when it is true — it is the one kind of trouble no
  # reallocation can fix, which is exactly why §9 asked for it. See `trouble_spec.rb`.
end
