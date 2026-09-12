# frozen_string_literal: true

require "rails_helper"

RSpec.describe HomePresenter do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let!(:main) { create(:account, user: user, opening_balance: 1_000) }
  let(:presenter) { described_class.new(user: user, today: today) }

  def rule_on(name, *traits, **attributes)
    category = create(:category, user: user, name: name)
    create(:rule, *traits, category: category, starts_on: Date.new(2026, 1, 1), **attributes)
  end

  it "reads the pot, free to spend and the claimed share", :aggregate_failures do
    rule_on("Groceries", amount: 400)
    create(:account, user: user, opening_balance: 250)

    expect(presenter.in_checking).to eq(1_000)
    expect(presenter.free_to_spend).to eq(600)
    expect(presenter.claimed_percent).to eq(40)
    expect(presenter.other_accounts_total).to eq(250)
    expect(presenter).to be_money_parked_elsewhere
    expect(presenter).to be_anything_claimed
    expect(presenter).not_to be_short
    expect(presenter.troubles).to be_empty
  end

  it "reports a shortfall and who gives way, choices first", :aggregate_failures do
    rule_on("Rent", :bill, amount: 900)
    rule_on("Fun", :choice, amount: 300)

    expect(presenter).to be_short
    expect(presenter.shortfall).to eq(200)
    expect(presenter.uncovered_claims.map { |u| [u.name, u.amount] }).to eq([["Fun", 200]])
    expect(presenter.troubles.map(&:kind)).to eq([:shortfall])
  end

  it "counts savings in claimed and free, and puts a savings claim in the give-way list between usage and bills", :aggregate_failures do
    # `main` is the top-level `let!`, with a $1,000 opening balance — a plain overspend drains the
    # pot below the sum of the three claims (340 excluding the bill), so all three give way.
    create(:entry, item: create(:item, category: create(:category, user: user, name: "Repairs")), amount: 970, date: today)
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 300, starts_on: user.period_containing(today).first)
    create(:rule, :rate, :bill, amount: 50, category: create(:category, user: user, name: "Rent"), starts_on: Date.new(2026, 1, 1))
    create(:rule, :rate, :choice, amount: 40, category: create(:category, user: user, name: "Fun"), starts_on: Date.new(2026, 1, 1))
    presenter = described_class.new(user: user, today: today)

    expect(presenter.claimed).to eq(390)
    expect(presenter.uncovered_claims.map { |u| [u.name, u.kind] }).to eq([["Fun", :choice], ["Emergency", :savings], ["Rent", :bill]])
  end

  it "flags an overdrawn other account and a structural gap", :aggregate_failures do
    other = create(:account, user: user)
    create(:transfer, from_account: other, to_account: main, amount: 10, date: today)
    rule_on("Rent", :bill, amount: 5_000)
    # Aug 21 opens the last complete period; income before it leaves AccountLedger no period to
    # average, and typical income nil is not a structural verdict.
    create(:entry, :income, user: user, amount: 100, date: Date.new(2026, 8, 21))

    kinds = presenter.troubles.map(&:kind)
    expect(kinds).to include(:overdraft, :structural)
    expect(presenter.overdrawn_other_accounts).to eq([other])
  end

  it "reads the four tiles off the ledger", :aggregate_failures do
    create(:account, user: user, name: "Checking", opening_balance: 1_000) unless user.main_account
    rule_on("Groceries", :rate, amount: 400)
    emergency = create(:account, user: user, name: "Emergency", opening_balance: 500)
    create(:savings_target, account: emergency, amount: 200, starts_on: user.period_containing(today).first)
    create(:entry, item: create(:item, category: user.categories.find_by!(name: "Groceries")), amount: 30, date: today)

    tiles = described_class.new(user: user, today: today).tiles
    expect(tiles).to have_attributes(checking: 970, spent_this_period: 30, claimed: 570, budget_claim: 370, savings_claim: 200, free: 400, savings_total: 500, savings_owed: 200, savings_count: 1)
  end

  # Rent: started Sep 4 in the period its Sep 12 due date falls in, so it is fully planned; the
  # $200 spent in its lane is what leaves it short.
  def seed_upcoming!
    create(:account, user: user, name: "Checking", opening_balance: 5_000) unless user.main_account
    rule_on("Dentist", :bill, amount: 300, anchor_date: Date.new(2026, 9, 12), starts_on: Date.new(2026, 8, 1))
    rule_on("Vet", :bill, amount: 180, anchor_date: Date.new(2026, 10, 1), starts_on: Date.new(2026, 9, 4))
    rule_on("Insurance", :bill, amount: 1_200, anchor_date: Date.new(2026, 12, 1), starts_on: Date.new(2026, 9, 4))
    rent = rule_on("Rent", :bill, amount: 900, anchor_date: Date.new(2026, 9, 12), starts_on: Date.new(2026, 9, 4))
    create(:entry, item: create(:item, category: rent.category), amount: 200, date: Date.new(2026, 9, 6))
  end

  it "lists dated rules due within 30 days, anything short first and then soonest", :aggregate_failures do
    seed_upcoming!
    presenter = described_class.new(user: user, today: today)

    expect(presenter.upcoming.map { |u| [u.name, u.due_on, u.state] })
      .to eq([["Rent", Date.new(2026, 9, 12), :short], ["Dentist", Date.new(2026, 9, 12), :ready], ["Vet", Date.new(2026, 10, 1), :building]])
    expect(presenter.upcoming_shown.size).to eq(3)
    expect(presenter.upcoming_hidden).to be_empty
    expect(presenter.upcoming_footer_words).to eq("3 due in the next 30 days")
  end

  it "heads the page with the day and where it sits in the period", :aggregate_failures do
    expect(presenter.day_words).to eq("Wednesday, September 9")
    expect(presenter.period_words).to eq("Day 6 of 14 in this period · next payday Sep 18")
  end

  # Past the cap, the rest are counted by state rather than listed.
  it "shows four and counts the rest by state", :aggregate_failures do
    create(:account, user: user, name: "Checking", opening_balance: 50_000) unless user.main_account
    ["Water", "Internet", "Phone", "Gym", "Trash", "Gas"].each_with_index do |name, index|
      rule_on(name, :bill, amount: 100, anchor_date: Date.new(2026, 9, 12 + index), starts_on: Date.new(2026, 8, 1))
    end
    rule_on("Tuition", :bill, amount: 2_000, anchor_date: Date.new(2026, 10, 5), starts_on: Date.new(2026, 9, 4))
    presenter = described_class.new(user: user, today: today)

    expect(presenter.upcoming_shown.map(&:name)).to eq(["Water", "Internet", "Phone", "Gym"])
    expect(presenter.upcoming_hidden.map(&:name)).to eq(["Trash", "Gas", "Tuition"])
    expect(presenter.upcoming_footer_words).to eq("3 more by Oct 9 · 2 ready · 1 still building")
  end

  def seed_kinds!
    rule_on("Rent", :bill, amount: 900)
    rule_on("Fun", :choice, amount: 300)
    rule_on("Groceries", :usage, amount: 400)
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
  end

  it "reads four kind columns in the order they hold on, each with its total and count", :aggregate_failures do
    seed_kinds!

    columns = presenter.columns
    expect(columns.map(&:kind)).to eq([:bill, :savings, :usage, :choice])
    expect(columns.map(&:name)).to eq(["Bills", "Savings", "Usage", "Choice"])
    expect(columns.map(&:total)).to eq([900, 200, 400, 300])
    expect(columns.map(&:count_words)).to eq(["1 rule", "1 account", "1 rule", "1 rule"])
    expect(presenter.rule_count).to eq(3)
  end

  it "fills a rule kind's column with claim lines and the savings column with savings lines", :aggregate_failures do
    seed_kinds!

    columns = presenter.columns
    expect(columns.first.rows.map { |row| row.category.name }).to eq(["Rent"])
    expect(columns.second.rows.map(&:name)).to eq(["Emergency"])
    expect(columns.second).to be_savings
  end

  it "keeps an empty kind as an empty column and never a missing one", :aggregate_failures do
    rule_on("Rent", :bill, amount: 900)

    columns = presenter.columns
    expect(columns.size).to eq(4)
    expect(columns.map(&:empty?)).to eq([false, true, true, true])
    expect(columns.second.count_words).to eq("0 accounts")
  end

  it "splits claimed into four shares that sum to claimed, as rounded percents", :aggregate_failures do
    rule_on("Rent", :bill, amount: 600)
    rule_on("Fun", :choice, amount: 200)
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
    presenter = described_class.new(user: user, today: today)

    shares = presenter.claimed_shares
    expect(shares.map(&:kind)).to eq([:bill, :savings, :usage, :choice])
    expect(shares.map(&:amount)).to eq([600, 200, 0, 200])
    expect(shares.map(&:percent)).to eq([60, 20, 0, 20])
    expect(shares.sum(0.to_d, &:amount)).to eq(presenter.claimed)
  end

  it "gives every share a zero percent when nothing is claimed" do
    expect(presenter.claimed_shares.map(&:percent)).to eq([0, 0, 0, 0])
  end

  it "lists spending in categories no rule claims" do
    create(:entry, :expense, user: user, amount: 42, date: Date.new(2026, 9, 6))

    expect(presenter.unbudgeted_rows.map(&:spent)).to eq([42])
  end

  it "has no spent-this-period figure for a user who has declared no cadence" do
    undeclared = create(:user)
    create(:account, user: undeclared, opening_balance: 1_000)

    presenter = described_class.new(user: undeclared, today: today)

    expect(presenter.spent_this_period).to be_nil
  end
end
