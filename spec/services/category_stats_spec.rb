# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategoryStats do
  let(:user) { create(:user) }
  let(:june) { Date.new(2026, 6, 1) }

  def stats_for(category, date = june, period: :monthly)
    described_class.new(category, date, period: period)
  end

  describe "#total_amount" do
    let(:category) { create(:category, :expense, user: user, name: "Groceries") }
    let(:item) { create(:item, category: category, name: "Weekly shop") }

    before do
      create(:entry, item: item, amount: 100, date: Date.new(2026, 6, 3))
      create(:entry, item: item, amount: 40, date: Date.new(2026, 6, 28))
      create(:entry, item: item, amount: 500, date: Date.new(2026, 2, 14))
      create(:entry, item: item, amount: 900, date: Date.new(2026, 7, 1))
    end

    it "sums the month the date falls in, and nothing on either side of it" do
      expect(stats_for(category).total_amount).to eq(140)
    end

    it "sums from January through the end of that month year to date" do
      expect(stats_for(category, period: :ytd).total_amount).to eq(640)
    end

    it "reads its range off the date it was given", :aggregate_failures do
      expect(stats_for(category).date_range).to eq(Date.new(2026, 6, 1)..Date.new(2026, 6, 30))
      expect(stats_for(category, period: :ytd).date_range).to eq(Date.new(2026, 1, 1)..Date.new(2026, 6, 30))
    end

    it "defaults to the owner's today" do
      travel_to Time.utc(2026, 6, 20) do
        expect(category.stats.date_range).to eq(Date.new(2026, 6, 1)..Date.new(2026, 6, 30))
      end
    end
  end

  describe "#previous_month_change_percentage and #previous_month_trend" do
    let(:category) { create(:category, :income, user: user, name: "Salary") }
    let(:item) { create(:item, category: category, name: "Paycheck") }

    it "reports the rise on the month before as a percentage", :aggregate_failures do
      create(:entry, item: item, amount: 2_500, date: Date.new(2026, 5, 10))
      create(:entry, item: item, amount: 3_000, date: Date.new(2026, 6, 10))

      expect(stats_for(category).previous_month_change_percentage).to eq(20)
      expect(stats_for(category).previous_month_trend).to eq(:up)
    end

    it "reports the fall the same way, and calls it down", :aggregate_failures do
      create(:entry, item: item, amount: 2_500, date: Date.new(2026, 5, 10))
      create(:entry, item: item, amount: 2_000, date: Date.new(2026, 6, 10))

      expect(stats_for(category).previous_month_change_percentage).to eq(-20)
      expect(stats_for(category).previous_month_trend).to eq(:down)
    end

    it "answers zero when the month before is empty, rather than dividing by it" do
      create(:entry, item: item, amount: 3_000, date: Date.new(2026, 6, 10))

      expect(stats_for(category).previous_month_change_percentage).to eq(0)
    end

    # The comparison is an income reading: an expense category's spending is not a trend anything
    # asks this figure for.
    it "answers zero for an expense category" do
      expense = create(:category, :expense, user: user, name: "Groceries")
      expense_item = create(:item, category: expense)
      create(:entry, item: expense_item, amount: 100, date: Date.new(2026, 5, 10))
      create(:entry, item: expense_item, amount: 300, date: Date.new(2026, 6, 10))

      expect(stats_for(expense).previous_month_change_percentage).to eq(0)
    end
  end

  describe "#top_items" do
    let(:category) { create(:category, :expense, user: user, name: "Groceries") }

    before do
      amounts = { "Butcher" => 300, "Market" => 120, "Corner shop" => 60, "Bakery" => 20 }
      amounts.each do |name, amount|
        create(:entry, item: create(:item, category: category, name: name), amount: amount, date: Date.new(2026, 6, 5))
      end
      create(:entry, item: create(:item, category: category, name: "Last month"), amount: 900, date: Date.new(2026, 5, 5))
    end

    it "returns the month's three biggest items, largest first" do
      expect(stats_for(category).top_items.map { |item, amount| [item.name, amount] })
        .to eq([["Butcher", 300], ["Market", 120], ["Corner shop", 60]])
    end

    it "takes a wider limit" do
      expect(stats_for(category).top_items(4).keys.map(&:name)).to eq(["Butcher", "Market", "Corner shop", "Bakery"])
    end

    it "leaves out an item with nothing in the month" do
      create(:item, category: category, name: "Unused")

      expect(stats_for(category).top_items(10).keys.map(&:name)).not_to include("Unused")
    end
  end

  describe "#current_month_items" do
    let(:category) { create(:category, :expense, user: user, name: "Groceries") }
    let(:butcher) { create(:item, category: category, name: "Butcher") }
    let(:market) { create(:item, category: category, name: "Market") }

    before do
      create(:entry, item: butcher, amount: 100, date: Date.new(2026, 6, 4))
      create(:entry, item: butcher, amount: 50, date: Date.new(2026, 6, 20))
      create(:entry, item: market, amount: 40, date: Date.new(2026, 6, 8))
      create(:entry, item: market, amount: 900, date: Date.new(2026, 5, 8))
    end

    it "carries each item's total, its entries and the latest of them, biggest total first", :aggregate_failures do
      result = stats_for(category).current_month_items

      expect(result.keys.map(&:name)).to eq(["Butcher", "Market"])
      expect(result[butcher][:total_amount]).to eq(150)
      expect(result[butcher][:entry_count]).to eq(2)
      expect(result[butcher][:entries].size).to eq(2)
      expect(result[butcher][:latest_entry].date).to eq(Date.new(2026, 6, 20))
      expect(result[market][:total_amount]).to eq(40)
    end

    it "holds no key for an item with nothing in the month" do
      create(:item, category: category, name: "Unused")

      expect(stats_for(category).current_month_items.keys.map(&:name)).to eq(["Butcher", "Market"])
    end
  end
end
