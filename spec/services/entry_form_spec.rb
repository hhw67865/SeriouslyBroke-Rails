# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntryForm do
  let(:user) { create(:user) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let(:bread) { create(:item, category: groceries, name: "Bread") }

  def build_form(params, entry: Entry.new, category_id: nil) = described_class.new(user, entry, params, category_id: category_id)

  it "evaluates a formula in the amount and writes the chosen item", :aggregate_failures do
    form = build_form({ amount: "12.5 * 2", date: "2026-09-05", description: "loaves", item_id: bread.id })

    expect(form.save).to be(true)
    expect(form.entry).to have_attributes(amount: 25, date: Date.new(2026, 9, 5), item: bread)
  end

  it "creates the item by name in the given category, reusing a same-named one", :aggregate_failures do
    fresh = build_form({ amount: "3", date: "2026-09-05", item_id: "", item_attributes: { name: "Milk" } }, category_id: groceries.id)
    expect(fresh.save).to be(true)
    expect(fresh.entry.item).to have_attributes(name: "Milk", category: groceries)

    again = build_form({ amount: "4", date: "2026-09-06", item_id: "new", item_attributes: { name: "milk" } }, category_id: groceries.id)
    expect(again.save).to be(true)
    expect(again.entry.item).to eq(fresh.entry.item)
    expect(groceries.items.count).to eq(1)
  end

  it "keeps a bad formula as typed so the model refuses it", :aggregate_failures do
    form = build_form({ amount: "abc", date: "2026-09-05", item_id: bread.id })

    expect(form.save).to be(false)
    expect(form.errors[:amount]).to be_present
  end

  it "edits an existing entry in place", :aggregate_failures do
    entry = create(:entry, item: bread, amount: 10)
    form = build_form({ amount: "15" }, entry: entry)

    expect(form.save).to be(true)
    expect(entry.reload.amount).to eq(15)
  end
end
