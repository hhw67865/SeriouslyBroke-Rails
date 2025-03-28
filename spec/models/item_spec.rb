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

  describe "enums" do
    it { is_expected.to define_enum_for(:frequency).with_values(one_time: 0, monthly: 1, yearly: 2) }
  end

  describe "delegation" do
    let(:user) { create(:user) }
    let(:category) { create(:category, user: user) }
    let(:item) { create(:item, category: category) }

    it "delegates user to category" do
      expect(item.user).to eq(user)
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
