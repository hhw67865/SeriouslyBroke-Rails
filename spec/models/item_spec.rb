# frozen_string_literal: true

require "rails_helper"

RSpec.describe Item do
  let(:category) { create(:category) }

  it "needs a name, unique in its category ignoring case", :aggregate_failures do
    create(:item, category: category, name: "Coffee")

    expect(build(:item, category: category, name: "coffee")).not_to be_valid
    expect(build(:item, category: category, name: "")).not_to be_valid
  end

  it "takes its rule with it when deleted" do
    item = create(:item, category: category)
    create(:rule, category: category, item: item)

    expect { item.destroy! }.to change(Rule, :count).by(-1)
  end

  describe "#last_entry" do
    it "is the newest entry by date, then by created_at" do
      item = create(:item, category: category)
      create(:entry, item: item, date: Date.new(2026, 6, 1))
      newest = create(:entry, item: item, date: Date.new(2026, 6, 10))

      expect(item.last_entry).to eq(newest)
    end

    it "is nil for an item with no entries" do
      expect(create(:item, category: category).last_entry).to be_nil
    end
  end

  describe ".merge" do
    it "moves every entry onto the target and deletes the sources", :aggregate_failures do
      target = create(:item, category: category)
      source = create(:item, :with_entries, category: category, entries_count: 2)

      described_class.merge(target: target, sources: [source])

      expect(target.entries.count).to eq(2)
      expect(described_class.exists?(source.id)).to be(false)
    end

    it "moves a source's rule onto a target that has none" do
      target = create(:item, category: category)
      source = create(:item, category: category)
      rule = create(:rule, category: category, item: source)

      described_class.merge(target: target, sources: [source])

      expect(rule.reload.item).to eq(target)
    end

    it "refuses when both items carry a rule, and says the target has one", :aggregate_failures do
      target = create(:item, category: category)
      source = create(:item, category: category, name: "Bread")
      create(:rule, category: category, item: target)
      create(:rule, category: category, item: source)

      expect(described_class.merge(target: target, sources: [source])).to be(false)
      expect(described_class.exists?(source.id)).to be(true)
      expect(source.errors[:base]).to eq(["Bread #{Item::RULE_ALREADY_THERE}"])
    end

    it "refuses two ruled sources, and names them both", :aggregate_failures do
      target = create(:item, category: category)
      sources = [create(:item, category: category, name: "Bread"), create(:item, category: category, name: "Milk")]
      sources.each { |source| create(:rule, category: category, item: source) }

      expect(described_class.merge(target: target, sources: sources)).to be(false)
      expect(sources.map { |source| described_class.exists?(source.id) }).to all(be(true))
      expect(sources.first.errors[:base]).to eq(["#{Item::RULES_COLLIDE} — Bread and Milk both carry one"])
    end
  end

  describe "#move_to_category" do
    let(:other) { create(:category, user: category.user) }

    it "moves the item, or merges it into a same-named item there", :aggregate_failures do
      item = create(:item, category: category, name: "Coffee")
      twin = create(:item, category: other, name: "coffee")
      create(:entry, item: item)

      item.move_to_category(other)

      expect(described_class.exists?(item.id)).to be(false)
      expect(twin.entries.count).to eq(1)
    end

    it "takes the item's rule with it", :aggregate_failures do
      item = create(:item, category: category, name: "Coffee")
      rule = create(:rule, category: category, item: item)

      expect(item.move_to_category(other)).to be(true)
      expect(rule.reload.category).to eq(other)
      expect(item.reload.category).to eq(other)
    end

    it "refuses to carry a rule into an income category", :aggregate_failures do
      income = create(:category, :income, user: category.user)
      item = create(:item, category: category, name: "Coffee")
      create(:rule, category: category, item: item)

      expect(item.move_to_category(income)).to be(false)
      expect(item.errors[:base].first).to include(Item::RULE_NEEDS_AN_EXPENSE)
      expect(item.reload.category).to eq(category)
    end
  end
end
