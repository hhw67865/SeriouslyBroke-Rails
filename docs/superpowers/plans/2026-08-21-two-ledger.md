# Two-Ledger Implementation Plan — Categories Hold the Money

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the envelope/goal pool layer: categories hold money, carry rules and targets; `pools` keeps only accounts; two ledgers (physical, purpose) partition one total.

**Architecture:** A strangler sequence. Task 1's migration ADDS the purpose ledger's tables (`allocations`, three category columns, `budgets.category_id`) and backfills them from pools while every old reader keeps working. Tasks 2–7 build the purpose-ledger core and convert one subsystem at a time — each with its own specs green — while old pool code stays alive underneath. Task 8 drops the old rows, columns and classes in one migration and turns `pool_movements` into `account_movements`. Task 9 verifies on Ming and closes the docs.

**Tech Stack:** Rails 8.1, PostgreSQL (money columns, UUID PKs), RSpec/Capybara/FactoryBot, simple_form, Tailwind, Stimulus.

**Spec:** `docs/superpowers/specs/2026-08-21-two-ledger-design.md` — read it first; §2's invariant is every task's acceptance test.

## Global Constraints

- **THE INVARIANT, both ledgers, to the cent, per user:** `pot + Σ accounts == income − expenses == available + Σ category holdings`. Every task that touches a writer or reader asserts it with raw SQL on planted fixtures (house precedent: `spec/services/start_date_rule_spec.rb`'s "keeps Σ pools == bank truth … by raw SQL").
- **Movements never cross ledgers.** `account_movements` (née `pool_movements`): both sides ACCOUNT rows, always. `allocations`: both sides categories or NULL (= available). There is no account→category movement — enforced by shape, not validation.
- **One reader per question.** `CategoryLedger::ENTRY_CATEGORY_ID` is the ONLY spelling of "which category does an expense drain" (the start-date rule re-anchored on `categories.funded_since`, timezone-aware exactly as `PoolBalanceLedger::ENTRY_POOL_ID` is today — copy its `AT TIME ZONE` pair). Its Ruby mirror is `Category#counts_spending_on?(date)`. No other file compares `funded_since`.
- **New code never reads a pool for anything but an account.** `Pool` rows of type budget/savings still exist in the DB until Task 8; code written in Tasks 2–7 must not depend on them.
- **The cutover migration (`db/migrate/20260817000000_…`) stays FROZEN**; its spec must stay green through Task 8 via `spec/support/schema_rewind.rb` (extend the rewind list; do not edit the migration).
- **The dev database is real user data (Ming only may be read — `mingguan0809@gmail.com` / `password123` locally).** Task 1's and Task 8's migrations run against it; nothing else touches it; **nobody uses the app between Task 1 and Task 8** (old writers and new readers coexist mid-plan — fine in tests, stale in a live DB).
- Commit style: single line `type/scope: description`, no Co-Authored-By, explicit paths (never `git add -A`). Never push. Never merge to main.
- Spec files ONE at a time; `pgrep -f "[r]spec spec/system"` before any system run. `bin/ci` runs zero RSpec examples — never cite it.
- `Date.current` never lazily inside `travel_to`. Money assertions on planted literals; both directions on every rule. `rubocop -A` clean per commit; new Tailwind classes → `bin/rails tailwindcss:build`.
- Factories: the `:pool` factory's `:budget_pool`/`:savings` traits DIE in Task 8. From Task 2, new specs use `:category` traits (`:funded`, `:savings`) and `:allocation`; old specs keep their factories until the task that converts them.

---

### Task 1: The migration — add the purpose ledger and backfill it

**Files:**
- Create: `db/migrate/20260821000000_categories_hold_the_money.rb`
- Test: `spec/migrations/two_ledger_spec.rb`
- Modify: `spec/support/schema_rewind.rb` (register the new migration so `cutover_spec` still rewinds correctly — read the file's shared context first)

**Interfaces:**
- Produces (schema): `allocations` table; `categories.funded_since date`, `categories.target_amount money scale 2`, `categories.priority integer default 0 not null`; `budgets.category_id uuid` (FK, index); nothing dropped.
- Produces (data): every budget-type pool's single category carries its `start_date→funded_since`, `target_amount`, `priority`; every rule carries `category_id`; every savings pool has a NEW expense category (same name, target, priority, `funded_since = start_date`, `tracked: false`) ; every `pool_movements` row with a non-account endpoint has become an `allocations` row and been deleted from `pool_movements`; `entries.pool_id` nulled (counted, printed).

- [ ] **Step 1: Write the failing migration spec** — `spec/migrations/two_ledger_spec.rb`, in `cutover_spec.rb`'s idiom (migration-local planting past the model with `save!(validate: false)`, raw-SQL verification, sabotage arms). Core examples:

```ruby
# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260821000000_categories_hold_the_money")

RSpec.describe CategoriesHoldTheMoney do
  let(:migration) { described_class.new }
  let(:user) { create(:user) }
  let(:main) { create(:pool, :account, user: user, name: "Checking") }

  before { user.update!(default_account: main) }

  def envelope(name, start:, priority: 1, target: nil)
    create(:pool, :budget_pool, user: user, account: main, name: name,
                                start_date: start, priority: priority, target_amount: target)
  end

  def bank_truth
    ActiveRecord::Base.connection.select_value(<<~SQL).to_d
      SELECT COALESCE(SUM(CASE WHEN c.category_type = 1 THEN e.amount::numeric
                               ELSE -e.amount::numeric END), 0)
      FROM entries e JOIN items i ON i.id = e.item_id JOIN categories c ON c.id = i.category_id
      WHERE c.user_id = '#{user.id}'
    SQL
  end

  def purpose_total
    # available + Σ category holdings, computed off the NEW tables only
    ActiveRecord::Base.connection.select_value(<<~SQL).to_d
      WITH spend AS (
        SELECT COALESCE(SUM(e.amount::numeric), 0) AS total
        FROM entries e JOIN items i ON i.id = e.item_id JOIN categories c ON c.id = i.category_id
        WHERE c.user_id = '#{user.id}' AND c.category_type = 0),
      income AS (
        SELECT COALESCE(SUM(e.amount::numeric), 0) AS total
        FROM entries e JOIN items i ON i.id = e.item_id JOIN categories c ON c.id = i.category_id
        WHERE c.user_id = '#{user.id}' AND c.category_type = 1)
      SELECT income.total - spend.total FROM income, spend
    SQL
  end

  it "folds an envelope into its one category and re-parents its rule", :aggregate_failures do
    food = envelope("Food", start: Date.new(2026, 8, 1), priority: 2)
    category = create(:category, :expense, user: user, pool: food, name: "Food")
    rule = create(:pool_budget, :per_period_rate, pool: food, amount: 120)

    migration.up

    expect(category.reload.funded_since).to eq(Date.new(2026, 8, 1))
    expect(category.priority).to eq(2)
    expect(rule.reload.category_id).to eq(category.id)
  end

  it "turns a savings goal into a savings category carrying its holdings", :aggregate_failures do
    trip = create(:pool, :savings, user: user, account: main, name: "Trip", target_amount: 900,
                                   start_date: Date.new(2026, 6, 1))
    create(:pool_movement, from_pool: main, to_pool: trip, amount: 250, date: Time.zone.now)

    migration.up

    saved = user.categories.find_by(name: "Trip")
    expect(saved.target_amount).to eq(900)
    expect(saved.tracked).to be(false)
    allocation = Allocation.find_by(to_category_id: saved.id)
    expect(allocation.from_category_id).to be_nil        # from AVAILABLE
    expect(allocation.amount).to eq(250)
    expect(PoolMovement.where(to_pool: trip)).to be_empty
  end

  it "keeps account↔account movements where they are" do
    ally = create(:pool, :account, user: user, name: "Ally")
    create(:pool_movement, from_pool: main, to_pool: ally, amount: 40, date: Time.zone.now)

    expect { migration.up }.not_to change { PoolMovement.count }
  end

  it "refuses an envelope with two categories, naming it, and writes nothing" do
    food = envelope("Food", start: Date.current)
    create(:category, :expense, user: user, pool: food, name: "Groceries")
    create(:category, :expense, user: user, pool: food, name: "Restaurants")

    expect { migration.up }.to raise_error(/Food.*2 categories/)
    expect(Allocation.count).to eq(0)
  end

  it "leaves both ledgers equal to bank truth" do
    food = envelope("Food", start: Date.new(2026, 8, 1))
    category = create(:category, :expense, user: user, pool: food, name: "Food")
    pay = create(:category, :income, user: user, pool: main, name: "Pay")
    create(:entry, item: create(:item, category: pay), amount: 1000, date: Date.current)
    create(:entry, item: create(:item, category: category), amount: 60, date: Date.current)
    create(:pool_movement, from_pool: main, to_pool: food, amount: 200, date: Time.zone.now,
                           kind: :allocation)

    migration.up

    expect(purpose_total).to eq(bank_truth)
    expect(bank_truth).to eq(940)
  end
end
```

  (The `Allocation` constant does not exist until Task 2 — for THIS spec use a migration-local `CategoriesHoldTheMoney::MigrationAllocation < ActiveRecord::Base; self.table_name = "allocations"` in the examples, as `cutover_spec` does with its migration-local classes. Replace `Allocation` above accordingly.)

- [ ] **Step 2: Run it — FAILS** (no migration file).

- [ ] **Step 3: Write the migration.** Cutover discipline: migration-local table classes, `update_all`/raw inserts (no callbacks), envelopes-first, per-user receipts via `say`, pre-flight that NAMES refusals before any write, self-verification independent of app readers. Skeleton (fill every `# …` with the SQL the step names — no method may remain a stub):

```ruby
# frozen_string_literal: true

# CATEGORIES HOLD THE MONEY (two-ledger spec §7). Adds the purpose ledger's tables and backfills
# them from the pool layer WITHOUT dropping anything — old readers keep working until Task 8's
# drop. Per user, all-or-nothing under the Migrator's transaction; refuses shapes it will not
# guess at (a budget pool with 0 or 2+ categories) by NAMING them before the first write.
class CategoriesHoldTheMoney < ActiveRecord::Migration[8.1]
  class MigrationPool < ActiveRecord::Base; self.table_name = "pools"; end
  class MigrationCategory < ActiveRecord::Base; self.table_name = "categories"; end
  class MigrationBudget < ActiveRecord::Base; self.table_name = "budgets"; end
  class MigrationMovement < ActiveRecord::Base; self.table_name = "pool_movements"; end
  class MigrationAllocation < ActiveRecord::Base; self.table_name = "allocations"; end
  class MigrationUser < ActiveRecord::Base; self.table_name = "users"; end

  ACCOUNT = 0
  BUDGET = 1
  SAVINGS = 2
  EXPENSE = 0

  class PreflightFailed < StandardError; end

  def up
    create_schema
    preflight!
    MigrationUser.find_each { |user| convert(user) }
  end

  def down
    drop_table :allocations
    remove_reference :budgets, :category, foreign_key: true, type: :uuid
    remove_column :categories, :funded_since
    remove_column :categories, :target_amount
    remove_column :categories, :priority
    # The backfilled data is not reversed: categories minted for savings pools stay (harmless),
    # and the allocations they held are gone with the table. Down exists for the schema rewind
    # only — a real reversal is a restore.
  end

  private

  def create_schema
    add_column :categories, :funded_since, :date
    add_column :categories, :target_amount, :money, scale: 2
    add_column :categories, :priority, :integer, null: false, default: 0
    add_reference :budgets, :category, type: :uuid, foreign_key: true, index: true

    create_table :allocations, id: :uuid do |t|
      t.uuid :from_category_id   # NULL = available
      t.uuid :to_category_id     # NULL = available
      t.money :amount, scale: 2, null: false
      t.datetime :date, null: false
      t.integer :kind, null: false, default: 0
      t.uuid :source_entry_id
      t.timestamps
    end
    add_foreign_key :allocations, :categories, column: :from_category_id
    add_foreign_key :allocations, :categories, column: :to_category_id
    add_foreign_key :allocations, :entries, column: :source_entry_id
    add_index :allocations, :from_category_id
    add_index :allocations, :to_category_id
    add_index :allocations, :source_entry_id
    add_index :allocations, :date
    add_check_constraint :allocations, "amount > 0::money", name: "allocations_positive_amount"
    add_check_constraint :allocations,
                         "from_category_id IS DISTINCT FROM to_category_id",
                         name: "allocations_distinct_sides"
  end

  # NAMES every budget pool whose category count is not exactly 1. Savings pools may have 0
  # (they get a minted category) or 1; 2+ is refused for both types.
  def preflight!
    rows = select_all(<<~SQL)
      SELECT p.id, p.name, p.pool_type, u.email, COUNT(c.id) AS categories
      FROM pools p
      JOIN users u ON u.id = p.user_id
      LEFT JOIN categories c ON c.pool_id = p.id
      WHERE p.pool_type <> #{ACCOUNT}
      GROUP BY p.id, p.name, p.pool_type, u.email
      HAVING (p.pool_type = #{BUDGET} AND COUNT(c.id) <> 1) OR COUNT(c.id) > 1
    SQL
    return if rows.empty?

    raise PreflightFailed, rows.map { |r|
      "#{r['email']}: pool #{r['name']} (#{r['id']}) has #{r['categories']} categories"
    }.join("; ")
  end

  def convert(user)
    pools = MigrationPool.where(user_id: user.id).where.not(pool_type: ACCOUNT)
    category_of = {}   # pool id → category id
    pools.each { |pool| category_of[pool.id] = fold(pool, user) }
    moved = convert_movements(user, category_of)
    nulled = MigrationEntryOverrides.null_for(user)  # see note below
    verify!(user)
    say "#{user.email}: #{pools.count} pools folded; #{moved} movements -> allocations; " \
        "#{nulled} entry overrides cleared; purpose == physical == bank truth"
  end

  # One pool → its category (existing for budget pools; minted for savings pools without one).
  def fold(pool, user)
    category = MigrationCategory.find_by(pool_id: pool.id) ||
               MigrationCategory.create!(user_id: user.id, name: pool.name, category_type: EXPENSE,
                                         pool_id: user.default_account_id, tracked: false,
                                         created_at: now, updated_at: now)
    category.update_columns(funded_since: pool.start_date, target_amount: pool.target_amount,
                            priority: pool.priority)
    MigrationBudget.where(pool_id: pool.id).update_all(category_id: category.id)
    category.id
  end

  # Every movement with a non-account endpoint becomes an allocation: an account endpoint maps
  # to NULL (available), a pool endpoint to its category. Account↔account rows stay.
  def convert_movements(user, category_of)
    # … SELECT pool_movements joined to both endpoint pools for this user WHERE either endpoint
    #   pool_type <> ACCOUNT; INSERT INTO allocations (…) with the mapping; DELETE the converted
    #   rows; return the count.
  end

  def verify!(user)
    # … raw SQL: (a) physical total = income − expenses over the user's entries — unchanged by
    #   construction, recompute and compare to the pre-conversion figure captured in #convert;
    #   (b) purpose total = income − expenses (available is derived, so this is the identity the
    #   spec's §2 states — assert Σ allocations balance: every allocation's from/to sides sum to
    #   zero net, i.e. SUM(amount where to NOT NULL) − SUM(amount where from NOT NULL) equals the
    #   Σ of the converted movements' net into former pools); raise naming the user on mismatch.
  end

  def now = Time.current
end
```

  `MigrationEntryOverrides.null_for(user)`: an `update_all(pool_id: nil)` over the user's entries with a non-null `pool_id`, returning the count — write it as a private method, not a class, if simpler. The spec §2 says no paid-from lane survives.

- [ ] **Step 4: Run the spec green.** Then `spec/migrations/cutover_spec.rb` — it will FAIL until `spec/support/schema_rewind.rb` also rewinds this migration (its planted shapes predate the new columns/tables): add `CategoriesHoldTheMoney` to the rewind's migration list in the correct order (newest first on the way down). Re-run cutover_spec: 49/49.

- [ ] **Step 5: Run the migration on test and dev** (`RAILS_ENV=test bin/rails db:migrate`; `bin/rails db:migrate` — dev is Ming's real data; capture the `say` receipts in the report). Then run: `spec/seeds_spec.rb` (seeds are pool-native until Task 8 — must stay green since nothing dropped), `spec/models/pool_spec.rb`, `spec/services/pool_balance_ledger_spec.rb` as the "old readers untouched" control.

- [ ] **Step 6: Commit** — `feat/two-ledger: the purpose ledger's tables exist and hold every envelope's money`.

---

### Task 2: The purpose-ledger core — Allocation, Category-as-holder, CategoryLedger, and the physical reader

**Files:**
- Create: `app/models/allocation.rb`, `app/services/category_ledger.rb`, `app/services/account_ledger.rb`, `spec/factories/allocations.rb`
- Modify: `app/models/category.rb`, `app/models/budget.rb`, `spec/factories/categories.rb`, `spec/factories/budgets.rb` (add a `:category_rule` factory or trait)
- Test: `spec/models/allocation_spec.rb`, `spec/models/category_holdings_spec.rb`, `spec/services/category_ledger_spec.rb`, `spec/services/two_ledger_invariant_spec.rb`, `spec/services/account_ledger_spec.rb`

**Interfaces:**
- Produces: `Allocation` (`belongs_to :from_category, optional`, `belongs_to :to_category, optional`, `belongs_to :source_entry, optional`, `enum :kind, { transfer: 0, allocation: 1, sweep: 2 }, prefix: true`, scopes `.for_entry`, `.distributed`); `Category#funded_since`, `#target_amount`, `#priority`, `has_many :budgets`, `has_many :allocations_in/out`, `#holder?` (= expense? && funded_since.present?), `#savings?` (= holder? && target_amount.present? && budgets.none?), `#counts_spending_on?(date)`; `Budget belongs_to :category` (required) with `Budget.for_user(user)` = `where(category_id: user.categories.select(:id))`; `CategoryLedger.new(categories, as_of:)` with `#terms_for(category)` returning the same five-key hash `PoolBalanceLedger#terms_for` returns today (`income` is always 0 for a category; `expense`, `movements_in`, `movements_out`, `last_funded_on`) plus `#available` (a money figure: income − unfunded expenses − net allocations from root); `CategoryLedger::ENTRY_CATEGORY_ID` + `ENTRY_CATEGORY_JOINS`; `AccountLedger.new(user)` with `#balance_of(account)`: main = income − expenses ± account movements; others = account movements only; `#pot` = balance of main.

- [ ] **Step 1: Failing specs.** The invariant spec is the keystone — write it first:

```ruby
# frozen_string_literal: true

require "rails_helper"

# THE TWO-LEDGER INVARIANT (spec §2): pot + Σ accounts == income − expenses == available +
# Σ category holdings. Both partitions computed by the app's own readers; bank truth by raw SQL.
RSpec.describe "The two-ledger invariant" do
  let(:user) { create(:user) }
  let(:main) { create(:pool, :account, user: user, name: "Checking") }
  let(:ally) { create(:pool, :account, user: user, name: "Ally") }
  let(:food) { create(:category, :expense, :funded, user: user, name: "Food", funded_since: Date.new(2026, 8, 1)) }
  let(:misc) { create(:category, :expense, user: user, name: "Misc") }   # never funded
  let(:pay)  { create(:category, :income, user: user, name: "Pay") }

  before { user.update!(default_account: main) }

  def bank_truth
    ActiveRecord::Base.connection.select_value(<<~SQL).to_d
      SELECT COALESCE(SUM(CASE WHEN c.category_type = 1 THEN e.amount::numeric
                               ELSE -e.amount::numeric END), 0)
      FROM entries e JOIN items i ON i.id = e.item_id JOIN categories c ON c.id = i.category_id
      WHERE c.user_id = '#{user.id}'
    SQL
  end

  def physical = AccountLedger.new(user).then { |l| l.pot + l.balance_of(ally) }
  def purpose  = CategoryLedger.new(user.categories.expenses).then { |l| l.available + [food, misc].sum { |c| l.holding_of(c) } }

  it "holds after income, allocation, funded and unfunded spending, an account transfer, and a savings round-trip",
     :aggregate_failures do
    create(:entry, item: create(:item, category: pay), amount: 1000, date: Date.new(2026, 8, 5))
    create(:allocation, to_category: food, amount: 300, date: Time.zone.parse("2026-08-06 12:00"))
    create(:entry, item: create(:item, category: food), amount: 40, date: Date.new(2026, 8, 7))   # funded
    create(:entry, item: create(:item, category: misc), amount: 25, date: Date.new(2026, 8, 7))   # unfunded
    create(:entry, item: create(:item, category: food), amount: 10, date: Date.new(2026, 7, 20))  # pre-funded
    create(:pool_movement, from_pool: main, to_pool: ally, amount: 200, date: Time.zone.parse("2026-08-08 12:00"))
    create(:allocation, from_category: food, amount: 50, date: Time.zone.parse("2026-08-09 12:00"))  # back to available

    expect(bank_truth).to eq(925)
    expect(physical).to eq(925)
    expect(purpose).to eq(925)
    expect(CategoryLedger.new([food]).holding_of(food)).to eq(210)   # 300 − 40 − 50; the $10 predates funding
    expect(CategoryLedger.new([food, misc]).available).to eq(715)   # 1000 − 25 − 10 − 300 + 50
  end
end
```

  `holding_of(category)` is the convenience over `terms_for` (movements_in − movements_out − expense). Write the ledger, allocation, category and account-ledger specs in the same style: planted literals, both directions (an entry on the boundary day in Tokyo, the pool-less/unfunded fall-through to available, an income entry never draining a category, an allocation between two categories leaving available untouched, `AccountLedger` for a user whose main has no movements).

- [ ] **Step 2: FAIL.** **Step 3: Implement.**

  `app/models/allocation.rb`:

```ruby
# frozen_string_literal: true

# THE PURPOSE LEDGER'S ONLY WRITER BESIDES ENTRIES (two-ledger spec §2). A side is a category or
# NULL, and NULL means AVAILABLE — the root every allocation ultimately draws on. No account
# ever appears here: allocating money is an act of intention, not location, so it moves
# nothing physical. Kinds keep the distribution vocabulary (`allocation`/`sweep` are what a
# distribution writes and may replace; `transfer` is a hand move).
class Allocation < ApplicationRecord
  belongs_to :from_category, class_name: "Category", optional: true, touch: true
  belongs_to :to_category, class_name: "Category", optional: true, touch: true
  belongs_to :source_entry, class_name: "Entry", optional: true

  enum :kind, { transfer: 0, allocation: 1, sweep: 2 }, prefix: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true
  validate :sides_must_differ
  validate :sides_must_be_expense_categories_of_one_user

  scope :for_entry, ->(entry) { where(source_entry: entry) }
  scope :distributed, -> { where(kind: [:allocation, :sweep]) }

  def user = (from_category || to_category)&.user

  private

  def sides_must_differ
    return unless from_category_id.present? && from_category_id == to_category_id

    errors.add(:to_category, "must differ from the source")
  end

  def sides_must_be_expense_categories_of_one_user
    sides = [from_category, to_category].compact
    return errors.add(:base, "needs at least one category") if sides.empty?
    return errors.add(:base, "must stay within one user") if sides.map(&:user).uniq.size > 1

    errors.add(:base, "only expense categories hold money") unless sides.all?(&:expense?)
  end
end
```

  `app/services/category_ledger.rb` — port `PoolBalanceLedger`'s shape (batched grouped sums, `terms_for`, `as_of`, `for_as_of!`) onto categories with these two constants (the whole rule; nothing else compares `funded_since`):

```ruby
  # WHICH CATEGORY AN EXPENSE DRAINS — the start-date rule re-anchored (spec §4). An expense
  # drains its category from the category's funded_since onward (the user's local day, exactly
  # as PoolBalanceLedger did it), and drains AVAILABLE (NULL) before that or when the category
  # was never funded. Income never drains a category: it lands in available.
  ENTRY_CATEGORY_ID = Arel.sql(<<~SQL.squish)
    CASE
      WHEN categories.category_type = #{Category.category_types[:income]} THEN NULL
      WHEN categories.funded_since IS NULL THEN NULL
      WHEN (entries.date AT TIME ZONE 'UTC'
              AT TIME ZONE COALESCE(category_users.timezone, 'UTC'))::date
           >= categories.funded_since THEN categories.id
      ELSE NULL
    END
  SQL

  ENTRY_CATEGORY_JOINS = [
    "INNER JOIN users AS category_users ON category_users.id = categories.user_id"
  ].freeze
```

  `#available` = Σ income (all entries of the user's income categories) − Σ expenses whose `ENTRY_CATEGORY_ID` is NULL − Σ allocations with `from_category_id IS NULL` + Σ allocations with `to_category_id IS NULL`, all bounded by `as_of`.

  `app/services/account_ledger.rb` (the physical ledger, small): `pot` = income − expenses (ALL the user's entries — every expense leaves checking, spec §2) − `pool_movements` out of main + into main; `balance_of(other)` = movements in − out. Both over ACCOUNT rows only.

  `Category`: the columns' validations (`priority` non-negative integer; `target_amount` > 0 when present; `funded_since` a date), `has_many :budgets, dependent: :destroy`, `has_many :allocations_in/out` (class Allocation, foreign keys), `#holder?`, `#savings?`, `#counts_spending_on?(date)` (Ruby mirror: `holder? && local_day(date) >= funded_since` — reuse the existing private `#local_day`). Leave `belongs_to :pool` and the pool validators IN PLACE for now (old readers still need them; Task 8 removes them) — but make `belongs_to :pool` `optional: true` so Task 1's minted savings categories and Task 7's new categories are valid, and gate `pool_must_be_reachable` on `pool.present?`.

  `Budget`: `belongs_to :category, optional: true` for now + `validate :must_belong_to_a_category` (required in practice), `for_user` via categories, `#user` = `category&.user || pool&.user`, `item_must_belong_to_category` (item's category == category). Keep `pool` association alive until Task 8.

  Factories: `:category` gains traits `:funded { funded_since { 1.year.ago.to_date } }` and `:savings { funded; target_amount { 500 } }`; `:allocation` factory (`to_category`, `amount { 100 }`, `date { Time.zone.now }`, `kind { :transfer }`); `:budget` factory gains `category` (a `:category_rule` variant with `category { association :category, :funded }`, `pool nil`).

- [ ] **Step 4: All new specs green; then the old controls**: `spec/models/category_spec.rb`, `spec/models/budget_spec.rb`, `spec/services/pool_balance_ledger_spec.rb`, `spec/migrations/cutover_spec.rb` — the optional-izing of two associations must not move any pinned behavior.

- [ ] **Step 5: Commit** — `feat/two-ledger: categories hold money — Allocation, CategoryLedger, and the physical reader`.

---

### Task 3: The calculator stack on categories

**Files:**
- Create: `app/services/holding_calculator.rb`, `app/services/holding_status.rb`, `app/services/holding_projection.rb` (ports of `PoolCalculator`/`PoolStatus`/`PoolProjection` — copy, then re-aim every pool read at a category; old classes stay until Task 8)
- Modify: `app/services/budget_calculator.rb` (`#user` via `budget.user`; nothing else should reference a pool — grep), `app/models/budget.rb` (`#calculator` unchanged; `.steady_need` over `for_user` — now category-scoped), `app/services/distribution_clock.rb` (`changed_after_distributing?(category)` — read `allocations` instead of `pool_movements`)
- Test: `spec/services/holding_calculator_spec.rb`, `spec/services/holding_status_spec.rb`, `spec/services/holding_projection_spec.rb` (ports of the three pool specs with `:category` fixtures — every example that pinned a figure keeps the figure), `spec/services/distribution_clock_spec.rb` (converted)

**Interfaces:**
- Produces: `HoldingCalculator.new(category, as_of:, today:, adjustment:, terms:)` with the SAME public API `PoolCalculator` exposes today (`balance`/`current_balance`, `allocated_balances`, `reserve`, `free_amount`, `goal_required`, `per_period_rate`, `required`, `progress_percentage`, `remaining_amount`, `period_closed?`, `sweepable_amount`, `contributions`, `withdrawals`) minus `income_within` (income never reaches a category; `AccountLedger` owns period income now); `HoldingStatus.new(category, today:, pending:, terms:)` same six-state vocabulary; `HoldingProjection.for(category, net_of_sweep:, pending:, **ledger)`; `Category#calculator`, `#status`, `#timeline`.
- Consumes: `CategoryLedger#terms_for`, `Category#savings?` where `PoolCalculator` read `pool.pool_type_savings?`, `Category#holder?` where it read `pool_type_budget?`.

- [ ] **Step 1: Port the specs first** — copy `spec/services/pool_calculator_spec.rb` to `holding_calculator_spec.rb`, rewrite fixtures (`create(:pool, :budget_pool, …)` → `create(:category, :expense, :funded, …)`; `create(:pool_movement, from_pool: account, to_pool: pool)` → `create(:allocation, to_category: category)`; `create(:pool_budget, pool:)` → `create(:budget, category:)`), keep every planted figure. Run: every example fails on the missing constant. Same for status and projection.
- [ ] **Step 2: Port the classes.** Mechanical rules: `pool` → `category`; `pool.budgets` → `category.budgets`; `pool.pool_type_savings?` → `category.savings?`; `pool.pool_type_budget?` → `category.holder? && !category.savings?`; movement terms come from `CategoryLedger`; `entries_for_pool` → `Entry.draining(category)` — a new scope on `Entry` that filters by `CategoryLedger::ENTRY_CATEGORY_ID = :id` with `ENTRY_CATEGORY_JOINS` (the port of `reaching_pool`, added in this task, with one spec both directions). `income_within` moves to `AccountLedger#income_within(range)` (Task 4's distribute reads it there).
- [ ] **Step 3: Specs green** (ported files + `spec/services/budget_calculator_spec.rb` + `spec/models/budget_steady_ask_spec.rb` — steady_need now walks categories; fixtures converted where they built pools).
- [ ] **Step 4: Commit** — `feat/two-ledger: the calculator stack reads categories`.

---

### Task 4: Distribute and reallocate write allocations

**Files:**
- Modify: `app/services/allocation_calculator.rb`, `app/services/allocation_committer.rb`, `app/presenters/distribution_presenter.rb`, `app/controllers/distributions_controller.rb`, `app/views/distributions/*`, `app/helpers/distributions_helper.rb`, `app/helpers/distribution_confirmation_helper.rb`
- Modify: `app/presenters/reallocation_presenter.rb`, `app/controllers/pool_movements_controller.rb` → **rename to** `app/controllers/allocations_controller.rb` (+ route `resources :allocations, only: [:new, :create]` replacing `pool_movements`), `app/views/pool_movements/new.html.erb` → `app/views/allocations/new.html.erb`, `app/helpers/pool_movements_helper.rb` → `allocations_helper.rb`
- Test: convert `spec/services/allocation_calculator_spec.rb`, `allocation_committer_spec.rb`, `spec/presenters/distribution_presenter_spec.rb`, `spec/requests/distributions_spec.rb`, `spec/system/distributions/*` (3 files), `spec/system/pool_movements/*` (4 files → `spec/system/allocations/`)

**Interfaces:**
- Consumes: `HoldingCalculator`/`HoldingProjection`, `CategoryLedger`, `AccountLedger#income_within`, `Allocation`.
- Produces: ONE distribution per period over ALL the user's holder categories by `priority` (spec §2: the purpose ledger has ONE root, so the per-account fill dies — `DistributionsController#distribution_account`/`default_account`/`fallback_account_by_income` are deleted; `AllocationCalculator.new(user:, today:, overrides:)`); sweeps write `Allocation(kind: sweep, from: category, to: NULL)`; allocations write `Allocation(kind: allocation, from: NULL, to: category, source_entry: <the period's income entry if any, else nil>)` — keep the distribution-replaceability link the same way `PoolMovement.distributed` is used today; `AllocationCommitter#replace_previous_distribution` deletes `Allocation.distributed` in the period.
- The reallocation screen moves money `category → category` or `available ↔ category` (`Allocation kind: transfer`); `ReallocationPresenter.source_order(category)` = `[category.priority, category.name]` (no account arm); its "No account" destination group and `must_not_cross_accounts` DIE (nothing crosses anything).

- [ ] **Step 1: Convert the specs first**, keeping every planted figure; the per-account examples in `distributions_spec.rb` ("opens on main…") are DELETED with the concept they tested — say so per example in the report. Run: red.
- [ ] **Step 2: Port the code** by the Task 3 rules; the waterfall's `Row`/`Line`/`Fill`/`Redirect` vocabulary keeps its names with `category` where it said `pool`; `available` comes from `CategoryLedger#available` (projected: minus pending, as today's `opening_buffer` logic does with the account buffer — read `DistributionPresenter#opening_buffer` and `#income_this_period_from` and re-aim them at `AccountLedger#income_within` and `CategoryLedger#available`).
- [ ] **Step 3: Green, one file at a time**; then the invariant spec from Task 2 extended with one example: "a committed distribution leaves both ledgers equal" (income 1000 → distribute → Σ still 1000 both sides).
- [ ] **Step 4: Commit** — `feat/two-ledger: distributing and reallocating write allocations over one root`.

---

### Task 5: Budget page, suggestions, rule CRUD, sacrifice

**Files:**
- Modify: `app/presenters/budget_page_presenter.rb` (groups are categories; `Band`/`account_bands`/`orphan_rules` DIE; reorder scope = all holder categories), `app/controllers/budget_page_controller.rb` (`#reorder` → `Category.apply_fill_order(user:, category_ids:)` — port `Pool.apply_fill_order`'s refusal+renumber to Category), `app/controllers/budgets_controller.rb` (owner = category: `BUDGET_FIELDS` swaps `:pool_id` → `:category_id`; `#set_envelope`/`#build_envelope` die — accepting a proposal stamps `funded_since` on the category if blank; the standalone form's picker lists `current_user.categories.expenses` — the dated-bill shape becomes creatable here: `basis`, `interval_months`, `anchor_date`, `item_id` rendered, `shape_must_be_valid` unchanged), `app/services/budget_proposal.rb` (no envelope minting/re-pointing: `write_all` = stamp funded_since + write rule), `app/services/suggestion_engine.rb` ("rate" detector = expense categories with spending in the window and `funded_since IS NULL`; drift/dead over category rules; `#fed_pool_ids`/`#default_account_id`/`#envelope_half`/`joined` die), `app/presenters/sacrifice_presenter.rb` (`#pool_rules` → `Budget.for_user(user)`), `app/views/budget_page/*` (no account bands, group header = category; `_suggestion*.erb` lose the re-point sentence and the joined-pool clause), `app/views/budgets/_form.html.erb`, `app/helpers/budget_page_helper.rb`, JS `reorder_controller.js` posts `category_ids[]`
- Test: convert `spec/presenters/budget_page_presenter_spec.rb`, `sacrifice_presenter_spec.rb`, `spec/services/suggestion_engine_spec.rb`, `spec/services/budget_proposal_spec.rb` (if present; else `spec/requests/budget_proposals_spec.rb`), `spec/requests/budget_page_spec.rb`, `budgets_spec.rb`, `suggestion_dismissals_spec.rb`, `spec/system/budget_page/*` (4), `spec/system/budgets/form_spec.rb`, `spec/system/sacrifices/show_spec.rb`

**Interfaces:**
- Consumes: Task 3's stack, `Category#priority`/`#funded_since`, `Allocation`.
- Produces: `Category.apply_fill_order(user:, category_ids:)`, `Category.in_fill_order` (holders by priority), the rule form's category picker; the suggestion "accept" payload carries `category_id` only (no `pool`/`pool_id` keys — `SuggestionDismissal` subjects unchanged).

- [ ] Same rhythm: convert specs (keep figures; delete per-account examples explicitly), port, green one file at a time, commit — `feat/two-ledger: rules, suggestions and the budget page live on categories`.

---

### Task 6: Home and the entry impact card

**Files:**
- Modify: `app/presenters/home_presenter.rb` (accounts band reads `AccountLedger` — `current_buffer_for` becomes `balance_of`; `pools_for(account)`, `orphan_*`, `Row#orphan`, `reachable_pools`, `all_pools` DIE; the category band: `available`, holder categories by priority, waterfall/cutoff/fixes over categories; `awaiting_funding?`/`awaiting_opening_balance?` read `AccountLedger`), `app/controllers/home_controller.rb`, `app/views/home/*` (`_account` shows the account's balance only — no pools inside it; a new `_categories.html.erb` band renders holder rows via `_pool_row` renamed `_holding_row`; `_orphans` DELETED; `_attention` loses the orphan term; `_standing` reads available), `app/helpers/home_helper.rb`, `app/presenters/entry_impact_presenter.rb` (`#pool` → `#holding` = `category if category.counts_spending_on?(date)`, `unbudgeted?` = no holding, `goal?` = `category.savings?`), `app/views/entries/_impact.html.erb`, `app/javascript/controllers/app/entry/impact_controller.js` (targets renamed if any say `pool`), `app/controllers/account_fundings_controller.rb` + `opening_balances_controller.rb` (`main.total` → `AccountLedger#pot`; `Pool#total` dies), `app/views/shared/_pool_status.html.erb` → `_holding_status.html.erb` (one rename, every renderer follows)
- Test: convert `spec/presenters/home_presenter_spec.rb`, `entry_impact_presenter_spec.rb`, `spec/requests/home_spec.rb`, `entry_impact_spec.rb`, `account_fundings_spec.rb`, `opening_balances_spec.rb`, `spec/system/home/*` (6), `spec/system/entries/impact_spec.rb`, `spec/helpers/*` (2)

- [ ] Same rhythm; commit — `feat/two-ledger: Home shows two ledgers, and the impact card reads the category`.

---

### Task 7: Categories screens, savings, dashboard, and the death of the Pools screens

**Files:**
- Modify: `app/controllers/categories_controller.rb` (`category_params`: `:pool_id` OUT; `:target_amount`, `:priority`, `:funded_since` IN), `app/views/categories/_form.html.erb` (no pool picker; target/priority/funded_since fields with hints), `app/views/categories/_partials/show/_budget_card.html.erb` + `_pool_card.html.erb` → one `_holdings_card.html.erb` (balance, rules, savings progress when `savings?`), `_summary_card`, `_suggestion_pointer`, `_category_card` (savings progress on the index card), `app/presenters/category_budget_presenter.rb`, dashboard presenters (`pools_summary` → savings categories; `buffer_funded?` → `!holder?`), `app/views/dashboard/_pools_strip.html.erb` (savings categories)
- Delete: `app/controllers/pools/categories_controller.rb`, `app/views/pools/categories/`, `app/views/pools/{index,show,new,edit,_form,_pool}.html.erb`, `app/helpers/pools_helper.rb`'s envelope arms; **routes**: `resources :pools` → `resources :bank_accounts, only: [:create, :edit, :update, :destroy]` (accounts keep rename/delete; `PoolsController` narrows to those three actions or folds into `BankAccountsController` — plan ruling: fold, and delete `PoolsController`); the sidebar's "Pools" nav item → "Categories" already exists; savings live there
- Test: convert `spec/requests/categories_spec.rb`, `spec/system/categories/*` (7 pool-touching files), `spec/system/dashboard/*` (3), `spec/requests/pools_spec.rb` → `bank_accounts_spec.rb` (extend), `spec/system/pools/*` (11 files: the account-relevant examples move to `spec/system/home/` or `spec/system/bank_accounts/`; the envelope/goal ones are DELETED — list each deletion in the report)

- [ ] Same rhythm; commit — `feat/two-ledger: categories are the one screen for what money is for`.

---

### Task 8: The drop — old rows, columns, classes; `pool_movements` becomes `account_movements`

**Files:**
- Create: `db/migrate/20260821010000_drop_the_pool_layer.rb`
- Modify/Delete: `app/models/pool.rb` (accounts only: name/uniqueness, `movements_in/out`, `#balance` via `AccountLedger`; every envelope/goal method, NOUNS, REFUSALS, destroy re-pointing, fill order, `#total`, `create_auto_categories` DELETED), `app/models/pool_movement.rb` → `app/models/account_movement.rb` (both sides must be accounts; kinds shrink to `transfer` — a check constraint or validation; `source_entry` stays for routing), `app/models/entry.rb` (`belongs_to :pool`, `reaching_pool`, `in_pool_named`, `effective_pool`, `income_must_land_in_an_account`, `pool_must_belong_to_user` DELETED; `route_income_to!` writes `AccountMovement`; searchable `:pool` field removed — update `docs/searchable-system-reference.md`'s worked example), `app/models/category.rb` (`belongs_to :pool`, `pool_must_be_reachable`, `income_must_land_in_an_account`, `effective_pool`, `buffer_funded?` DELETED), `app/models/budget.rb` (`pool` association and validators DELETED; `category` required), `app/models/user.rb` (`destroy_child_pools_first` DELETED), DELETE `app/services/pool_calculator.rb`, `pool_status.rb`, `pool_projection.rb`, `pool_balance_ledger.rb`, `app/presenters/reallocation_presenter.rb`'s dead arms, `db/seeds.rb` (rewritten category-native: same demo states, no envelopes; header state table updated), `spec/seeds_spec.rb`, `spec/factories/pools.rb` (account only), `spec/factories/pool_movements.rb` → `account_movements.rb`, `spec/support/schema_rewind.rb` (register the drop migration), every remaining spec that still says `budget_pool`/`savings`/`pool_movement` (`grep -rln "budget_pool\|:savings\b\|pool_movement" spec/` must return only `spec/migrations/*`)
- Migration: DELETE FROM pools WHERE pool_type <> 0 (after verifying every such pool's category carries `funded_since` — the Task 1 receipt — and that no `categories.pool_id`/`budgets.pool_id`/`entries.pool_id` references remain non-null except `categories.pool_id` → main, which is dropped with the column); `remove_column :categories, :pool_id`, `:entries, :pool_id`, `:budgets, :pool_id`; `remove_column :pools, :account_id` + its CHECK, `add_check_constraint :pools, "pool_type = 0", name: "pools_are_accounts"`; `rename_table :pool_movements, :account_movements`; `remove_column :pools, :start_date, :target_amount, :priority` (accounts don't use them — `target_amount`'s "buffer marker" was a parked question; ruling: dropped, the parked question is answered "no"); `budgets.category_id` NOT NULL.
- Test: `spec/migrations/drop_the_pool_layer_spec.rb` (rows gone, columns gone, invariant unchanged pre/post by raw SQL, the rename), `spec/migrations/cutover_spec.rb` 49/49 through the extended rewind, then **the FULL SUITE sequentially** (the controller's `run_suite.sh` loop — every file, one at a time; the tally line goes in the report).

- [ ] Order inside the task: (1) migration + its spec; (2) run the migration on test; (3) the model/class deletions and the spec sweep to green; (4) the migration on dev (Ming's data — receipt in the report); (5) seeds rewrite + seeds_spec; (6) full suite; (7) two commits — `feat/two-ledger: the pool layer is gone — pools are accounts, movements are account movements` and `chore/two-ledger: seeds and specs speak categories`.

---

### Task 9: Verification on Ming + docs closure

- [ ] Browser as Ming: Home shows the accounts band (Checking's balance = pot), the categories band with Food & Grocery holding $0 and its rule, `available` = her whole pot (nothing allocated), the period range; Budget page groups by category with no account bands; Categories page shows Food & Grocery's holdings card; no "Pools" nav; screenshot at 1440px left at repo root for the controller, console clean.
- [ ] Σ both ledgers on Ming by raw SQL (scoped to her email) == income − expenses == `AccountLedger#pot` (she has one account) == `CategoryLedger#available` (+ 0 holdings).
- [ ] Docs: `2026-08-21-two-ledger-design.md` → DELIVERED with an "as built" §10 (drifts + open items — at minimum: the `target_amount` on accounts dropped; the reallocation screen's new route; anything Task 8's sweep deleted that the spec didn't list); `docs/coding-standards.md` lines 7–13 rewritten for the new model; `docs/searchable-system-reference.md`'s worked example re-pointed at a surviving searchable field; `2026-08-14-envelope-budgeting-design.md` and `2026-08-18-main-account-design.md` get a one-line SUPERSEDED-in-part header pointing here.
- [ ] Commit — `docs/two-ledger: delivered — one total, two ledgers, verified on Ming`.

---

## Self-review (at write time)

- **Spec coverage:** §2 invariant → Task 2's keystone spec + every writer task's extension; §2 "no account→category movement" → shape of the two tables (T1/T8); §3 categories' job → T2 (columns/associations), T3 (calculators), T5 (rules), T7 (screens/savings); §4 start-date re-anchored → T2's `ENTRY_CATEGORY_ID` + `counts_spending_on?`; §5 deletions → T7 (screens), T8 (rows/columns/classes); §6 physical ledger untouched → `AccountLedger` reproduces today's account figures (numerically identical: every expense category already pointed at main); §7 migration → T1 (add+backfill, refuses multi-category) + T8 (drop); §8 out-of-scope respected (no table rename beyond `pool_movements`, no paid-from); §9 testing → per task.
- **Placeholders:** Task 1's `convert_movements`/`verify!` bodies are described as SQL steps rather than pasted (the plan says "no method may remain a stub"); Tasks 3–7 are ports with explicit mechanical rules, spec-first, figures preserved — the codebase's implementers have executed this shape before (Plan 3's seeds rewrite, the main-account plan). No TBDs.
- **Type consistency:** `CategoryLedger#terms_for`/`#available`/`#holding_of`, `AccountLedger#pot`/`#balance_of`/`#income_within`, `HoldingCalculator`/`HoldingStatus`/`HoldingProjection`, `Allocation` kinds, `Category#holder?`/`#savings?`/`#counts_spending_on?`, `Category.apply_fill_order(user:, category_ids:)`, `Entry.draining(category)` — each defined in one task and consumed by name in later ones.
