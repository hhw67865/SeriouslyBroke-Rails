# frozen_string_literal: true

require "rails_helper"

RSpec.describe SavingsPool, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:categories).dependent(:nullify) }
    it { is_expected.to have_many(:items).through(:categories) }
    it { is_expected.to have_many(:entries).through(:items) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:target_amount) }
  end

  describe "#timeline_entries" do
    it "includes contributions and withdrawals after start_date", :aggregate_failures do
      user = create(:user)
      pool = create(:savings_pool, user: user, start_date: Date.new(2025, 6, 1))
      savings_item = create(:item, category: create(:category, :savings, user: user, savings_pool: pool))
      expense_item = create(:item, category: create(:category, :expense, user: user, savings_pool: pool))

      contribution = create(:entry, item: savings_item, date: Date.new(2025, 7, 1))
      withdrawal = create(:entry, item: expense_item, date: Date.new(2025, 8, 1))
      before_start = create(:entry, item: savings_item, date: Date.new(2025, 5, 1))

      results = pool.timeline_entries

      expect(results).to include(contribution, withdrawal)
      expect(results).not_to include(before_start)
    end
  end

  describe "auto-created categories on create" do
    let(:user) { create(:user) }

    it "does not create any categories when both flags are nil" do
      pool = create(:savings_pool, user: user, name: "Emergency Fund")

      expect(pool.categories.count).to eq(0)
    end

    it "does not create any categories when both flags are '0'" do
      pool = create(
        :savings_pool,
        user: user,
        name: "Emergency Fund",
        create_expense_category: "0",
        create_savings_category: "0"
      )

      expect(pool.categories.count).to eq(0)
    end

    it "creates an expense category when create_expense_category is truthy", :aggregate_failures do
      pool = create(:savings_pool, user: user, name: "Emergency Fund", create_expense_category: "1")
      category = pool.categories.first

      expect(pool.categories.count).to eq(1)
      expect(category.name).to eq("Emergency Fund Expense")
      expect(category.category_type).to eq("expense")
      expect(category.user).to eq(user)
    end

    it "creates a savings category when create_savings_category is truthy", :aggregate_failures do
      pool = create(:savings_pool, user: user, name: "Emergency Fund", create_savings_category: "1")
      category = pool.categories.first

      expect(pool.categories.count).to eq(1)
      expect(category.name).to eq("Emergency Fund Savings")
      expect(category.category_type).to eq("savings")
      expect(category.user).to eq(user)
    end

    it "creates both categories when both flags are truthy", :aggregate_failures do
      pool = create(:savings_pool, user: user, name: "Emergency Fund", create_expense_category: "1", create_savings_category: "1")

      expect(pool.categories.count).to eq(2)
      expect(pool.categories.pluck(:name)).to contain_exactly("Emergency Fund Expense", "Emergency Fund Savings")
      expect(pool.categories.pluck(:category_type)).to contain_exactly("expense", "savings")
    end

    it "appends ' 2' when the base name is taken" do
      create(:category, user: user, name: "Test Pool Expense", category_type: :expense)

      pool = create(
        :savings_pool,
        user: user,
        name: "Test Pool",
        create_expense_category: "1"
      )

      expect(pool.categories.first.name).to eq("Test Pool Expense 2")
    end

    it "appends ' 3' when base name and ' 2' are both taken" do
      create(:category, user: user, name: "Test Pool Expense", category_type: :expense)
      create(:category, user: user, name: "Test Pool Expense 2", category_type: :expense)

      pool = create(
        :savings_pool,
        user: user,
        name: "Test Pool",
        create_expense_category: "1"
      )

      expect(pool.categories.first.name).to eq("Test Pool Expense 3")
    end

    it "treats collisions as case-insensitive" do
      create(:category, user: user, name: "test pool expense", category_type: :expense)

      pool = create(
        :savings_pool,
        user: user,
        name: "Test Pool",
        create_expense_category: "1"
      )

      expect(pool.categories.first.name).to eq("Test Pool Expense 2")
    end

    it "only checks collisions against the same user's categories" do
      other_user = create(:user)
      create(:category, user: other_user, name: "Emergency Fund Expense", category_type: :expense)

      pool = create(
        :savings_pool,
        user: user,
        name: "Emergency Fund",
        create_expense_category: "1"
      )

      expect(pool.categories.first.name).to eq("Emergency Fund Expense")
    end
  end
end
