# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entry do
  let(:user) { create(:user) }
  let(:main) { create(:account, user: user) }
  let(:savings) { create(:account, user: user) }

  describe "validations", :aggregate_failures do
    it "needs a positive amount and a date" do
      expect(build(:entry, amount: 0)).not_to be_valid
      expect(build(:entry, amount: 12.5, date: nil)).not_to be_valid
      expect(build(:entry, amount: 12.5)).to be_valid
    end

    it "lets income land in one of the user's accounts, and spending only in main" do
      expect(build(:entry, :income, user: user, account: savings)).to be_valid
      expect(build(:entry, :income, user: user, account: create(:account))).not_to be_valid
      expect(build(:entry, :expense, user: user, account: savings)).not_to be_valid
      expect(build(:entry, :expense, user: user, account: nil)).to be_valid
    end
  end

  describe "#landing_account" do
    it "is the chosen account, else main", :aggregate_failures do
      main

      expect(create(:entry, :income, user: user, account: savings).landing_account).to eq(savings)
      expect(create(:entry, :income, user: user).landing_account).to eq(main)
    end
  end

  describe "scopes", :aggregate_failures do
    let(:groceries) { create(:category, user: user, name: "Groceries") }
    let(:bread) { create(:item, category: groceries, name: "Bread") }
    let(:milk) { create(:item, category: groceries, name: "Milk") }

    it "separates income from spending and tracked from untracked" do
      spend = create(:entry, item: bread)
      earn = create(:entry, :income, user: user)
      groceries.update!(tracked: false)

      expect(described_class.expenses).to eq([spend])
      expect(described_class.incomes).to eq([earn])
      expect(described_class.expenses.tracked).to be_empty
    end

    it "finds a rule's lane: its item, or the category's items that have no rule" do
      bread_rule = create(:rule, category: groceries, item: bread)
      whole_rule = create(:rule, category: groceries)
      on_bread = create(:entry, item: bread)
      on_milk = create(:entry, item: milk)

      expect(described_class.in_lane_of(bread_rule)).to eq([on_bread])
      expect(described_class.in_lane_of(whole_rule)).to eq([on_milk])
      expect(described_class.on_unruled_items).to eq([on_milk])
    end

    it "counts from a day" do
      old = create(:entry, item: bread, date: Date.new(2026, 1, 1))
      recent = create(:entry, item: bread, date: Date.new(2026, 6, 1))

      expect(described_class.since(Date.new(2026, 3, 1))).to eq([recent])
      expect(described_class.since(Date.new(2026, 1, 1))).to contain_exactly(old, recent)
    end
  end
end
