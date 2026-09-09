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
    expect(ledger.rules_of(groceries)).to contain_exactly(bread_rule, whole_rule)
    expect(ledger.total_claims).to eq(220)
    expect(ledger.pot).to eq(870)
    expect(ledger.free).to eq(650)
    expect(ledger.total_money).to eq(870)
  end

  it "loads its rows in a fixed number of queries" do
    3.times { create(:rule, :rate, category: create(:category, user: user), starts_on: Date.new(2026, 1, 1)) }
    queries = 0
    counter = ->(_name, _start, _finish, _id, payload) { queries += 1 unless ["SCHEMA", "CACHE"].include?(payload[:name]) }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { ledger.total_claims }

    expect(queries).to be <= 8
  end

  it "refuses a rule it does not hold" do
    expect { ledger.calculator_for(create(:rule)) }.to raise_error(ClaimLedger::UnknownRule)
  end

  # The rate rule's item and the fund rule's category, with their spending and an adjustment,
  # extracted so the example above stays within RSpec/ExampleLength.
  def seed_grocery_rules
    bread_rule = create(:rule, :rate, amount: 100, category: groceries, item: bread, starts_on: Date.new(2026, 1, 1))
    whole_rule = create(:rule, :keeps_unspent, amount: 60, category: groceries, starts_on: Date.new(2026, 8, 1))
    create(:entry, item: bread, amount: 30, date: Date.new(2026, 9, 5))
    create(:entry, item: milk, amount: 100, date: Date.new(2026, 8, 25))
    create(:adjustment, rule: whole_rule, amount: 10, date: Date.new(2026, 9, 6))
    [bread_rule, whole_rule]
  end
end
