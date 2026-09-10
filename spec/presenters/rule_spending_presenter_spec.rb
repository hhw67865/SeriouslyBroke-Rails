# frozen_string_literal: true

require "rails_helper"

RSpec.describe RuleSpendingPresenter do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }

  it "is empty when nothing has been spent", :aggregate_failures do
    rule = create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1))

    presenter = described_class.new(rule, today: today)

    expect(presenter.rows).to be_empty
    expect(presenter.total).to eq(0)
  end

  it "groups a whole-category rule's rows by item, largest subtotal first", :aggregate_failures do
    rule = create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1))
    bread = create(:item, category: groceries, name: "Bread")
    milk = create(:item, category: groceries, name: "Milk")
    create(:entry, item: bread, amount: 30, date: today)
    create(:entry, item: milk, amount: 50, date: today)
    create(:entry, item: milk, amount: 20, date: today)

    presenter = described_class.new(rule, today: today)

    expect(presenter).to be_grouped
    expect(presenter.rows.map { |row| [row.name, row.amount, row.count] }).to eq([["Milk", 70, 2], ["Bread", 30, 1]])
    expect(presenter.total).to eq(rule.claim_calculator(today: today).spent_this_period)
  end

  it "lists an item rule's own entries newest first, named by description or the item", :aggregate_failures do
    bread = create(:item, category: groceries, name: "Bread")
    rule = create(:rule, :rate, amount: 400, category: groceries, item: bread, starts_on: Date.new(2026, 1, 1))
    create(:entry, item: bread, amount: 10, date: today - 1, description: "")
    create(:entry, item: bread, amount: 15, date: today, description: "Trader Joe's")

    presenter = described_class.new(rule, today: today)

    expect(presenter).not_to be_grouped
    expect(presenter.rows.map { |row| [row.name, row.amount, row.date] })
      .to eq([["Trader Joe's", 15, today], ["Bread", 10, today - 1]])
  end

  it "marks the total over when spending outran the rule's amount" do
    bread = create(:item, category: groceries, name: "Bread")
    rule = create(:rule, :rate, amount: 20, category: groceries, item: bread, starts_on: Date.new(2026, 1, 1))
    create(:entry, item: bread, amount: 25, date: today)

    expect(described_class.new(rule, today: today)).to be_over
  end
end
