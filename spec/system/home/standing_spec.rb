# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home Standing", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before { sign_in user, scope: :user }

  def envelope(name, amount, priority: 1)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    create(:pool_budget, :per_period_rate, pool: pool, amount: amount)
    pool
  end

  # MAIN-ACCOUNT SPEC §6: an income category may only point at the user's main account, so the
  # category here is always Checking's, never `into`'s. The money still ends up in `into` — the
  # entry lands in Checking and a `transfer` PoolMovement carries the same amount on to `into`,
  # exactly the write Task 3's routing feature automates for a real "deposit into another
  # account" choice. Checking's own balance nets to unchanged (income in, movement out); `into`
  # gains exactly what it always gained.
  def deposit(amount, into: checking)
    category = create(:category, :income, user: user, pool: checking)
    entry = create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
    return entry if into == checking

    create(:pool_movement, from_pool: checking, to_pool: into, amount: amount, date: Date.current, source_entry: entry)
    entry
  end

  # A pool attached to no account. Savings pools stay this way until Plan 3's backfill.
  # `#orphan` IS DELETED WITH THE SHAPE IT BUILT (plan 3, task 6): a pool attached to no account,
  # which `Pool#account_matches_pool_type` and `CHECK ((pool_type = 0) = (account_id IS NULL))` now
  # refuse — the second past the model. FIVE examples went with it, named where they stood. The
  # standing band's "of what you need belongs to N pools with no account" clause is KEPT and now
  # fires for nobody; deleting the orphan apparatus is the follow-up this tightening creates, named
  # in `Pool::REFUSALS` and in the task 6 report.

  it "says you're covered when the money is there", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(1_000)

    visit root_path

    expect(page).to have_css("h2", text: "You're covered")
    expect(page).to have_content("$600.00")
    expect(page).to have_no_content("short this period")
    expect(page).to have_no_content("overdrawn")
    # Every pool here has an account, so the covered branch's own orphan clause must not fire.
    expect(page).to have_no_content("of what you need belongs to")
  end

  # DELETED (plan 3, task 6): "names the unfundable part even when you're covered" and "counts
  # only the pools the unfundable figure came from when short". Both planted `#orphan` and both
  # pinned the same care — the clause names a sum and a SIZE side by side, so the two must describe
  # the same set or a reader dividing one by the other gets a figure about a pool asking for
  # nothing. See the note on `#orphan`'s deletion above.

  it "states the gap when you're short", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(150)

    visit root_path

    expect(page).to have_css("h2", text: "$250.00 short")
    expect(page).to have_content("You need $400.00")
    expect(page).to have_content("You have $150.00")
    expect(page).to have_no_content("You're covered")
    # Single account, every pool assigned: shortfall IS total_required - available, and
    # neither explanation may fire on a screen whose figures already reconcile.
    expect(page).to have_no_content("can't close the gap")
    expect(page).to have_no_content("with no account")
  end

  # DELETED (plan 3, task 6), three more on the same fixture:
  #
  #   * "reconciles the figures when a pool no account can fund is part of what you owe" — the
  #     headline arithmetic explained when $600 − $100 implies a $500 gap under a $300 headline.
  #   * "stays silent about a pool with no account that needs nothing this period" — why the clause
  #     is gated on the FIGURE rather than on `orphan_pools.any?`, which printed "$0.00 of what you
  #     need belongs to 1 pool". This one had already gone GREEN-BUT-WRONG when the `:pool` factory
  #     started housing its pools: it asserts an absence, so a housed goal satisfied it too.
  #   * "keeps the buffer honest when a pool belongs to no account" — `available - total_required`
  #     would print "-$400.00 stays in your buffer" at a user whose accounts are in order. (It sat
  #     further down the file, beside the stranded-in-another-account example.)
  #
  # The other reconciliation clause — money stranded in ANOTHER ACCOUNT — is reachable and is
  # asserted below; it is the same sentence shape with a live cause.

  # With more than one account the two headline figures cannot be subtracted to reach the
  # shortfall — the difference is cash sitting where this period's pools cannot reach it.
  it "explains the arithmetic when money is stranded in another account", :aggregate_failures do
    envelope("Rent", 400)
    deposit(1_000, into: create(:pool, :account, user: user, name: "Ally"))

    visit root_path

    expect(page).to have_css("h2", text: "$400.00 short")
    expect(page).to have_content("You need $400.00")
    expect(page).to have_content("You have $1,000.00")
    expect(page).to have_content("$1,000.00 of that sits in accounts with nothing left to fund")
  end

  # An overdraft is excluded from both headline figures by design, so the band has to name
  # it or a user $400 down reads "You're covered" and nothing else.
  it "names an overdrawn account beside the figures that exclude it", :aggregate_failures do
    groceries = envelope("Groceries", 400)
    create(:pool_movement, from_pool: checking, to_pool: groceries, amount: 400)

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
