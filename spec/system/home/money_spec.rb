# frozen_string_literal: true

require "rails_helper"

# THE MONEY COLUMN — Home's first two answers as three stat tiles (two-shapes spec §3): how much is
# in checking, how much of that is FREE, and what sits outside it. This file is
# `spec/system/home/hero_spec.rb`'s successor, and the rename is the card's: `_hero.html.erb` is
# deleted and `_money.html.erb` is what renders here.
#
# ── CARRIED WHOLE, because they are still true of the tiles that replaced the card. Every figure
# example in `hero_spec` is below at its own figures, with two hooks renamed by the partial:
# `[data-hero]` → `[data-money]` and `[data-free-to-spend]` → `[data-free]`. Not one number moved —
# `free = pot − Σ claims` is Task 1's and this task did not touch it.
#
# ── MOVED TO `runway_spec.rb` (three examples): the period bar. See the marker at its own site for
# why the period left this card.
#
# ── NEW WITH §3: the two-segment claimed bar (`[data-claimed-bar]`, three examples — the fraction,
# the clamp, and the refusal on an overdrawn pot) and the third tile (`[data-other-accounts]`,
# `[data-account-chip]`, both directions).
#
# EVERY COPY ASSERTION IN THIS FILE BUT ONE IS SCOPED TO THE COLUMN — through a data hook
# (`[data-in-checking]`, `[data-free]`, `[data-free-subline]`, `[data-checking-overdrawn]`,
# `[data-claimed-bar]`, `[data-other-accounts]`) or inside `within("[data-money]")` for the ones
# that assert a word is ABSENT, which no hook can carry. The exception is the page-wide dead-words
# example (FINAL review — L-6), which is page-wide on purpose: a word is dead when NOTHING on the
# screen says it, and every other spelling of that rule in this suite is scoped to one region.
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
#   * "does not call a deficit money nothing claims on a covered period" — the MED-1 fixture. The
#     reader it was about (`projected_buffer`) is deleted; the word is dead (spec §3). The fixture is
#     carried into "is honest when spending has drained the root", which asserts the same $100 the
#     same way round.
#   * "still states what is left over on a covered period in the black" — the other direction of the
#     same branch, and the same "$600.00 spare" figure. Carried as free money, once.
#   * "explains the arithmetic when available itself is in the red" — `[data-available-in-the-red]`
#     and its whole paragraph are gone with the word "available", which Home no longer says (§3).
#     Its fixture (in $100, spent $500 unbudgeted, a $400 rule) is carried into the negative-free
#     example so the state is still measured; only the machinery sentence dies.
RSpec.describe "Home Money Column", type: :system do
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

  # MONEY WALKED OUT OF CHECKING INTO A SECOND ACCOUNT — the fixture behind every "sits elsewhere"
  # sentence and the third tile. It lowers the pot and raises nothing the rules can claim, which is
  # exactly the state §2 says is SHOWN and never subtracted.
  def walk_over(name, amount)
    account = create(:pool, :account, user: user, name: name)
    create(
      :account_movement,
      from_pool: checking,
      to_pool: account,
      amount: amount,
      date: Date.current,
      kind: :transfer
    )
    account
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
    expect(page).to have_css("[data-free]", text: "$600.00")
    expect(page).to have_css("[data-free-subline]", text: "$400.00 of checking is claimed by your rules")
    # THE WORDS THIS CARD NO LONGER SAYS, asserted rather than assumed. "Spoken for" and "set aside"
    # JOIN THE LIST IN TASK 3 and they are the whole vocabulary change: both named money that had been
    # MOVED — a distribution's remaining ask, and a holding — and nothing moves. A rule CLAIMS money
    # where it sits.
    within("[data-money]") do
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

    expect(page).to have_css("[data-free]", text: "$1,600.00")
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
    ["[data-money]", "[data-this-period]"].each do |region|
      within(region) { expect(page).to have_no_content(/distribut/i) }
    end
    expect(page).to have_no_css("[data-trouble]")
  end

  # ** THE WHOLE DEAD LIST, OVER ALL FOUR REGIONS, IN ONE EXAMPLE (fix round 1 — LOW-5). ** The two
  # pins above it and `this_period_spec`'s each covered part of the plan's Global Constraints and a
  # different part: between them "goal", "fund", "spoken for" and "allocation" were unasserted on
  # three of the four panels. This walks the list against every region Home owns, on a fixture that
  # renders all four at once — a shortfall makes the strip appear, and the strip is the panel most
  # likely to reach for the retired vocabulary because it is the one giving instructions.
  #
  # PLANTED: $150 in against a $400 rate rule and a $5,000 goal due next year, so `free` is under and
  # the strip renders with its give-way walk; the goal is what would have said "goal" or "fund".
  #
  # ** SCOPED, AND THE SCOPE IS THE POINT FOR "fund". ** "Fund this account" is the ONBOARDING card's
  # own button (main-account spec §5) and is a live, correct sentence about a bank account — a
  # page-wide `/\bfund/i` would fail on it. The four regions are where the RULES are described, and
  # that is where the word is dead. A word boundary as well, so "funded" and "refund" in a category
  # name a user typed are not what this example is about.
  # THE LIST ITSELF, as a method rather than a constant (rubocop's `RSpec/LeakyConstantDeclaration`:
  # a constant declared in an example group leaks into the whole suite). Each entry is a word the
  # plan's Global Constraints retired, in the case-insensitive form the rule needs — a substring
  # match passes over "Available", which is exactly the spelling this app uses.
  def dead_words
    [
      /available/i,
      /unclaimed/i,
      /buffer/i,
      /distribut/i,
      /allocat/i,
      /spoken for/i,
      /set aside/i,
      /builds up/i,
      /\bgoal/i,
      /\bfund\b/i
    ]
  end

  # A GOAL ON THE SCREEN, which is the rule that would have said "goal" or "fund": $5,000 by a day
  # next year, on a category funded a year back.
  def goal(name, target, priority: 2)
    category = create(
      :category,
      :expense,
      user: user,
      name: name,
      priority: priority,
      funded_since: Date.current - 1.year
    )
    create(
      :budget,
      category: category,
      amount: target,
      basis: :monthly,
      interval_months: nil,
      rule_type: :choice,
      anchor_date: Date.current + 300.days
    )
  end

  it "says none of the retired vocabulary in any of Home's four panels", :aggregate_failures do
    deposit(150)
    envelope("Groceries", 400)
    goal("Vacation", 5_000)

    visit root_path

    expect(page).to have_css("[data-trouble]")
    ["[data-money]", "[data-runway]", "[data-this-period]", "[data-trouble]"].each do |region|
      within(region) { dead_words.each { |word| expect(page).to have_no_content(word) } }
    end
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
    expect(page).to have_css("[data-free]", text: "-$100.00")
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
    expect(page).to have_css("[data-free]", text: "$1,200.00")
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
    expect(page).to have_css("[data-free]", text: "$1,200.00")
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
    expect(page).to have_css("[data-free]", text: "$1,000.00")
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

    expect(page).to have_css("[data-free]", text: "-$250.00")
    expect(page).to have_css("[data-free].text-status-danger")
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
    expect(page).to have_css("[data-free]", text: "-$200.00")
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
    expect(page).to have_css("[data-free]", text: "-$100.00")
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

    expect(page).to have_css("[data-free]", text: "-$100.00")
    expect(page).to have_css("[data-free-subline]", text: "You have spent past what you had")
    expect(page).to have_no_css("[data-free-subline]", text: "Your rules claim")
    within("[data-money]") do
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

  # ── ** THE PERIOD BAR AND ITS THREE EXAMPLES MOVED TO `runway_spec.rb` (two-shapes §3). ** The
  # period is the runway's subject now — its ruler, its ticks and its pace line are all drawn on it —
  # and two panels drawing the same fortnight was how "7 days left" came to be printed twice on one
  # screen by two readers that could disagree. All three went with their hooks:
  # "draws the period as a bar with the days that are left" (`[data-period-range]`,
  # `[data-period-progress]`, `[data-period-days-left]`), "says one day rather than 1 days on the
  # closing eve", and "shows no period bar before a period is declared" — which is now the runway's
  # own absence, asserted there against `[data-runway]`.

  # ── THE CLAIMED BAR (§3): THE SUBLINE AS A PICTURE ─────────────────────────────────────────────

  # ** TWO SEGMENTS OF THE POT, AND THE FIGURE IS THE CLAIMED ONE. ** $1,000 in with a $400 rate
  # rule claiming its whole rate is `round(400 ÷ 1,000 × 100)` = **40%** claimed, which is the same
  # subtraction the two figures above it print — a bar that disagreed with them would be a third
  # arithmetic on one card.
  it "draws what is claimed as a fraction of what is in checking", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(1_000)

    visit root_path

    expect(page).to have_css("[data-claimed-bar='40']")
    expect(page).to have_css("[data-claimed-bar] [data-claimed-fill]")
  end

  # ** CLAMPED, NOT RUN OFF THE CARD. ** $150 in against a $400 rule claims more than the whole pot,
  # so the bar is full and RED — the state the figure above it prints as −$250.00. A bar 267% wide
  # would simply leave the tile.
  it "fills the bar red when the rules claim more than checking holds", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(150)

    visit root_path

    expect(page).to have_css("[data-claimed-bar='100']")
    expect(page).to have_css("[data-claimed-fill].bg-status-danger")
  end

  # ** NO POT, NO FRACTION. ** An overdrawn account is not a quantity anything can be a fraction of,
  # and a bar there would have to invent a denominator — the same refusal every other bar on this
  # screen makes. The figures are still both printed, which is the half that must not go with it.
  it "draws no bar at all on an overdrawn account", :aggregate_failures do
    groceries = create(:category, :expense, user: user, name: "Groceries", funded_since: Date.current - 1.year)
    deposit(1_000)
    create(:entry, item: create(:item, category: groceries), amount: 1_100, date: Date.current)

    visit root_path

    expect(page).to have_no_css("[data-claimed-bar]")
    expect(page).to have_css("[data-in-checking]", text: "-$100.00")
    expect(page).to have_css("[data-free]", text: "-$100.00")
  end

  # ── THE THIRD TILE: MONEY THAT IS NOT IN CHECKING (§3) ─────────────────────────────────────────

  # THE FIGURE AND THE NAMES. The subline already says how much sits elsewhere; the tile says WHICH
  # accounts, which the line at the foot of the page could only answer once it was opened.
  it "names the accounts the rest of the money sits in", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(2_000)
    walk_over("Ally", 300)
    walk_over("Vanguard", 100)

    visit root_path

    # CASE-INSENSITIVE, because the tile's label is `uppercase` in CSS and Capybara reads the
    # RENDERED text: the string in the template is "In 2 other accounts" and the string on the
    # screen is "IN 2 OTHER ACCOUNTS". The count is what this line is pinning either way.
    expect(page).to have_css("[data-other-accounts]", text: /in 2 other accounts/i)
    expect(page).to have_css("[data-other-accounts-total]", text: "$400.00")
    expect(page).to have_css("[data-account-chip='Ally']")
    expect(page).to have_css("[data-account-chip='Vanguard']")
  end

  # THE OTHER DIRECTION: one account is no tile at all. "$0.00 in 0 other accounts" would be the app
  # inventing an absence, and the money column would carry a third of its height saying nothing.
  it "leaves the tile off a screen with only one account" do
    envelope("Groceries", 400)
    deposit(1_000)

    visit root_path

    expect(page).to have_no_css("[data-other-accounts]")
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

    # ** THE TILES STACK (§3), which at this width is what "column" means: three tiles one above the
    # other, each as wide as the card. The measurement is the tile's own rect against the one below
    # it — two tiles side by side at 375px would share a top edge, which is exactly the layout a
    # `grid-cols-2` that forgot its breakpoint produces.
    it "stacks the money tiles inside a 375px viewport", :aggregate_failures do
      envelope("Groceries", 400)
      deposit(1_000)
      walk_over("Vanguard", 100)

      visit root_path

      expect(page).to have_css("[data-in-checking]", text: "$900.00")
      expect(page).to have_css("[data-free]", text: "$500.00")

      checking_tile = page.find("[data-in-checking]").native.rect
      others_tile = page.find("[data-other-accounts]").native.rect

      expect(others_tile.y).to be > checking_tile.y
      expect(others_tile.x + others_tile.width).to be <= 375
    end

    it "fits the card and its figures inside a 375px viewport", :aggregate_failures do
      envelope("Groceries", 400)
      deposit(1_000)

      visit root_path

      expect(page).to have_css("[data-in-checking]", text: "$1,000.00")
      expect(page).to have_css("[data-free]", text: "$600.00")

      hero = page.find("[data-money]").native.rect
      figure = page.find("[data-free]").native.rect

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
