# frozen_string_literal: true

require "rails_helper"

RSpec.describe Category, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:savings_pool).optional }
    it { is_expected.to have_many(:items).dependent(:destroy) }
    it { is_expected.to have_many(:entries).through(:items) }
    it { is_expected.to have_one(:budget).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:category_type) }

    context "when category has a budget" do
      let(:category) { create(:category, :income) }

      it "only allows budgets for expense categories", :aggregate_failures do
        budget = build(:budget, category: category)
        expect(budget).not_to be_valid
        expect(budget.errors[:category]).to include("must be an expense category")
      end
    end

    context "when changing category_type from expense to non-expense" do
      let(:category) { create(:category, :expense) }
      let!(:budget) { create(:budget, category: category) }

      it "destroys the budget when changing to income" do
        category.update!(category_type: :income)
        expect(Budget.exists?(budget.id)).to be false
      end

      it "destroys the budget when changing to savings" do
        category.update!(category_type: :savings)
        expect(Budget.exists?(budget.id)).to be false
      end

      it "keeps the budget when remaining as expense" do
        category.update!(name: "Updated Name")
        expect(Budget.exists?(budget.id)).to be true
      end
    end
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:category_type).with_values(expense: 0, income: 1, savings: 2) }
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let!(:expense_category) { create(:category, category_type: :expense, user: user) }
    let!(:income_category) { create(:category, category_type: :income, user: user) }
    let!(:savings_category) { create(:category, category_type: :savings, user: user, savings_pool: create(:savings_pool, user: user)) }

    describe ".expenses" do
      it "returns only expense categories" do
        expect(described_class.expenses).to contain_exactly(expense_category)
      end
    end

    describe ".incomes" do
      it "returns only income categories" do
        expect(described_class.incomes).to contain_exactly(income_category)
      end
    end

    describe ".savings" do
      it "returns only savings categories" do
        expect(described_class.savings).to contain_exactly(savings_category)
      end
    end
  end
end
