# frozen_string_literal: true

require "rails_helper"

RSpec.describe Item, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:category) }
    it { is_expected.to have_many(:entries).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
  end

  describe "delegation" do
    let(:user) { create(:user) }
    let(:category) { create(:category, user: user) }
    let(:item) { create(:item, category: category) }

    it "delegates user to category" do
      expect(item.user).to eq(user)
    end
  end

  describe ".merge" do
    let(:user) { create(:user) }
    let(:category) { create(:category, user: user) }
    let(:target) { create(:item, name: "Target", category: category) }
    let(:first_source) { create(:item, name: "Source A", category: category) }
    let(:second_source) { create(:item, name: "Source B", category: category) }

    before do
      create_list(:entry, 2, item: target)
      create_list(:entry, 3, item: first_source)
      create(:entry, item: second_source)
    end

    it "transfers all entries to target and destroys sources", :aggregate_failures do
      described_class.merge(target: target, sources: [first_source, second_source])

      expect(target.entries.count).to eq(6)
      expect(described_class.exists?(first_source.id)).to be(false)
      expect(described_class.exists?(second_source.id)).to be(false)
    end
  end

  describe "#move_to_category" do
    let(:user) { create(:user) }
    let(:source_category) { create(:category, name: "Source", user: user) }
    let(:target_category) { create(:category, name: "Target", user: user) }

    it "moves item to target category" do
      item = create(:item, name: "My Item", category: source_category)

      item.move_to_category(target_category)

      expect(item.reload.category).to eq(target_category)
    end

    it "merges with existing same-named item in target category", :aggregate_failures do
      item = create(:item, name: "Groceries", category: source_category)
      create_list(:entry, 2, item: item)
      existing = create(:item, name: "Groceries", category: target_category)
      create(:entry, item: existing)

      item.move_to_category(target_category)

      expect(described_class.exists?(item.id)).to be(false)
      expect(existing.entries.count).to eq(3)
    end
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let(:categories) do
      {
        expense: create(:category, category_type: :expense, user: user),
        income: create(:category, category_type: :income, user: user),
        savings: create(:category, category_type: :savings, user: user, savings_pool: create(:savings_pool, user: user))
      }
    end

    let!(:expense_item) { create(:item, category: categories[:expense]) }
    let!(:income_item) { create(:item, category: categories[:income]) }
    let!(:savings_item) { create(:item, category: categories[:savings]) }

    describe ".expenses" do
      it "returns only items from expense categories" do
        expect(described_class.expenses).to contain_exactly(expense_item)
      end
    end

    describe ".incomes" do
      it "returns only items from income categories" do
        expect(described_class.incomes).to contain_exactly(income_item)
      end
    end

    describe ".savings" do
      it "returns only items from savings categories" do
        expect(described_class.savings).to contain_exactly(savings_item)
      end
    end
  end
end
