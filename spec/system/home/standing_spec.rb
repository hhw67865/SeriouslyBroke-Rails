# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home Standing", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before { sign_in user, scope: :user }

  def envelope(name, amount, priority: 1)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    create(:pool_budget, :per_paycheck_rate, pool: pool, amount: amount)
    pool
  end

  def deposit(amount, into: checking)
    category = create(:category, :income, user: user, pool: into)
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  # A pool attached to no account. Savings pools stay this way until Plan 3's backfill.
  def orphan(name, amount)
    pool = create(:pool, user: user, name: name, target_amount: 5_000, priority: 1)
    create(:pool_budget, :per_paycheck_rate, pool: pool, amount: amount)
    pool
  end

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

  # Being covered is true of the ACCOUNTS. It says nothing about a pool no account can reach,
  # and the covered branch used to say nothing either — so a user was told they were fine
  # while $200 of what they owe this period could not be funded at all. Same figure, same
  # gate and the same fix as the short branch; only the framing changes.
  #
  # The second orphan here owns none of the figure, and the count must leave it out: the
  # clause names a sum and a size side by side, and describing two different sets with them
  # invites the reader to divide one by the other. "$200.00 … belongs to 2 pools" reads as
  # about $100 each, and one of those pools is asking for nothing at all.
  it "names the unfundable part even when you're covered", :aggregate_failures do
    orphan("Old Goal", 200)
    create(:pool, user: user, name: "Finished Goal", target_amount: 5_000, priority: 2)
    envelope("Rent", 400)
    deposit(1_000)

    visit root_path

    expect(page).to have_css("h2", text: "You're covered")
    expect(page).to have_content("$600.00 stays in your buffer after this period")
    expect(page).to have_content("$200.00 of what you need belongs to 1 pool with no account")
    expect(page).to have_no_content("2 pools with no account")
    # Both are still problems and both are still named — it is only the arithmetic the
    # sentence claims that has to describe one set.
    expect(page).to have_content("Finished Goal")
  end

  it "counts only the pools the unfundable figure came from when short", :aggregate_failures do
    orphan("Old Goal", 200)
    create(:pool, user: user, name: "Finished Goal", target_amount: 5_000, priority: 2)
    envelope("Rent", 400)
    deposit(100)

    visit root_path

    expect(page).to have_css("h2", text: "$300.00 short")
    expect(page).to have_content("$200.00 of what you need belongs to 1 pool with no account")
    expect(page).to have_no_content("2 pools with no account")
  end

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

  # The figures a reader can subtract must reach the headline, or be told why not. Here
  # $600 - $100 implies a $500 gap under a $300 headline, and the missing $200 is a pool
  # no account can fund — with the buffer at zero, as it always is when one account is
  # short, so gating the explanation on the buffer alone said nothing at all.
  it "reconciles the figures when a pool no account can fund is part of what you owe", :aggregate_failures do
    orphan("Old Goal", 200)
    envelope("Rent", 400)
    deposit(100)

    visit root_path

    expect(page).to have_css("h2", text: "$300.00 short")
    expect(page).to have_content("You need $600.00")
    expect(page).to have_content("You have $100.00")
    expect(page).to have_content("$200.00 of what you need belongs to 1 pool with no account")
    expect(page).to have_no_content("can't close the gap")
  end

  # The other half of the clause above, and the reason it is gated on the FIGURE rather than
  # on there being an orphan at all: a pool with no account whose own requirement is already
  # zero — a dateless goal sitting at target, a fulfilled anchored rule, or as here a goal
  # with no rule on it yet — leaves the figures reconciling exactly. Gated on `orphan_pools.any?`
  # this printed "$0.00 of what you need belongs to 1 pool with no account": accurate, and
  # about a cause that is not live. It is still a problem, and the band below still says so.
  it "stays silent about a pool with no account that needs nothing this period", :aggregate_failures do
    create(:pool, user: user, name: "Old Goal", target_amount: 5_000, priority: 1)
    envelope("Rent", 400)
    deposit(100)

    visit root_path

    expect(page).to have_css("h2", text: "$300.00 short")
    expect(page).to have_no_content("with no account")
    expect(page).to have_no_content("$0.00 of what you need")
    expect(page).to have_content("Old Goal")
  end

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

  # A pool no account can fund is owed but is not a gap, so the period stays covered — and
  # the buffer must be what is actually left in the accounts. `available - total_required`
  # would print "-$400.00 stays in your buffer" at a user whose accounts are in order.
  it "keeps the buffer honest when a pool belongs to no account", :aggregate_failures do
    orphan("Old Goal", 500)
    deposit(100)

    visit root_path

    expect(page).to have_css("h2", text: "You're covered")
    expect(page).to have_content("$100.00 stays in your buffer after this period")
    expect(page).to have_no_content("-$")
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
