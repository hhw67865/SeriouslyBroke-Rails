# Pools & Rules Foundation — Implementation Plan (1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the complete domain model and calculators for envelope budgeting — pools, funding rules, movements, and pay cadence — without changing a single user-facing screen.

**Architecture:** Purely additive. `savings_pools` is renamed to `pools` and gains a type, a parent account, and a priority. `budgets` gains a nullable `pool_id` alongside its existing `category_id` so old category budgets keep working untouched while new pool budgets become possible. A new `pool_movements` table records transfers. Two new calculators compute what each rule and pool needs. Nothing is deleted; the existing suite stays green at every step.

**Tech Stack:** Rails 8.1, PostgreSQL (UUID PKs, `money` columns), RSpec, FactoryBot, Shoulda Matchers, Faker.

**Spec:** `docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md`

## Global Constraints

- **Work on a branch, commit each task, never push.** All work happens on
  `feature/envelope-budgeting`. Commit when a task is complete and its specs are
  green. **Never run `git push`** under any circumstance.
- **Commit messages are single-line**, no `Co-Authored-By` trailer.
- **Nothing may be deleted in this plan.** No dropped columns, no removed
  methods, no deleted specs. Removal happens in Plan 3.
- `# frozen_string_literal: true` at the top of every Ruby file.
- UUID primary keys: `id: :uuid, default: -> { "gen_random_uuid()" }`.
- Money columns: `t.money "name", scale: 2`.
- Run `bundle exec rubocop -A` before finishing any task.
- Run spec files **one at a time**, never a directory or the full suite:
  `bundle exec rspec spec/models/pool_spec.rb`
- Follow `docs/coding-standards.md` (Fat Models, Skinny Controllers, DRY) and the
  `system-test-writer` skill for any system specs.
- This plan adds **no** controllers, routes, or views. UI is Plan 2.

---

## File Structure

**Created**

| file | responsibility |
| --- | --- |
| `app/models/pool_movement.rb` | a transfer between two pools |
| `app/services/budget_calculator.rb` | one rule: due date, shortfall, required |
| `app/services/pool_calculator.rb` | one pool: balance, allocation across rules, required |
| `spec/factories/pool_movements.rb` | movement factory |
| `spec/models/pool_movement_spec.rb` | movement model spec |
| `spec/services/budget_calculator_spec.rb` | rule math |
| `spec/services/pool_calculator_spec.rb` | pool math |
| `spec/models/user_pay_dates_spec.rb` | cadence math |

**Modified**

| file | change |
| --- | --- |
| `app/models/savings_pool.rb` → `app/models/pool.rb` | renamed; gains type, account, priority |
| `app/models/budget.rb` | gains pool mode alongside category mode |
| `app/models/category.rb` | `savings_pool` → `pool` |
| `app/models/entry.rb` | `savings_pool` → `pool`; adds `pool` override |
| `app/models/user.rb` | `savings_pools` → `pools`; adds `pay_dates` |
| `app/models/item.rb` | adds `has_one :budget` |
| ~30 files referencing `savings_pool` | mechanical rename (Task 1) |

---

## Task 1: Rename SavingsPool to Pool

Mechanical rename with **zero behaviour change**. The entire existing suite is
the regression test. Do this first so every later task uses final names.

**Files:**
- Create: `db/migrate/<timestamp>_rename_savings_pools_to_pools.rb`
- Rename: `app/models/savings_pool.rb` → `app/models/pool.rb`
- Rename: `app/services/savings_pool_calculator.rb` → `app/services/pool_calculator.rb`
- Rename: `app/controllers/savings_pools_controller.rb` → `app/controllers/pools_controller.rb`
- Rename: `app/controllers/savings_pools/` → `app/controllers/pools/`
- Rename: `app/views/savings_pools/` → `app/views/pools/`
- Rename: `spec/factories/savings_pools.rb` → `spec/factories/pools.rb`
- Rename: `spec/models/savings_pool_spec.rb` → `spec/models/pool_spec.rb`
- Rename: `spec/services/savings_pool_calculator_spec.rb` → `spec/services/pool_calculator_spec.rb`
- Rename: `spec/system/savings_pools/` → `spec/system/pools/`
- Modify: `config/routes.rb`, `app/models/{category,entry,user}.rb`, all dashboard presenters and views listed by the grep in Step 2

**Interfaces:**
- Consumes: nothing
- Produces: `Pool` (was `SavingsPool`), `Category#pool` / `pool_id` (was `savings_pool`), `User#pools`, `Pool#calculator` returning `PoolCalculator`, route helpers `pools_path` / `pool_path`

- [ ] **Step 1: Write the migration**

```ruby
# frozen_string_literal: true

class RenameSavingsPoolsToPools < ActiveRecord::Migration[8.1]
  def change
    rename_table :savings_pools, :pools
    rename_column :categories, :savings_pool_id, :pool_id
  end
end
```

`rename_table` carries indexes and foreign keys with it, so nothing else is needed.

- [ ] **Step 2: Inventory every reference before touching anything**

Run: `grep -rn "savings_pool\|SavingsPool" app lib db/seeds.rb spec config --include="*.rb" --include="*.erb" | wc -l`

Record the count. Then list the files:

Run: `grep -rl "savings_pool\|SavingsPool" app lib db/seeds.rb spec config | sort`

Do **not** touch `db/migrate/` — historical migrations must keep their original
table names or they will no longer replay from scratch.

- [ ] **Step 3: Rename the files**

```bash
git mv app/models/savings_pool.rb app/models/pool.rb
git mv app/services/savings_pool_calculator.rb app/services/pool_calculator.rb
git mv app/controllers/savings_pools_controller.rb app/controllers/pools_controller.rb
git mv app/controllers/savings_pools app/controllers/pools
git mv app/views/savings_pools app/views/pools
git mv spec/factories/savings_pools.rb spec/factories/pools.rb
git mv spec/models/savings_pool_spec.rb spec/models/pool_spec.rb
git mv spec/services/savings_pool_calculator_spec.rb spec/services/pool_calculator_spec.rb
git mv spec/system/savings_pools spec/system/pools
git mv app/views/pools/_savings_pool.html.erb app/views/pools/_pool.html.erb
```

- [ ] **Step 4: Rewrite the identifiers**

Order matters — longest first, so `savings_pool_id` is not half-replaced by the
`savings_pool` rule.

```bash
FILES=$(grep -rl "savings_pool\|SavingsPool" app lib db/seeds.rb spec config)
sed -i '' \
  -e 's/savings_pool_id/pool_id/g' \
  -e 's/savings_pools/pools/g' \
  -e 's/savings_pool/pool/g' \
  -e 's/SavingsPoolCalculator/PoolCalculator/g' \
  -e 's/SavingsPoolsController/PoolsController/g' \
  -e 's/SavingsPool/Pool/g' \
  $FILES
```

Then fix the three things `sed` gets wrong:

1. `app/models/category.rb` — the `savings` enum value and the `:savings` trait
   must **not** have been renamed. Verify `enum :category_type` still reads
   `savings: 2`, and that `create_savings_category` on the pool model is intact.
2. `app/views/pools/show.html.erb` and `index.html.erb` — user-facing copy like
   "Savings Pool" should now read "Pool"; check headings and empty states.
3. `config/routes.rb` — confirm the block reads:

```ruby
resources :pools do
  member do
    get :categories, to: "pools/categories#index"
    patch :categories, to: "pools/categories#update"
  end
end
```

- [ ] **Step 5: Migrate and verify nothing was missed**

Run: `rails db:migrate`
Run: `grep -rn "savings_pool\|SavingsPool" app lib db/seeds.rb spec config`
Expected: no output. (Matches inside `db/migrate/` are correct and expected.)

- [ ] **Step 6: Run every affected spec file, one at a time**

```bash
bundle exec rspec spec/models/pool_spec.rb
bundle exec rspec spec/models/category_spec.rb
bundle exec rspec spec/models/entry_spec.rb
bundle exec rspec spec/models/item_spec.rb
bundle exec rspec spec/models/user_spec.rb
bundle exec rspec spec/models/budget_spec.rb
bundle exec rspec spec/services/pool_calculator_spec.rb
bundle exec rspec spec/system/pools/index/cards_spec.rb
bundle exec rspec spec/system/pools/show/progress_section_spec.rb
bundle exec rspec spec/system/categories/show/savings_pool_spec.rb
bundle exec rspec spec/system/dashboard/index/savings_pools_spec.rb
bundle exec rspec spec/system/entries/index/search_spec.rb
```

Expected: all PASS. A failure here is a missed reference, not a design problem.

- [ ] **Step 7: Verify seeds still run**

Run: `rails db:seed:replant`
Expected: completes without error.

- [ ] **Step 8: Lint and commit**

```bash
bundle exec rubocop -A
git add -A
git commit -m "refactor/pools: renamed SavingsPool to Pool"
```

---

## Task 2: Give pools a type, an account, and a priority

**Files:**
- Create: `db/migrate/<timestamp>_add_type_and_account_to_pools.rb`
- Modify: `app/models/pool.rb`
- Modify: `spec/factories/pools.rb`
- Test: `spec/models/pool_spec.rb`

**Interfaces:**
- Consumes: `Pool` from Task 1
- Produces: `Pool#pool_type` (enum `account`/`budget`/`savings`), `Pool#account` / `#account_id`, `Pool#child_pools`, `Pool#priority`, `Pool#total`, scopes `Pool.accounts` / `.budgets` / `.savings` / `.by_priority`, factory traits `:account` / `:budget_pool` / `:savings_pool`

- [ ] **Step 1: Write the failing test**

Add to `spec/models/pool_spec.rb`:

```ruby
describe "pool_type" do
  it { is_expected.to define_enum_for(:pool_type).with_values(account: 0, budget: 1, savings: 2) }

  it "requires budget pools to name an account" do
    pool = build(:pool, :budget_pool, account: nil)

    expect(pool).not_to be_valid
    expect(pool.errors[:account]).to include("must be set for budget and savings pools")
  end

  it "forbids account pools from naming an account" do
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

  it "requires the parent to belong to the same user" do
    pool = build(:pool, :budget_pool, user: create(:user), account: create(:pool, :account))

    expect(pool).not_to be_valid
    expect(pool.errors[:account]).to include("must belong to the same user")
  end
end

describe "#total" do
  it "sums the account's own balance and its child pools" do
    user = create(:user)
    checking = create(:pool, :account, user: user)
    create(:pool, :budget_pool, user: user, account: checking)

    expect(checking.child_pools.count).to eq(1)
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
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/models/pool_spec.rb`
Expected: FAIL — `NoMethodError: undefined method 'pool_type'` and unknown factory traits.

- [ ] **Step 3: Write the migration**

```ruby
# frozen_string_literal: true

class AddTypeAndAccountToPools < ActiveRecord::Migration[8.1]
  def change
    add_column :pools, :pool_type, :integer, null: false, default: 2
    add_column :pools, :priority, :integer, null: false, default: 0
    add_reference :pools, :account, type: :uuid, foreign_key: { to_table: :pools }, null: true

    add_index :pools, [:user_id, :priority]
  end
end
```

Default `2` (`savings`) preserves the meaning of every existing row: today all
pools are savings pools. `account_id` stays null on them until Plan 3's data
migration creates accounts.

Run: `rails db:migrate`

- [ ] **Step 4: Add the model behaviour**

In `app/models/pool.rb`, add below the existing associations:

```ruby
  belongs_to :account, class_name: "Pool", optional: true
  has_many :child_pools, class_name: "Pool", foreign_key: :account_id, dependent: :restrict_with_error,
                         inverse_of: :account

  # prefix: true is load-bearing — an unprefixed `account?` ("is an account")
  # sitting beside the `account` association ("its parent account") reads as its
  # own opposite and inverts silently.
  enum :pool_type, { account: 0, budget: 1, savings: 2 }, prefix: true

  scope :accounts, -> { where(pool_type: :account) }
  scope :budgets, -> { where(pool_type: :budget) }
  scope :savings, -> { where(pool_type: :savings) }
  scope :by_priority, -> { order(:priority, :name) }

  validate :account_matches_pool_type

  # What the bank actually says: unallocated cash plus every pool inside it.
  def total
    calculator.current_balance + child_pools.sum { |pool| pool.calculator.current_balance }
  end
```

`current_balance` (not `balance`) — Task 8 renames the primary method and keeps
`current_balance` as an alias, so this line is correct both before and after.

Relax the presence validations, since only savings pools have a target, and add
the per-user name uniqueness the spec requires (§3.2):

```ruby
  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :target_amount, presence: true, if: :pool_type_savings?
  validates :start_date, presence: true
```

And add the private validator:

```ruby
  def account_matches_pool_type
    if pool_type_account?
      errors.add(:account, "cannot be set on an account") if account_id.present?
      return
    end

    # Budget pools only. Savings pools are exempt until Plan 3's data migration
    # creates accounts and backfills them — every existing row is a savings pool
    # with account_id nil, so requiring it here invalidates the whole database.
    # PLAN 3 OBLIGATION: tighten this to include savings once the backfill lands.
    if account.blank?
      errors.add(:account, "must be set for budget and savings pools") if pool_type_budget?
      return
    end

    errors.add(:account, "must be an account") unless account.pool_type_account?
    errors.add(:account, "must belong to the same user") unless account.user_id == user_id
  end
```

**Note:** `Pool#savings?` now comes from the enum. The pre-existing
`create_savings_category` / `create_expense_category` attr_accessors are
unrelated and stay as they are.

- [ ] **Step 5: Update the factory**

Replace `spec/factories/pools.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :pool do
    name { "#{Faker::Commerce.product_name} #{Faker::Number.number(digits: 3)}" }
    target_amount { Faker::Number.decimal(l_digits: 3, r_digits: 2) }
    start_date { 1.year.ago.to_date }
    pool_type { :savings }
    association :user

    trait :account do
      pool_type { :account }
      name { "#{Faker::Bank.name} #{Faker::Number.number(digits: 3)}" }
      target_amount { nil }
      account { nil }
    end

    trait :budget_pool do
      pool_type { :budget }
      target_amount { nil }
      account { association :pool, :account, user: user }
    end

    trait :savings_pool do
      pool_type { :savings }
      account { association :pool, :account, user: user }
    end
  end
end
```

The bare `:pool` factory keeps producing an account-less savings pool so every
existing spec written against Task 1 still passes.

- [ ] **Step 6: Run the tests**

Run: `bundle exec rspec spec/models/pool_spec.rb`
Expected: PASS.

Run these to confirm nothing regressed:

```bash
bundle exec rspec spec/services/pool_calculator_spec.rb
bundle exec rspec spec/models/category_spec.rb
bundle exec rspec spec/system/pools/index/cards_spec.rb
bundle exec rspec spec/system/pools/form_spec.rb
```

Expected: PASS.

- [ ] **Step 7: Lint and commit**

```bash
bundle exec rubocop -A
git add -A
git commit -m "feature/pools: added pool types, parent accounts, and funding priority"
```

---

## Task 3: Pay cadence on the user

**Files:**
- Create: `db/migrate/<timestamp>_add_pay_schedule_to_users.rb`
- Modify: `app/models/user.rb`
- Modify: `spec/factories/users.rb`
- Test: `spec/models/user_pay_dates_spec.rb`

**Interfaces:**
- Consumes: `Pool` from Task 2
- Produces: `User#pay_cadence` (enum `weekly`/`biweekly`/`semimonthly`/`monthly`), `User#pay_anchor_date`, `User#default_account`, `User#pay_dates(from:, to:) -> Array<Date>` (inclusive both ends, ascending), factory trait `:biweekly`

- [ ] **Step 1: Write the failing test**

Create `spec/models/user_pay_dates_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "#pay_dates" do
    it "returns [] when no cadence is configured" do
      user = create(:user)

      expect(user.pay_dates(from: Date.new(2026, 2, 1), to: Date.new(2026, 3, 1))).to eq([])
    end

    it "walks biweekly from the anchor" do
      user = create(:user, pay_cadence: :biweekly, pay_anchor_date: Date.new(2026, 2, 6))

      dates = user.pay_dates(from: Date.new(2026, 2, 6), to: Date.new(2026, 3, 20))

      expect(dates).to eq([Date.new(2026, 2, 6), Date.new(2026, 2, 20),
                           Date.new(2026, 3, 6), Date.new(2026, 3, 20)])
    end

    it "starts from the first pay date on or after `from`" do
      user = create(:user, pay_cadence: :biweekly, pay_anchor_date: Date.new(2026, 2, 6))

      dates = user.pay_dates(from: Date.new(2026, 2, 7), to: Date.new(2026, 3, 7))

      expect(dates).to eq([Date.new(2026, 2, 20), Date.new(2026, 3, 6)])
    end

    # An anchor is ONE occurrence of a repeating schedule, not its start, so the
    # series extends backward from it too.
    it "extends backward from an anchor in the future" do
      user = create(:user, pay_cadence: :biweekly, pay_anchor_date: Date.new(2026, 5, 1))

      dates = user.pay_dates(from: Date.new(2026, 4, 1), to: Date.new(2026, 5, 20))

      expect(dates).to eq([Date.new(2026, 4, 3), Date.new(2026, 4, 17),
                           Date.new(2026, 5, 1), Date.new(2026, 5, 15)])
    end

    it "returns [] when the range is inverted" do
      user = create(:user, :biweekly)

      expect(user.pay_dates(from: Date.new(2026, 3, 1), to: Date.new(2026, 2, 1))).to eq([])
    end

    it "walks weekly" do
      user = create(:user, pay_cadence: :weekly, pay_anchor_date: Date.new(2026, 2, 6))

      dates = user.pay_dates(from: Date.new(2026, 2, 6), to: Date.new(2026, 2, 27))

      expect(dates).to eq([Date.new(2026, 2, 6), Date.new(2026, 2, 13),
                           Date.new(2026, 2, 20), Date.new(2026, 2, 27)])
    end

    it "walks monthly on the anchor's day" do
      user = create(:user, pay_cadence: :monthly, pay_anchor_date: Date.new(2026, 1, 15))

      dates = user.pay_dates(from: Date.new(2026, 2, 1), to: Date.new(2026, 4, 30))

      expect(dates).to eq([Date.new(2026, 2, 15), Date.new(2026, 3, 15), Date.new(2026, 4, 15)])
    end

    it "clamps a monthly anchor day to short months" do
      user = create(:user, pay_cadence: :monthly, pay_anchor_date: Date.new(2026, 1, 31))

      dates = user.pay_dates(from: Date.new(2026, 2, 1), to: Date.new(2026, 3, 31))

      expect(dates).to eq([Date.new(2026, 2, 28), Date.new(2026, 3, 31)])
    end

    it "pays twice a month for semimonthly, 15 days apart" do
      user = create(:user, pay_cadence: :semimonthly, pay_anchor_date: Date.new(2026, 1, 1))

      dates = user.pay_dates(from: Date.new(2026, 2, 1), to: Date.new(2026, 3, 31))

      expect(dates).to eq([Date.new(2026, 2, 1), Date.new(2026, 2, 16),
                           Date.new(2026, 3, 1), Date.new(2026, 3, 16)])
    end

    it "gives a 3-paycheck month for biweekly pay" do
      user = create(:user, pay_cadence: :biweekly, pay_anchor_date: Date.new(2026, 1, 2))

      dates = user.pay_dates(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 31))

      expect(dates.count).to eq(3)
    end
  end

  describe "#default_account" do
    it "must be an account pool owned by the user" do
      user = create(:user)
      other = create(:pool, :account)
      user.default_account = other

      expect(user).not_to be_valid
      expect(user.errors[:default_account]).to include("must be an account you own")
    end
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/models/user_pay_dates_spec.rb`
Expected: FAIL — `unknown attribute 'pay_cadence'`.

- [ ] **Step 3: Write the migration**

```ruby
# frozen_string_literal: true

class AddPayScheduleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :pay_cadence, :integer
    add_column :users, :pay_anchor_date, :date
    add_reference :users, :default_account, type: :uuid, foreign_key: { to_table: :pools }, null: true
  end
end
```

Run: `rails db:migrate`

- [ ] **Step 4: Implement on the model**

In `app/models/user.rb`, add to the associations block:

```ruby
  belongs_to :default_account, class_name: "Pool", optional: true

  enum :pay_cadence, { weekly: 0, biweekly: 1, semimonthly: 2, monthly: 3 }, prefix: :pay

  validate :default_account_is_own_account

  STRIDE_DAYS = { "weekly" => 7, "biweekly" => 14 }.freeze

  # Every pay date in [from, to], ascending. Empty unless a cadence is configured.
  def pay_dates(from:, to:)
    from = from.to_date
    to = to.to_date
    return [] if pay_cadence.blank? || pay_anchor_date.blank? || to < from

    case pay_cadence
    when "weekly", "biweekly" then strided_pay_dates(STRIDE_DAYS.fetch(pay_cadence), from, to)
    when "monthly"            then monthly_pay_dates([pay_anchor_date.day], from, to)
    when "semimonthly"        then monthly_pay_dates(semimonthly_days, from, to)
    else []
    end
  end
```

And privately:

```ruby
  def strided_pay_dates(stride, from, to)
    steps = ((from - pay_anchor_date).to_i / stride.to_f).ceil
    first = pay_anchor_date + (steps * stride)
    return [] if first > to

    (first..to).step(stride).to_a
  end

  def monthly_pay_dates(days, from, to)
    dates = []
    cursor = from.beginning_of_month
    while cursor <= to
      days.each do |day|
        date = cursor.change(day: [day, cursor.end_of_month.day].min)
        dates << date if date.between?(from, to)
      end
      cursor = cursor.next_month
    end
    dates.sort
  end

  def semimonthly_days
    first = pay_anchor_date.day
    [first, first <= 15 ? first + 15 : first - 15].sort
  end

  def default_account_is_own_account
    return if default_account.blank?
    return if default_account.pool_type_account? && default_account.user_id == id

    errors.add(:default_account, "must be an account you own")
  end
```

`prefix: :pay` keeps the enum from generating a bare `User#weekly?`, which would
be meaningless on a user.

- [ ] **Step 5: Add the factory trait**

In `spec/factories/users.rb`, inside the `factory :user` block:

```ruby
    trait :biweekly do
      pay_cadence { :biweekly }
      pay_anchor_date { Date.new(2026, 2, 6) }
    end
```

- [ ] **Step 6: Run the tests**

Run: `bundle exec rspec spec/models/user_pay_dates_spec.rb`
Expected: PASS — all 12 examples.

Run: `bundle exec rspec spec/models/user_spec.rb`
Expected: PASS.

- [ ] **Step 7: Lint and commit**

```bash
bundle exec rubocop -A
git add -A
git commit -m "feature/users: added pay cadence and pay date calculation"
```

---

## Task 4: Budgets gain a pool mode

`budgets.category_id` becomes nullable and `pool_id` is added beside it. A budget
is in exactly one mode. Every existing category budget keeps working unchanged;
Plan 3 drops the category mode entirely.

**Files:**
- Create: `db/migrate/<timestamp>_add_pool_mode_to_budgets.rb`
- Modify: `app/models/budget.rb`
- Modify: `app/models/pool.rb`, `app/models/item.rb`
- Modify: `spec/factories/budgets.rb`
- Test: `spec/models/budget_spec.rb`

**Interfaces:**
- Consumes: `Pool` (Task 2)
- Produces: `Budget#pool`, `Budget#item`, `Budget#interval_months`, `Budget#anchor_date`, `Budget#basis` (enum `monthly`/`per_paycheck`), `Budget#pool_mode?`, `Pool#budgets`, `Item#budget`, factory `:pool_budget` with traits `:rate`, `:per_paycheck_rate`, `:recurring`, `:one_time`

- [ ] **Step 1: Write the failing test**

Add to `spec/models/budget_spec.rb`:

```ruby
describe "pool mode" do
  let(:user) { create(:user) }
  let(:account) { create(:pool, :account, user: user) }
  let(:pool) { create(:pool, :budget_pool, user: user, account: account) }

  it "is valid attached to a pool with no category" do
    expect(build(:budget, pool: pool, category: nil)).to be_valid
  end

  it "rejects a budget attached to neither" do
    budget = build(:budget, pool: nil, category: nil)

    expect(budget).not_to be_valid
    expect(budget.errors[:base]).to include("must belong to either a category or a pool")
  end

  it "rejects a budget attached to both" do
    budget = build(:budget, pool: pool, category: create(:category, :expense, user: user))

    expect(budget).not_to be_valid
    expect(budget.errors[:base]).to include("cannot belong to both a category and a pool")
  end

  it "rejects a budget on an account pool" do
    budget = build(:budget, pool: account, category: nil)

    expect(budget).not_to be_valid
    expect(budget.errors[:pool]).to include("cannot be an account")
  end
end

describe "the four valid shapes" do
  let(:user) { create(:user) }
  let(:pool) { create(:pool, :budget_pool, user: user, account: create(:pool, :account, user: user)) }

  it "accepts a per-paycheck rate rule" do
    budget = build(:budget, pool: pool, category: nil,
                            anchor_date: nil, interval_months: nil, basis: :per_paycheck)

    expect(budget).to be_valid
  end

  it "accepts a monthly rate rule" do
    budget = build(:budget, pool: pool, category: nil,
                            anchor_date: nil, interval_months: 1, basis: :monthly)

    expect(budget).to be_valid
  end

  it "accepts a recurring obligation" do
    budget = build(:budget, pool: pool, category: nil,
                            anchor_date: Date.new(2026, 6, 1), interval_months: 6, basis: :monthly)

    expect(budget).to be_valid
  end

  it "accepts a one-time obligation" do
    budget = build(:budget, pool: pool, category: nil,
                            anchor_date: Date.new(2026, 6, 1), interval_months: nil, basis: :monthly)

    expect(budget).to be_valid
  end

  it "rejects a per-paycheck rule with an anchor date" do
    budget = build(:budget, pool: pool, category: nil,
                            anchor_date: Date.new(2026, 6, 1), interval_months: nil, basis: :per_paycheck)

    expect(budget).not_to be_valid
    expect(budget.errors[:basis]).to include("per-paycheck rules cannot have a due date or interval")
  end

  it "rejects a monthly rule with neither an anchor nor an interval" do
    budget = build(:budget, pool: pool, category: nil,
                            anchor_date: nil, interval_months: nil, basis: :monthly)

    expect(budget).not_to be_valid
    expect(budget.errors[:interval_months]).to include("is required for a monthly rule with no due date")
  end

  it "rejects a non-positive interval" do
    budget = build(:budget, pool: pool, category: nil, interval_months: 0, basis: :monthly)

    expect(budget).not_to be_valid
    expect(budget.errors[:interval_months]).to include("must be greater than 0")
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

  it "rejects an item from a category pointing at a different pool" do
    other_pool = create(:pool, :budget_pool, user: user, account: account)
    stray = create(:item, category: create(:category, :expense, user: user, pool: other_pool))
    budget = build(:budget, :recurring, pool: pool, category: nil, item: stray)

    expect(budget).not_to be_valid
    expect(budget.errors[:item]).to include("must belong to a category in this pool")
  end

  it "rejects an item already claimed by another rule" do
    create(:budget, :recurring, pool: pool, category: nil, item: item)
    budget = build(:budget, :recurring, pool: pool, category: nil, item: item)

    expect(budget).not_to be_valid
    expect(budget.errors[:item]).to include("is already used by another rule")
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/models/budget_spec.rb`
Expected: FAIL — `unknown attribute 'pool'`. The pre-existing category-mode
examples in this file must still pass at the end of the task.

- [ ] **Step 3: Write the migration**

```ruby
# frozen_string_literal: true

class AddPoolModeToBudgets < ActiveRecord::Migration[8.1]
  def change
    change_column_null :budgets, :category_id, true

    add_reference :budgets, :pool, type: :uuid, foreign_key: true, null: true
    add_reference :budgets, :item, type: :uuid, foreign_key: true, null: true

    add_column :budgets, :interval_months, :integer
    add_column :budgets, :anchor_date, :date
    add_column :budgets, :basis, :integer, null: false, default: 0

    add_index :budgets, :item_id, unique: true, where: "item_id IS NOT NULL",
                        name: "index_budgets_on_item_id_unique"
  end
end
```

Existing rows keep `category_id`, get `pool_id: nil`, `basis: 0` (`monthly`), and
`interval_months: nil` — which is a valid one-time shape, but category-mode
budgets never consult the shape validator, so this is inert. `prorated` is left
alone; Plan 3 drops it.

Run: `rails db:migrate`

- [ ] **Step 4: Rewrite the Budget model**

Replace `app/models/budget.rb`:

```ruby
# frozen_string_literal: true

class Budget < ApplicationRecord
  belongs_to :category, optional: true, touch: true
  belongs_to :pool, optional: true, touch: true
  belongs_to :item, optional: true

  enum :basis, { monthly: 0, per_paycheck: 1 }, prefix: true

  validates :amount, presence: true
  validates :interval_months, numericality: { greater_than: 0 }, allow_nil: true

  validate :exactly_one_owner
  validate :category_must_be_expense, if: :category_mode?
  validate :category_must_not_have_pool, if: :category_mode?
  validate :pool_must_not_be_an_account, if: :pool_mode?
  validate :shape_must_be_valid, if: :pool_mode?
  validate :item_must_belong_to_pool, if: :pool_mode?

  def category_mode? = category_id.present?
  def pool_mode? = pool_id.present?

  def user = category_mode? ? category.user : pool.user

  def calculator(today: Date.current)
    BudgetCalculator.new(self, today: today)
  end

  private

  def exactly_one_owner
    errors.add(:base, "must belong to either a category or a pool") if category_id.blank? && pool_id.blank?
    errors.add(:base, "cannot belong to both a category and a pool") if category_id.present? && pool_id.present?
  end

  def category_must_be_expense
    errors.add(:category, "must be an expense category") unless category&.expense?
  end

  def category_must_not_have_pool
    errors.add(:category, "cannot have a budget when linked to a savings pool") if category&.pool_id?
  end

  def pool_must_not_be_an_account
    errors.add(:pool, "cannot be an account") if pool&.pool_type_account?
  end

  # See docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md §3.1
  def shape_must_be_valid
    if basis_per_paycheck?
      if anchor_date.present? || interval_months.present?
        errors.add(:basis, "per-paycheck rules cannot have a due date or interval")
      end
      return
    end

    return if anchor_date.present?

    errors.add(:interval_months, "is required for a monthly rule with no due date") if interval_months.blank?
  end

  def item_must_belong_to_pool
    return if item.blank?

    errors.add(:item, "must belong to a category in this pool") unless item.category.pool_id == pool_id

    claimed = Budget.where(item_id: item_id).where.not(id: id).exists?
    errors.add(:item, "is already used by another rule") if claimed
  end
end
```

- [ ] **Step 5: Wire up the associations**

In `app/models/pool.rb`:

```ruby
  has_many :budgets, dependent: :destroy
```

In `app/models/item.rb`:

```ruby
  has_one :budget, dependent: :nullify
```

- [ ] **Step 6: Extend the factory**

Replace `spec/factories/budgets.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :budget do
    amount { Faker::Number.decimal(l_digits: 3, r_digits: 2) }
    association :category, factory: [:category, :expense]

    trait :prorated do
      prorated { true }
    end

    factory :pool_budget do
      category { nil }
      association :pool, factory: [:pool, :budget_pool]
      basis { :monthly }
      interval_months { 1 }
      anchor_date { nil }
    end

    # $300 every pay period, no due date — the catch-all
    trait :per_paycheck_rate do
      basis { :per_paycheck }
      interval_months { nil }
      anchor_date { nil }
    end

    # $600 a month, no due date
    trait :rate do
      basis { :monthly }
      interval_months { 1 }
      anchor_date { nil }
    end

    # $800 every 6 months, next due Jun 1
    trait :recurring do
      basis { :monthly }
      interval_months { 6 }
      anchor_date { Date.new(2026, 6, 1) }
    end

    # a savings goal or one-off bill — never rolls
    trait :one_time do
      basis { :monthly }
      interval_months { nil }
      anchor_date { Date.new(2026, 8, 1) }
    end
  end
end
```

- [ ] **Step 7: Run the tests**

Run: `bundle exec rspec spec/models/budget_spec.rb`
Expected: PASS — both the new pool-mode examples and every pre-existing
category-mode example.

Run these to confirm the category path is untouched:

```bash
bundle exec rspec spec/services/category_calculator_spec.rb
bundle exec rspec spec/models/category_spec.rb
bundle exec rspec spec/system/budgets/form_spec.rb
bundle exec rspec spec/system/categories/show/budget_spec.rb
```

Expected: PASS.

- [ ] **Step 8: Lint and commit**

```bash
bundle exec rubocop -A
git add -A
git commit -m "feature/budgets: budgets can now attach to a pool with a cadence and due date"
```

---

## Task 5: PoolMovement

**Files:**
- Create: `db/migrate/<timestamp>_create_pool_movements.rb`
- Create: `app/models/pool_movement.rb`
- Create: `spec/factories/pool_movements.rb`
- Create: `spec/models/pool_movement_spec.rb`
- Modify: `app/models/pool.rb`, `app/models/entry.rb`

**Interfaces:**
- Consumes: `Pool` (Task 2)
- Produces: `PoolMovement#from_pool` / `#to_pool` / `#amount` / `#date` / `#source_entry`, `PoolMovement#crosses_accounts?`, `Pool#movements_in` / `#movements_out`, `Entry#pool_movements`, factory `:pool_movement`

- [ ] **Step 1: Write the failing test**

Create `spec/models/pool_movement_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PoolMovement, type: :model do
  let(:user) { create(:user) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:groceries) { create(:pool, :budget_pool, user: user, account: checking, name: "Groceries") }
  let(:car) { create(:pool, :budget_pool, user: user, account: checking, name: "Car") }

  describe "associations" do
    it { is_expected.to belong_to(:from_pool).class_name("Pool") }
    it { is_expected.to belong_to(:to_pool).class_name("Pool") }
    it { is_expected.to belong_to(:source_entry).class_name("Entry").optional }
  end

  describe "validations" do
    it "requires a positive amount" do
      movement = build(:pool_movement, from_pool: checking, to_pool: groceries, amount: 0)

      expect(movement).not_to be_valid
      expect(movement.errors[:amount]).to include("must be greater than 0")
    end

    it "rejects a movement to the same pool" do
      movement = build(:pool_movement, from_pool: checking, to_pool: checking)

      expect(movement).not_to be_valid
      expect(movement.errors[:to_pool]).to include("must differ from the source pool")
    end

    it "rejects a movement between two users' pools" do
      movement = build(:pool_movement, from_pool: checking, to_pool: create(:pool, :account))

      expect(movement).not_to be_valid
      expect(movement.errors[:to_pool]).to include("must belong to the same user")
    end
  end

  describe "#crosses_accounts?" do
    it "is false for two pools in the same account" do
      movement = build(:pool_movement, from_pool: groceries, to_pool: car)

      expect(movement).not_to be_crosses_accounts
    end

    it "is false when moving from an account to its own pool" do
      movement = build(:pool_movement, from_pool: checking, to_pool: groceries)

      expect(movement).not_to be_crosses_accounts
    end

    it "is true when the destination lives in a different account" do
      savings_account = create(:pool, :account, user: user, name: "Savings Account")
      vacation = create(:pool, :savings_pool, user: user, account: savings_account)
      movement = build(:pool_movement, from_pool: checking, to_pool: vacation)

      expect(movement).to be_crosses_accounts
    end
  end

  describe "grouping by source entry" do
    it "is destroyed with its source entry" do
      income = create(:entry, :income)
      create(:pool_movement, from_pool: checking, to_pool: groceries, source_entry: income)

      expect { income.destroy }.to change(described_class, :count).by(-1)
    end
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/models/pool_movement_spec.rb`
Expected: FAIL — `uninitialized constant PoolMovement`.

- [ ] **Step 3: Write the migration**

```ruby
# frozen_string_literal: true

class CreatePoolMovements < ActiveRecord::Migration[8.1]
  def change
    create_table :pool_movements, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :from_pool, type: :uuid, null: false, foreign_key: { to_table: :pools }
      t.references :to_pool, type: :uuid, null: false, foreign_key: { to_table: :pools }
      t.references :source_entry, type: :uuid, null: true, foreign_key: { to_table: :entries }
      t.money :amount, scale: 2, null: false
      t.datetime :date, null: false
      t.timestamps
    end

    add_index :pool_movements, :date
  end
end
```

Run: `rails db:migrate`

- [ ] **Step 4: Write the model**

Create `app/models/pool_movement.rb`:

```ruby
# frozen_string_literal: true

# A transfer of money between two of a user's own pools. Net worth is unchanged.
# Money entering or leaving the user's life is an Entry, never a PoolMovement.
class PoolMovement < ApplicationRecord
  belongs_to :from_pool, class_name: "Pool", touch: true
  belongs_to :to_pool, class_name: "Pool", touch: true
  belongs_to :source_entry, class_name: "Entry", optional: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true

  validate :pools_must_differ
  validate :pools_must_share_a_user

  scope :for_entry, ->(entry) { where(source_entry: entry) }

  delegate :user, to: :from_pool

  # True when the money has to physically move between real bank accounts.
  def crosses_accounts?
    (from_pool.account_id || from_pool.id) != (to_pool.account_id || to_pool.id)
  end

  private

  def pools_must_differ
    errors.add(:to_pool, "must differ from the source pool") if from_pool_id.present? && from_pool_id == to_pool_id
  end

  def pools_must_share_a_user
    return if from_pool.blank? || to_pool.blank?

    errors.add(:to_pool, "must belong to the same user") unless from_pool.user_id == to_pool.user_id
  end
end
```

`crosses_accounts?` treats an account pool as its own account, so
Checking → Groceries (a pool inside Checking) is correctly *not* a crossing.

- [ ] **Step 5: Wire up the associations**

In `app/models/pool.rb`:

```ruby
  has_many :movements_in, class_name: "PoolMovement", foreign_key: :to_pool_id,
                          dependent: :destroy, inverse_of: :to_pool
  has_many :movements_out, class_name: "PoolMovement", foreign_key: :from_pool_id,
                           dependent: :destroy, inverse_of: :from_pool
```

In `app/models/entry.rb`:

```ruby
  has_many :pool_movements, foreign_key: :source_entry_id, dependent: :destroy, inverse_of: :source_entry
```

- [ ] **Step 6: Write the factory**

Create `spec/factories/pool_movements.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :pool_movement do
    amount { Faker::Number.decimal(l_digits: 2, r_digits: 2) }
    date { Time.zone.now }
    association :from_pool, factory: [:pool, :account]

    to_pool do
      association :pool, :budget_pool, user: from_pool.user, account: from_pool
    end
  end
end
```

- [ ] **Step 7: Run the tests**

Run: `bundle exec rspec spec/models/pool_movement_spec.rb`
Expected: PASS.

Run: `bundle exec rspec spec/models/entry_spec.rb`
Run: `bundle exec rspec spec/models/pool_spec.rb`
Expected: PASS.

- [ ] **Step 8: Lint and commit**

```bash
bundle exec rubocop -A
git add -A
git commit -m "feature/pools: added pool movements for transfers between pools"
```

---

## Task 6: Entry pool override

One nullable column so an income entry can name the account it landed in, and any
entry can override its category's pool.

**Files:**
- Create: `db/migrate/<timestamp>_add_pool_to_entries.rb`
- Modify: `app/models/entry.rb`, `app/models/category.rb`
- Test: `spec/models/entry_spec.rb`

**Interfaces:**
- Consumes: `Pool` (Task 2), `User#default_account` (Task 3)
- Produces: `Entry#pool` (association), `Entry#effective_pool -> Pool | nil`, `Category#effective_pool -> Pool | nil`

- [ ] **Step 1: Write the failing test**

Add to `spec/models/entry_spec.rb`:

```ruby
describe "#effective_pool" do
  let(:user) { create(:user) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:groceries) { create(:pool, :budget_pool, user: user, account: checking) }

  it "uses the entry's own pool when set" do
    savings_account = create(:pool, :account, user: user, name: "Savings Account")
    category = create(:category, :income, user: user, pool: checking)
    entry = create(:entry, item: create(:item, category: category), pool: savings_account)

    expect(entry.effective_pool).to eq(savings_account)
  end

  it "falls back to the category's pool" do
    category = create(:category, :expense, user: user, pool: groceries)
    entry = create(:entry, item: create(:item, category: category))

    expect(entry.effective_pool).to eq(groceries)
  end

  it "falls back to the user's default account when the category has no pool" do
    user.update!(default_account: checking)
    category = create(:category, :expense, user: user, pool: nil)
    entry = create(:entry, item: create(:item, category: category))

    expect(entry.effective_pool).to eq(checking)
  end

  it "is nil when nothing resolves" do
    category = create(:category, :expense, user: user, pool: nil)
    entry = create(:entry, item: create(:item, category: category))

    expect(entry.effective_pool).to be_nil
  end

  it "rejects a pool belonging to another user" do
    category = create(:category, :expense, user: user, pool: groceries)
    entry = build(:entry, item: create(:item, category: category), pool: create(:pool, :account))

    expect(entry).not_to be_valid
    expect(entry.errors[:pool]).to include("must belong to the same user")
  end
end
```

And add to `spec/models/category_spec.rb` (spec §3.2 — income lands in an
account, never directly in an envelope):

```ruby
describe "income categories" do
  let(:user) { create(:user) }
  let(:checking) { create(:pool, :account, user: user) }

  it "may point at an account pool" do
    expect(build(:category, :income, user: user, pool: checking)).to be_valid
  end

  it "may point at no pool at all" do
    expect(build(:category, :income, user: user, pool: nil)).to be_valid
  end

  it "may not point at a budget pool" do
    groceries = create(:pool, :budget_pool, user: user, account: checking)
    category = build(:category, :income, user: user, pool: groceries)

    expect(category).not_to be_valid
    expect(category.errors[:pool]).to include("must be an account for income categories")
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/models/entry_spec.rb`
Expected: FAIL — `unknown attribute 'pool'`.

- [ ] **Step 3: Write the migration**

```ruby
# frozen_string_literal: true

class AddPoolToEntries < ActiveRecord::Migration[8.1]
  def change
    add_reference :entries, :pool, type: :uuid, foreign_key: true, null: true
  end
end
```

Run: `rails db:migrate`

- [ ] **Step 4: Implement the fallback chain**

In `app/models/entry.rb`:

```ruby
  belongs_to :pool, optional: true

  validate :pool_must_belong_to_user

  # entry override -> category's pool -> the user's default account
  def effective_pool
    pool || category.effective_pool
  end

  private

  def pool_must_belong_to_user
    return if pool.blank?

    errors.add(:pool, "must belong to the same user") unless pool.user_id == user.id
  end
```

In `app/models/category.rb`. **`effective_pool` must be public** — `PoolCalculator`
and Plan 2 both call it; the `private` below applies only to the validator:

```ruby
  validate :income_must_land_in_an_account

  # public
  def effective_pool
    pool || user.default_account
  end

  private

  def income_must_land_in_an_account
    return if pool.blank? || !income?

    errors.add(:pool, "must be an account for income categories") unless pool.pool_type_account?
  end
```

- [ ] **Step 5: Run the tests**

Run: `bundle exec rspec spec/models/entry_spec.rb`
Expected: PASS.

Run: `bundle exec rspec spec/models/category_spec.rb`
Expected: PASS.

- [ ] **Step 6: Lint and commit**

```bash
bundle exec rubocop -A
git add -A
git commit -m "feature/entries: entries can override their category's pool"
```

---

## Task 7: BudgetCalculator

The requirement math for a single rule. See spec §4.1 and §4.2.

**Files:**
- Create: `app/services/budget_calculator.rb`
- Create: `spec/services/budget_calculator_spec.rb`

**Interfaces:**
- Consumes: `Budget` (Task 4), `User#pay_dates` (Task 3)
- Produces: `BudgetCalculator.new(budget, today:)` with `#target`, `#due_date`, `#period_end`, `#cycles_completed`, `#overdue?`, `#shortfall(allocated)`, `#periods_until_due`, `#required(allocated)`. `allocated` is the portion of the pool's balance assigned to this rule and is supplied by `PoolCalculator` in Task 8.

- [ ] **Step 1: Write the failing test**

Create `spec/services/budget_calculator_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BudgetCalculator, type: :model do
  let(:user) { create(:user, pay_cadence: :biweekly, pay_anchor_date: Date.new(2026, 2, 6)) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:car) { create(:pool, :budget_pool, user: user, account: checking, name: "Car") }
  let(:category) { create(:category, :expense, user: user, name: "Car Spending", pool: car) }
  let(:today) { Date.new(2026, 2, 6) }

  describe "#due_date" do
    it "is the end of the calendar month for a monthly rate rule" do
      budget = create(:pool_budget, :rate, pool: car, amount: 80)

      expect(budget.calculator(today: today).due_date).to eq(Date.new(2026, 2, 28))
    end

    it "is the day before the next paycheck for a per-paycheck rate rule" do
      budget = create(:pool_budget, :per_paycheck_rate, pool: car, amount: 300)

      expect(budget.calculator(today: today).due_date).to eq(Date.new(2026, 2, 19))
    end

    it "is the anchor itself for a one-time rule" do
      budget = create(:pool_budget, :one_time, pool: car, amount: 500, anchor_date: Date.new(2026, 8, 1))

      expect(budget.calculator(today: today).due_date).to eq(Date.new(2026, 8, 1))
    end

    it "rolls by elapsed intervals when the rule has no item" do
      budget = create(:pool_budget, :recurring, pool: car, amount: 800,
                                                interval_months: 6, anchor_date: Date.new(2026, 6, 1))

      expect(budget.calculator(today: Date.new(2026, 7, 1)).due_date).to eq(Date.new(2026, 12, 1))
    end

    it "does NOT roll on the date alone when the rule has an item" do
      item = create(:item, category: category, name: "Insurance")
      budget = create(:pool_budget, :recurring, pool: car, amount: 800,
                                                interval_months: 6, anchor_date: Date.new(2026, 6, 1),
                                                item: item)

      expect(budget.calculator(today: Date.new(2026, 7, 1)).due_date).to eq(Date.new(2026, 6, 1))
    end

    it "rolls once the bill is actually recorded on the item" do
      item = create(:item, category: category, name: "Insurance")
      budget = create(:pool_budget, :recurring, pool: car, amount: 800,
                                                interval_months: 6, anchor_date: Date.new(2026, 6, 1),
                                                item: item)
      create(:entry, item: item, amount: 800, date: Date.new(2026, 6, 2))

      expect(budget.calculator(today: Date.new(2026, 7, 1)).due_date).to eq(Date.new(2026, 12, 1))
    end
  end

  describe "#overdue?" do
    let(:item) { create(:item, category: category, name: "Insurance") }
    let(:budget) do
      create(:pool_budget, :recurring, pool: car, amount: 800,
                                       interval_months: 6, anchor_date: Date.new(2026, 6, 1), item: item)
    end

    it "is true when the due date has passed with no entry" do
      expect(budget.calculator(today: Date.new(2026, 6, 3))).to be_overdue
    end

    it "is false once the entry is recorded" do
      create(:entry, item: item, amount: 800, date: Date.new(2026, 6, 2))

      expect(budget.calculator(today: Date.new(2026, 6, 3))).not_to be_overdue
    end

    it "is never true for a rule with no item" do
      no_item = create(:pool_budget, :recurring, pool: car, amount: 800,
                                                 interval_months: 6, anchor_date: Date.new(2026, 6, 1))

      expect(no_item.calculator(today: Date.new(2026, 12, 3))).not_to be_overdue
    end
  end

  describe "#required" do
    # Spec §4.4: Car pool, Feb 6, biweekly. Paydays Feb 6, Feb 20, Mar 6...
    it "spreads an obligation across the paychecks before it is due" do
      budget = create(:pool_budget, pool: car, amount: 600,
                                    interval_months: 6, anchor_date: Date.new(2026, 3, 1))

      # 2 paydays in [Feb 6, Mar 1]: Feb 6 and Feb 20. Shortfall 600 - 500 = 100.
      expect(budget.calculator(today: today).required(500)).to eq(50.00)
    end

    it "demands the whole shortfall when the bill lands before the next paycheck" do
      budget = create(:pool_budget, pool: car, amount: 600,
                                    interval_months: 6, anchor_date: Date.new(2026, 2, 7))

      expect(budget.calculator(today: today).required(0)).to eq(600.00)
    end

    it "is zero when the rule is already funded" do
      budget = create(:pool_budget, pool: car, amount: 600,
                                    interval_months: 6, anchor_date: Date.new(2026, 3, 1))

      expect(budget.calculator(today: today).required(600)).to eq(0)
    end

    it "is zero when the rule is overfunded" do
      budget = create(:pool_budget, pool: car, amount: 600,
                                    interval_months: 6, anchor_date: Date.new(2026, 3, 1))

      expect(budget.calculator(today: today).required(750)).to eq(0)
    end

    it "rises sharply after an unexpected expense drains the reserve" do
      budget = create(:pool_budget, pool: car, amount: 600,
                                    interval_months: 6, anchor_date: Date.new(2026, 3, 1))

      # spec §4.4: after $420 of tires, insurance is left with only $80 allocated
      expect(budget.calculator(today: today).required(80)).to eq(260.00)
    end

    it "spreads a distant obligation thinly" do
      budget = create(:pool_budget, pool: car, amount: 180,
                                    interval_months: 12, anchor_date: Date.new(2026, 8, 15))

      # 14 paydays in [Feb 6, Aug 15]
      expect(budget.calculator(today: today).required(0)).to eq(12.86)
    end
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/services/budget_calculator_spec.rb`
Expected: FAIL — `uninitialized constant BudgetCalculator`.

- [ ] **Step 3: Write the calculator**

Create `app/services/budget_calculator.rb`:

```ruby
# frozen_string_literal: true

# Computes what a single funding rule needs from the next paycheck.
# See docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md §4.1-4.2
class BudgetCalculator
  attr_reader :budget, :today

  def initialize(budget, today: Date.current)
    @budget = budget
    @today = today
  end

  def target = budget.amount

  # The cycle rolls when the bill is PAID, not when the date passes. Rolling on
  # the date alone would silently forget an obligation that was never settled.
  def due_date
    return period_end if budget.anchor_date.nil?
    return budget.anchor_date if budget.interval_months.nil?

    budget.anchor_date + (cycles_completed * budget.interval_months).months
  end

  def period_end
    budget.basis_per_paycheck? ? pay_period_end : today.end_of_month
  end

  def cycles_completed
    return elapsed_cycles if budget.item.nil?

    budget.item.entries.where(date: budget.anchor_date..).count
  end

  # How many occurrences of this bill have already come due, regardless of what
  # was recorded. Once today reaches the anchor, one occurrence has passed — so
  # this is (whole intervals elapsed) + 1, never a bare division.
  def elapsed_cycles
    return 0 if today < budget.anchor_date

    months = ((today.year * 12) + today.month) - ((budget.anchor_date.year * 12) + budget.anchor_date.month)
    months -= 1 if today.day < budget.anchor_date.day
    (months / budget.interval_months) + 1
  end

  def overdue?
    budget.item.present? && due_date < today
  end

  def shortfall(allocated)
    [target - allocated, 0].max
  end

  def periods_until_due
    [user.pay_dates(from: today, to: due_date).count, 1].max
  end

  def required(allocated)
    (shortfall(allocated) / periods_until_due).round(2)
  end

  private

  # Budget#user resolves in both category and pool mode, so this never nils out.
  def user = budget.user

  def pay_period_end
    next_payday = user.pay_dates(from: today + 1, to: today + 45).first
    next_payday ? next_payday - 1 : today.end_of_month
  end
end
```

- [ ] **Step 4: Run the tests**

Run: `bundle exec rspec spec/services/budget_calculator_spec.rb`
Expected: PASS — all 16 examples.

If `required` returns a `BigDecimal` that fails `eq(50.00)`, the money column is
returning a string; add `.to_d` where `budget.amount` is read in `#target`.

- [ ] **Step 5: Lint and commit**

```bash
bundle exec rubocop -A
git add -A
git commit -m "feature/pools: added budget calculator for per-paycheck funding requirements"
```

---

## Task 8: PoolCalculator

Replaces the balance logic renamed in Task 1. Spec §2.2 and §4.3.

**Files:**
- Modify: `app/services/pool_calculator.rb`
- Modify: `spec/services/pool_calculator_spec.rb`
- Modify: `app/models/pool.rb`

**Interfaces:**
- Consumes: `BudgetCalculator` (Task 7), `PoolMovement` (Task 5), `Entry#effective_pool` (Task 6)
- Produces: `PoolCalculator#balance`, `#allocated_balances -> {Budget => BigDecimal}`, `#free_amount`, `#required`, `#reserve`, and the retained `#progress_percentage` / `#remaining_amount` / `#current_balance`

- [ ] **Step 1: Write the failing test**

Add to `spec/services/pool_calculator_spec.rb` (keep the existing examples; they
cover the savings-pool behaviour that must survive):

```ruby
describe "envelope behaviour" do
  let(:envelope_user) { create(:user, pay_cadence: :biweekly, pay_anchor_date: Date.new(2026, 2, 6)) }
  let(:checking) { create(:pool, :account, user: envelope_user, name: "Checking") }
  let(:car) { create(:pool, :budget_pool, user: envelope_user, account: checking, name: "Car") }
  let(:car_category) { create(:category, :expense, user: envelope_user, name: "Car Spending", pool: car) }
  let(:today) { Date.new(2026, 2, 6) }

  describe "#balance" do
    it "counts movements in, movements out, and expense entries" do
      create(:pool_movement, from_pool: checking, to_pool: car, amount: 700)
      create(:pool_movement, from_pool: car, to_pool: checking, amount: 50)
      create(:entry, item: create(:item, category: car_category), amount: 70, date: today)

      expect(car.calculator(today: today).balance).to eq(580.00)
    end

    it "counts income entries into an account" do
      income_category = create(:category, :income, user: envelope_user, pool: checking)
      create(:entry, item: create(:item, category: income_category), amount: 2_400, date: today)
      create(:pool_movement, from_pool: checking, to_pool: car, amount: 400)

      expect(checking.calculator(today: today).balance).to eq(2_000.00)
    end

    it "goes negative when a pool is overspent" do
      create(:pool_movement, from_pool: checking, to_pool: car, amount: 100)
      create(:entry, item: create(:item, category: car_category), amount: 150, date: today)

      expect(car.calculator(today: today).balance).to eq(-50.00)
    end
  end

  describe "#allocated_balances" do
    # Spec §4.4 — earliest due date fills first.
    let!(:gas) { create(:pool_budget, :rate, pool: car, amount: 80) }
    let!(:insurance) do
      create(:pool_budget, pool: car, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
    end
    let!(:registration) do
      create(:pool_budget, pool: car, amount: 180, interval_months: 12, anchor_date: Date.new(2026, 8, 15))
    end

    it "fills by due date and leaves nothing free", :aggregate_failures do
      create(:pool_movement, from_pool: checking, to_pool: car, amount: 580)
      calc = car.calculator(today: today)

      expect(calc.allocated_balances[gas]).to eq(80.00)
      expect(calc.allocated_balances[insurance]).to eq(500.00)
      expect(calc.allocated_balances[registration]).to eq(0)
      expect(calc.free_amount).to eq(0)
    end

    it "reports the surplus beyond every rule as free" do
      create(:pool_movement, from_pool: checking, to_pool: car, amount: 1_000)

      expect(car.calculator(today: today).free_amount).to eq(140.00)
    end

    it "gives every rule zero when the pool is negative", :aggregate_failures do
      create(:entry, item: create(:item, category: car_category), amount: 50, date: today)
      calc = car.calculator(today: today)

      expect(calc.allocated_balances.values).to all(eq(0))
      expect(calc.free_amount).to eq(0)
    end

    it "totals the pool's requirement across its rules" do
      create(:pool_movement, from_pool: checking, to_pool: car, amount: 580)

      # gas $0 + insurance $50.00 + registration $12.86
      expect(car.calculator(today: today).required).to eq(62.86)
    end

    it "raises the requirement after an unexpected expense" do
      create(:pool_movement, from_pool: checking, to_pool: car, amount: 580)
      create(:entry, item: create(:item, category: car_category, name: "New tires"), amount: 420, date: today)

      # gas $0 + insurance $260.00 + registration $12.86
      expect(car.calculator(today: today).required).to eq(272.86)
    end
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/services/pool_calculator_spec.rb`
Expected: FAIL — `wrong number of arguments` or `undefined method 'allocated_balances'`.

- [ ] **Step 3: Rewrite the calculator**

Replace `app/services/pool_calculator.rb`:

```ruby
# frozen_string_literal: true

# Computes a pool's balance and how that balance is spoken for by its rules.
# See docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md §2.2, §4.3
class PoolCalculator
  attr_reader :pool, :today

  def initialize(pool, as_of: nil, today: Date.current)
    @pool = pool
    @as_of = as_of
    @today = today
  end

  def balance
    income_entries_total + movements_in_total - movements_out_total - expense_entries_total
  end

  # Retained for the savings-pool views; identical to #balance.
  alias current_balance balance

  # Earliest due date fills first: the money you need soonest must actually be there.
  def allocated_balances
    @allocated_balances ||= begin
      remaining = balance
      budgets_by_due_date.index_with do |budget|
        taken = remaining.clamp(0, budget.amount)
        remaining -= taken
        taken
      end
    end
  end

  def reserve = allocated_balances.values.sum

  def free_amount = [balance - reserve, 0].max

  def required
    budgets_by_due_date.sum { |budget| budget.calculator(today: today).required(allocated_balances[budget]) }
  end

  def progress_percentage
    return 0 unless pool.target_amount.to_f.positive?

    [(balance / pool.target_amount * 100).round, 100].min
  end

  def remaining_amount
    [pool.target_amount.to_f - balance, 0].max
  end

  def contributions = movements_in_total

  def withdrawals = movements_out_total + expense_entries_total

  private

  def budgets_by_due_date
    @budgets_by_due_date ||= pool.budgets.includes(:item, :pool).sort_by { |b| b.calculator(today: today).due_date }
  end

  # Entry.incomes / .expenses already join item: :category, so do not join again.
  # An entry's own pool_id overrides its category's, so both must be honoured —
  # otherwise Entry#pool is a column nothing reads.
  def income_entries_total
    scoped(Entry.incomes.merge(entries_for_pool)).sum(:amount)
  end

  def expense_entries_total
    scoped(Entry.expenses.merge(entries_for_pool)).sum(:amount)
  end

  # One predicate rather than .or — Entry.incomes already carries the categories
  # join, and .or rejects relations whose joins differ structurally.
  def entries_for_pool
    Entry.where(
      "entries.pool_id = :id OR (entries.pool_id IS NULL AND categories.pool_id = :id)",
      id: pool.id
    )
  end

  def movements_in_total = scoped(pool.movements_in).sum(:amount)

  def movements_out_total = scoped(pool.movements_out).sum(:amount)

  def scoped(relation)
    @as_of ? relation.where(date: ..@as_of) : relation
  end
end
```

- [ ] **Step 4: Update the Pool entry point**

In `app/models/pool.rb`, replace the existing `#calculator`:

```ruby
  def calculator(as_of: nil, today: Date.current)
    PoolCalculator.new(self, as_of: as_of, today: today)
  end
```

The keyword-only signature means every existing `pool.calculator(as_of: ...)`
call site keeps working unchanged.

- [ ] **Step 5: Run the tests**

Run: `bundle exec rspec spec/services/pool_calculator_spec.rb`
Expected: PASS — the new envelope examples **and** every pre-existing
savings-pool example.

The old examples build contributions from savings-category entries, which
`#balance` no longer counts. If they fail, that is expected and correct — mark
those examples pending with
`pending "savings-category contributions become movements in Plan 3"` rather than
deleting or rewriting them. Plan 3 converts them.

- [ ] **Step 6: Run the wider regression set**

```bash
bundle exec rspec spec/models/pool_spec.rb
bundle exec rspec spec/system/pools/show/progress_section_spec.rb
bundle exec rspec spec/system/pools/index/cards_spec.rb
bundle exec rspec spec/system/dashboard/index/savings_pools_spec.rb
bundle exec rspec spec/system/dashboard/index/savings_tab_spec.rb
```

Any failure here is a pool whose balance previously came from savings entries.
Mark pending with the same note; do not change the calculator to accommodate it.
Record the list of pending examples in the handoff — Plan 3 starts by clearing it.

- [ ] **Step 7: Lint and commit**

```bash
bundle exec rubocop -A
git add -A
git commit -m "feature/pools: pool calculator derives balance from movements and entries"
```

Then report to the user: Plan 1 complete, plus the list of examples left pending
for Plan 3.

---

## Plan 1 Done

At this point the app has a complete envelope-budgeting domain model with no UI
attached to it. Every existing screen behaves exactly as before.

**Plan 2 (Allocation flow)** builds `AllocationCalculator` and
`AllocationCommitter` on top of `PoolCalculator#required`, then the pools index,
the rule form, the paycheck split screen, and reallocation.

**Plan 3 (Cutover)** runs the §6.1 data migration, drops `category_type: savings`
and `budgets.category_id`, reworks `CategoryCalculator` and the four dashboard
presenters, rewrites the seeds, and clears every example this plan left pending.
