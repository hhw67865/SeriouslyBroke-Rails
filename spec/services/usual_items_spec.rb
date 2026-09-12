# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsualItems do
  let(:user) { create(:user) }
  let(:category) { create(:category, :expense, user: user) }
  let(:today) { Date.new(2026, 9, 10) }

  def usual(window: 90, limit: 8)
    described_class.new(user, today: today, window: window, limit: limit).rows
  end

  it "ranks the item entered more often first, even when it was entered less recently" do
    frequent = create(:item, category: category, name: "Coffee")
    recent = create(:item, category: category, name: "Tea")
    create_list(:entry, 3, item: frequent, date: today - 30)
    create(:entry, item: recent, date: today - 1)

    expect(usual.map { |row| row.item.name }).to eq(["Coffee", "Tea"])
  end

  it "breaks an equal count by the more recently entered item" do
    older = create(:item, category: category, name: "Coffee")
    newer = create(:item, category: category, name: "Tea")
    create(:entry, item: older, date: today - 30)
    create(:entry, item: newer, date: today - 1)

    expect(usual.map { |row| row.item.name }).to eq(["Tea", "Coffee"])
  end

  it "excludes an item with nothing entered inside the window" do
    stale = create(:item, category: category, name: "Stale")
    create(:entry, item: stale, date: today - 91)

    expect(usual).to be_empty
  end

  it "caps the rows at the given limit, most-used first" do
    items = create_list(:item, 3, category: category)
    items.each { |item| create(:entry, item: item, date: today - 1) }

    expect(usual(limit: 2).size).to eq(2)
  end

  it "carries the item's newest entry as last", :aggregate_failures do
    item = create(:item, category: category, name: "Coffee")
    create(:entry, item: item, date: today - 10, amount: 3)
    newest = create(:entry, item: item, date: today - 1, amount: 4)

    row = usual.first
    expect(row.last).to eq(newest)
    expect(row.count).to eq(2)
  end

  it "never surfaces another user's items" do
    other_item = create(:item, :expense)
    create(:entry, item: other_item, date: today - 1)
    mine = create(:item, category: category, name: "Mine")
    create(:entry, item: mine, date: today - 1)

    expect(usual.map(&:item)).to eq([mine])
  end
end
