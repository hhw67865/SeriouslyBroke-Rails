# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pool, type: :model do
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

  describe "pool_type" do
    it { is_expected.to define_enum_for(:pool_type).with_values(account: 0, budget: 1, savings: 2).with_prefix }

    it "requires budget pools to name an account", :aggregate_failures do
      pool = build(:pool, :budget_pool, account: nil)

      expect(pool).not_to be_valid
      expect(pool.errors[:account]).to include("must be set for budget and savings pools")
    end

    it "forbids account pools from naming an account", :aggregate_failures do
      user = create(:user)
      checking = create(:pool, :account, user: user)
      pool = build(:pool, :account, user: user, account: checking)

      expect(pool).not_to be_valid
      expect(pool.errors[:account]).to include("cannot be set on an account")
    end

    it "requires the parent to be an account pool", :aggregate_failures do
      user = create(:user)
      groceries = create(:pool, :budget_pool, user: user, account: create(:pool, :account, user: user))
      pool = build(:pool, :budget_pool, user: user, account: groceries)

      expect(pool).not_to be_valid
      expect(pool.errors[:account]).to include("must be an account")
    end

    it "requires the parent to belong to the same user", :aggregate_failures do
      pool = build(:pool, :budget_pool, user: create(:user), account: create(:pool, :account))

      expect(pool).not_to be_valid
      expect(pool.errors[:account]).to include("must belong to the same user")
    end
  end

  describe "name uniqueness" do
    it "rejects a second pool with the same name for the same user", :aggregate_failures do
      user = create(:user)
      create(:pool, user: user, name: "Emergency Fund")

      duplicate = build(:pool, user: user, name: "Emergency Fund")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include("has already been taken")
    end

    it "compares names case-insensitively" do
      user = create(:user)
      create(:pool, user: user, name: "Emergency Fund")

      expect(build(:pool, user: user, name: "emergency fund")).not_to be_valid
    end

    it "allows the same name under a different user" do
      create(:pool, user: create(:user), name: "Emergency Fund")

      expect(build(:pool, user: create(:user), name: "Emergency Fund")).to be_valid
    end
  end

  describe "#total" do
    let(:user) { create(:user) }

    # PoolCalculator#current_balance is (savings-category entries) - (expense-category
    # entries), both dated on or after the pool's start_date.
    def deposit(pool, amount)
      category = create(:category, :savings, user: pool.user, pool: pool, name: "#{pool.name} In")
      create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
    end

    def withdraw(pool, amount)
      category = create(:category, :expense, user: pool.user, pool: pool, name: "#{pool.name} Out")
      create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
    end

    it "sums the account's own balance and its child pools", :aggregate_failures do
      checking = create(:pool, :account, user: user)
      groceries = create(:pool, :budget_pool, user: user, account: checking)
      vacation = create(:pool, :savings_pool, user: user, account: checking)

      deposit(checking, 100) # unallocated cash
      deposit(groceries, 60)
      withdraw(groceries, 35) # groceries nets 25
      deposit(vacation, 40)

      expect(checking.child_pools).to contain_exactly(groceries, vacation)
      expect(groceries.calculator.current_balance).to eq(25)
      expect(checking.total).to eq(165)
    end

    it "equals the pool's own balance when it has no child pools" do
      pool = create(:pool, :account, user: user)

      deposit(pool, 70)

      expect(pool.total).to eq(70)
    end
  end

  describe ".by_priority" do
    it "orders ascending by priority then name", :aggregate_failures do
      user = create(:user)
      account = create(:pool, :account, user: user)
      rent = create(:pool, :budget_pool, user: user, account: account, name: "Rent", priority: 1)
      car = create(:pool, :budget_pool, user: user, account: account, name: "Car", priority: 3)
      food = create(:pool, :budget_pool, user: user, account: account, name: "Food", priority: 2)

      expect(user.pools.budgets.by_priority.to_a).to eq([rent, food, car])
    end
  end

  describe "#timeline_entries" do
    it "includes contributions and withdrawals after start_date", :aggregate_failures do
      user = create(:user)
      pool = create(:pool, user: user, start_date: Date.new(2025, 6, 1))
      savings_item = create(:item, category: create(:category, :savings, user: user, pool: pool))
      expense_item = create(:item, category: create(:category, :expense, user: user, pool: pool))

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
      pool = create(:pool, user: user, name: "Emergency Fund")

      expect(pool.categories.count).to eq(0)
    end

    it "does not create any categories when both flags are '0'" do
      pool = create(
        :pool,
        user: user,
        name: "Emergency Fund",
        create_expense_category: "0",
        create_savings_category: "0"
      )

      expect(pool.categories.count).to eq(0)
    end

    it "creates an expense category when create_expense_category is truthy", :aggregate_failures do
      pool = create(:pool, user: user, name: "Emergency Fund", create_expense_category: "1")
      category = pool.categories.first

      expect(pool.categories.count).to eq(1)
      expect(category.name).to eq("Emergency Fund Expense")
      expect(category.category_type).to eq("expense")
      expect(category.user).to eq(user)
    end

    it "creates a savings category when create_savings_category is truthy", :aggregate_failures do
      pool = create(:pool, user: user, name: "Emergency Fund", create_savings_category: "1")
      category = pool.categories.first

      expect(pool.categories.count).to eq(1)
      expect(category.name).to eq("Emergency Fund Savings")
      expect(category.category_type).to eq("savings")
      expect(category.user).to eq(user)
    end

    it "creates both categories when both flags are truthy", :aggregate_failures do
      pool = create(:pool, user: user, name: "Emergency Fund", create_expense_category: "1", create_savings_category: "1")

      expect(pool.categories.count).to eq(2)
      expect(pool.categories.pluck(:name)).to contain_exactly("Emergency Fund Expense", "Emergency Fund Savings")
      expect(pool.categories.pluck(:category_type)).to contain_exactly("expense", "savings")
    end

    it "appends ' 2' when the base name is taken" do
      create(:category, user: user, name: "Test Pool Expense", category_type: :expense)

      pool = create(
        :pool,
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
        :pool,
        user: user,
        name: "Test Pool",
        create_expense_category: "1"
      )

      expect(pool.categories.first.name).to eq("Test Pool Expense 3")
    end

    it "treats collisions as case-insensitive" do
      create(:category, user: user, name: "test pool expense", category_type: :expense)

      pool = create(
        :pool,
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
        :pool,
        user: user,
        name: "Emergency Fund",
        create_expense_category: "1"
      )

      expect(pool.categories.first.name).to eq("Emergency Fund Expense")
    end
  end
end
