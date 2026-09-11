# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClaimLedger do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:ledger) { described_class.new(user, today: today) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let(:bread) { create(:item, category: groceries, name: "Bread") }
  let(:milk) { create(:item, category: groceries, name: "Milk") }

  before { create(:account, user: user, opening_balance: 1_000) }

  it "hands every rule a calculator fed from batched rows and agrees with the calculators", :aggregate_failures do
    bread_rule, whole_rule = seed_grocery_rules

    expect(ledger.rules).to contain_exactly(bread_rule, whole_rule)
    expect(ledger.claim_of(bread_rule)).to eq(70).and eq(ClaimCalculator.new(bread_rule, today: today).claim)
    expect(ledger.claim_of(whole_rule)).to eq(150).and eq(ClaimCalculator.new(whole_rule, today: today).claim)
    expect(ledger.claim_of_category(groceries)).to eq(220)
    expect(ledger.budget_claim).to eq(220)
    expect(ledger.claimed).to eq(220)
    expect(ledger.pot).to eq(870)
    expect(ledger.free).to eq(650)
    expect(ledger.budget).to eq(160)
  end

  it "lists savings claims beside rule claims, in give-way order, and sums both", :aggregate_failures do
    seed_grocery_rules
    emergency = seed_savings_claims

    expect(ledger.savings_accounts).to eq([emergency])
    expect(ledger.claims.map { |claim| [claim.name, claim.kind, claim.claim] })
      .to eq([["Groceries", :usage, 150], ["Bread", :usage, 70], ["Emergency", :savings, 200], ["Rent", :bill, 50]])
    expect(ledger).to have_attributes(savings: 200, savings_claim: 200, claimed: 470, free: 400)
    expect(ledger.calculator_for(emergency)).to be_a(SavingsCalculator)
    expect(ledger.claims.find(&:account?).cuttable).to be(true)
    expect(ledger.claims.find { |c| c.name == "Rent" }.cuttable).to be(true)
  end

  it "loads its rows in a fixed number of queries" do
    3.times { create(:rule, :rate, category: create(:category, user: user), starts_on: Date.new(2026, 1, 1)) }
    queries = 0
    counter = ->(_name, _start, _finish, _id, payload) { queries += 1 unless ["SCHEMA", "CACHE"].include?(payload[:name]) }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { ledger.claimed }

    expect(queries).to be <= 8
  end

  it "refuses a rule it does not hold" do
    expect { ledger.calculator_for(create(:rule)) }.to raise_error(ClaimLedger::UnknownSource)
  end

  # The rate rule's item and the fund rule's category, with their spending and an adjustment,
  # extracted so the example above stays within RSpec/ExampleLength.
  def seed_grocery_rules
    bread_rule = create(:rule, :rate, amount: 100, category: groceries, item: bread, starts_on: Date.new(2026, 1, 1))
    whole_rule = create(:rule, :keeps_unspent, amount: 60, category: groceries, starts_on: Date.new(2026, 8, 1))
    create(:entry, item: bread, amount: 30, date: Date.new(2026, 9, 5))
    create(:entry, item: milk, amount: 100, date: Date.new(2026, 8, 25))
    create(:adjustment, source: whole_rule, amount: 10, date: Date.new(2026, 9, 6))
    [bread_rule, whole_rule]
  end

  # An Emergency account with a $200 target and a Rent bill, so the savings claim example stays
  # within RSpec/ExampleLength.
  def seed_savings_claims
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
    create(:rule, :rate, :bill, amount: 50, category: create(:category, user: user, name: "Rent"), starts_on: Date.new(2026, 1, 1))
    emergency
  end
end
