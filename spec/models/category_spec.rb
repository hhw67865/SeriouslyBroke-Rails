# frozen_string_literal: true

require "rails_helper"

RSpec.describe Category, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:pool) }
    it { is_expected.to have_many(:items).dependent(:destroy) }
    it { is_expected.to have_many(:entries).through(:items) }
    # `have_one(:budget)` IS DELETED WITH THE ASSOCIATION (plan 3, task 4). A Budget belongs to a
    # POOL; `budgets.category_id` is nil on every row and Task 6 drops the column.
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:category_type) }

    # EVERY CATEGORY NAMES ITS LANE (plan 3 decision 3). Both directions, because the whole point of
    # the line is that the nil is no longer expressible: a nil `pool_id` used to be documented as
    # "the user's default account" and `PoolBalanceLedger::ENTRY_POOL_ID` resolved it to nowhere, so
    # such a category's spending left the pool tree while `Σ pools == bank truth` claimed otherwise.
    context "when the category names no pool" do
      let(:user) { create(:user) }

      it "is refused", :aggregate_failures do
        category = build(:category, :expense, user: user, pool: nil)

        expect(category).not_to be_valid
        expect(category.errors[:pool]).to include("must exist")
      end

      it "is accepted the moment a pool is named" do
        expect(build(:category, :expense, user: user, pool: create(:pool, :account, user: user))).to be_valid
      end
    end
  end

  # TWO VALUES, AND `savings: 2` IS RETIRED RATHER THAN RENUMBERED (plan 3, task 5). This is the
  # planted literal that says integer 2 is not reused: a third type added later takes 3, and this
  # example fails if anybody puts one at 2.
  describe "enums" do
    it { is_expected.to define_enum_for(:category_type).with_values(expense: 0, income: 1) }
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let(:pool) { create(:pool, user: user) }
    let!(:expense_category) { create(:category, category_type: :expense, user: user) }
    let!(:pool_covered_category) { create(:category, category_type: :expense, user: user, pool: pool) }
    let!(:income_category) { create(:category, category_type: :income, user: user) }

    describe ".expenses" do
      it "returns only expense categories" do
        expect(described_class.expenses).to contain_exactly(expense_category, pool_covered_category)
      end
    end

    describe ".incomes" do
      it "returns only income categories" do
        expect(described_class.incomes).to contain_exactly(income_category)
      end
    end

    # `.savings` IS GONE with the enum value (plan 3, task 5), and its absence is asserted rather
    # than left to a NoMethodError somebody reads as a typo.
    it "does not answer .savings at all" do
      expect(described_class).not_to respond_to(:savings)
    end
  end

  # THE RATE DETECTOR'S POPULATION, and after plan 3 it is exactly the account-pointed set: an
  # account IS the buffer (§7.1), so an expense category pointing at one is spending nothing
  # reserves. The "no pool at all" half this predicate used to admit is not a shape any more —
  # `belongs_to :pool` refuses it — and the `#budgetable?` reader it used to diverge from is gone
  # with the category cap.
  describe "#buffer_funded?" do
    let(:user) { create(:user) }
    let(:checking) { create(:pool, :account, user: user, name: "Checking") }
    let(:groceries) { create(:pool, :budget_pool, user: user, account: checking) }

    it "is true for a category pointing at an account" do
      expect(create(:category, :expense, user: user, pool: checking)).to be_buffer_funded
    end

    it "is false once an envelope holds the spending" do
      expect(create(:category, :expense, user: user, pool: groceries)).not_to be_buffer_funded
    end

    it "is false for an income category, whichever pool it names" do
      expect(create(:category, :income, user: user, pool: checking)).not_to be_buffer_funded
    end
  end

  describe "income categories" do
    let(:user) { create(:user) }
    let(:checking) { create(:pool, :account, user: user) }

    it "may point at an account pool" do
      expect(build(:category, :income, user: user, pool: checking)).to be_valid
    end

    it "may not point at a budget pool", :aggregate_failures do
      groceries = create(:pool, :budget_pool, user: user, account: checking)
      category = build(:category, :income, user: user, pool: groceries)

      expect(category).not_to be_valid
      expect(category.errors[:pool]).to include("must be an account for income categories")
    end

    it "may not point at a savings pool", :aggregate_failures do
      vacation = create(:pool, :savings_pool, user: user, account: checking)
      category = build(:category, :income, user: user, pool: vacation)

      expect(category).not_to be_valid
      expect(category.errors[:pool]).to include("must be an account for income categories")
    end

    it "does not constrain expense categories, which may point at a budget pool" do
      groceries = create(:pool, :budget_pool, user: user, account: checking)

      expect(build(:category, :expense, user: user, pool: groceries)).to be_valid
    end

    it "does not constrain expense categories, which may point at a savings goal" do
      vacation = create(:pool, :savings_pool, user: user, account: checking)

      expect(build(:category, :expense, user: user, pool: vacation)).to be_valid
    end
  end

  describe "#effective_pool" do
    let(:user) { create(:user) }
    let(:checking) { create(:pool, :account, user: user) }

    it "uses the category's own pool when set" do
      groceries = create(:pool, :budget_pool, user: user, account: checking)
      user.update!(default_account: checking)

      expect(create(:category, :expense, user: user, pool: groceries).effective_pool).to eq(groceries)
    end

    # THE FALLBACK THIS METHOD USED TO PROMISE, NOW REFUSED — Task 8's fix round.
    #
    # `pool || user&.default_account` read well and was kept by nothing: every balance in the app
    # resolves an entry through `COALESCE(entries.pool_id, categories.pool_id)`
    # (`PoolBalanceLedger::ENTRY_POOL_ID`), which has no default account in it. Two readers of one
    # question, and `Σ pools == your bank balance` turned on which one you asked.
    #
    # Asserted in BOTH directions, which is the only way this is worth anything: the reader says
    # nil, AND the nominated account's own balance is measured and does not contain the $60. A
    # method agreeing with a ledger is a claim about the ledger, so the ledger is asked.
    it "ignores the user's default account, because the ledger does", :aggregate_failures do
      user.update!(default_account: checking)
      groceries = create(:pool, :budget_pool, user: user, account: checking)
      category = create(:category, :expense, user: user, pool: groceries)
      create(:entry, item: create(:item, category: category), amount: 60, date: Date.current)

      expect(category.effective_pool).to eq(groceries)
      expect(groceries.calculator.balance).to eq(-60)
      expect(checking.calculator.balance).to eq(0)
    end

    it "uses the category's own pool when the user has no default account" do
      groceries = create(:pool, :budget_pool, user: user, account: checking)

      expect(create(:category, :expense, user: user, pool: groceries).effective_pool).to eq(groceries)
    end

    # Matches the guard Entry#effective_pool needs on its own link in the chain.
    it "is nil rather than raising when the category has no user" do
      expect(described_class.new(name: "Unfiled").effective_pool).to be_nil
    end
  end
end
