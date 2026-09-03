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
#     overdraft is now the red "In Checking" figure (§2), and a non-main account keeps the old strip
#     and its copy verbatim, because "none of the figures above count it" is still exactly true of it.
#   * all five sacrifice-link examples, unchanged. §9's permanent button has no new home in this
#     plan — the trouble strip (spec §5) lists physical overdraft, overdrawn category, overdue bill
#     and an undistributed period, and not this — so it stays on the card that replaced its band.
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
    expect(page).to have_content("the rest is set aside or spoken for")
    # THE WORDS THIS CARD NO LONGER SAYS (spec §3), asserted rather than assumed: the band it
    # replaced printed all three. SCOPED TO THE CARD, deliberately — the categories band below it
    # still prints "available now" and the attention band still branches on covered, and both are
    # Task 2's to sweep. A page-wide assertion here would fail for a reason that is not this task's
    # and would go green later for a reason that is not this card's.
    # "You're covered" is asserted absent in the drained-root example below, where it is the
    # headline that was actually wrong — not repeated here, which would only cost this example a
    # line without measuring a second thing.
    within("[data-hero]") do
      expect(page).to have_no_content("available")
      expect(page).to have_no_content("unclaimed")
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
    expect(page).to have_content("more is parked in other accounts")
  end

  # The other direction on the subline, so the gate cannot be satisfied by a card that simply always
  # prints it: with every dollar in checking there is no other account for anything to be parked in.
  it "says nothing about other accounts when the money is all in checking" do
    envelope("Groceries", 400)
    deposit(1_000)

    visit root_path

    expect(page).to have_no_content("more is parked in other accounts")
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
    expect(page).to have_content("More is set aside or spoken for than you have")
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
      expect(page).to have_no_content("unclaimed")
      expect(page).to have_no_content("You're covered")
    end
  end

  # A PHYSICAL OVERDRAFT (spec §2): the "In Checking" figure itself goes red, with one plain
  # sentence. It takes SPENDING to reach — money a category has claimed has not left the bank.
  it "turns the checking figure red when the account is overdrawn", :aggregate_failures do
    groceries = envelope("Groceries", 400)
    create(:entry, item: create(:item, category: groceries), amount: 400, date: Date.current)

    visit root_path

    expect(page).to have_css("[data-in-checking].text-status-danger", text: "-$400.00")
    expect(page).to have_content("already spent past zero")
  end

  # CARRIED FROM standing_spec's overdrawn-account example, on the half of it that survives whole: a
  # NON-MAIN account's overdraft is excluded from every figure on this card, so the old strip and
  # its copy are still exactly true and still needed.
  it "names a non-main account that has gone below zero", :aggregate_failures do
    ally = create(:pool, :account, user: user, name: "Ally")
    deposit(1_000)
    create(:account_movement, from_pool: ally, to_pool: checking, amount: 200, date: Date.current, kind: :transfer)

    visit root_path

    expect(page).to have_css("[data-overdrawn-account='Ally']", text: "Ally is overdrawn $200.00")
    expect(page).to have_content("none of the figures above count it")
    # The pot is fine — $1,000 of income plus the $200 that walked in — so the figure it is beside
    # must not have turned red as well.
    expect(page).to have_no_css("[data-in-checking].text-status-danger")
  end

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

  # ── §9'S PERMANENT BUTTON, CARRIED WHOLE ───────────────────────────────────────────────────────

  # The href is asserted, not just the label: a button that says the budget does not fit and goes
  # nowhere is the state this replaced, and it looked identical.
  it "shows the structural warning only when rules exceed typical income", :aggregate_failures do
    envelope("Rent", 3_000)

    visit root_path

    expect(page).to have_link("Your budget doesn't fit your income", href: sacrifice_path)
    expect(page).to have_css("[data-sacrifice-link]")
  end

  it "hides the structural warning when the budget fits", :aggregate_failures do
    envelope("Groceries", 400)

    visit root_path

    expect(page).to have_no_link("Your budget doesn't fit your income")
    expect(page).to have_no_css("[data-sacrifice-link]")
  end

  # THE BUTTON AND THE ROUTE ARE THE SAME CONDITION READ TWICE. Home shows it on
  # `structurally_underwater?` and /sacrifice refuses on the same test, so a button that rendered
  # where the route refuses would open a redirect straight back. Followed rather than merely
  # asserted, because only following it can tell the two apart.
  it "opens the sacrifice view when followed", :aggregate_failures do
    envelope("Rent", 3_000)

    visit root_path
    click_link "Your budget doesn't fit your income"

    expect(page).to have_current_path(sacrifice_path)
    expect(page).to have_content("$600.00 underwater every period")
  end

  # THE CARD AND THE BUTTON ANSWER DIFFERENT QUESTIONS, which is why §9 asks for the button to be
  # permanent. This period's cash is fine — the money is in the account — and the budget still does
  # not fit the income.
  it "keeps the button up on a period whose cash is comfortable", :aggregate_failures do
    envelope("Rent", 3_000)
    deposit(5_000)

    visit root_path

    expect(page).to have_css("[data-free-to-spend]", text: "$2,000.00")
    expect(page).to have_link("Your budget doesn't fit your income", href: sacrifice_path)
  end

  it "shows no structural warning before an income is declared" do
    user.update!(typical_income: nil)
    envelope("Rent", 3_000)

    visit root_path

    expect(page).to have_no_css("[data-sacrifice-link]")
  end

  # INCOME WITHOUT A CADENCE IS REACHABLE — the declaration form offers "Not set" for the period —
  # and `Budget.steady_need` still answers there, against a period the user has not agreed to. The
  # gate is both halves, and this is the half that only fails when one of them is dropped.
  it "shows no structural warning before a period is declared" do
    user.update!(period_cadence: nil, period_anchor_date: nil)
    envelope("Rent", 3_000)

    visit root_path

    expect(page).to have_no_css("[data-sacrifice-link]")
  end
end
