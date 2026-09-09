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

  describe ".merge" do
    it "moves every entry onto the target and deletes the sources", :aggregate_failures do
      target = create(:item, category: category)
      source = create(:item, :with_entries, category: category, entries_count: 2)

      described_class.merge(target: target, sources: [source])

      expect(target.entries.count).to eq(2)
      expect(described_class.exists?(source.id)).to be(false)
    end
  end

  describe "#move_to_category" do
    it "moves the item, or merges it into a same-named item there", :aggregate_failures do
      other = create(:category, user: category.user)
      item = create(:item, category: category, name: "Coffee")
      twin = create(:item, category: other, name: "coffee")
      create(:entry, item: item)

      item.move_to_category(other)

      expect(described_class.exists?(item.id)).to be(false)
      expect(twin.entries.count).to eq(1)
    end
  end
end
