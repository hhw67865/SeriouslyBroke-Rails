# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home Attention", type: :system do
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

  def attention_section = find("section[aria-labelledby='attention-heading']")

  def waterfall_section = find("div[aria-labelledby='waterfall-heading']")

  it "lists a pool that can't be funded in time", :aggregate_failures do
    dentist = create(:pool, :budget_pool, user: user, account: checking, name: "Dentist", priority: 1)
    create(:pool_budget, :one_time, pool: dentist, amount: 300, anchor_date: Date.current + 3.days)

    visit root_path

    within(attention_section) do
      expect(page).to have_content("Dentist")
      expect(page).to have_content("won't make it")
      expect(page).to have_content("1 thing needs you")
      expect(page).to have_no_content("Nothing needs you")
    end
  end

  it "says nothing needs you when every pool is quiet", :aggregate_failures do
    groceries = envelope("Groceries", 400)
    # The money has to arrive before it can be moved. Without this deposit the movement
    # below leaves Checking at -$400 and the fixture is not quiet at all — see the
    # overdrawn example, which is that same fixture kept deliberately.
    deposit(400)
    create(:pool_movement, from_pool: checking, to_pool: groceries, amount: 400)

    visit root_path

    within(attention_section) do
      expect(page).to have_content("Nothing needs you")
      expect(page).to have_no_content("Groceries")
      expect(page).to have_no_content("overdrawn")
    end
  end

  it "shows no waterfall when there is no gap to explain", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(1_000)

    visit root_path

    expect(page).to have_content("Nothing needs you")
    expect(page).to have_no_content("Where your money went")
    expect(page).to have_no_content("ran out here")
  end

  # An overdrawn account reaches neither #available (clamped at zero) nor #shortfall
  # (summed from the waterfall rows), so unless a band names it, a real $400 debt is
  # invisible on the one screen that exists to say where you stand.
  it "gives an overdrawn account a voice even when every envelope is quiet", :aggregate_failures do
    groceries = envelope("Groceries", 400)
    create(:pool_movement, from_pool: checking, to_pool: groceries, amount: 400)

    visit root_path

    expect(page).to have_content("Checking is overdrawn $400.00")
    within(attention_section) do
      expect(page).to have_content("1 thing needs you")
      expect(page).to have_content("overdrawn $400.00")
      expect(page).to have_no_content("Nothing needs you")
      # The light-danger fill is the only thing separating this row from any other, and a
      # state's single visual differentiator that nothing asserts is a state nothing pins.
      expect(page).to have_css("div.bg-status-danger-light", text: "overdrawn $400.00")
    end
  end

  # A pool attached to no account cannot be funded from anywhere, so it is deliberately not
  # a waterfall row and not part of the shortfall — it is a setup problem, and this list is
  # the only place it gets said. Savings pools stay account-less until Plan 3's backfill.
  it "names a pool that belongs to no account", :aggregate_failures do
    orphan("Old Goal", 200)
    envelope("Rent", 400)
    deposit(100)

    visit root_path

    within(attention_section) do
      expect(page).to have_content("Old Goal")
      expect(page).to have_content("no account — nothing can fund it")
    end
    # $300 short on Rent alone: the orphan's $200 is owed but is not a funding gap, and it
    # must not drag the cutoff above a row that money did reach.
    expect(page).to have_content("$300.00 short this period")
    expect(waterfall_section).to have_no_content("Old Goal")
  end

  it "counts more than one problem in the heading", :aggregate_failures do
    groceries = envelope("Groceries", 400)
    create(:pool_movement, from_pool: checking, to_pool: groceries, amount: 400)
    orphan("Old Goal", 200)

    visit root_path

    within(attention_section) do
      expect(page).to have_content("2 things need you")
      expect(page).to have_no_content("thing needs you")
    end
  end

  # The state that is short with nothing flagged: every rate envelope reads `left_to_spend`,
  # so no pool needs attention while the period is genuinely $300 down. "Nothing needs you"
  # here would be the exact lie this band exists to prevent.
  it "never says nothing needs you while the money runs out", :aggregate_failures do
    envelope("Rent", 400)
    deposit(100)

    visit root_path

    within(attention_section) do
      expect(page).to have_content("Nothing is flagged, but you're still short")
      expect(page).to have_no_content("Nothing needs you")
      expect(page).to have_content("Where your money went")
    end
  end

  # Each account drains its own pot, so there is no single moment the money ran out: a line
  # here would print above rows that were funded in full out of another account's cash.
  it "draws no cutoff when the user has more than one account", :aggregate_failures do
    ally = create(:pool, :account, user: user, name: "Ally")
    envelope("Rent", 400)
    deposit(100)
    spare = create(:pool, :budget_pool, user: user, account: ally, name: "Gas", priority: 2)
    create(:pool_budget, :per_paycheck_rate, pool: spare, amount: 200)
    deposit(500, into: ally)

    visit root_path

    expect(waterfall_section).to have_content("$100.00 of $400.00")
    expect(waterfall_section).to have_content("$200.00 of $200.00")
    expect(waterfall_section).to have_no_content("ran out here")
  end

  # The other cutoff branch: the money ran out inside the LAST row, so no pool sits below
  # the line and it has to render at the end of the list rather than not at all.
  it "shows the waterfall with a cutoff when short", :aggregate_failures do
    ["Rent", "Groceries"].each_with_index do |name, i|
      pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: i + 1)
      create(:pool_budget, :per_paycheck_rate, pool: pool, amount: 500)
    end
    category = create(:category, :income, user: user, pool: checking)
    create(:entry, item: create(:item, category: category), amount: 700, date: Date.current)

    visit root_path

    expect(page).to have_content("Where your money went")
    expect(page).to have_content("ran out here")
  end

  # The cutoff sits where the money ran out, and a pool funded $200 of $500 did receive
  # money: it belongs ABOVE the line, with only the pools that got nothing below it.
  it "draws the cutoff beneath the last pool that got any money", :aggregate_failures do
    { "Rent" => 500, "Groceries" => 500, "Dentist" => 500 }.each_with_index do |(name, amount), i|
      pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: i + 1)
      create(:pool_budget, :per_paycheck_rate, pool: pool, amount: amount)
    end
    deposit(700)

    visit root_path

    expect(waterfall_section.text).to match(/Rent.*Groceries.*ran out here.*Dentist/m)
    expect(waterfall_section).to have_content("$200.00 of $500.00")
    expect(waterfall_section).to have_content("$0.00 of $500.00")
    expect(waterfall_section).to have_content("$800.00 unfunded")
  end
end
