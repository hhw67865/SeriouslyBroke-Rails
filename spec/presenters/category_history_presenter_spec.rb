# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategoryHistoryPresenter do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }

  let(:oldest_period) { Date.new(2026, 7, 24)..Date.new(2026, 8, 6) }
  let(:middle_period) { Date.new(2026, 8, 7)..Date.new(2026, 8, 20) }
  let(:latest_period) { Date.new(2026, 8, 21)..Date.new(2026, 9, 3) }

  def spend(item, amount, on:) = create(:entry, item: item, amount: amount, date: on)

  it "has no periods, no rows and no figures with no history at all", :aggregate_failures do
    presenter = described_class.new(groceries, today: today)

    expect(presenter.periods).to eq([])
    expect(presenter.rows).to eq([])
    expect(presenter.everything_else.pattern.count).to eq(0)
    expect(presenter.everything_else_per_period).to be_nil
  end

  describe "with three periods of history" do
    let(:bread) { create(:item, category: groceries, name: "Bread") }
    let(:milk) { create(:item, category: groceries, name: "Milk") }

    before do
      spend(bread, 10, on: oldest_period.first)
      spend(bread, 20, on: middle_period.first)
      spend(bread, 30, on: latest_period.first)
      spend(milk, 5, on: middle_period.first)
    end

    it "hands each item a pattern read from its own entries, newest first", :aggregate_failures do
      presenter = described_class.new(groceries, today: today)

      bread_row = presenter.rows.find { |row| row.item == bread }
      milk_row = presenter.rows.find { |row| row.item == milk }

      expect(bread_row.pattern).to be_a(PaymentPattern)
      expect(bread_row.pattern.last_paid).to eq([latest_period.first, 30.to_d])
      expect(bread_row.pattern.count).to eq(3)
      expect(milk_row.pattern.last_paid).to eq([middle_period.first, 5.to_d])
    end

    it "lists items alphabetically" do
      presenter = described_class.new(groceries, today: today)

      expect(presenter.rows.map { |row| row.item.name }).to eq(["Bread", "Milk"])
    end

    it "sums everything else's per-period figure from items with no rule of their own", :aggregate_failures do
      create(:rule, :rate, category: groceries, item: bread, amount: 100, starts_on: Date.new(2026, 1, 1))

      presenter = described_class.new(groceries, today: today)

      expect(presenter.everything_else.pattern.last_paid).to eq([middle_period.first, 5.to_d])
      expect(presenter.everything_else_per_period).to eq(1.67)
    end

    it "sets ruled_by for an item ruled by another rule, and nil for the rule being edited", :aggregate_failures do
      rule = create(:rule, :rate, category: groceries, item: bread, amount: 100, starts_on: Date.new(2026, 1, 1))

      without_rule = described_class.new(groceries, today: today)
      editing_rule = described_class.new(groceries, today: today, rule: rule)

      expect(without_rule.rows.find { |row| row.item == bread }.ruled_by).to eq(rule)
      expect(editing_rule.rows.find { |row| row.item == bread }.ruled_by).to be_nil
    end

    it "excludes another whole-category rule from everything_else, but not the one being edited", :aggregate_failures do
      catch_all = create(:rule, :rate, category: groceries, amount: 200, starts_on: Date.new(2026, 1, 1))

      without_rule = described_class.new(groceries, today: today)
      editing_rule = described_class.new(groceries, today: today, rule: catch_all)

      expect(without_rule.everything_else.ruled_by).to eq(catch_all)
      expect(editing_rule.everything_else.ruled_by).to be_nil
    end

    it "draws the picker: everything else first and checked, each item, then a new item", :aggregate_failures do
      presenter = described_class.new(groceries, today: today)
      rows = presenter.picker_rows("")

      expect(rows.map(&:kind)).to eq([:everything, :item, :item, :new])
      expect(rows.map(&:checked)).to eq([true, false, false, false])
      expect(presenter.selected_name("")).to eq("Everything else in Groceries")
      expect(presenter.selected_name(bread.id)).to eq("Bread")
      expect(presenter.selected_name("new")).to eq("the new item")
    end

    it "pre-selects nothing when everything else is already ruled", :aggregate_failures do
      catch_all = create(:rule, :rate, category: groceries, amount: 200, starts_on: Date.new(2026, 1, 1))
      presenter = described_class.new(groceries, today: today)

      expect(presenter.picker_rows("").first).to have_attributes(disabled: true, checked: false, caption: "already has a rule")
      expect(presenter.selected_name("")).to eq("what you pick above")
      expect(described_class.new(groceries, today: today, rule: catch_all).picker_rows("").first.checked).to be(true)
    end

    it "gives the new-item row no history to show", :aggregate_failures do
      presenter = described_class.new(groceries, today: today)
      new_row = presenter.picker_rows("").last

      expect(new_row).to have_attributes(last_paid_words: nil, usually_words: nil, per_period: nil)
    end
  end

  describe "an item paid yearly" do
    let(:membership) { create(:item, category: groceries, name: "Membership") }

    before do
      spend(membership, 95, on: Date.new(2024, 9, 7))
      spend(membership, 95, on: Date.new(2025, 9, 7))
    end

    it "reads the yearly cadence off the picker row", :aggregate_failures do
      presenter = described_class.new(groceries, today: today)
      row = presenter.picker_rows("").find { |r| r.dom_id == "rule_item_#{membership.id}" }

      expect(row.last_paid_words).to eq("Sep 7, 2025 · $95.00")
      expect(row.usually_words).to eq("$95.00 every 12 months")
      expect(row.per_period).to eq((95.to_d * (365.25 / 365) / user.periods_per_year).round(2))
    end
  end

  describe "an item that has lapsed" do
    let(:parking) { create(:item, category: groceries, name: "Parking") }

    before do
      spend(parking, 10, on: today - 192)
      spend(parking, 10, on: today - 162)
      spend(parking, 10, on: today - 131)
    end

    it "marks the picker row lapsed and drops its per-period figure", :aggregate_failures do
      presenter = described_class.new(groceries, today: today)
      row = presenter.picker_rows("").find { |r| r.dom_id == "rule_item_#{parking.id}" }

      expect(row.usually_words).to eq("was $10.00 monthly")
      expect(row.per_period).to be_nil
    end

    it "flags the row stale, except when it is the one picked", :aggregate_failures do
      presenter = described_class.new(groceries, today: today)

      expect(presenter.picker_rows("").find { |r| r.dom_id == "rule_item_#{parking.id}" }.stale).to be(true)
      expect(presenter.picker_rows(parking.id).find { |r| r.dom_id == "rule_item_#{parking.id}" }.stale).to be(false)
      expect(presenter.picker_rows("").map(&:stale)).to include(false)
    end
  end
end
