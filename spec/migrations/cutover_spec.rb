# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260817000000_cutover_to_envelope_budgeting")

# THE ONLY MIGRATION IN THE CONVERSION THAT REWRITES USER DATA, exercised against the shapes a
# real database holds rather than the shape the demo happens to have: three caps (one reusing a
# same-named envelope, one blocked by a same-named GOAL), an account-less goal, a savings category
# with two items and three entries, unpooled income AND unpooled expense, a user with nothing at
# all, a user whose flagged default account is not their first, and a user whose only pool already
# holds the name the migration wants for their account.
#
# EVERY EXPECTED FIGURE IS A PLANTED LITERAL, and the one that matters most is asserted in both
# directions: `Σ pools` is measured BEFORE the run — where it disagrees with the bank, which is
# the whole reason this migration exists — and after, where it must agree. That after-figure is
# read through the APP's calculators. The migration verifies itself in raw SQL precisely so these
# two ways of asking stay independent; an example that re-ran the migration's own query would
# only prove the query equals itself.
#
# The sabotage block is the point of the exercise. A verifier never shown failing proves nothing.
#
# The path is `spec/migrations/cutover_spec.rb` because the plan names that file; the cop wants it
# named after the migration class, which would put a timestamp-shaped filename in a plan document.
# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe CutoverToEnvelopeBudgeting do
  # Four worlds, planted in creation order — the migration walks users by `created_at`, and the
  # sabotage examples below name which user is expected to raise first.
  #
  # Hashes rather than a `let!` per record: the fixture is 20-odd rows and the alternative is 20
  # memoized helpers in one scope, which is a spec nobody can hold in their head.
  let!(:wild) { plant_wild }
  let!(:settled) { plant_settled }
  let!(:bare) { create(:user, email: "bare@example.com") }
  let!(:namesake) { plant_namesake }

  # ---------------------------------------------------------------------------------------------
  # The planted worlds
  # ---------------------------------------------------------------------------------------------

  # One account, an account-less goal, an envelope and a goal that already hold names three capped
  # categories want, and a savings category with items and entries.
  def plant_wild
    user = create(:user, email: "wild@example.com")
    pools = wild_pools(user)
    categories = wild_categories(user, pools)
    wild_entries(categories)

    { user: user }.merge(pools).merge(categories).merge(wild_caps(categories))
  end

  def wild_pools(user)
    checking = create(:pool, :account, user: user, name: "Checking")
    {
      checking: checking,
      holiday: create(:pool, user: user, name: "Holiday Fund", account: nil, target_amount: 2_000.00),
      utilities_pool: create(
        :pool,
        user: user,
        name: "Utilities",
        pool_type: :budget,
        account: checking,
        target_amount: nil
      ),
      rent_goal: create(:pool, user: user, name: "Rent", account: checking, target_amount: 5_000.00)
    }
  end

  def wild_categories(user, pools)
    {
      groceries: create(:category, :expense, user: user, name: "Groceries", pool: nil),
      utilities: create(:category, :expense, user: user, name: "Utilities", pool: nil),
      rent: create(:category, :expense, user: user, name: "Rent", pool: nil),
      salary: create(:category, :income, user: user, name: "Salary", pool: nil),
      coffee: create(:category, :expense, user: user, name: "Coffee", pool: nil),
      vacation: create(:category, :savings, user: user, name: "Vacation", pool: pools[:holiday])
    }
  end

  def wild_caps(categories)
    {
      groceries_cap: create(:budget, category: categories[:groceries], amount: 400.00),
      utilities_cap: create(:budget, category: categories[:utilities], amount: 150.00),
      rent_cap: create(:budget, category: categories[:rent], amount: 1_200.00)
    }
  end

  def wild_entries(categories)
    wild_income_entries(categories)
    wild_expense_entries(categories)
    wild_savings_entries(categories)
  end

  # Money in from the world — the positive half of bank truth.
  def wild_income_entries(categories)
    paycheck = item_in(categories[:salary], "Paycheck")
    entry_on(paycheck, 3_000.00, 7, 1)
    entry_on(paycheck, 500.00, 7, 15)
  end

  # Money out to it — the negative half.
  def wild_expense_entries(categories)
    entry_on(item_in(categories[:groceries], "Supermarket"), 220.00, 7, 2)
    entry_on(item_in(categories[:groceries], "Corner Shop"), 80.00, 7, 9)
    entry_on(item_in(categories[:utilities], "Electric"), 90.00, 7, 3)
    entry_on(item_in(categories[:rent], "Landlord"), 1_200.00, 7, 1)
    entry_on(item_in(categories[:coffee], "Cafe"), 12.50, 7, 4)
    entry_on(item_in(categories[:coffee], "Kiosk"), 7.25, 7, 11)
  end

  # Money that never crossed it — the shape the migration re-records as transfers.
  def wild_savings_entries(categories)
    flights = item_in(categories[:vacation], "Flights")
    entry_on(flights, 100.00, 6, 10)
    entry_on(flights, 250.00, 6, 20)
    entry_on(item_in(categories[:vacation], "Hotel"), 50.00, 7, 5)
  end

  def savings_moments
    [Time.zone.local(2026, 6, 10, 9), Time.zone.local(2026, 6, 20, 9), Time.zone.local(2026, 7, 5, 9)]
  end

  # Two accounts, and the FLAGGED default is the second — so "reuse the flag" and "take the first
  # account" answer differently here, which is the only way to tell which rule ran.
  def plant_settled
    user = create(:user, email: "settled@example.com")
    old_account = create(:pool, :account, user: user, name: "Old Account")
    main = create(:pool, :account, user: user, name: "Main")
    user.update!(default_account: main)
    dining = create(:category, :expense, user: user, name: "Dining", pool: nil)
    bonus = create(:category, :income, user: user, name: "Bonus", pool: nil)
    entry_on(item_in(dining, "Bistro"), 45.00, 7, 6)
    entry_on(item_in(bonus, "Q2 Bonus"), 200.00, 7, 7)

    { user: user, old_account: old_account, main: main, dining: dining, bonus: bonus }
  end

  # No account at all, and a GOAL already sitting on the name the migration reaches for.
  def plant_namesake
    user = create(:user, email: "namesake@example.com")
    goal = create(:pool, user: user, name: "Checking", account: nil, target_amount: 300.00)
    books = create(:category, :expense, user: user, name: "Books", pool: nil)
    entry_on(item_in(books, "Bookshop"), 30.00, 7, 8)

    { user: user, goal: goal, books: books }
  end

  def item_in(category, name) = create(:item, category: category, name: name)

  def entry_on(item, amount, month, day)
    create(:entry, item: item, amount: amount, date: Time.zone.local(2026, month, day, 9))
  end

  # ---------------------------------------------------------------------------------------------
  # Bank truth, by hand from the entries planted above
  #   wild:     3000 + 500 in, minus 220 + 80 + 90 + 1200 + 12.50 + 7.25 out = 1890.25
  #   settled:  200 in, minus 45 out                                         =  155.00
  #   bare:     nothing                                                      =    0.00
  #   namesake: nothing in, minus 30 out                                     =  -30.00
  # ---------------------------------------------------------------------------------------------
  def wild_bank_truth = BigDecimal("1890.25")
  def settled_bank_truth = BigDecimal("155.00")
  def namesake_bank_truth = BigDecimal("-30.00")

  def migrate!
    migration = described_class.new
    migration.suppress_messages { migration.up }
  end

  # `Σ pools` THROUGH THE APP'S OWN CALCULATORS — deliberately not the migration's SQL, so this
  # figure is a second and independent answer to the question the migration verified for itself.
  def app_total(user)
    user.pools.reload.to_a.sum(0.to_d) { |pool| pool.calculator.balance }
  end

  describe "the invariant it exists to create" do
    it "does not hold before the migration and does hold after it", :aggregate_failures do
      # The three savings entries are money the app invented: they enter a pool without ever
      # entering the user's life, so the pools claim $400 against a bank balance of $1,890.25.
      expect(app_total(wild[:user])).to eq(BigDecimal("400.00"))

      migrate!

      expect(app_total(wild[:user])).to eq(wild_bank_truth)
    end

    it "holds for every other user too", :aggregate_failures do
      migrate!

      expect(app_total(settled[:user])).to eq(settled_bank_truth)
      expect(app_total(bare)).to eq(0)
      expect(app_total(namesake[:user])).to eq(namesake_bank_truth)
    end
  end

  describe "step 1 — the default account" do
    it "adopts the user's only account when nothing is flagged" do
      migrate!

      expect(wild[:user].reload.default_account_id).to eq(wild[:checking].id)
    end

    it "keeps the flagged account even when it is not the first one", :aggregate_failures do
      migrate!

      expect(settled[:user].reload.default_account_id).to eq(settled[:main].id)
      expect(settled[:user].pools.accounts.count).to eq(2)
    end

    it "creates a Checking account for a user who has none", :aggregate_failures do
      migrate!

      expect(bare.reload.default_account).to have_attributes(name: "Checking", pool_type: "account", account_id: nil)
      expect(bare.pools.count).to eq(1)
    end

    it "suffixes the new account around a name a goal already holds", :aggregate_failures do
      migrate!

      expect(namesake[:user].reload.default_account.name).to eq("Checking 2")
      expect(namesake[:goal].reload.name).to eq("Checking")
    end
  end

  describe "step 2 — housing the account-less pools" do
    it "puts every non-account pool inside the default account", :aggregate_failures do
      migrate!

      expect(wild[:holiday].reload.account_id).to eq(wild[:checking].id)
      expect(namesake[:goal].reload.account_id).to eq(namesake[:user].reload.default_account_id)
    end

    it "leaves the account itself account-less" do
      migrate!

      expect(wild[:checking].reload.account_id).to be_nil
    end
  end

  describe "step 3 — envelopes first" do
    before { migrate! }

    it "creates an envelope named for the capped category and re-points the category at it", :aggregate_failures do
      envelope = wild[:user].pools.find_by(name: "Groceries")

      expect(envelope).to have_attributes(pool_type: "budget", account_id: wild[:checking].id)
      expect(wild[:groceries].reload.pool_id).to eq(envelope.id)
    end

    it "moves the cap onto the envelope in place, as a monthly rule" do
      expect(wild[:groceries_cap].reload).to have_attributes(
        pool_id: wild[:user].pools.find_by(name: "Groceries").id,
        category_id: nil,
        amount: BigDecimal("400.00"),
        interval_months: 1,
        basis: "monthly",
        anchor_date: nil,
        item_id: nil,
        prorated: false
      )
    end

    it "reuses an envelope that already carries the category's name", :aggregate_failures do
      expect(wild[:utilities].reload.pool_id).to eq(wild[:utilities_pool].id)
      expect(wild[:utilities_cap].reload.pool_id).to eq(wild[:utilities_pool].id)
      expect(wild[:user].pools.where(name: "Utilities").count).to eq(1)
    end

    it "refuses to hang a cap on a same-named GOAL and suffixes instead", :aggregate_failures do
      envelope = wild[:user].pools.find_by(name: "Rent 2")

      expect(envelope.pool_type).to eq("budget")
      expect(wild[:rent].reload.pool_id).to eq(envelope.id)
      expect(wild[:rent_cap].reload.pool_id).to eq(envelope.id)
      expect(Budget.where(pool_id: wild[:rent_goal].id)).not_to exist
    end

    it "leaves no category-mode rule anywhere, and one pool-mode rule per cap", :aggregate_failures do
      expect(Budget.where.not(category_id: nil).count).to eq(0)
      expect(Budget.for_user(wild[:user]).count).to eq(3)
    end

    it "gives the new envelopes a fill priority behind the pools the user already ordered" do
      expect(wild[:user].pools.where(name: ["Groceries", "Rent 2"]).pluck(:priority)).to contain_exactly(1, 2)
    end
  end

  describe "step 4 — the categories that are left" do
    before { migrate! }

    it "points unpooled income at the default account" do
      expect(wild[:salary].reload.pool_id).to eq(wild[:checking].id)
    end

    it "points unpooled expense at the default account" do
      expect(wild[:coffee].reload.pool_id).to eq(wild[:checking].id)
    end

    it "leaves no category anywhere without a pool" do
      expect(Category.where(pool_id: nil).count).to eq(0)
    end
  end

  describe "step 5 — savings entries become movements" do
    before { migrate! }

    it "writes one transfer per savings entry, at that entry's amount and moment", :aggregate_failures do
      movements = PoolMovement.where(to_pool: wild[:holiday]).order(:date)

      expect(movements.pluck(:amount)).to eq([BigDecimal("100.00"), BigDecimal("250.00"), BigDecimal("50.00")])
      expect(movements.pluck(:date)).to eq(savings_moments)
    end

    it "sends them out of the buffer, unattributed, as plain transfers", :aggregate_failures do
      movements = PoolMovement.where(to_pool: wild[:holiday])

      expect(movements.pluck(:from_pool_id).uniq).to eq([wild[:checking].id])
      expect(movements.pluck(:source_entry_id).uniq).to eq([nil])
      expect(movements.map(&:kind).uniq).to eq(["transfer"])
    end

    it "deletes the entries, their items and the savings categories", :aggregate_failures do
      expect(Entry.where(item_id: Item.where(category_id: wild[:vacation].id)).count).to eq(0)
      expect(Item.where(category_id: wild[:vacation].id).count).to eq(0)
      expect(Category.where(category_type: :savings).count).to eq(0)
    end

    it "conserves the count — three entries in, three movements out, none left behind", :aggregate_failures do
      expect(PoolMovement.count).to eq(3)
      expect(Entry.count).to eq(11)
    end
  end

  describe "the state it leaves behind" do
    before { migrate! }

    it "is legal under the app's own models, which never saw it written" do
      records = wild[:user].pools.to_a + wild[:user].categories.to_a +
                Budget.for_user(wild[:user]).to_a + PoolMovement.all.to_a

      expect(records.reject(&:valid?)).to eq([])
    end

    it "leaves the buffer holding everything no envelope or goal claimed", :aggregate_failures do
      # 3500 income, less 19.75 of buffer-funded coffee, less the 400 transferred out to the goal.
      expect(wild[:checking].reload.calculator.balance).to eq(BigDecimal("3080.25"))
      expect(wild[:holiday].reload.calculator.balance).to eq(BigDecimal("400.00"))
      expect(wild[:user].pools.find_by(name: "Groceries").calculator.balance).to eq(BigDecimal("-300.00"))
      expect(wild[:utilities_pool].reload.calculator.balance).to eq(BigDecimal("-90.00"))
      expect(wild[:user].pools.find_by(name: "Rent 2").calculator.balance).to eq(BigDecimal("-1200.00"))
      expect(wild[:rent_goal].reload.calculator.balance).to eq(0)
    end
  end

  describe "idempotence" do
    it "changes nothing on a second run" do
      migrate!
      after_first = snapshot

      migrate!

      expect(snapshot).to eq(after_first)
    end

    it "still verifies on a run with nothing left to do" do
      migrate!

      expect { migrate! }.not_to raise_error
    end
  end

  # Everything the migration can write, read back in a stable order.
  def snapshot
    {
      users: User.order(:email).pluck(:email, :default_account_id),
      pools: Pool.order(:user_id, :name).pluck(:user_id, :name, :pool_type, :account_id, :priority),
      categories: Category.order(:user_id, :name).pluck(:user_id, :name, :category_type, :pool_id),
      budgets: Budget.order(:amount).pluck(:pool_id, :category_id, :amount, :interval_months, :basis),
      entries: Entry.order(:date, :amount).pluck(:item_id, :amount, :date),
      movements: PoolMovement.order(:date, :amount).pluck(:from_pool_id, :to_pool_id, :amount, :date)
    }
  end

  # THE SABOTAGE BLOCK. The migration re-verifies on EVERY run, so a second run over a database
  # somebody has since broken is the verifier's own test bench.
  describe "the verification, shown failing" do
    before { migrate! }

    it "catches money that has left the user's own pool set" do
      steal_a_movement

      expect { migrate! }.to raise_error(described_class::VerificationFailed, /#{wild[:user].id}.*Σ pools/)
    end

    it "catches a category re-pointed at somebody else's pool" do
      # rubocop:disable Rails/SkipsModelValidations -- as above
      Category.where(id: wild[:coffee].id).update_all(pool_id: bare.reload.default_account_id)
      # rubocop:enable Rails/SkipsModelValidations

      expect { migrate! }.to raise_error(described_class::VerificationFailed, /Σ pools/)
    end

    # THE STRUCTURAL ARMS, ASKED DIRECTLY. Every one of them names a condition the migration's own
    # steps REPAIR — a pool-less category is re-pointed by step 4, an account-less pool housed by
    # step 2, a surviving cap converted by step 3 — so no re-run can trip them, which is a
    # property worth having and not a reason to leave them unproven.
    it "names every structural arm it can fail on", :aggregate_failures do
      break_every_structural_invariant
      message = verification_message(caps: 5, rules_before: 0)

      expect(message).to include("is not an account of this user")
      expect(message).to include("2 categories still have no pool")
      expect(message).to include("1 non-account pools still have no account")
      expect(message).to include("3 envelope rules created for 5 caps")
      expect(message).to include("1 category-mode caps survived")
      expect(message).to include("1 savings categories survived", "1 savings entries survived")
    end

    # ROLLBACK, PROVEN RATHER THAN ASSERTED: the failing run has real work to do before it
    # verifies, and none of that work may survive the raise.
    it "rolls the whole user back when verification fails after real work", :aggregate_failures do
      gym = create(:category, :expense, user: wild[:user], name: "Gym", pool: nil)
      cap = create(:budget, category: gym, amount: 60.00)
      steal_a_movement

      expect { migrate! }.to raise_error(described_class::VerificationFailed)
      expect(wild[:user].pools.where(name: "Gym")).not_to exist
      expect(cap.reload).to have_attributes(category_id: gym.id, pool_id: nil)
    end

    # THE PLAN'S OWN SUGGESTED SABOTAGE, AND IT DOES NOT FIRE — recorded rather than quietly
    # swapped out. Decision 2 says movements "net to zero by construction", and that is exactly
    # why DELETING one cannot break `Σ pools`: both halves leave together. What breaks the
    # invariant is a movement whose two ends stop belonging to the same user, which is the first
    # example above. This is the other direction of that pair.
    it "is not fooled into failing by a movement that simply went away", :aggregate_failures do
      PoolMovement.where(to_pool: wild[:holiday]).order(:amount).first.delete

      expect { migrate! }.not_to raise_error
      expect(app_total(wild[:user])).to eq(wild_bank_truth)
    end
  end

  def steal_a_movement
    movement = PoolMovement.where(to_pool: wild[:holiday]).order(:amount).first
    # rubocop:disable Rails/SkipsModelValidations -- bypassing `pools_must_share_a_user` is the point
    PoolMovement.where(id: movement.id).update_all(to_pool_id: bare.reload.default_account_id)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def break_every_structural_invariant
    unpool_a_category_and_evict_a_goal
    create(:budget, category: create(:category, :expense, user: wild[:user], name: "Gym", pool: nil), amount: 60.00)
    revived = create(:category, :savings, user: wild[:user], name: "Revived", pool: wild[:holiday])
    entry_on(item_in(revived, "Deposit"), 10.00, 7, 20)
  end

  def unpool_a_category_and_evict_a_goal
    # rubocop:disable Rails/SkipsModelValidations -- planting states the models refuse to write
    Category.where(id: wild[:coffee].id).update_all(pool_id: nil)
    Pool.where(id: wild[:holiday].id).update_all(account_id: nil)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def verification_message(caps:, rules_before:)
    described_class.new.send(
      :verify!,
      wild[:user].id,
      bare.reload.default_account_id,
      caps: caps,
      rules_before: rules_before
    )
    raise "the verification passed a database it should have refused"
  rescue described_class::VerificationFailed => e
    e.message
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
