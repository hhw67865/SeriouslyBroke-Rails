# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home Pools", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking", target_amount: 2_000) }

  before { sign_in user, scope: :user }

  def group(name) = find("[data-pool-group='#{name}']")

  def row(name) = find("[data-pool-name='#{name}']")

  # A rate envelope: refilled every period, and the shape that reads `left to spend`.
  def envelope(name, rate:, priority: 1)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    create(:pool_budget, :per_paycheck_rate, pool: pool, amount: rate)
    pool
  end

  # A bill that accumulates toward a date — the shape that reads `on track` while it is
  # being filled on schedule.
  def accumulating(name, amount:, due:, priority: 1)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    create(:pool_budget, pool: pool, amount: amount, interval_months: 1, anchor_date: due)
    pool
  end

  # A one-off bill with no interval to spread it over.
  def one_off(name, amount:, due:, priority: 1)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    create(:pool_budget, :one_time, pool: pool, amount: amount, anchor_date: due)
    pool
  end

  def deposit(amount, into: checking)
    category = create(:category, :income, user: user, pool: into, name: "#{into.name} pay")
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  def fund(pool, amount) = create(:pool_movement, from_pool: checking, to_pool: pool, amount: amount)

  # The two buffers are deliberately different numbers here: $1,000 in with $100 already
  # moved into the envelope leaves the account holding $900 NOW, and the $300 the rule still
  # wants this period leaves $600 AFTER the distribution. A band printing the other one is a
  # plausible wrong figure, which is the whole reason the readers are named for their moment.
  it "groups pools under their account and shows the buffer", :aggregate_failures do
    deposit(1_000)
    fund(envelope("Groceries", rate: 400), 100)

    visit root_path

    expect(page).to have_content("Checking")
    expect(group("Checking")).to have_content("Groceries")
    expect(group("Checking")).to have_content("$100.00 left")
    expect(group("Checking")).to have_content("buffer $900.00")
    expect(group("Checking")).to have_content("of $2,000.00")
    expect(page).to have_content("$600.00 stays in your buffer")
  end

  it "shows a balance on an on-track pool" do
    deposit(2_000)
    fund(accumulating("Rent", amount: 2_000, due: Date.current + 2.months), 2_000)

    visit root_path

    expect(row("Rent")).to have_content("$2,000.00 · on track")
  end

  it "auto-expands a pool that needs attention", :aggregate_failures do
    one_off("Dentist", amount: 300, due: Date.current + 3.days)

    visit root_path

    expect(row("Dentist")["data-expanded"]).to eq("true")
    expect(row("Dentist")).to have_content("won't make it")
    # The auto-expand exists to show the rule behind the trouble. A `data-expanded` flag
    # over an empty row would satisfy the attribute and none of the point.
    expect(row("Dentist")).to have_css("[data-role='pool-detail']")
    expect(row("Dentist")).to have_content("$300.00")
    expect(row("Dentist")).to have_content((Date.current + 3.days).strftime("%b %-d"))
  end

  it "leaves a quiet pool collapsed", :aggregate_failures do
    deposit(400)
    fund(envelope("Groceries", rate: 400), 400)

    visit root_path

    expect(row("Groceries")["data-expanded"]).to eq("false")
    # The other half of the same rule: a quiet pool renders its one line and nothing else.
    expect(row("Groceries")).to have_no_css("[data-role='pool-detail']")
  end

  # Two pools, one of each kind, on the same screen: the auto-expanded rows have to be
  # EXACTLY the ones needing attention. Either half alone passes against a view that
  # expands everything, or nothing.
  it "expands only the rows that need attention", :aggregate_failures do
    deposit(400)
    fund(envelope("Groceries", rate: 400), 400)
    one_off("Dentist", amount: 300, due: Date.current + 3.days, priority: 2)

    visit root_path

    expect(page).to have_css("[data-expanded='true']", count: 1)
    expect(row("Dentist")["data-expanded"]).to eq("true")
    expect(row("Groceries")["data-expanded"]).to eq("false")
  end

  # A pool with no account is excluded from #pools_for, so a band built purely as
  # "for each account, render its pools" renders it nowhere at all — and an account-less
  # savings pool is the ordinary shape until Plan 3's backfill.
  it "gives a pool with no account a group of its own", :aggregate_failures do
    create(:pool, user: user, name: "Old Goal", target_amount: 5_000, priority: 1)
    envelope("Groceries", rate: 400)

    visit root_path

    expect(group("No account")).to have_content("Old Goal")
    expect(group("No account")).to have_content("nothing can fund")
    # And it must not be filed under an account it does not belong to.
    expect(group("Checking")).to have_no_content("Old Goal")
    expect(group("No account")).to have_no_content("Groceries")
    # Its own status is quiet — a goal at $0 of $5,000 with no dated rule reads
    # `left to spend` — so only the "nothing can fund it" half makes this a problem, and
    # the row still has to open with the rest of the trouble rather than sit collapsed
    # under a red heading.
    expect(row("Old Goal")["data-expanded"]).to eq("true")
    expect(row("Old Goal")).to have_content("no distribution can reach it")
  end

  # The group header is the only thing that says these are unfundable, so it must stay
  # silent when every pool has an account — an empty "No account" heading over nothing
  # is a problem invented out of a healthy screen.
  it "shows no such group when every pool has an account", :aggregate_failures do
    envelope("Groceries", rate: 400)

    visit root_path

    expect(page).to have_css("[data-pool-group='Checking']")
    expect(page).to have_no_css("[data-pool-group='No account']")
    expect(page).to have_no_content("nothing can fund")
  end

  it "names an overdrawn account's buffer as the debt it is", :aggregate_failures do
    fund(envelope("Groceries", rate: 400), 400)

    visit root_path

    expect(group("Checking")).to have_content("buffer -$400.00")
    expect(group("Checking")).to have_css(".text-status-danger", text: "-$400.00")
  end
end
