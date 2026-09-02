# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home Standing", type: :system do
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
    create(:budget, :per_period_rate, pool: nil, category: category, amount: amount)
    category
  end

  # INCOME RAISES BOTH LEDGERS AT ONCE (§2): the pot, and available. It lands in main, which is the
  # only account income may land in.
  #
  # `into:` IS DELETED (Task 6) with the question it answered. Money used to be fundable only from
  # the account it was sitting in, so "deposit into Ally" was a fixture that changed what the
  # waterfall could reach; an allocation crosses nothing (§2), so where the cash physically sits has
  # no bearing on available at all.
  def deposit(amount)
    category = create(:category, :income, user: user, pool: checking)
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  # SPENDING THAT DRAINS AVAILABLE: an expense category that has never been funded holds nothing, so
  # its receipts come out of the root (§4's start-date rule).
  def spend_unbudgeted(amount)
    category = create(:category, :expense, user: user, name: "Unbudgeted")
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  it "says you're covered when the money is there", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(1_000)

    visit root_path

    expect(page).to have_css("h2", text: "You're covered")
    expect(page).to have_content("$600.00 is still unclaimed after this period")
    expect(page).to have_no_content("short this period")
    expect(page).to have_no_content("overdrawn")
  end

  it "states the gap when you're short", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(150)

    visit root_path

    expect(page).to have_css("h2", text: "$250.00 short")
    expect(page).to have_content("You need $400.00")
    expect(page).to have_content("You have $150.00")
    expect(page).to have_no_content("You're covered")
    # ONE ROOT, so the two figures above subtract to the headline and there is nothing to explain.
    # The only clause that can fire here is the negative-available one, and available is $150.
    expect(page).to have_no_css("[data-available-in-the-red]")
  end

  # ── DELETED (Task 6): four examples on the orphan and stranded-cash clauses.
  #
  #   * "reconciles the figures when a pool no account can fund is part of what you owe"
  #   * "stays silent about a pool with no account that needs nothing this period"
  #   * "keeps the buffer honest when a pool belongs to no account"
  #   * "explains the arithmetic when money is stranded in another account" — the last live one. It
  #     planted $1,000 in Ally against a $400 rule in Checking and pinned "$1,000.00 of that sits in
  #     accounts with nothing left to fund, so it can't close the gap". An allocation crosses no
  #     account (§2), so that money funds Rent in full and there is no gap to explain.
  #
  # THE STANDING BAND HAS ONE RECONCILIATION CLAUSE LEFT and it is new: available below zero. The
  # headline stops at what the categories miss, so a root that has been given out past what came in
  # is the one remaining reason `total_required - available` is not the shortfall.
  it "explains the arithmetic when available itself is in the red", :aggregate_failures do
    envelope("Rent", 400)
    deposit(100)
    spend_unbudgeted(500)

    visit root_path

    expect(page).to have_css("h2", text: "$400.00 short")
    expect(page).to have_content("You need $400.00")
    expect(page).to have_content("You have -$400.00")
    expect(page).to have_css("[data-available-in-the-red]", text: "more has been spent or claimed than came in")
  end

  # An overdraft is excluded from both headline figures by design, so the band has to name
  # it or a user $400 down reads "You're covered" and nothing else.
  # IT TAKES SPENDING TO REACH IT NOW, not an allocation: money a category has claimed has not left
  # the bank, so the pot only moves when an entry does.
  it "names an overdrawn account beside the figures that exclude it", :aggregate_failures do
    groceries = envelope("Groceries", 400)
    create(:entry, item: create(:item, category: groceries), amount: 400, date: Date.current)

    visit root_path

    expect(page).to have_content("Checking is overdrawn $400.00")
    expect(page).to have_content("none of the figures above count it")
  end

  # §9'S PERMANENT BUTTON, and it is live rather than a dead link now that /sacrifice exists.
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
  # where the route refuses would open a redirect straight back — which is exactly what a second,
  # divergent comparison here would produce. Followed rather than merely asserted, because only
  # following it can tell the two apart.
  it "opens the sacrifice view when followed", :aggregate_failures do
    envelope("Rent", 3_000)

    visit root_path
    click_link "Your budget doesn't fit your income"

    expect(page).to have_current_path(sacrifice_path)
    expect(page).to have_content("$600.00 underwater every period")
  end

  # THE HEADLINE AND THE BUTTON ANSWER DIFFERENT QUESTIONS, which is why §9 asks for the button to
  # be permanent rather than gated on the shortfall. This period's cash is fine — the money is in
  # the account — and the budget still does not fit the income. Both on one screen, because a
  # reader who saw only the first would think nothing was wrong.
  it "keeps the button up on a period whose cash is covered", :aggregate_failures do
    envelope("Rent", 3_000)
    deposit(5_000)

    visit root_path

    expect(page).to have_css("h2", text: "You're covered")
    expect(page).to have_link("Your budget doesn't fit your income", href: sacrifice_path)
  end

  # TASK 6 (main-account plan): which period the whole band is talking about. `travel_to` wraps
  # only the visit — the same discipline `spec/system/pools/show/connected_categories_spec.rb`
  # documents — because HomeController reads `Date.current` at request time and the range has to
  # be asked about a date genuinely inside the declared period, not whatever day the suite happens
  # to run on. `Date.new(2026, 8, 20)` is a planted literal, never a lazy `Date.current` resolved
  # inside the travelled block.
  it "names the period beside the standing sentence", :aggregate_failures do
    user.update!(period_cadence: :biweekly, period_anchor_date: Date.new(2026, 8, 14))
    envelope("Groceries", 400)
    deposit(1_000)

    travel_to(Date.new(2026, 8, 20)) { visit root_path }

    expect(page).to have_css("[data-period-range]", text: "Aug 14 – Aug 27")
  end

  # THE OTHER DIRECTION: no declared period, no invented range. Same gate
  # `structurally_underwater?` already trusts (`period_cadence`/`period_anchor_date` both blank),
  # asked here about a different band on the same screen.
  it "shows no period range before a period is declared" do
    user.update!(period_cadence: nil, period_anchor_date: nil)
    envelope("Groceries", 400)
    deposit(1_000)

    visit root_path

    expect(page).to have_no_css("[data-period-range]")
  end

  # An undeclared user has made no comparison, so there is no verdict to render — and the button
  # must not appear on a rules-need figure with no income to measure it against.
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
