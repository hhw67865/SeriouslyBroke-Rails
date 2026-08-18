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
  # THE SCHEMA THIS MIGRATION WAS WRITTEN FOR, REBUILT FOR THE LENGTH OF THE FILE — plan 3 task 6
  # adds two tightenings after this migration by timestamp, and both refuse shapes this file has to
  # plant. The shared context carries the whole reasoning and runs both migrations' `down` and `up`,
  # which is also what proves them reversible.
  include_context "with the schema its subject was written for",
                  TightenPoolShape,
                  DropCapEraBudgetColumns

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
      holiday: plant_houseless_pool(user: user, name: "Holiday Fund", target_amount: 2_000.00),
      utilities_pool: create(
        :pool,
        user: user,
        name: "Utilities",
        pool_type: :budget,
        account: checking,
        target_amount: nil
      ),
      rent_goal: create(:pool, user: user, name: "Rent", account: checking, target_amount: 5_000.00),
      # AN OVERSPENT GOAL, reached below by an EXPENSE category — a shape the demo has held since
      # Plan 2c (Health → Emergency Fund). It is here because step 5b's boundary is "budget pools
      # only", and a boundary is only tested by something sitting on the far side of it: with every
      # goal at zero or better, a step that wrongly zeroed goals too would pass every example.
      medical: create(:pool, user: user, name: "Medical Fund", account: checking, target_amount: 1_000.00)
    }
  end

  def wild_categories(user, pools)
    {
      groceries: plant_unpooled_category(:expense, user: user, name: "Groceries"),
      utilities: plant_unpooled_category(:expense, user: user, name: "Utilities"),
      rent: plant_unpooled_category(:expense, user: user, name: "Rent"),
      salary: plant_unpooled_category(:income, user: user, name: "Salary"),
      coffee: plant_unpooled_category(:expense, user: user, name: "Coffee"),
      health: create(:category, :expense, user: user, name: "Health", pool: pools[:medical]),
      vacation: plant_savings_category(user: user, name: "Vacation", pool: pools[:holiday])
    }
  end

  def wild_caps(categories)
    {
      groceries_cap: plant_cap(categories[:groceries], 400.00),
      utilities_cap: plant_cap(categories[:utilities], 150.00),
      rent_cap: plant_cap(categories[:rent], 1_200.00)
    }
  end

  # ---------------------------------------------------------------------------------------------
  # PLANTING LEGACY SHAPES PAST TODAY'S MODEL — and the reason it has to be done this way is the
  # whole point of this file.
  #
  # This spec's subject is data the app can no longer hold. Plan 3, task 3 landed
  # `Category belongs_to :pool` (required) and deleted `Budget belongs_to :category`, so
  # `create(:category, pool: nil)` raises RecordInvalid and `create(:budget, category: x)` raises
  # NoMethodError. Written through the app's models, this fixture stops building before the
  # migration is ever called — and the one migration in the project that rewrites user data loses
  # its only test, silently, on a green suite that no longer exercises it.
  #
  # THE FIX IS ON THIS SIDE AND NEVER ON THE VALIDATION'S. A migration exists precisely to meet rows
  # written under older rules, so a spec for one must be able to write them; a validation weakened
  # so a test can build its fixture is a validation that stops protecting production. The migration
  # itself makes the same move for the same reason (decision 1: `update_all` and migration-local
  # table classes throughout, so no callback and no future validation can fire), and
  # #misfile_a_pool_inside_an_envelope below was already written past the model deliberately.
  #
  # `save!(validate: false)` rather than raw INSERT: the factories still supply the columns and the
  # timestamps, `save!` still raises on a database refusal, and the only thing skipped is the set of
  # rules that postdate the rows being planted.
  # ---------------------------------------------------------------------------------------------
  def plant_unpooled_category(type, **attrs)
    build(:category, type, pool: nil, **attrs).tap { |category| category.save!(validate: false) }
  end

  # A SAVINGS CATEGORY, WHICH IS NOT A TYPE ANY MORE (plan 3, task 5). `savings: 2` left
  # `Category`'s enum with the cutover's last code slice, so `create(:category, :savings)` raises
  # ArgumentError and the very shape step 5 exists to convert could no longer be built through the
  # model — the same trap Amendment C armed for task 3's required `belongs_to :pool`, one task
  # later. The fix is on THIS side again: the integer goes in with `update_all`, and it is
  # `described_class::SAVINGS_CATEGORY` rather than a literal 2, so the fixture and the migration
  # read the retired value from one place. The migration's own table classes never consult the app
  # enum, so what it meets here is exactly what it would meet in a real database.
  def plant_savings_category(user:, name:, pool:)
    create(:category, :expense, user: user, name: name, pool: pool).tap do |category|
      # rubocop:disable Rails/SkipsModelValidations -- the enum refuses this value; a database does not
      Category.where(id: category.id).update_all(category_type: described_class::SAVINGS_CATEGORY)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  # AN ACCOUNT-LESS GOAL, WHICH IS THE SHAPE STEP 2 EXISTS TO HOUSE (plan 3, task 6). Before the
  # backfill this was the ordinary savings pool — the table was `savings_pools` and nothing in it
  # named an account. `Pool#account_matches_pool_type` now refuses it and the
  # `pools_account_matches_pool_type` CHECK refuses it again at the database, which is why the
  # rewind above is what makes this insert land at all. Third instance on this branch of the same
  # trap: the tightening that lands one task after the migration spec that has to plant what it
  # tightens.
  def plant_houseless_pool(**attrs)
    build(:pool, account: nil, **attrs).tap { |pool| pool.save!(validate: false) }
  end

  def plant_cap(category, amount)
    Budget.new(amount: amount).tap do |cap|
      cap.category_id = category.id
      cap.save!(validate: false)
    end
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

  # Money out to it — the negative half. The first four land in categories that will get envelopes;
  # the last three are already pooled or stay on the buffer.
  def wild_expense_entries(categories)
    entry_on(item_in(categories[:groceries], "Supermarket"), 220.00, 7, 2)
    entry_on(item_in(categories[:groceries], "Corner Shop"), 80.00, 7, 9)
    entry_on(item_in(categories[:utilities], "Electric"), 90.00, 7, 3)
    entry_on(item_in(categories[:rent], "Landlord"), 1_200.00, 7, 1)
    wild_unenveloped_expenses(categories)
  end

  def wild_unenveloped_expenses(categories)
    entry_on(item_in(categories[:coffee], "Cafe"), 12.50, 7, 4)
    entry_on(item_in(categories[:coffee], "Kiosk"), 7.25, 7, 11)
    entry_on(item_in(categories[:health], "Dentist"), 60.00, 7, 12)
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
    dining = plant_unpooled_category(:expense, user: user, name: "Dining")
    bonus = plant_unpooled_category(:income, user: user, name: "Bonus")
    entry_on(item_in(dining, "Bistro"), 45.00, 7, 6)
    entry_on(item_in(bonus, "Q2 Bonus"), 200.00, 7, 7)

    { user: user, old_account: old_account, main: main, dining: dining, bonus: bonus }
      .merge(settled_lodger(user, old_account))
  end

  # AN OVERDRAWN ENVELOPE LIVING SOMEWHERE OTHER THAN THE DEFAULT ACCOUNT — the shape the demo does
  # not have and therefore cannot test. Step 5b has to fund it from Old Account, the buffer that
  # historically paid for it; funding it from Main would invent a transfer between two real bank
  # accounts, which is what `PoolMovement#crosses_accounts?` reports and spec §5.4 defers.
  def settled_lodger(user, old_account)
    travel = create(
      :pool,
      user: user,
      name: "Travel",
      pool_type: :budget,
      account: old_account,
      target_amount: nil
    )
    category = create(:category, :expense, user: user, name: "Travel", pool: travel)
    entry_on(item_in(category, "Train Ticket"), 70.00, 7, 9)

    { travel: travel, travel_category: category }.merge(settled_lodging_goal(user, old_account))
  end

  # A GOAL PRE-HOUSED IN A NON-DEFAULT ACCOUNT, holding savings entries. Step 2 fills only a NULL
  # `account_id`, so this one keeps Old Account throughout — and step 5's entry→movement conversion
  # has to source from Old Account, not from the flagged default. Sourced from Main it would be a
  # transfer between two real banks: the shape §5.4 defers and `#crosses_accounts?` reports.
  def settled_lodging_goal(user, old_account)
    goal = create(:pool, user: user, name: "Retirement", account: old_account, target_amount: 9_000.00)
    category = plant_savings_category(user: user, name: "Retirement", pool: goal)
    entry_on(item_in(category, "Monthly Top-up"), 120.00, 7, 10)

    { retirement: goal }
  end

  # A POOL HOUSED IN SOMETHING THAT IS NOT AN ACCOUNT — `account_id` is not null, so the old
  # "IS NULL" test called it housed, while `Pool#account_matches_pool_type` calls it invalid and
  # Task 6's tightening would meet it with no remedy. Written past the model deliberately.
  def misfile_a_pool_inside_an_envelope(user, pool, envelope)
    # rubocop:disable Rails/SkipsModelValidations -- the model refuses this row; a database does not
    Pool.where(id: pool.id).update_all(account_id: envelope.id)
    # rubocop:enable Rails/SkipsModelValidations
  end

  # No account at all, and a GOAL already sitting on the name the migration reaches for.
  def plant_namesake
    user = create(:user, email: "namesake@example.com")
    goal = plant_houseless_pool(user: user, name: "Checking", target_amount: 300.00)
    books = plant_unpooled_category(:expense, user: user, name: "Books")
    entry_on(item_in(books, "Bookshop"), 30.00, 7, 8)

    { user: user, goal: goal, books: books }
  end

  def item_in(category, name) = create(:item, category: category, name: name)

  def entry_on(item, amount, month, day)
    create(:entry, item: item, amount: amount, date: Time.zone.local(2026, month, day, 9))
  end

  # ---------------------------------------------------------------------------------------------
  # Bank truth, by hand from the entries planted above
  #   wild:     3000 + 500 in, minus 220 + 80 + 90 + 1200 + 12.50 + 7.25 + 60 out = 1830.25
  #   settled:  200 in, minus 45 + 70 out (the 120 goal top-up is neither)   =   85.00
  #   bare:     nothing                                                      =    0.00
  #   namesake: nothing in, minus 30 out                                     =  -30.00
  # ---------------------------------------------------------------------------------------------
  def wild_bank_truth = BigDecimal("1830.25")
  def settled_bank_truth = BigDecimal("85.00")
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

  # ---------------------------------------------------------------------------------------------
  # THE BALANCE THE PRE-CUTOVER APP WOULD HAVE REPORTED — and it has to be spelled out here because
  # the app can no longer report one (plan 3, task 5).
  #
  # `PoolCalculator#balance` had a `savings_entries_total` term: entries in a savings CATEGORY were
  # money IN. That term and the category type died in the same commit, so the live reader now
  # answers 0 for a legacy goal funded entirely by savings entries — which is correct for every
  # database the app will ever be pointed at, and wrong for the three moments below, all of which
  # describe the world BEFORE `up` has run.
  #
  # This is NOT a second reader of anything live. It is `#balance` plus the one term that was
  # removed, used only on the far side of `migrate!`, and it is what keeps the strongest claim in
  # this file — a goal's balance is BYTE-IDENTICAL across the entry→movement swap — a real claim
  # rather than an assertion that zero equals zero.
  # ---------------------------------------------------------------------------------------------
  def legacy_savings_in(pool)
    savings_categories = Category.where(pool_id: pool.id, category_type: described_class::SAVINGS_CATEGORY)
    Entry.where(item_id: Item.where(category_id: savings_categories.select(:id)).select(:id)).sum(:amount)
  end

  def legacy_balance(pool) = pool.calculator.balance + legacy_savings_in(pool)

  def legacy_app_total(user)
    user.pools.reload.to_a.sum(0.to_d) { |pool| legacy_balance(pool) }
  end

  describe "the invariant it exists to create" do
    it "does not hold before the migration and does hold after it", :aggregate_failures do
      # The three savings entries are money the app invented — they enter a pool without ever
      # entering the user's life — and every paycheck ever recorded reaches no pool at all, because
      # Salary points at nothing. So the pools claim $340.00 against a bank balance of $1,830.25.
      expect(legacy_app_total(wild[:user])).to eq(BigDecimal("340.00"))

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

    # NOT-NULL IS NOT THE QUESTION. A pool filed inside an ENVELOPE has an `account_id` and no
    # account; the old check called it housed and let it through.
    it "re-houses a pool filed inside something that is not an account" do
      misfile_a_pool_inside_an_envelope(wild[:user], wild[:rent_goal], wild[:utilities_pool])

      migrate!

      expect(wild[:rent_goal].reload.account_id).to eq(wild[:checking].id)
    end

    # The other direction: a pool already living in a real account of the user's — just not the
    # DEFAULT one — is not disturbed.
    it "leaves a pool that already lives in one of the user's other accounts where it is" do
      migrate!

      expect(settled[:travel].reload.account_id).to eq(settled[:old_account].id)
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

    # THE SHAPE THE DEMO CANNOT TEST, on the step that had it wrong. Settled's Retirement goal lives
    # in Old Account while their default is Main; the conversion has to come out of the account the
    # goal actually lives in.
    it "funds a goal from the account it lives in, not from the default one", :aggregate_failures do
      movement = PoolMovement.find_by(to_pool: settled[:retirement])

      expect(movement).to have_attributes(from_pool_id: settled[:old_account].id, amount: BigDecimal("120.00"))
      expect(movement.crosses_accounts?).to be(false)
    end

    it "writes no movement anywhere that crosses an account boundary" do
      expect(PoolMovement.all.reject { |movement| movement.crosses_accounts? == false }).to eq([])
    end

    it "deletes the entries, their items and the savings categories", :aggregate_failures do
      expect(Entry.where(item_id: Item.where(category_id: wild[:vacation].id)).count).to eq(0)
      expect(Item.where(category_id: wild[:vacation].id).count).to eq(0)
      expect(Category.where(category_type: described_class::SAVINGS_CATEGORY).count).to eq(0)
    end

    it "conserves the count — three entries in, three movements out, none left behind", :aggregate_failures do
      expect(PoolMovement.where(to_pool: wild[:holiday]).count).to eq(3)
      expect(Entry.count).to eq(13)
    end
  end

  # STEP 5b. Wild's three envelopes open holding their categories' whole spending history —
  # Groceries −$300.00, Utilities −$90.00, Rent 2 −$1,200.00 — and each is cleared by one movement
  # out of the buffer. $1,590.00 in total, which is where the buffer's $3,080.25 goes.
  describe "step 5b — budget envelopes open at zero" do
    before { migrate! }

    it "leaves every budget envelope holding nothing at all" do
      expect(wild[:user].pools.budget_pools.map { |pool| pool.calculator.balance }).to all(eq(0))
    end

    it "pays each deficit out of the buffer, exactly once and exactly in full", :aggregate_failures do
      zeroing = PoolMovement.where(from_pool: wild[:checking], date: Time.zone.today.all_day)

      expect(zeroing.pluck(:amount).sort).to eq(
        [
          BigDecimal("90.00"),
          BigDecimal("300.00"),
          BigDecimal("1200.00")
        ]
      )
      expect(zeroing.map(&:kind).uniq).to eq(["transfer"])
      expect(wild[:checking].reload.calculator.balance).to eq(BigDecimal("1490.25"))
    end

    # THE FAR SIDE OF THE BOUNDARY: Medical Fund is a GOAL sitting at −$60.00, which is exactly the
    # shape step 5b would zero if it selected on the balance alone. It is left overdrawn, because a
    # goal's balance is real accumulated savings and this one really is overspent.
    it "does not touch the goals, whose balances are real savings", :aggregate_failures do
      expect(wild[:holiday].reload.calculator.balance).to eq(BigDecimal("400.00"))
      expect(wild[:medical].reload.calculator.balance).to eq(BigDecimal("-60.00"))
      expect(PoolMovement.where(to_pool: [wild[:rent_goal], wild[:medical]])).not_to exist
    end

    it "writes nothing on a second run, because nothing is negative any more" do
      expect { migrate! }.not_to change(PoolMovement, :count)
    end

    # THE SHAPE THE DEMO CANNOT TEST. Settled's Travel envelope is overdrawn $70.00 and lives in Old
    # Account, while the user's DEFAULT account is Main. Sourced from the default it would be a
    # transfer between two real banks; sourced from its own account it is a move inside one.
    it "funds an envelope from the account it lives in, not from the default one", :aggregate_failures do
      zeroing = PoolMovement.find_by(to_pool: settled[:travel])

      expect(zeroing).to have_attributes(from_pool_id: settled[:old_account].id, amount: BigDecimal("70.00"))
      expect(zeroing.crosses_accounts?).to be(false)
      expect(settled[:travel].reload.calculator.balance).to eq(0)
      # −70.00 opening Travel at zero, −120.00 funding the Retirement goal: both out of the account
      # that houses them, neither out of the flagged default.
      expect(settled[:old_account].reload.calculator.balance).to eq(BigDecimal("-190.00"))
    end
  end

  # THE OTHER DIRECTION on the promise step 5b is bounded by: a goal's balance is identical before
  # the migration and after it. The entry→movement swap replaces a `+amount` with the same
  # `+amount`, and no step re-points a category away from a goal or zeroes one.
  describe "what the migration promises not to move" do
    it "leaves every savings pool's balance exactly where it found it" do
      before_run = wild[:user].pools.savings_pools.to_h { |pool| [pool.id, legacy_balance(pool)] }

      migrate!

      expect(wild[:user].pools.savings_pools.reload.to_h { |pool| [pool.id, pool.calculator.balance] })
        .to eq(before_run)
    end

    it "and those balances are figures, not a coincidence of zeroes", :aggregate_failures do
      expect(legacy_balance(wild[:holiday])).to eq(BigDecimal("400.00"))
      expect(legacy_balance(wild[:medical])).to eq(BigDecimal("-60.00"))
      # The medical goal holds no savings entries at all, so the legacy reading and the live one
      # are the same number for it — which is what says the helper adds a term rather than a figure.
      expect(wild[:medical].calculator.balance).to eq(BigDecimal("-60.00"))
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
      # 3500 income, less 19.75 of buffer-funded coffee, less 400 transferred to the goal, less the
      # 1590 that opens the three envelopes at zero. The Health spending is NOT in that list — it
      # comes out of the goal it points at, which is why Medical Fund sits at −60 below.
      expect(wild[:checking].reload.calculator.balance).to eq(BigDecimal("1490.25"))
      expect(wild[:holiday].reload.calculator.balance).to eq(BigDecimal("400.00"))
      expect(wild[:medical].reload.calculator.balance).to eq(BigDecimal("-60.00"))
      expect(wild[:user].pools.budget_pools.map { |pool| pool.calculator.balance }).to all(eq(0))
      expect(wild[:rent_goal].reload.calculator.balance).to eq(0)
    end
  end

  # Savings entries are deleted, their categories and items with them, and a converted cap cannot be
  # told from a rule somebody wrote by hand afterwards. Undoing this means restoring a backup, and
  # the migration says so rather than offering a `down` that would lose more.
  # THE RUN LOG IS AN ARTEFACT OF THIS MIGRATION, NOT DECORATION. Step 5b's rows are the only thing
  # here the old database never held, the ruling behind them is still open, and their after-the-fact
  # signature (a `transfer`, dated on the run, into a budget pool, with no source entry) is matched
  # by an ordinary hand-made transfer on cutover day. The ids are the unique handle, and this run is
  # the only moment anything knows them. See #report_the_undo_list.
  describe "the run log" do
    it "names every zeroing movement it wrote, under the email that owns it", :aggregate_failures do
      output = captured_migration_output

      # Dated on the run day; every planted entry is in July, so nothing else lands on today.
      wild_ids = PoolMovement.where(from_pool: wild[:checking], date: Time.zone.today.all_day).pluck(:id)
      settled_id = PoolMovement.find_by(to_pool: settled[:travel]).id

      expect(wild_ids.size).to eq(3)
      expect(output).to include(*wild_ids, settled_id)
      expect(output).to match(/wild@example\.com: zeroing movements written/)
      expect(output).to match(/settled@example\.com: zeroing movements written/)
    end

    # THE OTHER DIRECTION. `bare` has no pool, no entry and nothing to zero, so it gets its receipt
    # and no undo list — an empty list beside a receipt is a line an operator has to read to learn
    # nothing.
    it "says nothing about an undo list for a user with no envelope to zero", :aggregate_failures do
      output = captured_migration_output

      expect(output).to match(/bare@example\.com: buffer Checking/)
      expect(output).not_to match(/bare@example\.com: zeroing movements written/)
    end
  end

  # `#migrate!` suppresses the migration's own output; this is the same run with the log KEPT, which
  # is the thing the undo list exists to land in. Same `$stdout` swap `spec/seeds_spec.rb` uses.
  def captured_migration_output
    migration = described_class.new
    migration.verbose = true
    original = $stdout
    $stdout = StringIO.new
    migration.up
    $stdout.string
  ensure
    $stdout = original
  end

  describe "reversal" do
    it "refuses to run backwards" do
      expect { described_class.new.down }.to raise_error(ActiveRecord::IrreversibleMigration)
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

  # THE PRE-FLIGHT BLOCK. Three shapes the migration meets, repairs in neither direction and cannot
  # survive downstream: `TightenPoolShape` refuses the first two one migration later, and the third
  # is a cross-user link no migration can honestly untangle. Each is planted PAST THE MODEL — the
  # same idiom every other fixture in this file uses, and for the same reason: `Pool`'s
  # case-insensitive uniqueness, `#account_matches_pool_type` and — since the commit that added
  # these examples — `Category#pool_must_belong_to_user` all refuse these rows at the model, which
  # is exactly why a database can still hold one and why the plants have to go past it.
  #
  # BOTH DIRECTIONS. Each example asserts the raise NAMES the offending rows — a refusal that says
  # only "duplicate names exist" leaves the operator where an `add_index` error would have — and the
  # last one asserts the run wrote NOTHING, which is the whole reason the check sits before the loop
  # rather than beside the other eight in #verify!.
  describe "the pre-flight, before a single write" do
    it "refuses two pools of one user whose names differ only in case, and names both", :aggregate_failures do
      twin = plant_duplicate_of(wild[:utilities_pool], "utilities")

      expect { migrate! }.to raise_error(described_class::PreflightFailed) { |error|
        expect(error.message).to include("user #{wild[:user].id} has 2 pools named \"utilities\"")
        expect(error.message).to include(wild[:utilities_pool].id, twin.id)
      }
    end

    it "refuses an account that is itself filed inside another pool, and names it", :aggregate_failures do
      misfile_an_account_inside(wild[:checking], wild[:utilities_pool])

      expect { migrate! }.to raise_error(described_class::PreflightFailed) { |error|
        expect(error.message).to include("account pool #{wild[:checking].id}")
        expect(error.message).to include("is filed inside pool #{wild[:utilities_pool].id}")
      }
    end

    # THE ONE THE VERIFIER ALREADY CAUGHT, AND WHY IT MOVED. A category pointing at a stranger's
    # pool makes BOTH users' `Σ pools` disagree with their bank truth, so the run already refused
    # it — with an arithmetic mismatch, after the writes, naming no category. The shape is the same;
    # what changed is that the abort is now a work item with three ids in it.
    it "refuses a category pointing at another user's pool, and names both owners", :aggregate_failures do
      point_a_category_at(wild[:coffee], settled[:main])

      expect { migrate! }.to raise_error(described_class::PreflightFailed) { |error|
        expect(error.message).to include("category #{wild[:coffee].id} (\"Coffee\", user #{wild[:user].id})")
        expect(error.message).to include("points at pool #{settled[:main].id}, owned by user #{settled[:user].id}")
      }
    end

    # THE POINT OF IT BEING A PRE-FLIGHT. Not "it rolls back" — the run is all-or-nothing and would
    # have rolled back anyway — but that the FIRST user is never touched, so the refusal costs the
    # database nothing and can be re-run the moment the named rows are fixed.
    #
    # THE PLANT IS THE DUPLICATE NAME, AND ONLY THAT ONE CAN CARRY THIS CLAIM. Measured, by moving
    # `preflight!` from the first line of `up` to the last: with a MISFILED ACCOUNT planted the
    # snapshot assertion still passes under the mutant, because that shape independently trips the
    # verifier's cross-account arm and the all-or-nothing run rolls back either way — the example
    # would be asserting the transaction, not the ordering. The duplicate name reaches the verifier
    # and SURVIVES it, so with the check at the end the migration writes every user and commits
    # before raising; the snapshot is what notices.
    it "leaves every user exactly as it found them", :aggregate_failures do
      plant_duplicate_of(wild[:utilities_pool], "utilities")
      before_state = snapshot

      expect { migrate! }.to raise_error(described_class::PreflightFailed)
      expect(snapshot).to eq(before_state)
    end

    # THE CLEAN PATH, SAID ONCE HERE TOO. Four planted worlds hold none of the three shapes, so the
    # pre-flight is invisible to every other example in this file — which is the claim those
    # examples all quietly depend on.
    it "passes a database holding none of the three, and lets the migration run" do
      expect { migrate! }.not_to raise_error
    end
  end

  # A SECOND POOL UNDER A NAME THE USER ALREADY HAS, differing only in case. `Pool` validates
  # uniqueness `case_sensitive: false` and `TightenPoolShape`'s index says the same thing in SQL, so
  # this row needs the same past-the-model planting every legacy shape in this file needs.
  def plant_duplicate_of(pool, name)
    build(:pool, user: pool.user, name: name, pool_type: :budget, account: pool.account, target_amount: nil)
      .tap { |twin| twin.save!(validate: false) }
  end

  # AN ACCOUNT WITH A PARENT — `#account_matches_pool_type` refuses it ("cannot be set on an
  # account") and `TightenPoolShape`'s CHECK refuses it again, past the model. The housing step
  # excludes ACCOUNT pools by type, so nothing in the migration ever looks at this row.
  def misfile_an_account_inside(account, parent)
    # rubocop:disable Rails/SkipsModelValidations -- the model refuses this row; a database does not
    Pool.where(id: account.id).update_all(account_id: parent.id)
    # rubocop:enable Rails/SkipsModelValidations
  end

  # A STRANGER'S POOL THAT ALREADY EXISTS — `settled`'s account rather than `bare`'s, because
  # `bare` has no pool at all until step 1 creates one and this shape has to be planted in the
  # PRE-cutover world the pre-flight actually reads.
  def point_a_category_at(category, pool)
    # rubocop:disable Rails/SkipsModelValidations -- `Category#pool_must_belong_to_user` refuses this
    Category.where(id: category.id).update_all(pool_id: pool.id)
    # rubocop:enable Rails/SkipsModelValidations
  end

  # THE SABOTAGE BLOCK. The migration re-verifies on EVERY run, so a second run over a database
  # somebody has since broken is the verifier's own test bench.
  describe "the verification, shown failing" do
    before { migrate! }

    it "catches money that has left the user's own pool set" do
      steal_a_movement

      expect { migrate! }.to raise_error(described_class::VerificationFailed, /#{wild[:user].id}.*Σ pools/)
    end

    # A CATEGORY RE-POINTED AT SOMEBODY ELSE'S POOL used to be asserted here, as a `Σ pools`
    # mismatch on a second run. It is now refused one step earlier and by name, so the example lives
    # in the pre-flight block above rather than being asserted twice against two different errors.
    # The arithmetic arm it used to exercise is the example above this comment, which breaks the
    # invariant in the one way no pre-flight can see: a movement whose two ends stop sharing a user.

    # THE STRUCTURAL ARMS, ASKED DIRECTLY. Every one of them names a condition the migration's own
    # steps REPAIR — a pool-less category is re-pointed by step 4, an account-less pool housed by
    # step 2, a surviving cap converted by step 3 — so no re-run can trip them, which is a
    # property worth having and not a reason to leave them unproven.
    it "names every structural arm it can fail on", :aggregate_failures do
      message = broken_verification_message

      expect(message).to include("is not an account of this user")
      expect(message).to include("2 categories still have no pool")
      expect(message).to include("1 non-account pools still have no account")
      expect(message).to include("3 envelope rules created for 5 caps")
      expect(message).to include("1 category-mode caps survived")
      expect(message).to include("1 savings categories survived", "1 savings entries survived")
    end

    # STEP 5b's TWO ARMS, and neither is implied by the invariant: a zeroing movement of the wrong
    # size still nets to zero, and a goal that drifted did so by money that stayed in the pool tree.
    it "reports an envelope left in deficit and a goal that moved", :aggregate_failures do
      message = broken_verification_message

      expect(message).to include("1 budget envelopes are still negative")
      expect(message).to include("moved 400.0 -> 410.0")
    end

    # ROLLBACK, PROVEN RATHER THAN ASSERTED: the failing run has real work to do before it
    # verifies, and none of that work may survive the raise.
    it "rolls the whole user back when verification fails after real work", :aggregate_failures do
      gym = plant_unpooled_category(:expense, user: wild[:user], name: "Gym")
      cap = plant_cap(gym, 60.00)
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

  # The snapshot is taken BEFORE the breakage, exactly as the migration takes its own — the drift
  # arm is about a goal moving during a run, so measuring after the move would prove nothing.
  def broken_verification_message
    savings_before = described_class.new.send(:pool_balances, wild[:user].id, described_class::SAVINGS_POOL)
    break_every_structural_invariant

    verification_message(caps: 5, rules_before: 0, savings_before: savings_before)
  end

  def break_every_structural_invariant
    unpool_a_category_and_evict_a_goal
    plant_cap(plant_unpooled_category(:expense, user: wild[:user], name: "Gym"), 60.00)
    # A savings entry that came back: it revives the category count, the entry count, AND — because
    # it lands in the goal's lane — moves the goal's balance from 400.00 to 410.00.
    revived = plant_savings_category(user: wild[:user], name: "Revived", pool: wild[:holiday])
    entry_on(item_in(revived, "Deposit"), 10.00, 7, 20)
    # Spending that arrived after the envelope was zeroed, putting it back into deficit.
    entry_on(item_in(wild[:groceries], "Late Receipt"), 25.00, 7, 21)
  end

  def unpool_a_category_and_evict_a_goal
    # rubocop:disable Rails/SkipsModelValidations -- planting states the models refuse to write
    Category.where(id: wild[:coffee].id).update_all(pool_id: nil)
    Pool.where(id: wild[:holiday].id).update_all(account_id: nil)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def verification_message(caps:, rules_before:, savings_before:)
    described_class.new.send(
      :verify!,
      wild[:user].id,
      bare.reload.default_account_id,
      caps: caps,
      rules_before: rules_before,
      savings_before: savings_before
    )
    raise "the verification passed a database it should have refused"
  rescue described_class::VerificationFailed => e
    e.message
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
