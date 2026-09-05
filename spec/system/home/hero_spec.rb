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
# EVERY COPY ASSERTION IN THIS FILE BUT ONE IS SCOPED TO THE CARD — through a data hook
# (`[data-in-checking]`, `[data-free-to-spend]`, `[data-free-subline]`, `[data-checking-overdrawn]`,
# `[data-period-range]`, `[data-period-progress]`, `[data-period-days-left]`,
# `[data-overdrawn-account]`) or inside `within("[data-hero]")` for the ones that assert a word is
# ABSENT, which no hook can carry. The exception is the page-wide dead-words example (FINAL review —
# L-6), which is page-wide on purpose: a word is dead when NOTHING on the screen says it, and every
# other spelling of that rule in this suite is scoped to one region. The hooks exist to be asserted
# through, and a file that names
# half of them and matches the other half on page text leaves the unasserted ones looking
# load-bearing when nothing holds them. `[data-period-days-left]` was added in Task 4 for the
# sharper reason: `_this_period`'s heading prints the SAME "7 days left" sentence, so the page-wide
# spelling of that assertion passed whether or not the card rendered a bar at all.
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
#   * "does not call a deficit money nothing claims on a covered period" — the MED-1 fixture. The reader
#     it was about (`projected_buffer`) is deleted; the word is dead (spec §3). The
#     fixture is carried into "is honest when spending has drained the root", which asserts the
#     same $100 the same way round.
#   * "still states what is left over on a covered period in the black" — the other direction of the
#     same branch, and the same "$600.00 spare" figure. Carried as free money, once.
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
    expect(page).to have_css("[data-free-subline]", text: "$400.00 of checking is claimed by your rules")
    # THE WORDS THIS CARD NO LONGER SAYS, asserted rather than assumed. "Spoken for" and "set aside"
    # JOIN THE LIST IN TASK 3 and they are the whole vocabulary change: both named money that had been
    # MOVED — a distribution's remaining ask, and a holding — and nothing moves. A rule CLAIMS money
    # where it sits.
    within("[data-hero]") do
      # CASE-INSENSITIVE: `have_no_content("available")` is a substring match, so it passes over a
      # card printing "Available" — the app's own spelling of the word — and therefore over exactly
      # the spelling that could slip in.
      expect(page).to have_no_content(/available|unclaimed|buffer|distribut|allocat/i)
      expect(page).to have_no_content(/spoken for|set aside/i)
    end
  end

  # ** THE THREE DEAD WORDS OVER THE WHOLE PAGE (FINAL review — L-6). ** Every other assertion of
  # this rule is scoped — to the card here, to the section in `this_period_spec` — and a word can
  # only be dead if nothing on the screen says it. This is the one page-wide spelling, and it is the
  # reason the header's "every copy assertion in this file is scoped to the card" now says "every
  # assertion but one".
  #
  # THE FIXTURE IS SHAPED TO AVOID THE TWO RULED EXCEPTIONS rather than to dodge a failure, and both
  # are recorded in the spec's §10: the trouble strip's fix button names AVAILABLE as a SOURCE
  # (`ReallocationPresenter::Root#name`, the mechanic's term on the screen it opens), and the
  # post-distribute flash says "stays available" in Distribute's own voice. So this user has money,
  # one rule that is comfortably covered, no fix to offer and no flash — a Home with nothing wrong
  # on it, which is the state the rule is actually about.
  it "says none of the dead words anywhere on Home", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(2_000)

    visit root_path

    expect(page).to have_css("[data-free-to-spend]", text: "$1,600.00")
    [/available/i, /unclaimed/i, /buffer/i].each { |word| expect(page).to have_no_content(word) }
    # "ALLOCATION" JOINED THE PAGE-WIDE LIST IN TASK 3, and it could not have before: the trouble
    # strip's fix buttons linked to `/allocations/new` and named AVAILABLE as their source. There are
    # no fix buttons — a fix was a purpose-side MOVE and there are none (§5) — so the ruled exception
    # this file's header recorded is gone with them.
    expect(page).to have_no_content(/allocat/i)
    # "DISTRIBUTE" IS SCOPED TO THE ANSWERS, NOT PAGE-WIDE, and the scope is honest rather than
    # convenient: the sidebar still carries a Distribute nav item until Task 4 deletes that screen.
    # What Task 3 owns is that none of Home's own three panels says it — the `:undistributed` trouble
    # arm and its button are gone.
    ["[data-hero]", "[data-this-period]"].each do |region|
      within(region) { expect(page).to have_no_content(/distribut/i) }
    end
    expect(page).to have_no_css("[data-trouble]")
  end

  # ** MONEY IN ANOTHER ACCOUNT IS SHOWN, NEVER SUBTRACTED (two-shapes spec §2, Henry's ruling of
  # 2026-09-05). ** THE SAME FIXTURE with $700 walked over to Ally: the claims are untouched, so
  # `free = 300 − 400` = **−$100.00** and the card says both facts in one sentence — what the rules
  # claim, and what sits elsewhere.
  #
  # ** IT READ $300.00, THE WHOLE POT, AND THE CLAIMS WERE INVISIBLE. ** `free` was
  # `min(pot, total_money − Σ claims)`: the $700 in Ally went into the subtraction and the answer was
  # then capped at the pot, so for every user whose other accounts covered their rules the two hero
  # figures were the same number. "Why is free to spend and the number in checking the same when some
  # is claimed?" is the question this example is the answer to.
  it "subtracts the claims from checking and says what sits elsewhere", :aggregate_failures do
    ally = create(:pool, :account, user: user, name: "Ally")
    envelope("Groceries", 400)
    deposit(1_000)
    create(:account_movement, from_pool: checking, to_pool: ally, amount: 700, date: Date.current, kind: :transfer)

    visit root_path

    expect(page).to have_css("[data-in-checking]", text: "$300.00")
    expect(page).to have_css("[data-free-to-spend]", text: "-$100.00")
    expect(page).to have_css("[data-free-subline]", text: "Your rules claim $100.00 more than checking holds")
    expect(page).to have_css("[data-free-subline]", text: "Move some in from your other accounts")
  end

  # ** THE POSITIVE ARM WITH MONEY ELSEWHERE, which is where the second clause is a fact rather than
  # an instruction. ** $2,000 in with $400 walked to Ally and a $400 rule: `free = 1,600 − 400` =
  # $1,200, and the card says "$400.00 of checking is claimed by your rules, and $400.00 sits in 1
  # other account". The COUNT is asserted because the clause names it and a card counting main would
  # say two.
  it "names what is claimed and what sits elsewhere when free is positive", :aggregate_failures do
    ally = create(:pool, :account, user: user, name: "Ally")
    envelope("Groceries", 400)
    deposit(2_000)
    create(:account_movement, from_pool: checking, to_pool: ally, amount: 400, date: Date.current, kind: :transfer)

    visit root_path

    expect(page).to have_css("[data-in-checking]", text: "$1,600.00")
    expect(page).to have_css("[data-free-to-spend]", text: "$1,200.00")
    expect(find("[data-free-subline]")).to have_text("$400.00 of checking is claimed by your rules")
      .and have_text("$400.00 sits in 1 other account")
  end

  # The other direction on the clause, so the gate cannot be satisfied by a card that always prints
  # it: with every dollar in checking there is no other account for anything to sit in.
  it "says nothing about other accounts when the money is all in checking", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(1_000)

    visit root_path

    expect(page).to have_css("[data-free-subline]", text: "$400.00 of checking is claimed by your rules")
    expect(page).to have_no_css("[data-free-subline]", text: "sits in")
  end

  # AN OVERDRAWN SECOND ACCOUNT IS NOT SOMEWHERE MONEY SITS, which is why the gate is the TOTAL's
  # sign: $200 walked IN from an Ally that is now $200 overdrawn is a DEBT the strip names, not a
  # place to transfer from. PLANTED: pot $1,200, nothing claimed, so `free` is $1,200.
  it "does not call an overdrawn second account money that sits elsewhere", :aggregate_failures do
    ally = create(:pool, :account, user: user, name: "Ally")
    deposit(1_000)
    create(:account_movement, from_pool: ally, to_pool: checking, amount: 200, date: Date.current, kind: :transfer)

    visit root_path

    expect(page).to have_css("[data-in-checking]", text: "$1,200.00")
    expect(page).to have_css("[data-free-to-spend]", text: "$1,200.00")
    expect(page).to have_css("[data-free-subline]", text: "$0.00 of checking is claimed by your rules")
    expect(page).to have_no_css("[data-free-subline]", text: "sits in")
  end

  # THE FRESH SIGNUP: money in, no rule anywhere, so `free` IS the pot to the cent and the claimed
  # figure is an honest $0.00. The card used to tell that user "the rest is set aside or spoken for"
  # about a rest of $0.00, then "none of it is claimed"; it states the figure now, which is true
  # whatever it is.
  it "states a claimed figure of nothing rather than describing a rest", :aggregate_failures do
    deposit(1_000)

    visit root_path

    expect(page).to have_css("[data-in-checking]", text: "$1,000.00")
    expect(page).to have_css("[data-free-to-spend]", text: "$1,000.00")
    expect(page).to have_css("[data-free-subline]", text: "$0.00 of checking is claimed by your rules")
  end

  # ── THE NEGATIVE STATES, WHICH ARE THE SAME CARD (spec §2) ─────────────────────────────────────

  # THE FIXTURE THAT KILLED "You're covered", CARRIED AT ITS OWN FIGURES — $250 more claimed than
  # exists. PLANTED: a $400-a-period rate rule with nothing spent claims the whole **$400.00** (§3.1),
  # against $150 in checking, so `free = 150 − 400` = **−$250.00**. The old band called this "$250.00
  # short this period"; the card says the same thing in the user's words and never clamps the figure
  # to zero.
  it "is honest when the claims ask for more than there is", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(150)

    visit root_path

    expect(page).to have_css("[data-free-to-spend]", text: "-$250.00")
    expect(page).to have_css("[data-free-to-spend].text-status-danger")
    expect(page).to have_css("[data-free-subline]", text: "Your rules claim $250.00 more than checking holds")
    expect(page).to have_no_css("[data-free-subline]", text: "Move some in")
    # ** AND IT DOES NOT ALSO SAY THE OVERSPEND'S SENTENCE. ** The pot is a healthy $150; what is
    # wrong is the rules, and "You have spent past what you had" would be a second, false cause.
    expect(page).to have_no_css("[data-free-subline]", text: "You have spent past what you had")
  end

  # ** THE MONEY IS IN THE WRONG ACCOUNT, AND THE CARD SAYS SO AS AN INSTRUCTION. ** $1,000 of
  # income, $1,200 walked over to Ally, and NOT ONE RULE: the pot is −$200 and nothing is claimed, so
  # `free` is −$200 and the second sentence is "Move some in from your other accounts."
  #
  # ** THE OLD CARD NEEDED A THIRD ARM FOR THIS AND THE ARM WAS UNREACHABLE FROM ONE ACCOUNT
  # (two-shapes §2). ** `free = min(pot, total_money − Σ claims)` went below zero here because the
  # CAP bound on a negative pot, and its sentence ("The money nothing claims is sitting outside
  # checking") was gated on an inequality rather than on a predicate about accounts. `free = pot − Σ
  # claims` has one cause per sign, so the arm is `#anything_claimed?` and `#money_parked_elsewhere?`
  # — the accounts line's own sum — and the two fixtures below are the two answers it can give.
  it "tells a user with money elsewhere to move some in", :aggregate_failures do
    ally = create(:pool, :account, user: user, name: "Ally")
    deposit(1_000)
    create(:account_movement, from_pool: checking, to_pool: ally, amount: 1_200, date: Date.current, kind: :transfer)

    visit root_path

    expect(page).to have_css("[data-in-checking].text-status-danger", text: "-$200.00")
    expect(page).to have_css("[data-free-to-spend]", text: "-$200.00")
    expect(page).to have_css("[data-free-subline]", text: "Move some in from your other accounts")
    expect(page).to have_no_css("[data-free-subline]", text: "You have spent past what you had")
    # The overdraft line states the fact and stops: the clause that used to follow it ("nothing is
    # free until money comes in") is what this user's transfer disproves.
    expect(page).to have_css("[data-checking-overdrawn]", text: "Your checking account is already spent past zero.")
    expect(page).to have_no_css("[data-checking-overdrawn]", text: "until money comes in")
  end

  # ** THE SINGLE-ACCOUNT HALF OF THE PAIR ABOVE. ** With nowhere to move money in FROM, the second
  # sentence is the plain one — and "Move some in from your other accounts" must stay off a screen
  # whose accounts line has nothing to send the user to.
  #
  # PLANTED: $1,000 in, $1,100 spent on a funded category carrying NO rule. Nothing is claimed and
  # the pot is `1,000 − 1,100` = **−$100.00**, so `free` is −$100.00.
  it "does not send a single-account user looking for money outside checking", :aggregate_failures do
    groceries = create(:category, :expense, user: user, name: "Groceries", funded_since: Date.current - 1.year)
    deposit(1_000)
    create(:entry, item: create(:item, category: groceries), amount: 1_100, date: Date.current)

    visit root_path

    expect(page).to have_css("[data-in-checking].text-status-danger", text: "-$100.00")
    expect(page).to have_css("[data-free-to-spend]", text: "-$100.00")
    expect(page).to have_css("[data-free-subline]", text: "You have spent past what you had")
    expect(page).to have_no_css("[data-free-subline]", text: "Move some in")
    # THE OTHER HALF OF THE CONTRADICTION was the accounts line, which had nothing in it to send the
    # user to. One account, so the page says "other account" nowhere.
    expect(page).to have_no_content("other account")
  end

  # ** THE STATE THE OLD BAND GOT WRONG (fix round 1 — MED-1). ** No rules at all, so nothing is
  # short and the band said "You're covered this period" over "-$100.00 is still unclaimed after
  # this period" — a deficit called unclaimed money. There is no branch left to get wrong: the card
  # renders the same three lines and the free figure is simply -$100.00.
  #
  # IT IS ALSO THE PURE OVERSPEND: nothing is claimed and the account has simply been spent past zero,
  # so "Your rules claim $X more than checking holds" would name something that does not exist.
  it "is honest when spending has drained the root", :aggregate_failures do
    spend_unbudgeted(100)

    visit root_path

    expect(page).to have_css("[data-free-to-spend]", text: "-$100.00")
    expect(page).to have_css("[data-free-subline]", text: "You have spent past what you had")
    expect(page).to have_no_css("[data-free-subline]", text: "Your rules claim")
    within("[data-hero]") do
      expect(page).to have_no_content("You're covered")
    end
  end

  # A PHYSICAL OVERDRAFT (answers-first §2): the "In Checking" figure itself goes red, with one plain
  # sentence. It takes SPENDING to reach — money a rule has claimed has not left the bank.
  #
  # THE OTHER DIRECTION OF THE PAIR: an overdrawn pot where the money really is gone. Nothing was
  # moved anywhere, so there is no other account for the "move some in" sentence to be about, and the
  # card must say the plain thing instead.
  #
  # PLANTED, AND THE SENTENCE CHANGED WITH THE READER: a $400 rate rule spent flat claims
  # `max(0, 400 − 400)` = **$0.00** (§3.1), so nothing is claimed and the honest arm is the pure
  # overspend's rather than the claims-outrun one's. The old card said "More is set aside or spoken
  # for than you have" about a category holding nothing at all.
  it "turns the checking figure red when the account is overdrawn", :aggregate_failures do
    groceries = envelope("Groceries", 400)
    create(:entry, item: create(:item, category: groceries), amount: 400, date: Date.current)

    visit root_path

    expect(page).to have_css("[data-in-checking].text-status-danger", text: "-$400.00")
    expect(page).to have_css("[data-checking-overdrawn]", text: "already spent past zero")
    expect(page).to have_css("[data-free-subline]", text: "You have spent past what you had")
    expect(page).to have_no_css("[data-free-subline]", text: "Move some in")
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
    expect(page).to have_css("[data-period-days-left]", text: "7 days left")
    expect(page).to have_css("[data-period-progress='50']")
  end

  # The singular, because "1 days left" is the kind of thing a reader stops trusting a screen over.
  it "says one day rather than 1 days on the closing eve" do
    user.update!(period_cadence: :biweekly, period_anchor_date: Date.new(2026, 8, 14))
    deposit(1_000)

    travel_to(Date.new(2026, 8, 26)) { visit root_path }

    expect(page).to have_css("[data-period-days-left]", text: "1 day left")
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
