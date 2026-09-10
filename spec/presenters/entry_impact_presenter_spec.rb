# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntryImpactPresenter do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }

  before { create(:account, user: user) }

  def impact(category:, amount: nil, entry: nil) = described_class.new(user: user, category: category, amount: amount, entry: entry, today: today)

  it "does not render for income, or for a category with no rule", :aggregate_failures do
    expect(impact(category: create(:category, :income, user: user))).not_to be_render
    expect(impact(category: groceries)).to be_render
    expect(impact(category: groceries)).to be_unbudgeted
    expect(impact(category: groceries)).not_to be_figures
  end

  it "shows the balance before and after for a rate rule", :aggregate_failures do
    create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1))
    create(:entry, item: create(:item, category: groceries), amount: 100, date: Date.new(2026, 9, 5))

    figures = impact(category: groceries, amount: "50")
    expect(figures.balance).to eq(300)
    expect(figures.balance_after).to eq(250)
    expect(figures.denominator).to eq(400)
    expect(figures.bar_percent).to eq(63)
    expect(figures).not_to be_overdrawn
    expect(impact(category: groceries, amount: "350")).to be_overdrawn
  end

  it "gives an edited entry its own amount back before subtracting the new one" do
    create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1))
    entry = create(:entry, item: create(:item, category: groceries), amount: 100, date: Date.new(2026, 9, 5))

    expect(impact(category: groceries, amount: "120", entry: entry).balance).to eq(400)
  end

  it "names a dated target and uses it as the bar's denominator", :aggregate_failures do
    create(:rule, :bill, amount: 600, anchor_date: Date.new(2026, 10, 15), category: groceries, starts_on: Date.new(2026, 8, 1))

    figures = impact(category: groceries, amount: "10")
    expect(figures).to be_fund
    expect(figures.fund_target).to eq(600)
    expect(figures.noun).to eq("bill")
    expect(figures.balance).to eq(400)
  end
end
