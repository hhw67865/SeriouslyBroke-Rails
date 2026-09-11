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
    # Sep 4 – Sep 17 on this user's grid, so eight days are left after today. See #period_progress.
    expect(presenter.per_day_pace).to eq((200.to_d / 8).round(2))
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

  it "measures the period and the runway", :aggregate_failures do
    rule_on("Dentist", :bill, amount: 300, anchor_date: Date.new(2026, 9, 12), starts_on: Date.new(2026, 8, 1))

    expect(presenter.period_progress).to have_attributes(day: 6, days: 14, days_left: 8)
    expect(presenter.runway.ticks.map(&:label)).to eq(["Dentist"])
    expect(presenter.runway.ticks.first.day_index).to eq(9)
  end

  it "lists spending in categories no rule claims" do
    create(:entry, :expense, user: user, amount: 42, date: Date.new(2026, 9, 6))

    expect(presenter.unbudgeted_rows.map(&:spent)).to eq([42])
  end
end
