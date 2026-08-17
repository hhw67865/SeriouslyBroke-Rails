# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pool, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:categories).dependent(:nullify) }
    it { is_expected.to have_many(:items).through(:categories) }
    it { is_expected.to have_many(:entries).through(:items) }
    it { is_expected.to have_many(:override_entries).dependent(:nullify) }
  end

  describe "destroying a pool an entry overrode to" do
    let(:user) { create(:user) }
    let(:checking) { create(:pool, :account, user: user, name: "Checking") }
    let(:groceries) { create(:pool, :budget_pool, user: user, account: checking) }

    # `checking` holds `groceries`, so restrict_with_error stops its destroy before the
    # entries foreign key is ever reached. The override has to name a childless account
    # for these to exercise the foreign key at all.
    let(:second_account) { create(:pool, :account, user: user, name: "Second Account") }

    # Without the nullify the entries foreign key raises and the destroy action 500s.
    it "releases the override instead of raising", :aggregate_failures do
      category = create(:category, :expense, user: user, pool: groceries)
      entry = create(:entry, item: create(:item, category: category), pool: second_account)

      expect { second_account.destroy }.not_to raise_error
      expect(entry.reload.pool).to be_nil
    end

    it "leaves the entry resolving through its category" do
      category = create(:category, :expense, user: user, pool: groceries)
      entry = create(:entry, item: create(:item, category: category), pool: second_account)

      second_account.destroy

      expect(entry.reload.effective_pool).to eq(groceries)
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:target_amount) }
  end

  # The buffer is not a special object: it is the money in an account no envelope has
  # claimed. A target on an account is therefore the buffer target — a health marker,
  # never a cap — so the target must be optional AND permitted on the same pool type.
  describe "buffer target" do
    it "allows a target on an account, as the buffer target" do
      expect(build(:pool, :account, target_amount: 2_000)).to be_valid
    end

    it "still allows an account with no target" do
      expect(build(:pool, :account, target_amount: nil)).to be_valid
    end
  end

  describe "pool_type" do
    it { is_expected.to define_enum_for(:pool_type).with_values(account: 0, budget: 1, savings: 2).with_prefix }

    # ONE NOUN PER TYPE (2d whole-plan review, fix 2). Three screens held three different words for
    # one savings pool — "Envelope" in the category page's budget block, "Savings Pool" on its pool
    # card, "goal" on the entry form's impact card — while every one of them classified the pool
    # correctly. All three read this now, so the mapping is asserted here whole rather than three
    # times over in three system suites.
    it "names each kind of pool in the app's one vocabulary", :aggregate_failures do
      user = create(:user)
      checking = create(:pool, :account, user: user, name: "Checking")

      expect(checking.noun).to eq("buffer")
      expect(create(:pool, :budget_pool, user: user, account: checking).noun).to eq("envelope")
      expect(create(:pool, pool_type: :savings, user: user).noun).to eq("goal")
    end

    # `fetch`, so a fourth pool type is a loud failure here rather than three screens quietly
    # defaulting to "envelope".
    it "refuses to name a type it does not know" do
      expect { described_class::NOUNS.fetch("wallet") }.to raise_error(KeyError)
    end

    it "requires budget pools to name an account", :aggregate_failures do
      pool = build(:pool, :budget_pool, account: nil)

      expect(pool).not_to be_valid
      expect(pool.errors[:account]).to include("must be set for budget pools")
    end

    # TODO(plan-3): once the account backfill lands, savings pools must require an account
    # too and this example flips to `not_to be_valid`. It is deliberately red-on-tighten.
    it "exempts savings pools from the account requirement until Plan 3 backfills accounts" do
      expect(build(:pool, pool_type: :savings, account: nil)).to be_valid
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

    # The id form of this check reads `nil == nil` when neither side is saved, so both the
    # pool and its parent are built here — persisting either one makes the comparison
    # discriminate on its own and the example stops testing anything.
    it "requires the parent to belong to the same user when nothing is saved yet", :aggregate_failures do
      pool = build(:pool, :budget_pool, user: build(:user), account: build(:pool, :account, user: build(:user)))

      pool.valid?

      expect(pool.errors[:account]).to include("must belong to the same user")
    end

    it "accepts a parent owned by the same unsaved user" do
      owner = build(:user)

      expect(build(:pool, :budget_pool, user: owner, account: build(:pool, :account, user: owner))).to be_valid
    end
  end

  # `pools.priority` is NOT NULL with a default of 0, and the form renders it as an integer
  # input — so a user who clears the box submits "", which casts to nil and, with nothing in
  # the model to catch it, reached the database as a NotNullViolation 500. The non-negative
  # bound rides along: exposing the field made an out-of-range priority reachable too, and a
  # negative one silently outranks every pool the user meant to fund first.
  describe "priority" do
    it "rejects a blank priority", :aggregate_failures do
      pool = build(:pool, priority: nil)

      expect(pool).not_to be_valid
      expect(pool.errors[:priority]).to include("can't be blank")
    end

    it "rejects a negative priority", :aggregate_failures do
      pool = build(:pool, priority: -1)

      expect(pool).not_to be_valid
      expect(pool.errors[:priority]).to include("must be greater than or equal to 0")
    end

    # Guarded through the form's own casting: "1.5" in an integer column truncates silently,
    # so the check has to see the string the input actually submits.
    it "rejects a non-integer priority", :aggregate_failures do
      pool = build(:pool)
      pool.priority = "1.5"

      expect(pool).not_to be_valid
      expect(pool.errors[:priority]).to include("must be an integer")
    end

    it "accepts zero, the column default and the first funding slot" do
      expect(build(:pool, priority: 0)).to be_valid
    end

    it "accepts a positive priority" do
      expect(build(:pool, priority: 7)).to be_valid
    end
  end

  # `account_matches_pool_type` only ever looked upward, at the parent, and
  # `dependent: :restrict_with_error` guards destroy alone. Nothing looked down: an account
  # holding envelopes could be turned into an envelope itself, at which point HomePresenter
  # drops it from `accounts`, its children belong to no group `pools_for` can find, and
  # `orphan_pools` skips them because their `account_id` is not nil. The envelopes render
  # nowhere on Home while still counting toward the money the period has to cover.
  describe "changing what a pool is while pools live inside it" do
    let(:user) { create(:user) }
    let(:checking) { create(:pool, :account, user: user, name: "Checking") }
    let(:ally) { create(:pool, :account, user: user, name: "Ally") }

    it "refuses to turn an account holding pools into an envelope", :aggregate_failures do
      create(:pool, :budget_pool, user: user, account: checking, name: "Rent")

      checking.assign_attributes(pool_type: :budget, account: ally)

      expect(checking).not_to be_valid
      expect(checking.errors[:pool_type]).to include(
        "can't be changed while other pools sit inside this account — move them out first"
      )
    end

    it "refuses to turn an account holding pools into a savings goal" do
      create(:pool, :savings_pool, user: user, account: checking, name: "Vacation")

      checking.assign_attributes(pool_type: :savings, account: ally, target_amount: 500)

      expect(checking).not_to be_valid
    end

    it "permits the change once the pools inside have been moved out" do
      rent = create(:pool, :budget_pool, user: user, account: checking, name: "Rent")
      rent.update!(account: ally)

      checking.reload.assign_attributes(pool_type: :budget, account: ally)

      expect(checking).to be_valid
    end

    # The guard must not fire on every account there is — a bank account nobody has put an
    # envelope inside yet is exactly the one a user is most likely to have mislabelled.
    it "permits a childless account to become an envelope" do
      checking.assign_attributes(pool_type: :budget, account: ally)

      expect(checking).to be_valid
    end

    # An account keeping its own type is not changing what it is, so holding pools must not
    # stop an unrelated edit from saving.
    it "leaves an ordinary edit to an account holding pools alone" do
      create(:pool, :budget_pool, user: user, account: checking, name: "Rent")

      expect(checking.update(name: "Checking Renamed")).to be(true)
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

    # The envelope-native counterpart to the two examples above: same structure, funded the
    # way PoolCalculator#balance will read money once Plan 3 lands — income entries and
    # movements rather than savings-category entries. Both shapes must total the same.
    it "sums the account's own balance and its child pools, funded by movements", :aggregate_failures do
      checking, groceries, vacation = funded_account

      expect(checking.child_pools).to contain_exactly(groceries, vacation)
      expect(checking.calculator.current_balance).to eq(100) # 200 paid in, 100 moved out
      expect(groceries.calculator.current_balance).to eq(25) # 60 moved in, 35 spent
      expect(vacation.calculator.current_balance).to eq(40)
      expect(checking.total).to eq(165)
    end

    it "equals the pool's own balance when it has no child pools, funded by movements" do
      pool = create(:pool, :account, user: user)

      pay(pool, 70)

      expect(pool.total).to eq(70)
    end

    def pay(pool, amount)
      category = create(:category, :income, user: pool.user, pool: pool, name: "#{pool.name} Paycheck")
      create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
    end

    def funded_account
      checking = create(:pool, :account, user: user)
      groceries = create(:pool, :budget_pool, user: user, account: checking)
      vacation = create(:pool, :savings_pool, user: user, account: checking)
      pay(checking, 200)
      create(:pool_movement, from_pool: checking, to_pool: groceries, amount: 60)
      create(:pool_movement, from_pool: checking, to_pool: vacation, amount: 40)
      withdraw(groceries, 35)
      [checking, groceries, vacation]
    end
  end

  describe ".by_priority" do
    it "orders ascending by priority then name", :aggregate_failures do
      user = create(:user)
      account = create(:pool, :account, user: user)
      rent = create(:pool, :budget_pool, user: user, account: account, name: "Rent", priority: 1)
      car = create(:pool, :budget_pool, user: user, account: account, name: "Car", priority: 3)
      food = create(:pool, :budget_pool, user: user, account: account, name: "Food", priority: 2)

      expect(user.pools.budget_pools.by_priority.to_a).to eq([rent, food, car])
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
