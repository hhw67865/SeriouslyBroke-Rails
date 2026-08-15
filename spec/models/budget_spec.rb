# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budget, type: :model do
  describe "associations" do
    # Dual-mode: a budget owns exactly one of category/pool, so neither is
    # required at the association level. `exactly_one_owner` enforces the pair.
    it { is_expected.to belong_to(:category).optional }
    it { is_expected.to belong_to(:pool).optional }
    it { is_expected.to belong_to(:item).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:amount) }

    describe "category type validation" do
      let(:income_category) { create(:category, :income) }

      it "requires category to be an expense category", :aggregate_failures do
        budget = build(:budget, category: income_category)
        expect(budget).not_to be_valid
        expect(budget.errors[:category]).to include("must be an expense category")
      end
    end

    describe "pool mutual exclusivity" do
      let(:user) { create(:user) }
      let(:pool) { create(:pool, user: user) }
      let(:expense_category) { create(:category, :expense, user: user, pool: pool) }

      it "rejects budget on a category linked to a savings pool", :aggregate_failures do
        budget = build(:budget, category: expense_category)
        expect(budget).not_to be_valid
        expect(budget.errors[:category]).to include("cannot have a budget when linked to a savings pool")
      end
    end
  end

  describe "prorated flag" do
    it "defaults to false" do
      expect(build(:budget).prorated).to be(false)
    end

    it "accepts true when explicitly set" do
      expect(build(:budget, :prorated).prorated).to be(true)
    end
  end

  describe "pool mode" do
    let(:user) { create(:user) }
    let(:account) { create(:pool, :account, user: user) }
    let(:pool) { create(:pool, :budget_pool, user: user, account: account) }

    it "is valid attached to a pool with no category" do
      expect(build(:budget, :rate, pool: pool, category: nil)).to be_valid
    end

    it "rejects a budget attached to neither", :aggregate_failures do
      budget = build(:budget, pool: nil, category: nil)

      expect(budget).not_to be_valid
      expect(budget.errors[:base]).to include("must belong to either a category or a pool")
    end

    it "rejects a budget attached to both", :aggregate_failures do
      budget = build(:budget, pool: pool, category: create(:category, :expense, user: user))

      expect(budget).not_to be_valid
      expect(budget.errors[:base]).to include("cannot belong to both a category and a pool")
    end

    it "rejects a budget on an account pool", :aggregate_failures do
      budget = build(:budget, pool: account, category: nil)

      expect(budget).not_to be_valid
      expect(budget.errors[:pool]).to include("cannot be an account")
    end
  end

  describe "the four valid shapes" do
    let(:user) { create(:user) }
    let(:pool) { create(:pool, :budget_pool, user: user, account: create(:pool, :account, user: user)) }

    it "accepts a per-paycheck rate rule" do
      budget = build(
        :budget,
        pool: pool,
        category: nil,
        anchor_date: nil,
        interval_months: nil,
        basis: :per_paycheck
      )

      expect(budget).to be_valid
    end

    it "accepts a monthly rate rule" do
      budget = build(
        :budget,
        pool: pool,
        category: nil,
        anchor_date: nil,
        interval_months: 1,
        basis: :monthly
      )

      expect(budget).to be_valid
    end

    it "accepts a recurring obligation" do
      budget = build(
        :budget,
        pool: pool,
        category: nil,
        anchor_date: Date.new(2026, 6, 1),
        interval_months: 6,
        basis: :monthly
      )

      expect(budget).to be_valid
    end

    it "accepts a one-time obligation" do
      budget = build(
        :budget,
        pool: pool,
        category: nil,
        anchor_date: Date.new(2026, 6, 1),
        interval_months: nil,
        basis: :monthly
      )

      expect(budget).to be_valid
    end

    it "rejects a per-paycheck rule with an anchor date", :aggregate_failures do
      budget = build(
        :budget,
        pool: pool,
        category: nil,
        anchor_date: Date.new(2026, 6, 1),
        interval_months: nil,
        basis: :per_paycheck
      )

      expect(budget).not_to be_valid
      expect(budget.errors[:basis]).to include("per-paycheck rules cannot have a due date or interval")
    end

    it "rejects a monthly rule with neither an anchor nor an interval", :aggregate_failures do
      budget = build(
        :budget,
        pool: pool,
        category: nil,
        anchor_date: nil,
        interval_months: nil,
        basis: :monthly
      )

      expect(budget).not_to be_valid
      expect(budget.errors[:interval_months]).to include("is required for a monthly rule with no due date")
    end

    it "rejects a non-positive interval", :aggregate_failures do
      budget = build(:budget, pool: pool, category: nil, interval_months: 0, basis: :monthly)

      expect(budget).not_to be_valid
      expect(budget.errors[:interval_months]).to include("must be greater than 0")
    end
  end

  describe ":pool_budget factory" do
    # Guards the interface later tasks build on: every shape trait must produce a
    # valid record under `build`, where associations are not yet persisted.
    it "builds a valid rate rule by default" do
      expect(build(:pool_budget)).to be_valid
    end

    it "builds a valid record for every shape trait", :aggregate_failures do
      [:rate, :per_paycheck_rate, :recurring, :one_time].each do |trait|
        expect(build(:pool_budget, trait)).to be_valid
      end
    end
  end

  describe "item attribution" do
    let(:user) { create(:user) }
    let(:account) { create(:pool, :account, user: user) }
    let(:pool) { create(:pool, :budget_pool, user: user, account: account) }
    let(:category) { create(:category, :expense, user: user, pool: pool) }
    let(:item) { create(:item, category: category) }

    it "accepts an item whose category points at this pool" do
      budget = build(:budget, :recurring, pool: pool, category: nil, item: item)

      expect(budget).to be_valid
    end

    it "rejects an item from a category pointing at a different pool", :aggregate_failures do
      other_pool = create(:pool, :budget_pool, user: user, account: account)
      stray = create(:item, category: create(:category, :expense, user: user, pool: other_pool))
      budget = build(:budget, :recurring, pool: pool, category: nil, item: stray)

      expect(budget).not_to be_valid
      expect(budget.errors[:item]).to include("must belong to a category in this pool")
    end

    it "rejects an item already claimed by another rule", :aggregate_failures do
      create(:budget, :recurring, pool: pool, category: nil, item: item)
      budget = build(:budget, :recurring, pool: pool, category: nil, item: item)

      expect(budget).not_to be_valid
      expect(budget.errors[:item]).to include("is already used by another rule")
    end

    it "does not treat item-less rules as claiming each other" do
      create(:budget, :recurring, pool: pool, category: nil, item: nil)

      expect(build(:budget, :rate, pool: pool, category: nil, item: nil)).to be_valid
    end

    it "does not report a conflict for an unsaved item" do
      unsaved = Item.new(name: "Maintenance", category: category)

      expect(build(:budget, :recurring, pool: pool, category: nil, item: unsaved)).to be_valid
    end
  end
end
