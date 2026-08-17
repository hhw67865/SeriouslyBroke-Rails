# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budget, type: :model do
  describe "associations" do
    # `optional` at the association level, required by #must_belong_to_a_pool — so an owner-less
    # rule reports on `:base` ("must belong to a pool"), which is where the form renders it, rather
    # than as "Pool must exist" against a control the form does not offer.
    it { is_expected.to belong_to(:pool).optional }
    it { is_expected.to belong_to(:item).optional }

    # A RULE IS NOT OWNED BY A CATEGORY (plan 3, task 3). The column survives until Task 6 drops it,
    # so this asserts the RUBY support is gone rather than the schema.
    it "has no category association at all" do
      expect(described_class.reflect_on_association(:category)).to be_nil
    end
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
  end

  # ONE OWNER, AND IT IS A POOL. `#exactly_one_owner` used to police a pair — neither, and both —
  # because a rule could be owned by a category instead; the cap is deleted, so there is one owner
  # to have or lack. Both directions, because "must belong to a pool" is worth nothing if a rule
  # with a pool is also refused.
  describe "pool ownership" do
    let(:user) { create(:user) }
    let(:account) { create(:pool, :account, user: user) }
    let(:pool) { create(:pool, :budget_pool, user: user, account: account) }

    it "is valid attached to a pool" do
      expect(build(:budget, :rate, pool: pool)).to be_valid
    end

    it "rejects a rule attached to nothing", :aggregate_failures do
      budget = build(:budget, pool: nil)

      expect(budget).not_to be_valid
      expect(budget.errors[:base]).to include("must belong to a pool")
    end

    it "rejects a budget on an account pool", :aggregate_failures do
      budget = build(:budget, pool: account)

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
        anchor_date: nil,
        interval_months: nil,
        basis: :monthly
      )

      expect(budget).not_to be_valid
      expect(budget.errors[:interval_months]).to include("is required for a monthly rule with no due date")
    end

    it "rejects a non-positive interval", :aggregate_failures do
      budget = build(:budget, pool: pool, interval_months: 0, basis: :monthly)

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
    def pool_rule(*traits, **attrs) = build(:pool_budget, *traits, **attrs)

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

    # THE ONE ORDER HAZARD LEFT, in the direction that would misfire if the cascade were
    # rearranged: a per-period rule carries no interval either, so an interval-first cascade calls
    # every rate rule a one-off. The second hazard was a category cap, which carried no interval at
    # all and had to be answered before the same arm; the cap is deleted and the arm it needed with
    # it, so the example that pinned it is gone rather than rewritten against a shape that no
    # longer exists.
    it "never reads a per-period rule's blank interval as a one-off", :aggregate_failures do
      expect(pool_rule(:per_period_rate).interval_months).to be_nil
      expect(pool_rule(:per_period_rate).cadence).not_to eq(:one_off)
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
    let(:rule) { create(:pool_budget, :per_period_rate, amount: 300) }

    def raw_basis(record)
      Budget.connection.select_value(Budget.sanitize_sql_array(["SELECT basis FROM budgets WHERE id = ?", record.id]))
    end

    it "writes per_period as the integer 1" do
      expect(raw_basis(rule)).to eq(1)
    end

    it "writes monthly as the integer 0" do
      expect(raw_basis(create(:pool_budget, :rate, amount: 300))).to eq(0)
    end

    # Planted by SQL rather than by the enum writer, because a row created before the rename is
    # exactly what no Ruby-side spelling can produce today.
    it "reads a row planted at 1 as per_period", :aggregate_failures do
      planted = create(:pool_budget, :rate, amount: 300)
      described_class.connection.execute(described_class.sanitize_sql_array(["UPDATE budgets SET basis = 1 WHERE id = ?", planted.id]))

      planted.reload

      expect(planted).to be_basis_per_period
      expect(planted.basis).to eq("per_period")
    end
  end

  describe "#user" do
    let(:user) { create(:user) }

    it "comes from the pool" do
      pool = create(:pool, :budget_pool, user: user, account: create(:pool, :account, user: user))

      expect(build(:budget, :rate, pool: pool).user).to eq(user)
    end

    # The state the form re-renders in after a failed submission.
    it "is nil for an owner-less budget rather than raising" do
      expect(build(:budget, pool: nil).user).to be_nil
    end
  end

  # WHAT THIS SCOPE IS NOW, AND WHAT IT DELIBERATELY NO LONGER PINS. It used to be a union — a rule
  # owned by one of the user's categories OR by one of their pools — and three examples here held
  # that category arm in place, including one asserting `user.budgets` (the association through
  # categories) still reached a cap. Plan 3, task 3 deletes the cap, the association and the arm,
  # so those examples are deleted with the behaviour rather than left failing.
  #
  # Every example that remains is a pair: what the relation must REACH, and what it must not — a
  # scope that returns everything passes every "finds it" assertion ever written.
  describe ".for_user" do
    let(:user) { create(:user) }
    let(:pool) { create(:pool, :budget_pool, user: user, account: create(:pool, :account, user: user)) }

    let(:stranger) { create(:user) }
    let(:stranger_pool) do
      create(:pool, :budget_pool, user: stranger, account: create(:pool, :account, user: stranger))
    end

    let!(:pool_rule) { create(:budget, :rate, pool: pool) }
    let!(:stranger_pool_rule) { create(:budget, :rate, pool: stranger_pool) }

    it "returns the user's rules and nobody else's", :aggregate_failures do
      expect(described_class.for_user(user)).to contain_exactly(pool_rule)
      expect(described_class.for_user(user)).not_to include(stranger_pool_rule)
    end

    # What BudgetsController#set_budget does with it. Findability is the point of the
    # scope; raising on a stranger's id is the point of it still being a scope.
    it "finds a rule by id" do
      expect(described_class.for_user(user).find(pool_rule.id)).to eq(pool_rule)
    end

    it "raises RecordNotFound for another user's rule" do
      expect { described_class.for_user(user).find(stranger_pool_rule.id) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end

    # The Budget page groups these by account and by pool, so the scope has to stay composable.
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
      budget = build(:budget, :recurring, pool: pool, item: item)

      expect(budget).to be_valid
    end

    it "rejects an item from a category pointing at a different pool", :aggregate_failures do
      other_pool = create(:pool, :budget_pool, user: user, account: account)
      stray = create(:item, category: create(:category, :expense, user: user, pool: other_pool))
      budget = build(:budget, :recurring, pool: pool, item: stray)

      expect(budget).not_to be_valid
      expect(budget.errors[:item]).to include("must belong to a category in this pool")
    end

    it "rejects an item already claimed by another rule", :aggregate_failures do
      create(:budget, :recurring, pool: pool, item: item)
      budget = build(:budget, :recurring, pool: pool, item: item)

      expect(budget).not_to be_valid
      expect(budget.errors[:item]).to include("is already used by another rule")
    end

    it "does not treat item-less rules as claiming each other" do
      create(:budget, :recurring, pool: pool, item: nil)

      expect(build(:budget, :rate, pool: pool, item: nil)).to be_valid
    end

    it "does not report a conflict for an unsaved item" do
      unsaved = Item.new(name: "Maintenance", category: category)

      expect(build(:budget, :recurring, pool: pool, item: unsaved)).to be_valid
    end

    # THE UNSAVED-POOL BRANCH, AND AN HONEST NOTE ABOUT WHAT IT NO LONGER DISCRIMINATES. Against an
    # unsaved pool `pool_id` is nil, and the comparison in #item_must_belong_to_pool is between
    # OBJECTS for that reason: an id comparison equated every POOL-LESS category with this pool and
    # let a stray item in. A pool-less category is not a shape the app can hold any more
    # (`Category belongs_to :pool`), so this example exercises the branch but can no longer kill the
    # ids-instead-of-objects mutant — an item in another pool's category is refused either way.
    # Recorded rather than dressed up: the guard is still right, and the fixture that proved it is
    # gone with the data shape.
    it "rejects a stray item even when this rule's pool is unsaved", :aggregate_failures do
      unsaved_pool = build(:pool, :budget_pool, user: user, account: account)
      other_pool = create(:pool, :budget_pool, user: user, account: account)
      stray = create(:item, category: create(:category, :expense, user: user, pool: other_pool))
      budget = build(:budget, :recurring, pool: unsaved_pool, item: stray)

      expect(budget).not_to be_valid
      expect(budget.errors[:item]).to include("must belong to a category in this pool")
    end

    # The self-exclusion branch of `where.not(id: id)`. UUID PKs are assigned at
    # insert, so every other example here runs the id-is-nil branch; only a
    # persisted rule re-validating exercises this one. A wrong `where.not` would
    # make a saved budget permanently unsavable.
    it "lets a persisted rule keep the item it already owns" do
      budget = create(:budget, :recurring, pool: pool, item: item)

      expect(budget).to be_valid
    end
  end
end
