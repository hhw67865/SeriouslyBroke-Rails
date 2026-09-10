# frozen_string_literal: true

require "rails_helper"

RSpec.describe BudgetPagePresenter do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:presenter) { described_class.new(user: user, today: today) }
  let(:salary) { create(:category, :income, user: user, name: "Salary") }

  before { create(:account, user: user, opening_balance: 1_000) }

  def earn(amount, on:) = create(:entry, item: create(:item, category: salary), amount: amount, date: on)

  # Two periods of income, because AccountLedger#typical_income averages COMPLETE periods that
  # begin on or after the first entry — one entry inside the previous period completes none.
  def a_period_of_income(amount)
    earn(amount, on: Date.new(2026, 8, 7))
    earn(amount, on: Date.new(2026, 8, 25))
  end

  def rule_on(name, *traits, priority: 0, **attributes)
    create(
      :rule,
      *traits,
      category: create(:category, user: user, name: name, priority: priority),
      starts_on: Date.new(2026, 1, 1),
      **attributes
    )
  end

  it "lists ruled categories by priority then the unruled ones by name", :aggregate_failures do
    rule_on("Rent", priority: 1, amount: 900)
    rule_on("Fun", priority: 0, amount: 100)
    create(:category, user: user, name: "Aardvark")

    expect(presenter.category_rows.map(&:name)).to eq(["Fun", "Rent", "Aardvark"])
    expect(presenter.reorderable_rows.map(&:name)).to eq(["Fun", "Rent"])
    expect(presenter.category_rows.first).to be_ruled
    expect(presenter.category_rows.last).not_to be_ruled
    expect(presenter).not_to be_no_categories
  end

  it "compares what the rules need with typical income", :aggregate_failures do
    rule_on("Rent", :bill, amount: 900)
    a_period_of_income(2_000)

    expect(presenter.rules_need).to eq(900)
    expect(presenter.typical_income).to eq(2_000)
    expect(presenter.leftover).to eq(1_100)
    expect(presenter).to be_declared
    expect(presenter).to be_history
    expect(presenter.tiles).to have_attributes(need: 900, income: 2_000, fits: true, declared: true)
    expect(presenter.type_overview).to eq([[:bill, 900]])
  end

  it "has no history and no verdict until a period completes", :aggregate_failures do
    rule_on("Rent", :bill, amount: 900)

    expect(presenter.typical_income).to be_nil
    expect(presenter).not_to be_history
    expect(presenter).not_to be_underwater
    expect(presenter.tiles.fits).to be(false)
  end

  it "is underwater when the rules need more than comes in" do
    rule_on("Rent", :bill, amount: 3_000)
    a_period_of_income(2_000)

    expect(presenter).to be_underwater
  end

  it "opens the category it is told to" do
    rent = rule_on("Rent", amount: 900).category

    expect(described_class.new(user: user, today: today, open_category_id: rent.id).open?(rent)).to be(true)
  end
end
