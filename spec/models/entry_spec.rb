# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entry, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:item) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:amount) }
    it { is_expected.to validate_presence_of(:date) }
  end

  describe "money handling" do
    it "stores decimal values correctly" do
      entry = create(:entry, amount: 15.99)
      expect(entry.amount).to eq(15.99)
    end

    it "handles negative amounts" do
      entry = create(:entry, amount: -10.50)
      expect(entry.amount).to eq(-10.50)
    end

    it "handles zero amounts" do
      entry = create(:entry, amount: 0)
      expect(entry.amount).to eq(0.00)
    end
  end

  describe "delegations" do
    let(:user) { create(:user) }
    let(:category) { create(:category, user: user) }
    let(:item) { create(:item, category: category) }
    let(:entry) { create(:entry, item: item) }

    it "delegates category to item" do
      expect(entry.category).to eq(category)
    end

    it "delegates user to item" do
      expect(entry.user).to eq(user)
    end
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let!(:expense_entry) { create(:entry, :expense, user: user) }
    let!(:income_entry) { create(:entry, :income, user: user) }
    let!(:savings_entry) { create(:entry, :savings, user: user) }

    describe ".expenses" do
      it "returns only expense entries", :aggregate_failures do
        expect(described_class.expenses).to include(expense_entry)
        expect(described_class.expenses).not_to include(income_entry)
        expect(described_class.expenses).not_to include(savings_entry)
      end
    end

    describe ".income" do
      it "returns only income entries", :aggregate_failures do
        expect(described_class.incomes).to include(income_entry)
        expect(described_class.incomes).not_to include(expense_entry)
        expect(described_class.incomes).not_to include(savings_entry)
      end
    end

    describe ".savings" do
      it "returns only savings entries", :aggregate_failures do
        expect(described_class.savings).to include(savings_entry)
        expect(described_class.savings).not_to include(expense_entry)
        expect(described_class.savings).not_to include(income_entry)
      end
    end
  end
end
