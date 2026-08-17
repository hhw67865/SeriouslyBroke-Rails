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

    # A negative amount is not merely wrong-looking: PoolCalculator's waterfall does
    # `remaining.clamp(0, budget.amount)`, and `clamp(0, negative)` raises. A zero amount
    # is a rule that demands nothing, which is what deleting it is for.
    describe "amount sign" do
      it "rejects a negative amount", :aggregate_failures do
        budget = build(:budget, amount: -50)

        expect(budget).not_to be_valid
        expect(budget.errors[:amount]).to include("must be greater than 0")
      end

      it "rejects a zero amount" do
        expect(build(:budget, amount: 0)).not_to be_valid
      end
    end

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

    it "accepts a per-period rate rule" do
      budget = build(
        :budget,
        pool: pool,
        category: nil,
        anchor_date: nil,
        interval_months: nil,
        basis: :per_period
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

    it "rejects a per-period rule with an anchor date", :aggregate_failures do
      budget = build(
        :budget,
        pool: pool,
        category: nil,
        anchor_date: Date.new(2026, 6, 1),
        interval_months: nil,
        basis: :per_period
      )

      expect(budget).not_to be_valid
      expect(budget.errors[:basis]).to include("per-period rules cannot have a due date or interval")
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

    # The fifth shape. Not a row in the table: a multi-month interval with no
    # anchor is row 3 missing its due date, and the calculator would read the due
    # date as the end of this month and demand all N months of money at once.
    it "rejects a multi-month interval with no anchor date", :aggregate_failures do
      budget = build(
        :budget,
        pool: pool,
        category: nil,
        anchor_date: nil,
        interval_months: 6,
        basis: :monthly
      )

      expect(budget).not_to be_valid
      expect(budget.errors[:interval_months]).to include("must be 1 for a monthly rule with no due date")
    end

    # The other combination that was unasserted in both directions: the existing
    # per-period rejection only exercises the anchor_date half of that guard.
    it "rejects a per-period rule with an interval", :aggregate_failures do
      budget = build(
        :budget,
        pool: pool,
        category: nil,
        anchor_date: nil,
        interval_months: 6,
        basis: :per_period
      )

      expect(budget).not_to be_valid
      expect(budget.errors[:basis]).to include("per-period rules cannot have a due date or interval")
    end
  end

  # THE FOUR SHAPES ABOVE, READ BACK OUT AS ONE SYMBOL. `HomeHelper#pool_rule_label` and
  # `BudgetPageHelper#budget_rule_basis` each held a copy of this cascade, in the same
  # hazard-ordered sequence; the classification lives here now and the two helpers keep only
  # their own words. Every arm is asserted, because a helper reduced to a lookup can no longer
  # catch a misclassification itself.
  describe "#cadence" do
    def pool_rule(*traits, **attrs) = build(:pool_budget, *traits, category: nil, **attrs)

    it "calls a per-period rate rule per-period" do
      expect(pool_rule(:per_period_rate).cadence).to eq(:per_period)
    end

    it "calls an anchorless monthly rate rule monthly" do
      expect(pool_rule(:rate).cadence).to eq(:monthly)
    end

    it "calls an anchored one-month rule monthly" do
      expect(pool_rule(interval_months: 1, anchor_date: Date.new(2026, 3, 1)).cadence).to eq(:monthly)
    end

    it "calls a multi-month rule every_n rather than naming the number" do
      expect(pool_rule(interval_months: 6, anchor_date: Date.new(2026, 3, 1)).cadence).to eq(:every_n)
    end

    it "calls an interval-less anchored rule a one-off" do
      expect(pool_rule(:one_time).cadence).to eq(:one_off)
    end

    # The two order hazards, each in the direction that would misfire if the cascade were
    # rearranged. A per-period rule carries no interval either, so an interval-first cascade
    # calls every rate rule a one-off; a category cap carries no interval at all
    # (#shape_must_be_valid only runs in pool mode) and would fall into the same arm.
    it "never reads a per-period rule's blank interval as a one-off", :aggregate_failures do
      expect(pool_rule(:per_period_rate).interval_months).to be_nil
      expect(pool_rule(:per_period_rate).cadence).not_to eq(:one_off)
    end

    it "calls a category-mode cap monthly rather than a one-off", :aggregate_failures do
      budget = build(:budget, category: build(:category, :expense), amount: 200)

      expect(budget.interval_months).to be_nil
      expect(budget.cadence).to eq(:monthly)
    end
  end

  # THE RENAME IS RUBY-SIDE ONLY. `per_paycheck` became `per_period` with no migration, so the
  # stored mapping `{ monthly: 0, per_period: 1 }` has to be exactly what it was — a rule written
  # under the old name still sits in the column as the integer 1, and every one of them would read
  # as `monthly` if the rename had re-numbered the enum. The two directions are asserted separately
  # because either alone can pass on a consistently-wrong mapping: the write asserts the integer
  # the new name produces, and the raw-SQL plant asserts what a row written before the rename now
  # reads as.
  describe "the stored basis mapping" do
    let(:rule) { create(:pool_budget, :per_period_rate, category: nil, amount: 300) }

    def raw_basis(record)
      Budget.connection.select_value(Budget.sanitize_sql_array(["SELECT basis FROM budgets WHERE id = ?", record.id]))
    end

    it "writes per_period as the integer 1" do
      expect(raw_basis(rule)).to eq(1)
    end

    it "writes monthly as the integer 0" do
      expect(raw_basis(create(:pool_budget, :rate, category: nil, amount: 300))).to eq(0)
    end

    # Planted by SQL rather than by the enum writer, because a row created before the rename is
    # exactly what no Ruby-side spelling can produce today.
    it "reads a row planted at 1 as per_period", :aggregate_failures do
      planted = create(:pool_budget, :rate, category: nil, amount: 300)
      described_class.connection.execute(described_class.sanitize_sql_array(["UPDATE budgets SET basis = 1 WHERE id = ?", planted.id]))

      planted.reload

      expect(planted).to be_basis_per_period
      expect(planted.basis).to eq("per_period")
    end
  end

  describe "#user" do
    let(:user) { create(:user) }

    it "comes from the category in category mode" do
      budget = build(:budget, category: create(:category, :expense, user: user))

      expect(budget.user).to eq(user)
    end

    it "comes from the pool in pool mode" do
      pool = create(:pool, :budget_pool, user: user, account: create(:pool, :account, user: user))

      expect(build(:budget, :rate, pool: pool, category: nil).user).to eq(user)
    end

    # The state the form re-renders in after a failed submission.
    it "is nil for an owner-less budget rather than raising" do
      expect(build(:budget, pool: nil, category: nil).user).to be_nil
    end
  end

  # The reader `User has_many :budgets, through: :categories` cannot be. Every example here
  # is a pair: what the relation must REACH, and what it must not — a scope that returns
  # everything passes every "finds it" assertion ever written.
  describe ".for_user" do
    let(:user) { create(:user) }
    let(:pool) { create(:pool, :budget_pool, user: user, account: create(:pool, :account, user: user)) }

    let(:stranger) { create(:user) }
    let(:stranger_pool) do
      create(:pool, :budget_pool, user: stranger, account: create(:pool, :account, user: stranger))
    end

    let!(:category_rule) { create(:budget, category: create(:category, :expense, user: user)) }
    let!(:pool_rule) { create(:budget, :rate, pool: pool, category: nil) }
    let!(:stranger_category_rule) { create(:budget, category: create(:category, :expense, user: stranger)) }
    let!(:stranger_pool_rule) { create(:budget, :rate, pool: stranger_pool, category: nil) }

    it "returns both modes and nobody else's" do
      expect(described_class.for_user(user)).to contain_exactly(category_rule, pool_rule)
    end

    # The half the association already reached, asserted so the union cannot be
    # "pool-mode instead of" rather than "pool-mode as well as".
    it "still reaches the category-mode rules the association reached" do
      expect(user.budgets).to contain_exactly(category_rule)
    end

    it "reaches a pool-mode rule the association misses", :aggregate_failures do
      expect(described_class.for_user(user)).to include(pool_rule)
      expect(user.budgets).not_to include(pool_rule)
    end

    it "excludes another user's rules in both modes", :aggregate_failures do
      expect(described_class.for_user(user)).not_to include(stranger_category_rule)
      expect(described_class.for_user(user)).not_to include(stranger_pool_rule)
    end

    # What BudgetsController#set_budget does with it. Findability is the point of the
    # scope; raising on a stranger's id is the point of it still being a scope.
    it "finds a pool-mode rule by id" do
      expect(described_class.for_user(user).find(pool_rule.id)).to eq(pool_rule)
    end

    it "raises RecordNotFound for another user's category-mode rule" do
      expect { described_class.for_user(user).find(stranger_category_rule.id) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end

    it "raises RecordNotFound for another user's pool-mode rule" do
      expect { described_class.for_user(user).find(stranger_pool_rule.id) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end

    # `.or` refuses relations of differing structure, so the scope has to stay composable
    # for the Budget page — which groups these by account and by pool.
    it "chains with further conditions" do
      expect(described_class.for_user(user).where(pool_id: pool.id)).to contain_exactly(pool_rule)
    end
  end

  describe ":pool_budget factory" do
    # Guards the interface later tasks build on: every shape trait must produce a
    # valid record under `build`, where associations are not yet persisted.
    it "builds a valid rate rule by default" do
      expect(build(:pool_budget)).to be_valid
    end

    it "builds a valid record for every shape trait", :aggregate_failures do
      [:rate, :per_period_rate, :recurring, :one_time].each do |trait|
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

    # Against an unsaved pool `pool_id` is nil, so an id comparison equated every
    # pool-less category with this pool and let a stray item in.
    it "rejects an item from a pool-less category even when the pool is unsaved", :aggregate_failures do
      unsaved_pool = build(:pool, :budget_pool, user: user, account: account)
      orphan = create(:item, category: create(:category, :expense, user: user, pool: nil))
      budget = build(:budget, :recurring, pool: unsaved_pool, category: nil, item: orphan)

      expect(budget).not_to be_valid
      expect(budget.errors[:item]).to include("must belong to a category in this pool")
    end

    # The self-exclusion branch of `where.not(id: id)`. UUID PKs are assigned at
    # insert, so every other example here runs the id-is-nil branch; only a
    # persisted rule re-validating exercises this one. A wrong `where.not` would
    # make a saved budget permanently unsavable.
    it "lets a persisted rule keep the item it already owns" do
      budget = create(:budget, :recurring, pool: pool, category: nil, item: item)

      expect(budget).to be_valid
    end
  end
end
