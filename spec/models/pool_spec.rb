# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pool, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:categories).dependent(:restrict_with_error) }
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

    # A BARE `Pool.new` IS AN ENVELOPE NOW (plan 3, task 6 flipped `pools.pool_type`'s column
    # default from 2 to 1), and `target_amount` is required on GOALS alone — so the bare subject
    # no longer exercises this rule at all and the matcher needs a goal to ask about. The default
    # flip is asserted directly in "the column defaults" below.
    it { expect(build(:pool, :savings_pool)).to validate_presence_of(:target_amount) }
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
      expect(pool.errors[:account]).to include("must be set for envelopes and goals")
    end

    # THE TODO(plan-3) FLIPPED, EXACTLY AS IT SAID IT WOULD. This example read
    # "exempts savings pools from the account requirement until Plan 3 backfills accounts" and
    # asserted `be_valid`; the cutover houses every goal and verifies it did, so the exemption is
    # gone and the example is its own opposite. Deliberately red-on-tighten, and it was.
    it "requires savings pools to name an account too", :aggregate_failures do
      pool = build(:pool, pool_type: :savings, account: nil)

      expect(pool).not_to be_valid
      expect(pool.errors[:account]).to include("must be set for envelopes and goals")
    end

    # The other direction of the same rule, and the shape the tightening must NOT refuse.
    it "accepts a goal that names one" do
      expect(build(:pool, :savings_pool)).to be_valid
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

  # ===============================================================================================
  # THE DATABASE'S OWN HALF OF THESE RULES (plan 3, task 6, spec §7a).
  #
  # EVERY EXAMPLE HERE WRITES PAST THE MODEL — `save!(validate: false)` and `update_column` — and
  # that is the entire point. The model already refuses all four shapes and its refusals are
  # asserted above; what these prove is that the refusal survives a writer that never asked it: a
  # console session, an `update_all`, a fixture, a future controller. A constraint tested through
  # the validation stack is a test of the validation stack.
  #
  # Both directions on both constraints: the violating write raises, and the conforming write of
  # the same shape lands. A CHECK constraint that refused everything would pass a one-sided test.
  # ===============================================================================================
  describe "the constraints in the schema" do
    let(:user) { create(:user) }
    let(:checking) { create(:pool, :account, user: user, name: "Checking") }

    describe "pools_account_matches_pool_type" do
      # rubocop:disable Rails/SkipsModelValidations -- writing past the model IS the subject here
      it "refuses an envelope whose account is cleared past the model" do
        envelope = create(:pool, :budget_pool, user: user, account: checking, name: "Groceries")

        expect { envelope.update_column(:account_id, nil) }
          .to raise_error(ActiveRecord::StatementInvalid, /pools_account_matches_pool_type/)
      end

      it "refuses a goal whose account is cleared past the model" do
        goal = create(:pool, :savings_pool, user: user, account: checking, name: "Holiday")

        expect { goal.update_column(:account_id, nil) }
          .to raise_error(ActiveRecord::StatementInvalid, /pools_account_matches_pool_type/)
      end

      # The other end of the equality. `(pool_type = 0) = (account_id IS NULL)` is one expression
      # refusing two opposite mistakes, and an OR of two ANDs could have shipped with one half.
      it "refuses an account that names a parent past the model" do
        second = create(:pool, :account, user: user, name: "Savings Account")

        expect { second.update_column(:account_id, checking.id) }
          .to raise_error(ActiveRecord::StatementInvalid, /pools_account_matches_pool_type/)
      end
      # rubocop:enable Rails/SkipsModelValidations

      it "accepts the two shapes it exists to allow", :aggregate_failures do
        envelope = build(:pool, :budget_pool, user: user, account: checking, name: "Groceries")
        account = build(:pool, :account, user: user, name: "Savings Account")

        expect { envelope.save!(validate: false) }.not_to raise_error
        expect { account.save!(validate: false) }.not_to raise_error
      end
    end

    describe "index_pools_on_user_id_and_lower_name" do
      it "refuses a duplicate name past the model" do
        create(:pool, :savings_pool, user: user, account: checking, name: "Emergency Fund")
        twin = build(:pool, :savings_pool, user: user, account: checking, name: "Emergency Fund")

        expect { twin.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
      end

      # THE FUNCTIONAL HALF, and the reason the index is on `lower(name)` rather than on the
      # column: the model's uniqueness is case-insensitive, so an index on the raw name would
      # accept a pair the model refuses and guard nothing the model does not already guard.
      it "refuses a name differing only in case past the model" do
        create(:pool, :savings_pool, user: user, account: checking, name: "Emergency Fund")
        twin = build(:pool, :savings_pool, user: user, account: checking, name: "emergency fund")

        expect { twin.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
      end

      it "accepts the same name under a different user, which is what the scope is for" do
        create(:pool, :savings_pool, user: user, account: checking, name: "Emergency Fund")
        stranger = create(:user)

        expect { create(:pool, :savings_pool, user: stranger, name: "Emergency Fund") }.not_to raise_error
      end
    end

    # THE COLUMN DEFAULT, FLIPPED 2 -> 1 (§7a). `savings` was the default because the table was
    # `savings_pools` and every row in it was one; an envelope is the ordinary pool now. Asserted
    # on a bare `Pool.new` rather than through the factory, which sets the type explicitly — the
    # default is only ever met by a writer that names no type.
    describe "the column defaults" do
      it "opens a typeless pool as an envelope" do
        expect(described_class.new.pool_type).to eq("budget")
      end
    end
  end

  describe "#total" do
    let(:user) { create(:user) }

    # PoolCalculator#current_balance is (savings-category entries) - (expense-category
    # entries), both dated on or after the pool's start_date.
    def withdraw(pool, amount)
      category = create(:category, :expense, user: pool.user, pool: pool, name: "#{pool.name} Out")
      create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
    end

    # THE SAVINGS-FUNDED TWINS OF THESE TWO ARE DELETED (plan 3, task 5). They built the same two
    # structures with a `deposit` helper that made a SAVINGS category and paid an entry into it,
    # and asserted the same totals — a pairing that existed to prove the envelope-native shape
    # below totalled the same as the savings-entry one. There is no savings-entry shape any more,
    # so the pair is one example twice and the surviving half is the one that describes the app.
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

  # THE POOL'S HISTORY, POST-CUTOVER. This replaces `#timeline_entries`, which OR'd savings-typed
  # entries with expense-typed ones and, once the savings category was gone, could only ever return
  # the second half — an empty list on every goal, beside a "Total Contributions" tile printing
  # real money.
  describe "#timeline" do
    let(:user) { create(:user) }
    let(:checking) { create(:pool, :account, user: user, name: "Checking") }
    let(:goal) { create(:pool, :savings_pool, user: user, account: checking, start_date: Date.new(2025, 6, 1)) }

    it "lists movements in and out and the spending of its own categories", :aggregate_failures do
      spending = create(:item, name: "Flights", category: create(:category, :expense, user: user, pool: goal, name: "Trip"))
      create(:pool_movement, from_pool: checking, to_pool: goal, amount: 200, date: Date.new(2025, 7, 1))
      create(:pool_movement, from_pool: goal, to_pool: checking, amount: 30, date: Date.new(2025, 7, 15))
      create(:entry, item: spending, amount: 45, date: Date.new(2025, 8, 1))

      rows = goal.timeline(limit: 8)

      expect(rows.map(&:label)).to eq(["Spent", "Moved out", "Moved in"])
      expect(rows.map(&:sign)).to eq([-1, -1, 1])
      expect(rows.map { |row| row.amount.to_i }).to eq([45, 30, 200])
      expect(rows.map(&:name)).to eq(["Flights", "Checking", "Checking"])
      expect(rows.map(&:detail)).to eq(["Trip", "moved by hand", "moved by hand"])
    end

    # BOTH DIRECTIONS ON THE CUTOFF. `#timeline_entries` bounded its rows at `start_date` while
    # `PoolCalculator#balance` ignores it, so a pre-start row counted toward the balance without
    # appearing in the list explaining it. The list is now the rows behind #contributions and
    # #withdrawals, and those have no cutoff either.
    it "includes rows from before start_date, because the balance beside it does" do
      create(:pool_movement, from_pool: checking, to_pool: goal, amount: 90, date: Date.new(2025, 5, 1))

      expect(goal.timeline(limit: 8).map { |row| row.amount.to_i }).to eq([90])
    end

    it "takes the newest `limit` rows across both sources", :aggregate_failures do
      5.times { |n| create(:pool_movement, from_pool: checking, to_pool: goal, amount: 10, date: Date.new(2025, 7, 1) + n.days) }
      spending = create(:item, category: create(:category, :expense, user: user, pool: goal, name: "Trip"))
      create(:entry, item: spending, amount: 45, date: Date.new(2025, 9, 1))

      rows = goal.timeline(limit: 2)

      expect(rows.size).to eq(2)
      expect(rows.map(&:label)).to eq(["Spent", "Moved in"])
    end

    it "is empty for a pool nothing has reached" do
      expect(create(:pool, :budget_pool, user: user, account: checking).timeline(limit: 8)).to be_empty
    end

    # THE LIST OBEYS THE START-DATE RULE BECAUSE THE TILES ABOVE IT DO (main-account spec §3). This
    # is the same argument the movement example above makes in the other direction: the timeline is
    # built out of exactly the rows `#contributions` and `#withdrawals` add up, so a row the ledger
    # has relocated to main cannot still be listed under the envelope explaining a figure it is no
    # longer part of. BOTH SIDES ARE ASSERTED on one fixture — the row leaves one list and arrives
    # in the other — because an example that only watched it vanish would pass against a reader
    # that had simply dropped it.
    it "sends a pre-start entry to the main account's list and off the envelope's", :aggregate_failures do
      user.update!(default_account: checking)
      envelope = create(:pool, :budget_pool, user: user, account: checking, name: "Trips", start_date: Date.new(2025, 6, 1))
      spending = create(:item, name: "Flights", category: create(:category, :expense, user: user, pool: envelope, name: "Trip"))
      create(:entry, item: spending, amount: 45, date: Date.new(2025, 5, 31))

      expect(envelope.timeline(limit: 8)).to be_empty
      expect(checking.timeline(limit: 8).map(&:name)).to eq(["Flights"])
    end
  end

  describe "auto-created categories on create" do
    let(:user) { create(:user) }

    it "does not create any categories when the flag is nil" do
      pool = create(:pool, user: user, name: "Emergency Fund")

      expect(pool.categories.count).to eq(0)
    end

    it "does not create any categories when the flag is '0'" do
      pool = create(:pool, user: user, name: "Emergency Fund", create_expense_category: "0")

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

    # `create_savings_category` IS GONE (plan 3, task 5) — the second checkbox on the pool form
    # minted a SAVINGS category. Asserted absent rather than left to a NoMethodError, and asserted
    # INERT as a param too: the attribute is unwritable, so a stale form post cannot make one.
    it "has no savings-category flag at all", :aggregate_failures do
      pool = build(:pool, user: user, name: "Emergency Fund")

      expect(pool).not_to respond_to(:create_savings_category)
      expect { pool.create_savings_category = "1" }.to raise_error(NoMethodError)
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
