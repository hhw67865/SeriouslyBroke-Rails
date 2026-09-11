# frozen_string_literal: true

require "rails_helper"

# Biweekly anchored Feb 6: Sep 9 sits in Sep 4 – Sep 17. A target since Aug 7 has walked three
# periods by Sep 9 (Aug 7–20, Aug 21–Sep 3, Sep 4–17).
RSpec.describe SavingsCalculator do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let!(:checking) { create(:account, user: user, name: "Checking", opening_balance: 5_000) }
  let(:account) { create(:account, user: user, name: "Emergency") }
  let(:paycheck) { create(:item, :income, user: user, name: "Paycheck") }

  def calculator(**rows) = described_class.new(account, today: today, **rows)

  def move(amount, on) = create(:transfer, from_account: checking, to_account: account, amount: amount, date: on)

  it "owes the fixed amount every period and nets what arrived, keeping extra", :aggregate_failures do
    create(:savings_target, account: account, amount: 200, starts_on: Date.new(2026, 8, 7))
    move(500, Date.new(2026, 8, 10))

    expect(calculator.periods.size).to eq(3)
    expect(calculator.owed_this_period).to eq(200)
    expect(calculator.claim).to eq(100)
    expect(calculator.countable_span).to eq(Date.new(2026, 8, 7)..today)
  end

  it "asks fresh every period when extra is not kept, and carries a shortfall", :aggregate_failures do
    account.update!(keeps_extra: false)
    create(:savings_target, account: account, amount: 200, starts_on: Date.new(2026, 8, 7))
    move(500, Date.new(2026, 8, 10))
    move(100, Date.new(2026, 8, 25))

    expect(calculator.claim).to eq(300)
  end

  it "owes a share of the item's entries in each period, from the share's own start", :aggregate_failures do
    create(:savings_target, :share, account: account, item: paycheck, percent: 10, starts_on: Date.new(2026, 8, 21))
    create(:entry, item: paycheck, amount: 2_000, date: Date.new(2026, 8, 10))
    create(:entry, item: paycheck, amount: 2_000, date: Date.new(2026, 8, 25))
    create(:entry, item: paycheck, amount: 3_000, date: Date.new(2026, 9, 8))

    expect(calculator.owed_this_period).to eq(300)
    expect(calculator.claim).to eq(500)
  end

  it "sums a fixed target and a share into one claim and one ask", :aggregate_failures do
    create(:savings_target, account: account, amount: 200, starts_on: Date.new(2026, 9, 4))
    create(:savings_target, :share, account: account, item: paycheck, percent: 10, starts_on: Date.new(2026, 9, 4))
    create(:entry, item: paycheck, amount: 1_000, date: Date.new(2026, 9, 8))

    expect(calculator.claim).to eq(300)
    expect(calculator(typical_income_by_item: { paycheck.id => 3_400.to_d }).ask).to eq(540)
  end

  it "applies an adjustment to the period it is dated in", :aggregate_failures do
    create(:savings_target, account: account, amount: 200, starts_on: Date.new(2026, 8, 21))
    create(:adjustment, source: account, amount: -150, date: Date.new(2026, 9, 6))

    expect(calculator.accrued_this_period).to eq(50)
    expect(calculator.claim).to eq(250)
  end

  it "claims nothing with no target or a start in the future, and ignores transfers before the start", :aggregate_failures do
    expect(calculator.claim).to eq(0)
    expect(calculator.countable_span).to eq(today...today)

    create(:savings_target, account: account, amount: 200, starts_on: Date.new(2026, 9, 20))
    expect(calculator.claim).to eq(0)

    account.savings_targets.delete_all
    create(:savings_target, account: account, amount: 200, starts_on: Date.new(2026, 9, 4))
    move(1_000, Date.new(2026, 8, 1))
    expect(calculator.claim).to eq(200)
  end

  it "takes its rows when handed them" do
    target = create(:savings_target, account: account, amount: 200, starts_on: Date.new(2026, 8, 21))
    handed = calculator(targets: [target], transfers: [[Date.new(2026, 8, 22), 150.to_d]], income: {}, adjustments: [])

    expect(handed.claim).to eq(250)
  end

  it "raises on an unknown row keyword instead of silently querying" do
    expect { calculator(bogus: []) }.to raise_error(ArgumentError, "unknown keyword: bogus")
  end

  it "caps the period walk at PERIOD_WALK_LIMIT" do
    create(:savings_target, account: account, amount: 200, starts_on: Date.new(2000, 1, 1))

    expect(calculator.periods.size).to eq(SavingsCalculator::PERIOD_WALK_LIMIT)
  end
end
