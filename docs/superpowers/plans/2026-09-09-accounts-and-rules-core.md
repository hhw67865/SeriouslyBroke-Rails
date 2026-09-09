# Accounts and Rules, Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the backend of the accounts-and-rules design from `main` in one straight line: the test infrastructure, the settings rename, the schema, the eight models, the data migration verified against production data, the ledgers and claim arithmetic, and the form objects.

**Architecture:** Two migrations (additive schema, then data conversion plus tightening) take `main`'s schema to the spec's. Eight models hold the constraints. Three services derive every figure at read time (`AccountLedger` for balances, `ClaimCalculator` for one rule's claim, `ClaimLedger` for a user's claims in a fixed number of queries). Form objects (`RuleForm`, `AdjustmentForm`, `EntryForm`, `CadenceChange`) own every write a screen makes. The screens come in the companion plan `2026-09-09-accounts-and-rules-screens.md`.

**Tech Stack:** Rails 8.1.1, Ruby 3.2.2, PostgreSQL 18, RSpec 7, FactoryBot, Capybara with Rack::Test and headless Chrome, parallel_tests.

**Spec:** `docs/superpowers/specs/2026-09-09-accounts-and-rules-design.md`

## Global Constraints

- Branch `feature/accounts-and-rules`, checked out in the worktree `.claude/worktrees/accounts-and-rules`. Run every command from there. The old branch `feature/envelope-budgeting` at commit `4ee68de` is a read-only reference; never merge it.
- Names, exactly: models `User Account Transfer Category Item Entry Rule Adjustment`; tables `accounts transfers categories items entries rules adjustments`; columns `users.main_account_id`, `entries.account_id`, `rules.starts_on`, `transfers.from_account_id` / `to_account_id`. Nothing is called `pool`, `budget` (the model), `bank_account`, `funded_since`, `default_account`, `typical_income`.
- Money columns are Postgres `money`, scale 2. Every date about money is a `date` column. Nothing stores a computed figure.
- Style: `bundle exec rubocop -A <changed files>` clean before every commit (`Layout/LineLength` 200, double quotes, `Metrics/AbcSize` 20, `Metrics/MethodLength` 20).
- Comments explain a non-obvious design choice in one or two lines. No dated rulings, no references to the old branch, no fix-round notes.
- **Gate for this plan:** after every task, `bundle exec rspec spec/models spec/services spec/helpers spec/migrations spec/requests` (the directories that exist at that point) is green. `spec/system` is the screens plan's gate, except `spec/system/settings` and `spec/system/smoke_spec.rb`, which stay green from Task 1 on. Between Task 3 and the screens plan, `main`'s remaining views do not render (they name savings pools); that is expected.
- Commits: one per task, with the messages given. At the end of each group there is a squash checkpoint that folds the group into the spec's logical commit with `git reset --soft`.
- Commit trailer on every commit:

```
Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TAyw5u1JpPMKXdADFnjtrC
```

---

## File Structure

| file | responsibility |
|---|---|
| `spec/support/capybara.rb` | drivers: Rack::Test by default, one headless Chrome per process for `:js` |
| `config/database.yml.example`, `config/ci.rb`, `Gemfile` | parallel test databases, CI runs rspec in parallel |
| `app/controllers/settings_controller.rb`, `app/views/settings/**` | the user settings page (was `accounts`) |
| `db/migrate/20260910000000_accounts_and_rules_schema.rb` | additive schema: new tables, new columns, constraints that need no data |
| `db/migrate/20260910000001_accounts_and_rules_data.rb` | per-user conversion of `main`'s data, assertions, then removal of the old shape |
| `app/models/account.rb` | an account, `Account.open`, main-ness, balance via the ledger |
| `app/models/transfer.rb` | a dated move between two of one user's accounts |
| `app/models/user.rb` | main account, period grid, `today`, `opening_day` |
| `app/models/category.rb` | two types, priority, regular flag, fill order |
| `app/models/item.rb` | as `main`, with one rule |
| `app/models/entry.rb` | landing account, lane scopes |
| `app/models/rule.rb` | shapes, cadence, validations, standing ask |
| `app/models/adjustment.rb` | a signed, dated delta on a rule |
| `app/services/account_ledger.rb` | balances, pot, total money, typical income |
| `app/services/claim_calculator.rb` | one rule's claim: the walk, due dates, settlement |
| `app/services/claim_ledger.rb` | every rule's calculator for a user from batched rows |
| `app/services/rule_form.rb` | the rule form's words to a rule's columns |
| `app/services/adjustment_form.rb` | top up, reduce, set aside, take back, skip |
| `app/services/entry_form.rb` | formula, item by id or name, landing account |
| `app/services/cadence_change.rb` | period change with optional scaling of per-period rules |
| `spec/factories/*.rb` | one factory per model |
| `spec/models/*_spec.rb`, `spec/services/*_spec.rb`, `spec/migrations/accounts_and_rules_spec.rb` | the proofs |

---

## Group A: infrastructure and the settings rename (spec commit 1)

Record the starting point before Task 1:

```bash
git rev-parse HEAD > /tmp/group_a_base
```

### Task 1: Test infrastructure

**Files:**
- Modify: `Gemfile`
- Modify: `spec/support/capybara.rb`
- Delete: `spec/support/database_cleaner.rb`
- Create: `config/database.yml.example`
- Modify: `config/database.yml` (local, ignored by git)
- Modify: `bin/setup:19-20`
- Modify: `config/ci.rb`
- Create: `spec/system/smoke_spec.rb`

**Interfaces:**
- Produces: system specs run under Rack::Test unless tagged `js: true`; `bundle exec parallel_rspec spec` works; `TEST_ENV_NUMBER` suffixes the test database name.

- [ ] **Step 1: Write the smoke spec (it fails until the drivers are configured)**

```ruby
# frozen_string_literal: true

require "rails_helper"

# Two examples that prove the two drivers: the in-process one renders a page, the browser one
# runs JavaScript. Everything else about the app is proven elsewhere.
RSpec.describe "Test drivers", type: :system do
  it "renders the sign-in page in-process" do
    visit new_user_session_path

    expect(page).to have_field("Email")
    expect(Capybara.current_driver).to eq(:rack_test)
  end

  it "runs JavaScript in one headless Chrome", :js do
    visit new_user_session_path

    expect(page.evaluate_script("1 + 1")).to eq(2)
    expect(Capybara.current_driver).to eq(:selenium_chrome_headless)
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/system/smoke_spec.rb`
Expected: the first example fails on `Capybara.current_driver` being `:selenium_chrome_headless`.

- [ ] **Step 3: Replace `spec/support/capybara.rb`**

```ruby
# frozen_string_literal: true

Capybara.default_max_wait_time = 5
# Let finders match aria-label so icon-only buttons are clickable by name.
Capybara.enable_aria_label = true

Capybara.register_driver :selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-gpu")
  options.add_argument("--disable-dev-shm-usage")
  options.add_argument("--window-size=1400,1400")
  options.add_option("goog:loggingPrefs", { browser: "ALL" })

  Capybara::Selenium::Driver.new(app, browser: :chrome, options:)
end

Capybara.javascript_driver = :selenium_chrome_headless

module CapybaraHelpers
  def wait_until
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop until yield
    end
  end
end

# Rack::Test unless an example says :js. One Chrome per process: Capybara resets the session
# between examples, and restarting the browser cost a second per example.
RSpec.configure do |config|
  config.include CapybaraHelpers, type: :system
  config.before(:each, type: :system) { driven_by(:rack_test) }
  config.before(:each, type: :system, js: true) { driven_by(:selenium_chrome_headless) }
end
```

- [ ] **Step 4: Remove DatabaseCleaner and add parallel_tests**

```bash
git rm spec/support/database_cleaner.rb
```

In `Gemfile`, delete the line `gem "database_cleaner-active_record", "~> 2.2"` and add `gem "parallel_tests"` inside `group :development, :test do ... end`, after `gem "pry-rails", "~> 0.3.11"`. Then:

```bash
bundle install
```

- [ ] **Step 5: Parallel test databases**

Create `config/database.yml.example` as a copy of your local `config/database.yml` with the `test:` block reading:

```yaml
test:
  <<: *default
  database: seriously_broke_test<%= ENV["TEST_ENV_NUMBER"] %>
```

Make the same change in your local `config/database.yml`. In `bin/setup`, replace lines 19-20 with the uncommented copy using the new name:

```ruby
  unless File.exist?("config/database.yml")
    FileUtils.cp "config/database.yml.example", "config/database.yml"
  end
```

Create the parallel databases once:

```bash
bundle exec rake parallel:create parallel:prepare
```

- [ ] **Step 6: CI runs rspec in parallel**

Replace `config/ci.rb` with:

```ruby
# frozen_string_literal: true

CI.run do
  step "Setup", "bin/setup --skip-server"
  step "Style: Ruby", "bin/rubocop"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Tests: databases", "bundle exec rake parallel:create parallel:prepare"
  step "Tests: RSpec", "bundle exec parallel_rspec spec"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"
end
```

- [ ] **Step 7: Run the smoke spec and the unit suite**

Run: `bundle exec rspec spec/system/smoke_spec.rb spec/models spec/services spec/helpers`
Expected: all green (2 smoke examples plus 105 unit examples).

- [ ] **Step 8: Commit**

```bash
bundle exec rubocop -A spec/support/capybara.rb spec/system/smoke_spec.rb config/ci.rb
git add -A
git commit -m "test: one browser per process, Rack::Test by default, parallel test databases"
```

### Task 2: The settings page is Settings

**Files:**
- Rename: `app/controllers/accounts_controller.rb` to `app/controllers/settings_controller.rb`
- Rename: `app/views/accounts/` to `app/views/settings/`
- Rename: `spec/system/account/` to `spec/system/settings/`
- Modify: `config/routes.rb`, `app/controllers/users/registrations_controller.rb:28`, `app/views/shared/_user_profile.html.erb:4`, `app/views/users/registrations/edit.html.erb:7,82`, `app/views/settings/_partials/show/_preferences_card.html.erb:12,27`, `spec/system/capybaras_spec.rb`, `spec/system/settings/**`

**Interfaces:**
- Produces: `settings_path`, `toggle_theme_settings_path`, `toggle_ming_mode_settings_path`; `SettingsController`. The names `account_path` and `AccountsController` are free.

- [ ] **Step 1: Move the files**

```bash
git mv app/controllers/accounts_controller.rb app/controllers/settings_controller.rb
git mv app/views/accounts app/views/settings
git mv spec/system/account spec/system/settings
```

- [ ] **Step 2: Rewrite the controller**

```ruby
# frozen_string_literal: true

class SettingsController < ApplicationController
  def show; end

  def toggle_theme
    current_user.toggle_theme!
    redirect_back_or_to settings_path
  end

  def toggle_ming_mode
    current_user.update(ming_mode: !current_user.ming_mode?)
    redirect_back_or_to settings_path
  end
end
```

- [ ] **Step 3: Route and references**

In `config/routes.rb` replace the `resource :account` block with:

```ruby
  resource :settings, only: [:show] do
    patch :toggle_theme
    patch :toggle_ming_mode
  end
```

Then rename every helper:

```bash
grep -rlE 'toggle_theme_account_path|toggle_ming_mode_account_path|account_path' app spec | xargs sed -i '' \
  -e 's/toggle_theme_account_path/toggle_theme_settings_path/g' \
  -e 's/toggle_ming_mode_account_path/toggle_ming_mode_settings_path/g' \
  -e 's/\baccount_path\b/settings_path/g'
grep -rn 'account_path\|AccountsController' app spec config
```

Expected: the last grep prints nothing.

- [ ] **Step 4: Run the settings specs**

Run: `bundle exec rspec spec/system/settings spec/system/capybaras_spec.rb`
Expected: green. If an example fails only because it needs JavaScript (a dropdown that is not a plain `<select>`, a button that submits by script), tag that one example `:js` and re-run.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "settings: the user settings page is Settings, freeing the name Account"
```

### Squash checkpoint A

```bash
git reset --soft "$(cat /tmp/group_a_base)"
git commit -m "test infrastructure and the settings rename

One browser per process, Rack::Test by default, no DatabaseCleaner, parallel test databases.
The user settings page moves from /account to /settings so Account can name a bank account."
git rev-parse HEAD > /tmp/group_b_base
```

---

## Group B: schema and models (spec commit 2)

### Task 3: The additive schema migration, and the purge of savings pools

**Files:**
- Create: `db/migrate/20260910000000_accounts_and_rules_schema.rb`
- Delete: `app/models/savings_pool.rb`, `app/models/budget.rb`, `app/services/savings_pool_calculator.rb`, `app/controllers/savings_pools_controller.rb`, `app/controllers/savings_pools/`, `app/controllers/budgets_controller.rb`, `app/helpers/savings_pools_helper.rb`, `app/views/savings_pools/`, `app/views/budgets/`, `spec/models/savings_pool_spec.rb`, `spec/models/budget_spec.rb`, `spec/models/category_spec.rb`, `spec/models/entry_spec.rb`, `spec/models/item_spec.rb`, `spec/models/user_spec.rb`, `spec/services/savings_pool_calculator_spec.rb`, `spec/factories/savings_pools.rb`, `spec/factories/budgets.rb`, `spec/system/savings_pools/`, `spec/system/budgets/`, `spec/system/dashboard/index/savings_pools_spec.rb`, `spec/system/dashboard/index/savings_tab_spec.rb`, `spec/system/categories/show/savings_pool_spec.rb`, `spec/system/categories/show/budget_spec.rb`
- Create: `app/models/rule.rb` (minimal, filled in by Task 8)
- Modify: `app/models/category.rb`, `app/models/entry.rb`, `app/models/item.rb`, `app/models/user.rb` (minimal, filled in by Tasks 5-7), `config/routes.rb`, `db/seeds.rb`

**Interfaces:**
- Produces: tables `accounts`, `transfers`, `adjustments`, `rules` (renamed from `budgets`); new columns per spec §7.1. `entries.day` and `rules.starts_on` are nullable until Task 9.

- [ ] **Step 1: Write the migration**

```ruby
# frozen_string_literal: true

# Everything the accounts-and-rules schema adds. Nothing here reads data, so it is reversible as
# written; the data migration that follows fills the nullable columns and removes main's shape.
class AccountsAndRulesSchema < ActiveRecord::Migration[8.1]
  def change
    create_accounts
    create_transfers
    extend_users
    extend_categories
    extend_entries
    reshape_rules
    create_adjustments
  end

  private

  def create_accounts
    create_table :accounts, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.money :opening_balance, scale: 2, null: false, default: 0
      t.date :opened_on
      t.timestamps
    end
    add_index :accounts, "user_id, lower(name)", unique: true, name: "index_accounts_on_user_id_and_lower_name"
  end

  def create_transfers
    create_table :transfers, id: :uuid do |t|
      t.references :from_account, type: :uuid, null: false, foreign_key: { to_table: :accounts }
      t.references :to_account, type: :uuid, null: false, foreign_key: { to_table: :accounts }
      t.money :amount, scale: 2, null: false
      t.date :date, null: false
      t.timestamps
    end
    add_index :transfers, :date
    add_check_constraint :transfers, "amount > 0::money", name: "transfers_positive_amount"
    add_check_constraint :transfers, "from_account_id <> to_account_id", name: "transfers_distinct_accounts"
  end

  def extend_users
    add_reference :users, :main_account, type: :uuid, foreign_key: { to_table: :accounts, on_delete: :nullify }
    add_column :users, :period_cadence, :integer
    add_column :users, :period_anchor_date, :date
  end

  def extend_categories
    add_column :categories, :priority, :integer, null: false, default: 0
    add_column :categories, :regular, :boolean, null: false, default: true
    add_check_constraint :categories, "priority >= 0", name: "categories_priority_non_negative"
    add_index :categories, "user_id, lower(name)", unique: true, name: "index_categories_on_user_id_and_lower_name"
  end

  def extend_entries
    add_column :entries, :day, :date
    add_reference :entries, :account, type: :uuid, foreign_key: true
    add_check_constraint :entries, "amount > 0::money", name: "entries_positive_amount"
  end

  def reshape_rules
    rename_table :budgets, :rules
    add_reference :rules, :item, type: :uuid, foreign_key: true
    add_column :rules, :rule_type, :integer, null: false, default: 1
    add_column :rules, :starts_on, :date
    add_column :rules, :anchor_date, :date
    add_column :rules, :interval_months, :integer
    add_column :rules, :keeps_unspent, :boolean, null: false, default: false
    add_check_constraint :rules, "amount > 0::money", name: "rules_positive_amount"
    add_check_constraint :rules, "interval_months IS NULL OR interval_months > 0", name: "rules_positive_interval"
    add_check_constraint :rules, "NOT (keeps_unspent AND anchor_date IS NOT NULL)", name: "rules_keeping_never_dates"
    add_check_constraint :rules, "interval_months IS NULL OR anchor_date IS NOT NULL", name: "rules_interval_needs_a_date"
    add_index :rules, :item_id, unique: true, where: "item_id IS NOT NULL", name: "index_rules_on_item_id_unique"
    add_index :rules, :category_id, unique: true, where: "item_id IS NULL", name: "index_rules_one_item_less_per_category"
  end

  def create_adjustments
    create_table :adjustments, id: :uuid do |t|
      t.references :rule, type: :uuid, null: false, foreign_key: true
      t.money :amount, scale: 2, null: false
      t.date :date, null: false
      t.timestamps
    end
    add_index :adjustments, :date
    add_check_constraint :adjustments, "amount <> 0::money", name: "adjustments_non_zero_amount"
  end
end
```

- [ ] **Step 2: Migrate, roll back, migrate again**

```bash
bin/rails db:migrate && bin/rails db:rollback && bin/rails db:migrate
RAILS_ENV=test bin/rails db:migrate
git diff --stat db/schema.rb
```

Expected: no errors, and `db/schema.rb` now has `accounts`, `transfers`, `adjustments`, `rules`.

- [ ] **Step 3: Purge the savings pool code and main's specs that describe it**

```bash
git rm -r app/models/savings_pool.rb app/models/budget.rb app/services/savings_pool_calculator.rb \
  app/controllers/savings_pools_controller.rb app/controllers/savings_pools app/controllers/budgets_controller.rb \
  app/helpers/savings_pools_helper.rb app/views/savings_pools app/views/budgets \
  spec/models/savings_pool_spec.rb spec/models/budget_spec.rb spec/models/category_spec.rb spec/models/entry_spec.rb \
  spec/models/item_spec.rb spec/models/user_spec.rb spec/services/savings_pool_calculator_spec.rb \
  spec/factories/savings_pools.rb spec/factories/budgets.rb spec/system/savings_pools spec/system/budgets \
  spec/system/dashboard/index/savings_pools_spec.rb spec/system/dashboard/index/savings_tab_spec.rb \
  spec/system/categories/show/savings_pool_spec.rb spec/system/categories/show/budget_spec.rb
```

In `config/routes.rb` delete the `resources :savings_pools do ... end` block and the `resources :budgets, only: [...]` line.

- [ ] **Step 4: Minimal models so the app boots**

`app/models/rule.rb`:

```ruby
# frozen_string_literal: true

class Rule < ApplicationRecord
  belongs_to :category, touch: true
end
```

`app/models/category.rb` (Task 6 replaces it whole):

```ruby
# frozen_string_literal: true

class Category < ApplicationRecord
  include ModelSearchable

  belongs_to :user, touch: true
  has_many :items, dependent: :destroy
  has_many :entries, through: :items
  has_many :rules, dependent: :destroy

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :category_type, presence: true

  enum :category_type, { expense: 0, income: 1 }

  scope :expenses, -> { where(category_type: :expense) }
  scope :incomes, -> { where(category_type: :income) }
  scope :tracked, -> { where(tracked: true) }
  scope :untracked, -> { where(tracked: false) }
  scope :with_type, ->(type) { (type.to_s == "income" ? incomes : expenses).includes(:items) }

  searchable :name, label: "Name"

  def calculator(date = Date.current, period: :monthly)
    CategoryCalculator.new(self, date, period: period)
  end
end
```

`app/models/entry.rb` (Task 7 replaces it whole): delete the `savings`, `budgetable_expenses` and `pool_covered_expenses` scopes. `app/models/item.rb`: delete the `savings` scope. `app/models/user.rb`: delete `has_many :savings_pools, dependent: :destroy` and change `has_many :budgets, through: :categories` to `has_many :rules, through: :categories`.

`db/seeds.rb` (the screens plan writes the real one):

```ruby
# frozen_string_literal: true

[Adjustment, Rule, Transfer, Entry, Item, Category, Account, User].each(&:delete_all)

User.create!(email: "demo@example.com", password: "password123", name: "Demo User", timezone: "America/New_York")
```

`Adjustment`, `Transfer` and `Account` do not exist yet; that is fine, seeds are not run until the screens plan.

- [ ] **Step 5: Boot and run what remains**

Run: `bin/rails runner 'puts Rule.count, Category.count'` then `bundle exec rspec spec/helpers spec/system/smoke_spec.rb`
Expected: two numbers, then green.

- [ ] **Step 6: Commit**

```bash
bundle exec rubocop -A db/migrate/20260910000000_accounts_and_rules_schema.rb app/models db/seeds.rb
git add -A
git commit -m "schema: accounts, transfers, rules and adjustments; savings pools are gone"
```

### Task 4: Account and Transfer

**Files:**
- Create: `app/models/account.rb`, `app/models/transfer.rb`, `spec/factories/accounts.rb`, `spec/factories/transfers.rb`, `spec/models/account_spec.rb`, `spec/models/transfer_spec.rb`
- Modify: `app/models/user.rb`

**Interfaces:**
- Produces: `Account.open(user, name:, balance:)` returns the account, persisted or with errors; `Account#main?`; `Account#transfers_in`, `#transfers_out`, `#entries`; `Transfer#user`; `User#accounts`, `User#main_account`, `User#opening_day`.
- `Account#balance` and `#correct_balance` arrive in Task 10 with the ledger.

- [ ] **Step 1: Factories**

`spec/factories/accounts.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "#{Faker::Bank.name} #{n}" }
    opening_balance { 0 }
    association :user

    # The first account a user gets is main, the rule Account.open applies. update_columns so a
    # :js example's request thread never races this write through has_many autosave validation.
    after(:create) do |account|
      if account.user.main_account_id.blank?
        account.user.update_columns(main_account_id: account.id) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
```

`spec/factories/transfers.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :transfer do
    amount { 50 }
    date { Date.current }
    association :from_account, factory: :account
    to_account { association :account, user: from_account.user }
  end
end
```

- [ ] **Step 2: Model specs**

`spec/models/account_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Account do
  let(:user) { create(:user) }

  describe "validations", :aggregate_failures do
    it "needs a name, unique per user ignoring case" do
      create(:account, user: user, name: "Checking")

      expect(build(:account, user: user, name: "")).not_to be_valid
      expect(build(:account, user: user, name: "checking")).not_to be_valid
      expect(build(:account, user: create(:user), name: "checking")).to be_valid
    end

    it "opens at zero unless told otherwise" do
      expect(build(:account).opening_balance).to eq(0)
      expect(build(:account, opening_balance: "abc")).not_to be_valid
    end
  end

  describe ".open" do
    it "creates the account and makes it main when the user has none", :aggregate_failures do
      account = described_class.open(user, name: "Checking", balance: 120.5)

      expect(account).to be_persisted
      expect(account.opening_balance).to eq(120.5)
      expect(account.opened_on).to eq(user.today)
      expect(user.reload.main_account).to eq(account)
    end

    it "opens the day before the user's first entry" do
      create(:entry, :income, user: user, date: Date.new(2026, 3, 10)).item.category.update!(user: user)

      expect(described_class.open(user, name: "Checking", balance: 0).opened_on).to eq(Date.new(2026, 3, 9))
    end

    it "never steals main from an existing account" do
      first = described_class.open(user, name: "Checking", balance: 0)
      described_class.open(user, name: "Savings", balance: 0)

      expect(user.reload.main_account).to eq(first)
    end

    it "returns the invalid record with its errors" do
      account = described_class.open(user, name: "", balance: 0)

      expect(account).not_to be_persisted
      expect(account.errors[:name]).to include("can't be blank")
    end
  end

  describe "#destroy" do
    it "refuses to delete main", :aggregate_failures do
      main = create(:account, user: user)

      expect(main.destroy).to be(false)
      expect(main.errors[:base]).to include("This is your main account — everything flows through it")
    end

    it "deletes another account with its transfers and sends its income entries back to main", :aggregate_failures do
      main = create(:account, user: user)
      other = create(:account, user: user)
      create(:transfer, from_account: main, to_account: other)
      entry = create(:entry, :income, user: user, account: other)
      entry.item.category.update!(user: user)

      expect { other.destroy! }.to change(Transfer, :count).by(-1)
      expect(entry.reload.account).to be_nil
    end
  end
end
```

`spec/models/transfer_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Transfer do
  let(:user) { create(:user) }
  let(:main) { create(:account, user: user) }
  let(:savings) { create(:account, user: user) }

  it "moves a positive amount on a date between two different accounts of one user", :aggregate_failures do
    expect(build(:transfer, from_account: main, to_account: savings, amount: 10)).to be_valid
    expect(build(:transfer, from_account: main, to_account: savings, amount: 0)).not_to be_valid
    expect(build(:transfer, from_account: main, to_account: savings, date: nil)).not_to be_valid
    expect(build(:transfer, from_account: main, to_account: main)).not_to be_valid
    expect(build(:transfer, from_account: main, to_account: create(:account))).not_to be_valid
  end

  it "belongs to the accounts' user" do
    expect(build(:transfer, from_account: main, to_account: savings).user).to eq(user)
  end
end
```

- [ ] **Step 3: Run them to see them fail**

Run: `bundle exec rspec spec/models/account_spec.rb spec/models/transfer_spec.rb`
Expected: fail with `uninitialized constant Account`.

- [ ] **Step 4: Models**

`app/models/account.rb`:

```ruby
# frozen_string_literal: true

class Account < ApplicationRecord
  include ModelSearchable

  belongs_to :user, touch: true
  has_many :transfers_in, class_name: "Transfer", foreign_key: :to_account_id, dependent: :destroy, inverse_of: :to_account
  has_many :transfers_out, class_name: "Transfer", foreign_key: :from_account_id, dependent: :destroy, inverse_of: :from_account
  has_many :entries, dependent: :nullify

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :opening_balance, presence: true, numericality: true

  before_destroy :main_is_not_deletable, prepend: true

  searchable :name, label: "Name"

  # Returns the account, saved or carrying its errors. The first account a user opens is main.
  def self.open(user, name:, balance:)
    account = user.accounts.new(name: name, opening_balance: balance, opened_on: user.opening_day)
    transaction do
      account.save && user.main_account.blank? && user.update!(main_account: account)
    end
    account
  end

  def main? = user.main_account_id == id

  private

  def main_is_not_deletable
    return unless main?
    return if destroyed_by_association

    errors.add(:base, "This is your main account — everything flows through it")
    throw(:abort)
  end
end
```

`app/models/transfer.rb`:

```ruby
# frozen_string_literal: true

class Transfer < ApplicationRecord
  belongs_to :from_account, class_name: "Account", touch: true
  belongs_to :to_account, class_name: "Account", touch: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true
  validate :accounts_differ
  validate :accounts_share_a_user

  delegate :user, to: :from_account

  private

  def accounts_differ
    return if from_account.blank? || to_account.blank?

    errors.add(:to_account, "must differ from the source account") if from_account == to_account
  end

  def accounts_share_a_user
    return if from_account.blank? || to_account.blank?

    errors.add(:to_account, "must belong to the same user") unless from_account.user_id == to_account.user_id
  end
end
```

In `app/models/user.rb` add, next to the other associations:

```ruby
  has_many :accounts, dependent: :destroy
  belongs_to :main_account, class_name: "Account", optional: true
```

and these methods (Task 5 rewrites the file whole and keeps them):

```ruby
  def today = Time.current.in_time_zone(timezone.presence || "UTC").to_date

  # The day before the first entry, so an opening balance predates everything that flowed since.
  def opening_day
    first = entries.minimum(:date)
    first ? first.to_date - 1 : today
  end
```

The entry factory's `:income` trait and the `account:` attribute come in Task 7; until then, replace the two examples that use `create(:entry, :income, ...)` with `pending "Task 7"` is NOT allowed. Instead, run Task 7's factory now: create `spec/factories/entries.rb` exactly as Task 7 Step 1 shows it, and add `belongs_to :account, optional: true` to `app/models/entry.rb`. Task 7 keeps both.

- [ ] **Step 5: Run the specs**

Run: `bundle exec rspec spec/models/account_spec.rb spec/models/transfer_spec.rb`
Expected: green.

- [ ] **Step 6: Commit**

```bash
bundle exec rubocop -A app/models/account.rb app/models/transfer.rb app/models/user.rb app/models/entry.rb spec/factories spec/models
git add -A
git commit -m "models: Account and Transfer"
```

### Task 5: User

**Files:**
- Modify: `app/models/user.rb` (whole file)
- Create: `spec/models/user_spec.rb`
- Modify: `spec/factories/users.rb`

**Interfaces:**
- Produces: `User#period_containing(date)` returns a `Range` of dates; `#period_boundaries(from:, to:)`; `#periods_per_year`; `#today`; `#opening_day`; `#toggle_theme!`; `User::PERIODS_PER_YEAR`; enum `period_cadence` with prefix `period_` (`period_weekly?` ...).

- [ ] **Step 1: Factory**

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    name { Faker::Name.name }
    email { Faker::Internet.unique.email }
    password { "password123" }
    password_confirmation { "password123" }

    trait :biweekly do
      period_cadence { :biweekly }
      period_anchor_date { Date.new(2026, 2, 6) }
    end

    trait :monthly do
      period_cadence { :monthly }
      period_anchor_date { Date.new(2026, 1, 15) }
    end
  end
end
```

- [ ] **Step 2: Spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  describe "validations", :aggregate_failures do
    it "needs an anchor date with a cadence" do
      expect(build(:user, period_cadence: :weekly, period_anchor_date: nil)).not_to be_valid
      expect(build(:user, period_cadence: nil, period_anchor_date: nil)).to be_valid
    end

    it "only takes one of its own accounts as main" do
      user = create(:user)
      other = create(:account)

      user.main_account = other

      expect(user).not_to be_valid
      expect(user.errors[:main_account]).to include("must be an account you own")
    end

    it "only takes a real timezone" do
      expect(build(:user, timezone: "Mars/Olympus")).not_to be_valid
      expect(build(:user, timezone: "America/New_York")).to be_valid
    end
  end

  describe "#today" do
    it "is the calendar day in the user's timezone" do
      user = build(:user, timezone: "Pacific/Auckland")

      travel_to Time.utc(2026, 3, 1, 23, 0) do
        expect(user.today).to eq(Date.new(2026, 3, 2))
      end
    end
  end

  describe "#period_boundaries and #period_containing", :aggregate_failures do
    it "strides fortnightly from the anchor" do
      user = build(:user, :biweekly)

      expect(user.period_boundaries(from: Date.new(2026, 9, 1), to: Date.new(2026, 9, 30)))
        .to eq([Date.new(2026, 9, 4), Date.new(2026, 9, 18)])
      expect(user.period_containing(Date.new(2026, 9, 9))).to eq(Date.new(2026, 9, 4)..Date.new(2026, 9, 17))
      expect(user.period_containing(Date.new(2026, 9, 18))).to eq(Date.new(2026, 9, 18)..Date.new(2026, 10, 1))
    end

    it "lands monthly periods on the anchor's day, clamped to short months" do
      user = build(:user, period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 31))

      expect(user.period_boundaries(from: Date.new(2026, 2, 1), to: Date.new(2026, 4, 30)))
        .to eq([Date.new(2026, 2, 28), Date.new(2026, 3, 31), Date.new(2026, 4, 30)])
      expect(user.period_containing(Date.new(2026, 3, 15))).to eq(Date.new(2026, 2, 28)..Date.new(2026, 3, 30))
    end

    it "splits a month in two for semimonthly" do
      user = build(:user, period_cadence: :semimonthly, period_anchor_date: Date.new(2026, 1, 1))

      expect(user.period_boundaries(from: Date.new(2026, 3, 1), to: Date.new(2026, 3, 31)))
        .to eq([Date.new(2026, 3, 1), Date.new(2026, 3, 16)])
    end

    it "falls back to the calendar month with no cadence" do
      user = build(:user)

      expect(user.period_containing(Date.new(2026, 9, 9))).to eq(Date.new(2026, 9, 1)..Date.new(2026, 9, 30))
      expect(user.periods_per_year).to eq(12)
    end
  end

  describe "#toggle_theme!" do
    it "flips between light and dark" do
      user = create(:user)

      expect { user.toggle_theme! }.to change(user, :theme).from("light").to("dark")
    end
  end
end
```

- [ ] **Step 3: Run it to see it fail**

Run: `bundle exec rspec spec/models/user_spec.rb`
Expected: failures on `period_containing`, `main_account` validation.

- [ ] **Step 4: The whole model**

```ruby
# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable

  has_many :categories, dependent: :destroy
  has_many :accounts, dependent: :destroy
  has_many :items, through: :categories
  has_many :entries, through: :items
  has_many :rules, through: :categories
  belongs_to :main_account, class_name: "Account", optional: true

  enum :theme, { light: 0, dark: 1 }
  enum :period_cadence, { weekly: 0, biweekly: 1, semimonthly: 2, monthly: 3 }, prefix: :period

  normalizes :timezone, with: ->(value) { value.presence }

  validates :email, confirmation: { case_sensitive: false }, if: :will_save_change_to_email?
  validates :timezone, inclusion: { in: TZInfo::Timezone.all_identifiers }, allow_nil: true
  validates :period_anchor_date, presence: { message: "is required when you set a period" }, if: :period_cadence
  validate :main_account_is_own

  PERIODS_PER_YEAR = { "weekly" => 52, "biweekly" => 26, "semimonthly" => 24, "monthly" => 12 }.freeze
  STRIDE_DAYS = { "weekly" => 7, "biweekly" => 14 }.freeze
  # Wide enough to hold a whole period on either side of any date, on any cadence.
  PERIOD_WINDOW_DAYS = 45

  def periods_per_year = PERIODS_PER_YEAR.fetch(period_cadence, 12)

  def today = Time.current.in_time_zone(timezone.presence || "UTC").to_date

  # The day before the first entry, so an opening balance predates everything that flowed since.
  def opening_day
    first = entries.minimum(:date)
    first ? first.to_date - 1 : today
  end

  def toggle_theme! = update(theme: light? ? :dark : :light)

  # Every period boundary in from..to on the user's grid, ascending. Empty without a cadence.
  def period_boundaries(from:, to:)
    from = from.to_date
    to = to.to_date
    return [] if period_cadence.blank? || period_anchor_date.blank? || to < from

    case period_cadence
    when "weekly", "biweekly" then strided_dates(STRIDE_DAYS.fetch(period_cadence), from, to)
    when "monthly" then monthly_dates([period_anchor_date.day], from, to)
    when "semimonthly" then monthly_dates(semimonthly_days, from, to)
    end
  end

  # The period holding the date: from its opening boundary to the day before the next one. The
  # calendar month without a cadence.
  def period_containing(date)
    date = date.to_date
    opened_on = period_boundaries(from: date - PERIOD_WINDOW_DAYS, to: date).last
    next_boundary = period_boundaries(from: date + 1, to: date + PERIOD_WINDOW_DAYS).first
    (opened_on || date.beginning_of_month)..(next_boundary ? next_boundary - 1 : date.end_of_month)
  end

  private

  def strided_dates(stride, from, to)
    steps = ((from - period_anchor_date).to_i / stride.to_f).ceil
    first = period_anchor_date + (steps * stride)
    return [] if first > to

    (first..to).step(stride).to_a
  end

  def monthly_dates(days, from, to)
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
    first = period_anchor_date.day
    [first, first <= 15 ? first + 15 : first - 15].sort
  end

  def main_account_is_own
    return if main_account.blank? || main_account.user_id == id

    errors.add(:main_account, "must be an account you own")
  end
end
```

- [ ] **Step 5: Run the specs**

Run: `bundle exec rspec spec/models/user_spec.rb spec/models/account_spec.rb`
Expected: green.

- [ ] **Step 6: Commit**

```bash
bundle exec rubocop -A app/models/user.rb spec/models/user_spec.rb spec/factories/users.rb
git add -A
git commit -m "models: User owns the period grid and the main account"
```

### Task 6: Category and Item

**Files:**
- Modify: `app/models/category.rb`, `app/models/item.rb` (whole files)
- Create: `spec/models/category_spec.rb`, `spec/models/item_spec.rb`
- Modify: `spec/factories/categories.rb`, `spec/factories/items.rb`

**Interfaces:**
- Produces: `Category.in_fill_order` (expense categories with a rule, by priority then name), `Category.with_a_rule`, `Category.regular`, `Category.apply_fill_order(user:, category_ids:)` returning true or false, `Category#ruled?`, `Category#display_color`, `Category::DEFAULT_COLOR`; `Item#rule`, `Item.merge`, `Item#move_to_category`.

- [ ] **Step 1: Factories**

`spec/factories/categories.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :category do
    name { Faker::Commerce.department + Faker::Number.number(digits: 2).to_s }
    color { Faker::Color.hex_color }
    category_type { :expense }
    association :user

    trait :income do
      category_type { :income }
      name { Faker::Job.field + Faker::Number.number(digits: 2).to_s }
    end

    trait :expense do
      category_type { :expense }
    end

    trait :irregular do
      regular { false }
    end

    trait :with_items_and_entries do
      transient do
        items_count { rand(2..4) }
      end

      after(:create) do |category, evaluator|
        create_list(:item, evaluator.items_count, :with_entries, category: category)
      end
    end
  end
end
```

`spec/factories/items.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :item do
    name { Faker::Commerce.product_name }
    description { Faker::Lorem.sentence }
    association :category

    trait :expense do
      transient do
        user { create(:user) }
      end
      category { association :category, :expense, user: user }
    end

    trait :income do
      transient do
        user { create(:user) }
      end
      category { association :category, :income, user: user }
    end

    trait :with_entries do
      transient do
        entries_count { rand(2..5) }
      end

      after(:create) do |item, evaluator|
        create_list(:entry, evaluator.entries_count, item: item)
      end
    end
  end
end
```

- [ ] **Step 2: Specs**

`spec/models/category_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Category do
  let(:user) { create(:user) }

  describe "validations", :aggregate_failures do
    it "has two types, a unique name per user, and a non-negative priority" do
      create(:category, user: user, name: "Groceries")

      expect(described_class.category_types.keys).to eq(["expense", "income"])
      expect(build(:category, user: user, name: "groceries")).not_to be_valid
      expect(build(:category, user: user, priority: -1)).not_to be_valid
      expect(build(:category, user: user, name: "  Rent  ").tap(&:valid?).name).to eq("Rent")
    end

    it "is regular and tracked by default" do
      category = create(:category, :income, user: user)

      expect(category).to be_regular
      expect(category).to be_tracked
    end
  end

  describe "scopes", :aggregate_failures do
    it "lists ruled expense categories in fill order" do
      groceries = create(:category, user: user, name: "Groceries", priority: 2)
      rent = create(:category, user: user, name: "Rent", priority: 1)
      create(:category, user: user, name: "Unruled", priority: 0)
      create(:rule, category: groceries)
      create(:rule, category: rent)

      expect(user.categories.in_fill_order).to eq([rent, groceries])
      expect(user.categories.with_a_rule).to contain_exactly(rent, groceries)
    end

    it "separates regular income from the rest" do
      salary = create(:category, :income, user: user)
      create(:category, :income, :irregular, user: user)

      expect(user.categories.incomes.regular).to eq([salary])
    end
  end

  describe ".apply_fill_order" do
    let!(:a) { create(:category, user: user, name: "A", priority: 0).tap { |c| create(:rule, category: c) } }
    let!(:b) { create(:category, user: user, name: "B", priority: 1).tap { |c| create(:rule, category: c) } }

    it "rewrites priorities in the given order", :aggregate_failures do
      expect(described_class.apply_fill_order(user: user, category_ids: [b.id, a.id])).to be(true)
      expect(b.reload.priority).to eq(0)
      expect(a.reload.priority).to eq(1)
    end

    it "refuses a list that is not exactly the ruled categories", :aggregate_failures do
      expect(described_class.apply_fill_order(user: user, category_ids: [a.id])).to be(false)
      expect(described_class.apply_fill_order(user: user, category_ids: [a.id, a.id])).to be(false)
      expect(described_class.apply_fill_order(user: user, category_ids: [])).to be(false)
      expect(a.reload.priority).to eq(0)
    end
  end

  describe "changing type" do
    it "sends an income category's entries back to main when it becomes expense" do
      account = create(:account, user: user)
      create(:account, user: user)
      category = create(:category, :income, user: user)
      entry = create(:entry, item: create(:item, category: category), account: account)

      category.update!(category_type: :expense)

      expect(entry.reload.account).to be_nil
    end
  end

  describe "#ruled? and #display_color", :aggregate_failures do
    it "answers from its rules and its colour" do
      category = create(:category, user: user, color: nil)

      expect(category).not_to be_ruled
      expect(category.display_color).to eq(Category::DEFAULT_COLOR)
      create(:rule, category: category)
      expect(category.reload).to be_ruled
    end
  end
end
```

`spec/models/item_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Item do
  let(:category) { create(:category) }

  it "needs a name, unique in its category ignoring case", :aggregate_failures do
    create(:item, category: category, name: "Coffee")

    expect(build(:item, category: category, name: "coffee")).not_to be_valid
    expect(build(:item, category: category, name: "")).not_to be_valid
  end

  it "takes its rule with it when deleted" do
    item = create(:item, category: category)
    create(:rule, category: category, item: item)

    expect { item.destroy! }.to change(Rule, :count).by(-1)
  end

  describe ".merge" do
    it "moves every entry onto the target and deletes the sources", :aggregate_failures do
      target = create(:item, category: category)
      source = create(:item, :with_entries, category: category, entries_count: 2)

      described_class.merge(target: target, sources: [source])

      expect(target.entries.count).to eq(2)
      expect(described_class.exists?(source.id)).to be(false)
    end
  end

  describe "#move_to_category" do
    it "moves the item, or merges it into a same-named item there", :aggregate_failures do
      other = create(:category, user: category.user)
      item = create(:item, category: category, name: "Coffee")
      twin = create(:item, category: other, name: "coffee")
      create(:entry, item: item)

      item.move_to_category(other)

      expect(described_class.exists?(item.id)).to be(false)
      expect(twin.entries.count).to eq(1)
    end
  end
end
```

- [ ] **Step 3: Run them to see them fail**

Run: `bundle exec rspec spec/models/category_spec.rb spec/models/item_spec.rb`
Expected: failures on `in_fill_order`, `apply_fill_order`, `regular`, `ruled?`, and `Rule` factory missing. Create `spec/factories/rules.rb` now exactly as Task 8 Step 1 shows it, and give `app/models/rule.rb` the `belongs_to :item, optional: true` line; Task 8 keeps both.

- [ ] **Step 4: Models**

`app/models/category.rb`:

```ruby
# frozen_string_literal: true

class Category < ApplicationRecord
  include ModelSearchable

  DEFAULT_COLOR = "#C9C78B"

  belongs_to :user, touch: true
  has_many :items, dependent: :destroy
  has_many :entries, through: :items
  has_many :rules, dependent: :destroy

  normalizes :name, with: ->(name) { name.squish }

  enum :category_type, { expense: 0, income: 1 }

  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }
  validates :category_type, presence: true
  validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  after_update :entries_return_to_main_when_no_longer_income

  scope :expenses, -> { where(category_type: :expense) }
  scope :incomes, -> { where(category_type: :income) }
  scope :tracked, -> { where(tracked: true) }
  scope :untracked, -> { where(tracked: false) }
  scope :regular, -> { where(regular: true) }
  scope :with_a_rule, -> { where(id: Rule.select(:category_id)) }
  # The give-way order on the home page: lower priority gives way first.
  scope :in_fill_order, -> { expenses.with_a_rule.order(:priority, :name) }
  scope :with_type, ->(type) { (type.to_s == "income" ? incomes : expenses).includes(:items) }

  searchable :name, label: "Name"

  # Rewrites priorities to match the submitted order. The list must be exactly the user's ruled
  # expense categories, once each; anything else is refused with nothing written.
  def self.apply_fill_order(user:, category_ids:)
    ids = Array(category_ids).map(&:to_s)
    return false if ids.empty? || ids.uniq.size != ids.size

    transaction do
      user.lock!
      ordered = user.categories.in_fill_order.to_a
      matches = ordered.map { |category| category.id.to_s }.sort == ids.sort
      if matches
        by_id = ordered.index_by { |category| category.id.to_s }
        ids.each_with_index { |id, index| by_id.fetch(id).update!(priority: index) }
      end
      matches
    end
  end

  def display_color = color.presence || DEFAULT_COLOR

  def ruled? = rules.load.any?

  def calculator(date = user.today, period: :monthly)
    CategoryCalculator.new(self, date, period: period)
  end

  private

  def entries_return_to_main_when_no_longer_income
    return unless saved_change_to_category_type == ["income", "expense"]

    entries.update_all(account_id: nil) # rubocop:disable Rails/SkipsModelValidations
  end
end
```

`app/models/item.rb`:

```ruby
# frozen_string_literal: true

class Item < ApplicationRecord
  include ModelSearchable

  belongs_to :category, touch: true
  has_many :entries, dependent: :destroy
  has_one :rule, dependent: :destroy

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true, uniqueness: { scope: :category_id, case_sensitive: false }

  delegate :user, to: :category

  searchable :name, label: "Name"

  scope :expenses, -> { joins(:category).where(categories: { category_type: :expense }) }
  scope :incomes, -> { joins(:category).where(categories: { category_type: :income }) }

  def self.merge(target:, sources:)
    transaction do
      sources.each do |source|
        source.entries.update_all(item_id: target.id) # rubocop:disable Rails/SkipsModelValidations
        source.reload.destroy!
      end
    end
  end

  def move_to_category(target_category)
    existing = target_category.items.find_by("LOWER(name) = ?", name.downcase)
    if existing
      self.class.merge(target: existing, sources: [self])
    else
      update!(category: target_category)
    end
  end
end
```

- [ ] **Step 5: Run the specs**

Run: `bundle exec rspec spec/models/category_spec.rb spec/models/item_spec.rb`
Expected: green.

- [ ] **Step 6: Commit**

```bash
bundle exec rubocop -A app/models/category.rb app/models/item.rb app/models/rule.rb spec/models spec/factories
git add -A
git commit -m "models: Category with priority and the regular flag; Item with one rule"
```

### Task 7: Entry

**Files:**
- Modify: `app/models/entry.rb` (whole file), `spec/factories/entries.rb`
- Create: `spec/models/entry_spec.rb`

**Interfaces:**
- Produces: `Entry.expenses`, `.incomes`, `.tracked`, `.on_unruled_items`, `.in_lane_of(rule)`, `.since(day)`; `Entry#landing_account`; `Entry#user`, `#category`. Factory traits `:expense` and `:income` take `user:`.

- [ ] **Step 1: Factory**

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :entry do
    amount { Faker::Number.decimal(l_digits: 2, r_digits: 2) }
    date { Date.current }
    description { Faker::Lorem.sentence }
    association :item

    trait :expense do
      transient do
        user { create(:user) }
      end
      item { association :item, :expense, user: user }
    end

    trait :income do
      transient do
        user { create(:user) }
      end
      item { association :item, :income, user: user }
    end

    trait :last_month do
      date { Date.current - 1.month }
    end

    trait :this_month do
      date { Date.current }
    end
  end
end
```

- [ ] **Step 2: Spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entry do
  let(:user) { create(:user) }
  let(:main) { create(:account, user: user) }
  let(:savings) { create(:account, user: user) }

  describe "validations", :aggregate_failures do
    it "needs a positive amount and a date" do
      expect(build(:entry, amount: 0)).not_to be_valid
      expect(build(:entry, amount: 12.5, date: nil)).not_to be_valid
      expect(build(:entry, amount: 12.5)).to be_valid
    end

    it "lets income land in one of the user's accounts, and spending only in main" do
      expect(build(:entry, :income, user: user, account: savings)).to be_valid
      expect(build(:entry, :income, user: user, account: create(:account))).not_to be_valid
      expect(build(:entry, :expense, user: user, account: savings)).not_to be_valid
      expect(build(:entry, :expense, user: user, account: nil)).to be_valid
    end
  end

  describe "#landing_account" do
    it "is the chosen account, else main", :aggregate_failures do
      main

      expect(create(:entry, :income, user: user, account: savings).landing_account).to eq(savings)
      expect(create(:entry, :income, user: user).landing_account).to eq(main)
    end
  end

  describe "scopes", :aggregate_failures do
    let(:groceries) { create(:category, user: user, name: "Groceries") }
    let(:bread) { create(:item, category: groceries, name: "Bread") }
    let(:milk) { create(:item, category: groceries, name: "Milk") }

    it "separates income from spending and tracked from untracked" do
      spend = create(:entry, item: bread)
      earn = create(:entry, :income, user: user)
      groceries.update!(tracked: false)

      expect(described_class.expenses).to eq([spend])
      expect(described_class.incomes).to eq([earn])
      expect(described_class.expenses.tracked).to be_empty
    end

    it "finds a rule's lane: its item, or the category's items that have no rule" do
      bread_rule = create(:rule, category: groceries, item: bread)
      whole_rule = create(:rule, category: groceries)
      on_bread = create(:entry, item: bread)
      on_milk = create(:entry, item: milk)

      expect(described_class.in_lane_of(bread_rule)).to eq([on_bread])
      expect(described_class.in_lane_of(whole_rule)).to eq([on_milk])
      expect(described_class.on_unruled_items).to eq([on_milk])
    end

    it "counts from a day" do
      old = create(:entry, item: bread, date: Date.new(2026, 1, 1))
      recent = create(:entry, item: bread, date: Date.new(2026, 6, 1))

      expect(described_class.since(Date.new(2026, 3, 1))).to eq([recent])
      expect(described_class.since(Date.new(2026, 1, 1))).to contain_exactly(old, recent)
    end
  end
end
```

- [ ] **Step 3: Run it to see it fail**

Run: `bundle exec rspec spec/models/entry_spec.rb`
Expected: failures on the account validations and the lane scopes.

- [ ] **Step 4: Model**

```ruby
# frozen_string_literal: true

class Entry < ApplicationRecord
  include ModelSearchable

  belongs_to :item, touch: true
  belongs_to :account, optional: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true
  validate :account_is_the_users
  validate :only_income_lands_in_an_account

  delegate :user, :category, to: :item

  scope :expenses, -> { joins(item: :category).where(categories: { category_type: :expense }) }
  scope :incomes, -> { joins(item: :category).where(categories: { category_type: :income }) }
  scope :tracked, -> { where(categories: { tracked: true }) }
  scope :on_unruled_items, -> { where.not(item_id: Rule.where.not(item_id: nil).select(:item_id)) }
  # A rule's lane: its item's entries, or the whole category's entries on items with no rule of their own.
  scope :in_lane_of, lambda { |rule|
    next where(item_id: rule.item_id) if rule.item_id.present?

    expenses.where(items: { category_id: rule.category_id }).on_unruled_items
  }
  scope :since, ->(day) { where(date: day..) }

  searchable :description, label: "Description"
  searchable :date, type: :date, label: "Date"
  searchable :item, through: :item, column: :name, label: "Item"
  searchable :category, through: [:item, :category], column: :name, label: "Category"

  # No account means main.
  def landing_account = account || user.main_account

  private

  def account_is_the_users
    return if account.blank? || item.blank?

    errors.add(:account, "must be one of your accounts") unless account.user_id == user.id
  end

  def only_income_lands_in_an_account
    return if account.blank? || item.blank? || category.income?

    errors.add(:account, "only income lands in an account — spending leaves your main account")
  end
end
```

- [ ] **Step 5: Run the specs**

Run: `bundle exec rspec spec/models/entry_spec.rb spec/models/account_spec.rb spec/models/category_spec.rb`
Expected: green.

- [ ] **Step 6: Commit**

```bash
bundle exec rubocop -A app/models/entry.rb spec/models/entry_spec.rb spec/factories/entries.rb
git add -A
git commit -m "models: Entry lands in an account and knows a rule's lane"
```

### Task 8: Rule and Adjustment

**Files:**
- Modify: `app/models/rule.rb` (whole file)
- Create: `app/models/adjustment.rb`, `spec/factories/rules.rb`, `spec/factories/adjustments.rb`, `spec/models/rule_spec.rb`, `spec/models/adjustment_spec.rb`

**Interfaces:**
- Produces: `Rule#shape` in `[:rate, :fund, :dated]`; `Rule#cadence` in `[:per_period, :one_off, :every_n]`; `Rule#steady_ask(today:)`; `Rule.steady_need(user, today:, ledger:)`; `Rule.sort_key(next_due_on:, amount:, id:)`; `Rule#type_rank`; `Rule#claim_calculator(today:, spending:, adjustments:)` (the class arrives in Task 11); `Rule#saving_toward_a_date?`; `Rule#user`, `#today`; `Rule::CATCH_ALL_TAKEN`; scopes `for_user`, `dated`, `per_period`, `saving_toward_a_date`. `Adjustment#user`, `Adjustment.dated_within(range)`.

- [ ] **Step 1: Factories**

`spec/factories/rules.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  # The default is a $300 per-period usage allowance that started a year ago, on a fresh expense
  # category. Traits pick the shape.
  factory :rule do
    amount { 300 }
    category { association :category, :expense }
    starts_on { Date.current - 1.year }
    rule_type { :usage }

    transient { due { Date.current + 9.months } }

    trait :rate do
      anchor_date { nil }
      interval_months { nil }
      keeps_unspent { false }
    end

    trait :keeps_unspent do
      anchor_date { nil }
      interval_months { nil }
      keeps_unspent { true }
    end

    trait :one_off do
      anchor_date { Date.current + 20 }
      interval_months { nil }
    end

    trait :by_date do
      anchor_date { due }
      interval_months { nil }
    end

    trait :rolling do
      anchor_date { Date.current + 20 }
      interval_months { 6 }
    end

    trait :bill do
      rule_type { :bill }
    end

    trait :usage do
      rule_type { :usage }
    end

    trait :choice do
      rule_type { :choice }
    end
  end
end
```

`spec/factories/adjustments.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :adjustment do
    rule { association :rule }
    amount { 100 }
    date { Date.current }

    trait :release do
      amount { -100 }
    end
  end
end
```

- [ ] **Step 2: Specs**

`spec/models/rule_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rule do
  let(:user) { create(:user, :biweekly) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let(:bread) { create(:item, category: groceries, name: "Bread") }

  describe "shapes", :aggregate_failures do
    it "reads its shape and cadence off two columns" do
      expect(build(:rule, :rate).shape).to eq(:rate)
      expect(build(:rule, :keeps_unspent).shape).to eq(:fund)
      expect(build(:rule, :one_off).shape).to eq(:dated)
      expect(build(:rule, :rate).cadence).to eq(:per_period)
      expect(build(:rule, :one_off).cadence).to eq(:one_off)
      expect(build(:rule, :rolling).cadence).to eq(:every_n)
    end

    it "knows a goal: dated once, whole category, not a bill" do
      expect(build(:rule, :by_date, :choice).saving_toward_a_date?).to be(true)
      expect(build(:rule, :by_date, :bill).saving_toward_a_date?).to be(false)
      expect(build(:rule, :rolling, :choice).saving_toward_a_date?).to be(false)
      expect(build(:rule, :by_date, :choice, item: bread, category: groceries).saving_toward_a_date?).to be(false)
    end
  end

  describe "validations", :aggregate_failures do
    it "needs a positive amount, a start, a type and a positive interval" do
      expect(build(:rule, amount: 0)).not_to be_valid
      expect(build(:rule, starts_on: nil)).not_to be_valid
      expect(build(:rule, rule_type: nil)).not_to be_valid
      expect(build(:rule, :rolling, interval_months: 0)).not_to be_valid
    end

    it "only rules an expense category, with an item from that category" do
      expect(build(:rule, category: create(:category, :income, user: user))).not_to be_valid
      expect(build(:rule, category: groceries, item: create(:item))).not_to be_valid
      expect(build(:rule, category: groceries, item: bread)).to be_valid
    end

    it "allows one whole-category rule per category and one rule per item" do
      create(:rule, category: groceries)
      create(:rule, category: groceries, item: bread)

      second_whole = build(:rule, category: groceries)
      expect(second_whole).not_to be_valid
      expect(second_whole.errors[:base]).to include(Rule::CATCH_ALL_TAKEN)
      expect(build(:rule, category: groceries, item: bread)).not_to be_valid
    end

    it "never keeps and dates at once, and never has an interval without a date" do
      expect(build(:rule, :one_off, keeps_unspent: true)).not_to be_valid
      expect(build(:rule, :rate, interval_months: 3)).not_to be_valid
    end
  end

  describe "#steady_ask", :aggregate_failures do
    let(:today) { Date.new(2026, 9, 9) }

    it "is the amount for a per-period rule and the per-period share for a rolling one" do
      expect(build(:rule, :rate, amount: 300, category: groceries).steady_ask(today: today)).to eq(300)
      expect(build(:rule, :keeps_unspent, amount: 60, category: groceries).steady_ask(today: today)).to eq(60)
      # $600 every 6 months on a biweekly grid: 600 × 12 / (26 × 6)
      expect(build(:rule, :rolling, amount: 600, interval_months: 6, category: groceries).steady_ask(today: today)).to eq(46.15)
    end
  end

  describe ".sort_key" do
    it "puts dated rules first, soonest first, then the largest amount" do
      keys = [
        described_class.sort_key(next_due_on: nil, amount: 500, id: "b"),
        described_class.sort_key(next_due_on: Date.new(2026, 10, 1), amount: 100, id: "a"),
        described_class.sort_key(next_due_on: Date.new(2026, 9, 20), amount: 50, id: "c")
      ]

      expect(keys.sort.map(&:last)).to eq(["c", "a", "b"])
    end
  end

  it "ranks types choice, usage, bill" do
    expect([build(:rule, :bill), build(:rule, :choice), build(:rule, :usage)].sort_by(&:type_rank).map(&:rule_type))
      .to eq(["choice", "usage", "bill"])
  end
end
```

`spec/models/adjustment_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Adjustment do
  it "is a non-zero amount on a date, on a rule", :aggregate_failures do
    expect(build(:adjustment, amount: 0)).not_to be_valid
    expect(build(:adjustment, date: nil)).not_to be_valid
    expect(build(:adjustment, :release)).to be_valid
  end

  it "belongs to the rule's user and can be picked by date", :aggregate_failures do
    adjustment = create(:adjustment, date: Date.new(2026, 9, 5))

    expect(adjustment.user).to eq(adjustment.rule.category.user)
    expect(described_class.dated_within(Date.new(2026, 9, 1)..Date.new(2026, 9, 30))).to eq([adjustment])
    expect(described_class.dated_within(Date.new(2026, 10, 1)..Date.new(2026, 10, 31))).to be_empty
  end
end
```

- [ ] **Step 3: Run them to see them fail**

Run: `bundle exec rspec spec/models/rule_spec.rb spec/models/adjustment_spec.rb`
Expected: failures on every validation and `shape`.

- [ ] **Step 4: Models**

`app/models/rule.rb`:

```ruby
# frozen_string_literal: true

class Rule < ApplicationRecord
  belongs_to :category, touch: true
  belongs_to :item, optional: true
  has_many :adjustments, dependent: :destroy

  enum :rule_type, { bill: 0, usage: 1, choice: 2 }

  # The give-way order: a choice gives way first, a bill last.
  TYPE_RANK = { choice: 0, usage: 1, bill: 2 }.freeze
  CATCH_ALL_TAKEN = "this category already has a rule covering all of its spending — change that " \
                    "one instead, or point this rule at a single item"
  NEVER_DUE = Date.new(9999, 12, 31)

  scope :for_user, ->(user) { where(category_id: user.categories.select(:id)) }
  scope :dated, -> { where.not(anchor_date: nil) }
  scope :per_period, -> { where(anchor_date: nil) }
  scope :saving_toward_a_date, -> { dated.where(item_id: nil, interval_months: nil).where.not(rule_type: :bill) }

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :starts_on, presence: true
  validates :rule_type, presence: true
  validates :interval_months, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :category_is_an_expense
  validate :item_is_in_the_category
  validate :one_item_less_rule_per_category
  validate :item_has_one_rule
  validate :keeping_never_dates
  validate :interval_needs_a_date

  delegate :user, to: :category

  # Dated rules first, soonest first, then the largest amount.
  def self.sort_key(next_due_on:, amount:, id:)
    [next_due_on.present? ? 0 : 1, next_due_on || NEVER_DUE, -amount.to_d, id]
  end

  # What every rule costs per period, summed.
  def self.steady_need(user, today: user.today, ledger: nil)
    rules = (ledger || ClaimLedger.new(user, today: today)).rules
    rules.sum(0.to_d) { |rule| rule.steady_ask(today: today) }
  end

  def today = user.today

  def type_rank = TYPE_RANK.fetch(rule_type.to_sym)

  def claim_calculator(today: self.today, spending: nil, adjustments: nil)
    ClaimCalculator.new(self, today: today, spending: spending, adjustments: adjustments)
  end

  def shape
    return :dated if anchor_date.present?

    keeps_unspent? ? :fund : :rate
  end

  def cadence
    return :per_period if anchor_date.blank?

    interval_months.blank? ? :one_off : :every_n
  end

  def saving_toward_a_date? = item_id.nil? && anchor_date.present? && interval_months.nil? && !bill?

  # What the rule costs each period: its amount, a one-off target spread to its date, or a rolling
  # amount spread over the interval on the user's grid.
  def steady_ask(today: self.today)
    case cadence
    when :per_period then amount.to_d
    when :one_off then claim_calculator(today: today).standing_ask
    else (amount.to_d * 12 / (user.periods_per_year * interval_months)).round(2)
    end
  end

  private

  def category_is_an_expense
    errors.add(:category, "must be an expense category") if category&.income?
  end

  def item_is_in_the_category
    return if item.blank? || category.blank?

    errors.add(:item, "must belong to this category") unless item.category_id == category.id
  end

  def one_item_less_rule_per_category
    return if item_id.present? || category_id.blank?

    errors.add(:base, CATCH_ALL_TAKEN) if Rule.where(category_id: category_id, item_id: nil).where.not(id: id).exists?
  end

  def item_has_one_rule
    return if item_id.blank?

    errors.add(:item, "is already used by another rule") if Rule.where(item_id: item_id).where.not(id: id).exists?
  end

  def keeping_never_dates
    return unless keeps_unspent? && anchor_date.present?

    errors.add(:anchor_date, "cannot be set on a rule that keeps what it doesn't spend")
  end

  def interval_needs_a_date
    return unless interval_months.present? && anchor_date.blank?

    errors.add(:interval_months, "needs a due date to count from")
  end
end
```

`app/models/adjustment.rb`:

```ruby
# frozen_string_literal: true

class Adjustment < ApplicationRecord
  belongs_to :rule, touch: true

  validates :amount, presence: true, numericality: { other_than: 0 }
  validates :date, presence: true

  scope :dated_within, ->(range) { where(date: range) }

  delegate :user, to: :rule
end
```

- [ ] **Step 5: Run the model directory**

Run: `bundle exec rspec spec/models`
Expected: green.

- [ ] **Step 6: Commit**

```bash
bundle exec rubocop -A app/models/rule.rb app/models/adjustment.rb spec/models spec/factories
git add -A
git commit -m "models: Rule with its three shapes, and Adjustment"
```

### Squash checkpoint B

```bash
git reset --soft "$(cat /tmp/group_b_base)"
git commit -m "schema and models: accounts, transfers, categories, items, entries, rules, adjustments

The additive schema migration, savings pools removed, and the eight models with their factories
and specs."
git rev-parse HEAD > /tmp/group_c_base
```

---

## Group C: the data migration (spec commit 3)

### Task 9: The data migration and its spec

**Files:**
- Create: `db/migrate/20260910000001_accounts_and_rules_data.rb`, `spec/migrations/accounts_and_rules_spec.rb`

**Interfaces:**
- Consumes: the schema from Task 3; models from Tasks 4-8 (used only by the spec's assertions, after `up`).
- Produces: a database in the spec's final shape; `entries.date` is a date; `savings_pools`, `categories.savings_pool_id`, `rules.prorated` are gone.

- [ ] **Step 1: The spec**

```ruby
# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260910000001_accounts_and_rules_data")

# Every example rewinds the data migration (which restores main's shape without data), plants
# main-shaped rows through anonymous table classes, runs the migration forward, and reads the
# result through today's models. The example transaction rolls the DDL back afterwards.
RSpec.describe AccountsAndRulesData do
  let(:migration) { described_class.new }
  let(:now) { Time.utc(2026, 9, 9, 12, 0) }

  def legacy(table) = Class.new(ActiveRecord::Base) { self.table_name = table }

  let(:pools) { legacy("savings_pools") }
  let(:categories) { legacy("categories") }
  let(:items) { legacy("items") }
  let(:entries) { legacy("entries") }
  let(:rules) { legacy("rules") }

  def step(direction)
    migration.suppress_messages { migration.migrate(direction) }
    [User, Account, Transfer, Category, Item, Entry, Rule, Adjustment].each(&:reset_column_information)
  end

  before { step(:down) }
  after { [User, Account, Transfer, Category, Item, Entry, Rule, Adjustment].each(&:reset_column_information) }

  def convert = step(:up)

  let(:expense) { 0 }
  let(:income) { 1 }
  let(:savings) { 2 }

  def plant_user(timezone: nil) = create(:user, timezone: timezone)

  def plant_pool(user, name, start_date: nil)
    pools.create!(user_id: user.id, name: name, start_date: start_date, created_at: now, updated_at: now)
  end

  def plant_category(user, name, type, pool: nil)
    categories.create!(user_id: user.id, name: name, category_type: type, savings_pool_id: pool&.id,
                       tracked: true, created_at: now, updated_at: now)
  end

  def plant_entry(category, amount, at:)
    item = items.create!(category_id: category.id, name: "Item #{SecureRandom.hex(3)}", created_at: now, updated_at: now)
    entries.create!(item_id: item.id, amount: amount, date: at, created_at: now, updated_at: now)
  end

  def plant_budget(category, amount, created_at:)
    rules.create!(category_id: category.id, amount: amount, prorated: false, created_at: created_at, updated_at: created_at)
  end

  it "gives every user a main Checking account opened the day before their first entry", :aggregate_failures do
    user = plant_user
    salary = plant_category(user, "Salary", income)
    plant_entry(salary, 1000, at: Time.utc(2026, 3, 10, 12))

    convert

    main = user.reload.main_account
    expect(main.name).to eq("Checking")
    expect(main.opened_on).to eq(Date.new(2026, 3, 9))
    expect(main.opening_balance).to eq(0)
  end

  it "opens a user with no entries on the run date" do
    user = plant_user

    travel_to(now) { convert }

    expect(user.reload.main_account.opened_on).to eq(Date.new(2026, 9, 9))
  end

  it "turns each savings pool into an account, opened on its start date, even with no categories", :aggregate_failures do
    user = plant_user
    plant_pool(user, "Vacation", start_date: Date.new(2026, 1, 1))
    plant_pool(user, "Empty pool")

    convert

    vacation = user.accounts.find_by!(name: "Vacation")
    expect(vacation.opened_on).to eq(Date.new(2026, 1, 1))
    expect(user.accounts.find_by!(name: "Empty pool").opened_on).to eq(user.main_account.opened_on)
    expect(user.accounts.count).to eq(3)
  end

  it "turns savings entries into transfers from main into the pool's account and deletes the category", :aggregate_failures do
    user = plant_user
    pool = plant_pool(user, "Vacation", start_date: Date.new(2026, 1, 1))
    saving = plant_category(user, "Vacation saving", savings, pool: pool)
    plant_entry(saving, 200, at: Time.utc(2026, 2, 1, 12))
    plant_entry(saving, 50, at: Time.utc(2026, 3, 1, 12))

    convert

    user.reload
    vacation = user.accounts.find_by!(name: "Vacation")
    expect(Transfer.where(from_account: user.main_account, to_account: vacation).order(:date).pluck(:date, :amount))
      .to eq([[Date.new(2026, 2, 1), 200], [Date.new(2026, 3, 1), 50]])
    expect(Category.where(user: user, name: "Vacation saving")).not_to exist
    expect(Item.count).to eq(0)
    expect(Entry.count).to eq(0)
    expect(AccountLedger.new(user).balance_of(vacation)).to eq(250)
  end

  it "mints an account named after a savings category that has no pool" do
    user = plant_user
    saving = plant_category(user, "Robinhood", savings)
    plant_entry(saving, 75, at: Time.utc(2026, 4, 1, 12))

    convert

    expect(AccountLedger.new(user.reload).balance_of(user.accounts.find_by!(name: "Robinhood"))).to eq(75)
  end

  it "keeps the total across accounts equal to income minus spending", :aggregate_failures do
    user = plant_user
    salary = plant_category(user, "Salary", income)
    food = plant_category(user, "Food", expense)
    saving = plant_category(user, "Emergency", savings)
    plant_entry(salary, 3000, at: Time.utc(2026, 5, 1, 12))
    plant_entry(food, 400, at: Time.utc(2026, 5, 2, 12))
    plant_entry(saving, 1000, at: Time.utc(2026, 5, 3, 12))

    convert

    ledger = AccountLedger.new(user.reload)
    expect(ledger.total_money).to eq(2600)
    expect(ledger.pot).to eq(1600)
    expect(ledger.balance_of(user.accounts.find_by!(name: "Emergency"))).to eq(1000)
  end

  it "suffixes account names that clash", :aggregate_failures do
    user = plant_user
    plant_pool(user, "checking")
    plant_category(user, "Vacation", savings, pool: plant_pool(user, "Vacation"))
    plant_category(user, "vacation", savings)

    convert

    expect(user.reload.main_account.name).to eq("Checking 2")
    expect(user.accounts.pluck(:name)).to contain_exactly("checking", "Checking 2", "Vacation", "vacation 2")
  end

  it "drops the pool link from the categories that survive", :aggregate_failures do
    user = plant_user
    pool = plant_pool(user, "Bills")
    plant_category(user, "Utilities", expense, pool: pool)

    convert

    utilities = Category.find_by!(name: "Utilities")
    expect(utilities.priority).to eq(0)
    expect(utilities).to be_regular
    expect(Category.column_names).not_to include("savings_pool_id")
  end

  it "stamps each rule with its budget's creation day in the user's timezone" do
    user = plant_user(timezone: "America/New_York")
    food = plant_category(user, "Food", expense)
    plant_budget(food, 400, created_at: Time.utc(2026, 3, 1, 3, 0))

    convert

    rule = Rule.find_by!(category_id: food.id)
    expect(rule.starts_on).to eq(Date.new(2026, 2, 28))
    expect(rule).to have_attributes(rule_type: "usage", anchor_date: nil, interval_months: nil, keeps_unspent: false, amount: 400)
  end

  it "converts entry timestamps to the user's calendar day, UTC when none is set", :aggregate_failures do
    ny = plant_user(timezone: "America/New_York")
    utc = plant_user
    plant_entry(plant_category(ny, "Food", expense), 10, at: Time.utc(2026, 3, 1, 3, 30))
    plant_entry(plant_category(utc, "Food", expense), 10, at: Time.utc(2026, 3, 1, 3, 30))

    convert

    expect(Entry.joins(item: :category).where(categories: { user_id: ny.id }).pick(:date)).to eq(Date.new(2026, 2, 28))
    expect(Entry.joins(item: :category).where(categories: { user_id: utc.id }).pick(:date)).to eq(Date.new(2026, 3, 1))
    expect(Entry.columns_hash["date"].type).to eq(:date)
  end

  it "removes main's shape", :aggregate_failures do
    convert

    connection = ActiveRecord::Base.connection
    expect(connection.table_exists?("savings_pools")).to be(false)
    expect(Rule.column_names).not_to include("prorated")
    expect(Entry.column_names).not_to include("day")
    expect(connection.check_constraints("categories").map(&:name)).to include("categories_two_types")
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/migrations/accounts_and_rules_spec.rb`
Expected: `cannot load such file` for the migration.

- [ ] **Step 3: The migration**

```ruby
# frozen_string_literal: true

# rubocop:disable Rails/SkipsModelValidations
# Converts main's data into the accounts-and-rules shape, then removes what main had and this
# schema does not. Runs inside the Migrator's transaction: any refused assertion rolls the whole
# run back. Migration-local table classes, so today's models never read yesterday's columns.
class AccountsAndRulesData < ActiveRecord::Migration[8.1]
  class Refused < StandardError; end

  EXPENSE = 0
  INCOME = 1
  SAVINGS = 2

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationAccount < ActiveRecord::Base
    self.table_name = "accounts"
  end

  class MigrationTransfer < ActiveRecord::Base
    self.table_name = "transfers"
  end

  class MigrationCategory < ActiveRecord::Base
    self.table_name = "categories"
  end

  class MigrationItem < ActiveRecord::Base
    self.table_name = "items"
  end

  class MigrationEntry < ActiveRecord::Base
    self.table_name = "entries"
  end

  class MigrationRule < ActiveRecord::Base
    self.table_name = "rules"
  end

  class MigrationPool < ActiveRecord::Base
    self.table_name = "savings_pools"
  end

  def up
    stamp_days
    MigrationUser.order(:created_at, :id).each { |user| convert(user) }
    tighten
  end

  # Restores main's shape, not its rows: accounts, transfers and stamped dates stay, the dropped
  # columns and table come back empty. Enough to rebuild a development database.
  def down
    create_table :savings_pools, id: :uuid do |t|
      t.string :name, null: false
      t.money :target_amount, scale: 2
      t.date :start_date
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.timestamps
    end
    add_reference :categories, :savings_pool, type: :uuid, foreign_key: true
    add_column :rules, :prorated, :boolean, null: false, default: false
    remove_check_constraint :categories, name: "categories_two_types"
    change_column_null :rules, :starts_on, true
    rename_column :entries, :date, :day
    add_column :entries, :date, :datetime
    execute "UPDATE entries SET date = day::timestamp"
    change_column_null :entries, :date, false
  end

  private

  def now = @now ||= Time.current

  # Every entry's calendar day in its owner's timezone, before anything reads a date.
  def stamp_days
    execute <<~SQL.squish
      UPDATE entries
         SET day = (entries.date AT TIME ZONE 'UTC' AT TIME ZONE COALESCE(users.timezone, 'UTC'))::date
        FROM items, categories, users
       WHERE items.id = entries.item_id AND categories.id = items.category_id AND users.id = categories.user_id
    SQL
  end

  def convert(user)
    truth = bank_truth(user)
    main = mint_account(user, "Checking", opened_on: opening_day(user))
    user.update_columns(main_account_id: main.id)
    receipt = { accounts: 1, transfers: 0, entries: 0 }
    expected = Hash.new(0.to_d)
    pool_accounts = accounts_for_pools(user, main, receipt)
    convert_savings(user, main, pool_accounts, receipt, expected)
    MigrationCategory.where(user_id: user.id).update_all(savings_pool_id: nil, updated_at: now)
    receipt[:rules] = stamp_rules(user)
    verify!(user, truth, expected, main)
    say "#{user.email}: #{receipt[:accounts]} accounts, #{receipt[:transfers]} transfers from " \
        "#{receipt[:entries]} savings entries, #{receipt[:rules]} rules"
  end

  def accounts_for_pools(user, main, receipt)
    MigrationPool.where(user_id: user.id).order(:created_at, :id).to_h do |pool|
      receipt[:accounts] += 1
      [pool.id, mint_account(user, pool.name, opened_on: pool.start_date || main.opened_on)]
    end
  end

  def convert_savings(user, main, pool_accounts, receipt, expected)
    MigrationCategory.where(user_id: user.id, category_type: SAVINGS).order(:created_at, :id).each do |category|
      account = pool_accounts[category.savings_pool_id]
      if account.nil?
        receipt[:accounts] += 1
        account = mint_account(user, category.name, opened_on: main.opened_on)
      end
      rows = entries_of_category(category).pluck(:amount, :day)
      move_savings(rows, main, account)
      expected[account.id] += rows.sum(0.to_d) { |amount, _day| amount.to_d }
      receipt[:transfers] += rows.size
      receipt[:entries] += delete_category(category)
    end
  end

  def mint_account(user, name, opened_on:)
    MigrationAccount.create!(user_id: user.id, name: unique_name(user, name), opening_balance: 0,
                             opened_on: opened_on, created_at: now, updated_at: now)
  end

  def unique_name(user, base)
    taken = MigrationAccount.where(user_id: user.id).pluck(:name).map(&:downcase).to_set
    return base unless taken.include?(base.downcase)

    suffix = 2
    suffix += 1 while taken.include?("#{base} #{suffix}".downcase)
    "#{base} #{suffix}"
  end

  def opening_day(user)
    first = entries_of(user).minimum(:day)
    first ? first - 1 : Date.current
  end

  def entries_of(user)
    MigrationEntry
      .joins("JOIN items ON items.id = entries.item_id JOIN categories ON categories.id = items.category_id")
      .where(categories: { user_id: user.id })
  end

  def entries_of_category(category)
    MigrationEntry.where(item_id: MigrationItem.where(category_id: category.id).select(:id))
  end

  def move_savings(rows, main, account)
    return if rows.empty?

    MigrationTransfer.insert_all!(rows.map do |amount, day|
      { from_account_id: main.id, to_account_id: account.id, amount: amount, date: day, created_at: now, updated_at: now }
    end)
  end

  def delete_category(category)
    deleted = entries_of_category(category).delete_all
    MigrationItem.where(category_id: category.id).delete_all
    category.delete
    deleted
  end

  def stamp_rules(user)
    rules = MigrationRule.where(category_id: MigrationCategory.where(user_id: user.id).select(:id))
    zone = user.timezone.presence || "UTC"
    rules.find_each { |rule| rule.update_columns(starts_on: rule.created_at.in_time_zone(zone).to_date) }
    rules.count
  end

  def bank_truth(user)
    sum_of(user, INCOME) - sum_of(user, EXPENSE)
  end

  def sum_of(user, type) = entries_of(user).where(categories: { category_type: type }).sum(:amount).to_d

  def verify!(user, truth, expected, main)
    balances = balances_of(user, main)
    total = balances.values.sum(0.to_d)
    refuse(user, "accounts hold #{total} but the books said #{truth}") unless total == truth
    expected.each do |account_id, amount|
      held = balances.fetch(account_id, 0.to_d)
      refuse(user, "account #{account_id} holds #{held} but its savings summed to #{amount}") unless held == amount
    end
    refuse(user, "a savings category survived") if MigrationCategory.where(user_id: user.id, category_type: SAVINGS).exists?
    unstarted = MigrationRule.where(category_id: MigrationCategory.where(user_id: user.id).select(:id), starts_on: nil)
    refuse(user, "a rule has no start") if unstarted.exists?
  end

  def balances_of(user, main)
    base = bank_truth(user)
    ids = MigrationAccount.where(user_id: user.id).pluck(:id)
    ins = MigrationTransfer.where(to_account_id: ids).group(:to_account_id).sum(:amount)
    outs = MigrationTransfer.where(from_account_id: ids).group(:from_account_id).sum(:amount)
    ids.to_h do |id|
      opening = id == main.id ? base : 0.to_d
      [id, opening + ins.fetch(id, 0).to_d - outs.fetch(id, 0).to_d]
    end
  end

  def refuse(user, reason) = raise(Refused, "#{user.email}: #{reason}")

  def tighten
    remove_column :entries, :date
    rename_column :entries, :day, :date
    change_column_null :entries, :date, false
    change_column_null :rules, :starts_on, false
    remove_column :rules, :prorated
    remove_reference :categories, :savings_pool, type: :uuid, foreign_key: true, index: true
    drop_table :savings_pools
    add_check_constraint :categories, "category_type IN (0, 1)", name: "categories_two_types"
  end
end
# rubocop:enable Rails/SkipsModelValidations
```

- [ ] **Step 4: Migrate both databases, then run the spec**

```bash
bin/rails db:migrate && RAILS_ENV=test bin/rails db:migrate
bin/rails db:rollback STEP=1 && bin/rails db:migrate
bundle exec rspec spec/migrations/accounts_and_rules_spec.rb
```

Expected: the rollback and re-run print one receipt line per user (the dev database currently holds only what the schema task left), and the spec is green. `AccountLedger` does not exist until Task 10, so the three examples that use it fail with `uninitialized constant AccountLedger`: leave them red, finish Task 10, and re-run this file as Task 10's last step.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A db/migrate/20260910000001_accounts_and_rules_data.rb spec/migrations/accounts_and_rules_spec.rb
git add -A
git commit -m "migration: main's data becomes accounts, transfers and rules"
```

### Squash checkpoint C

Do this after Task 10 has made the migration spec fully green:

```bash
git reset --soft "$(cat /tmp/group_c_base)"
git commit -m "data migration: main's data becomes accounts, transfers and rules

Per user: a main Checking account, one account per savings pool, savings entries as transfers,
budgets as per-period usage rules, entry timestamps as calendar days. Asserts bank totals to the
cent, then removes savings pools and main's columns."
git rev-parse HEAD > /tmp/group_d_base
```

Note: this squash includes Task 10's commit. That is deliberate; Task 10 is the ledger the migration spec reads through.

---

## Group D: ledgers and claims (spec commit 4)

### Task 10: AccountLedger, and Account#balance

**Files:**
- Create: `app/services/account_ledger.rb`, `spec/services/account_ledger_spec.rb`
- Modify: `app/models/account.rb`

**Interfaces:**
- Produces: `AccountLedger.new(user, today: user.today)` with `#balance_of(account)`, `#pot`, `#total_money`, `#income_within(range)`, `#typical_income` (BigDecimal or nil), `#complete_periods(limit)`; `AccountLedger::NotAnAccount`. `Account#balance`, `Account#correct_balance(typed)`.

- [ ] **Step 1: Spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountLedger do
  let(:user) { create(:user, :biweekly) }
  let(:main) { create(:account, user: user, opening_balance: 100) }
  let(:savings) { create(:account, user: user) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:ledger) { described_class.new(user, today: today) }

  def earn(amount, on:, account: nil, category: salary)
    create(:entry, item: create(:item, category: category), amount: amount, date: on, account: account)
  end

  def spend(amount, on:)
    create(:entry, item: create(:item, category: food), amount: amount, date: on)
  end

  let(:salary) { create(:category, :income, user: user, name: "Salary") }
  let(:food) { create(:category, user: user, name: "Food") }

  describe "#balance_of", :aggregate_failures do
    it "is opening plus what landed, minus what left, plus transfers in, minus transfers out" do
      main
      earn(50, on: today)
      earn(20, on: today, account: savings)
      spend(30, on: today)
      create(:transfer, from_account: main, to_account: savings, amount: 40, date: today)

      expect(ledger.balance_of(main)).to eq(80)
      expect(ledger.balance_of(savings)).to eq(60)
      expect(ledger.pot).to eq(80)
      expect(ledger.total_money).to eq(140)
    end

    it "refuses another user's account" do
      expect { ledger.balance_of(create(:account)) }.to raise_error(AccountLedger::NotAnAccount)
    end

    it "is zero for a user with no main account" do
      expect(described_class.new(create(:user), today: today).pot).to eq(0)
    end
  end

  describe "#typical_income" do
    let(:gifts) { create(:category, :income, :irregular, user: user, name: "Gifts") }

    it "averages regular income over the last two complete periods", :aggregate_failures do
      # Grid: ... Aug 7-20, Aug 21-Sep 3, [Sep 4-17 is today's period]
      earn(2000, on: Date.new(2026, 8, 7))
      earn(2200, on: Date.new(2026, 8, 25))
      earn(500, on: Date.new(2026, 8, 26), category: gifts)
      earn(999, on: Date.new(2026, 9, 5))

      expect(ledger.complete_periods(2)).to eq([Date.new(2026, 8, 7)..Date.new(2026, 8, 20), Date.new(2026, 8, 21)..Date.new(2026, 9, 3)])
      expect(ledger.typical_income).to eq(2100)
    end

    it "uses one period when only one is complete since the first entry" do
      earn(2000, on: Date.new(2026, 8, 10))
      earn(2200, on: Date.new(2026, 8, 25))

      expect(ledger.typical_income).to eq(2200)
    end

    it "is nil with no complete period", :aggregate_failures do
      expect(ledger.typical_income).to be_nil
      earn(2000, on: Date.new(2026, 9, 5))
      expect(ledger.typical_income).to be_nil
    end
  end

  describe "Account#balance and #correct_balance", :aggregate_failures do
    it "reads through the ledger and corrects by moving the opening balance" do
      main
      spend(30, on: today)

      expect(main.balance).to eq(70)
      main.correct_balance(250)
      expect(main.reload.opening_balance).to eq(280)
      expect(main.balance).to eq(250)
    end
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/services/account_ledger_spec.rb`
Expected: `uninitialized constant AccountLedger`.

- [ ] **Step 3: The ledger**

```ruby
# frozen_string_literal: true

# Balances for one user in a fixed number of queries. A balance is the opening balance, plus
# income that landed in the account, minus spending (main only), plus transfers in, minus out.
class AccountLedger
  class NotAnAccount < StandardError; end

  # How many complete periods typical income averages over.
  TYPICAL_PERIODS = 2
  PERIOD_WALK_LIMIT = 600

  attr_reader :user, :today

  def initialize(user, today: user.today)
    @user = user
    @today = today
  end

  def balance_of(account)
    raise NotAnAccount, "#{account.name} belongs to another user" unless account.user_id == user.id

    account.opening_balance.to_d + income_into(account) - expenses_from(account) +
      transfers_in(account) - transfers_out(account)
  end

  def pot = main.present? ? balance_of(main) : 0.to_d

  def total_money = user.accounts.sum(0.to_d) { |account| balance_of(account) }

  def income_within(range) = user_entries(Entry.incomes).where(date: range).sum(:amount).to_d

  # The mean of regular income over the last complete periods, nil until one period is complete.
  def typical_income
    periods = complete_periods(TYPICAL_PERIODS)
    return nil if periods.empty?

    (periods.sum(0.to_d) { |period| regular_income_within(period) } / periods.size).round(2)
  end

  # The last `limit` complete periods before today's, that begin on or after the first entry.
  def complete_periods(limit)
    first = user.entries.minimum(:date)
    return [] if first.nil?

    periods = []
    cursor = user.period_containing(user.period_containing(today).first - 1)
    while periods.size < limit && cursor.first >= first && periods.size < PERIOD_WALK_LIMIT
      periods.unshift(cursor)
      cursor = user.period_containing(cursor.first - 1)
    end
    periods
  end

  private

  def main = user.main_account

  def main?(account) = main.present? && account.id == main.id

  def income_into(account)
    landed = income_by_account.fetch(account.id, 0.to_d)
    main?(account) ? landed + income_by_account.fetch(nil, 0.to_d) : landed
  end

  def expenses_from(account) = main?(account) ? total_expenses : 0.to_d

  def transfers_in(account) = transfer_totals(:to_account_id).fetch(account.id, 0.to_d)

  def transfers_out(account) = transfer_totals(:from_account_id).fetch(account.id, 0.to_d)

  def income_by_account
    @income_by_account ||= user_entries(Entry.incomes).group("entries.account_id").sum(:amount).transform_values(&:to_d)
  end

  def total_expenses = @total_expenses ||= user_entries(Entry.expenses).sum(:amount).to_d

  def transfer_totals(column)
    @transfer_totals ||= {}
    @transfer_totals[column] ||= Transfer.where(column => user.accounts.select(:id)).group(column).sum(:amount).transform_values(&:to_d)
  end

  def user_entries(scope) = scope.where(categories: { user_id: user.id })

  def regular_income_within(period)
    user_entries(Entry.incomes).where(categories: { regular: true }, date: period).sum(:amount).to_d
  end
end
```

Add to `app/models/account.rb`, after `def main?`:

```ruby
  def balance = AccountLedger.new(user).balance_of(self)

  # Moves the opening balance so that the balance today equals the typed figure. Nothing else moves.
  def correct_balance(typed)
    update(opening_balance: opening_balance.to_d + (BigDecimal(typed.to_s) - balance))
  end
```

- [ ] **Step 4: Run the ledger spec and the migration spec**

Run: `bundle exec rspec spec/services/account_ledger_spec.rb spec/migrations/accounts_and_rules_spec.rb`
Expected: both green.

- [ ] **Step 5: Commit, then run squash checkpoint C**

```bash
bundle exec rubocop -A app/services/account_ledger.rb app/models/account.rb spec/services/account_ledger_spec.rb
git add -A
git commit -m "services: AccountLedger"
```

Now perform **Squash checkpoint C** above.

### Task 11: ClaimCalculator

**Files:**
- Create: `app/services/claim_calculator.rb`, `spec/services/claim_calculator_spec.rb`

**Interfaces:**
- Consumes: `Rule` (Task 8), `User#period_containing`, `#period_boundaries` (Task 5), `Entry.in_lane_of` (Task 7).
- Produces: `ClaimCalculator.new(rule, today:, spending: nil, adjustments: nil)` where `spending` and `adjustments` are arrays of `[Date, BigDecimal]` or nil to query. Public: `#shape`, `#rate?`, `#dated?`, `#fund?`, `#allowance?`, `#claim`, `#built_up`, `#planned_this_period`, `#standing_ask`, `#accrued_this_period`, `#spent_this_period`, `#over?`, `#raw_rate`, `#over_by`, `#next_due_on`, `#overdue?`, `#settled?`, `#settled_on`, `#periods_left`, `#target`, `#window_start`, `#counts_spending_on?(day)`, `#countable_span`.

- [ ] **Step 1: Spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

# Grid: biweekly from 2026-02-06. Today 2026-09-09 sits in Sep 4..Sep 17. Earlier periods:
# Jul 24..Aug 6, Aug 7..Aug 20, Aug 21..Sep 3.
RSpec.describe ClaimCalculator do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let(:bread) { create(:item, category: groceries, name: "Bread") }

  def spend(amount, on:) = create(:entry, item: bread, amount: amount, date: on)

  def calculator(rule) = described_class.new(rule, today: today)

  describe "a rate rule" do
    let(:rule) { create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1)) }

    it "claims the amount less this period's spending, never below zero", :aggregate_failures do
      spend(310, on: Date.new(2026, 9, 5))
      spend(999, on: Date.new(2026, 9, 1)) # last period: does not count

      expect(calculator(rule).claim).to eq(90)
      expect(calculator(rule).spent_this_period).to eq(310)
      expect(calculator(rule).accrued_this_period).to eq(400)
      expect(calculator(rule).planned_this_period).to eq(400)
      expect(calculator(rule).standing_ask).to eq(400)
      expect(calculator(rule)).not_to be_over
    end

    it "takes adjustments this period and reports overspending", :aggregate_failures do
      spend(310, on: Date.new(2026, 9, 5))
      create(:adjustment, rule: rule, amount: -100, date: Date.new(2026, 9, 6))

      expect(calculator(rule).claim).to eq(0)
      expect(calculator(rule).raw_rate).to eq(-10)
      expect(calculator(rule)).to be_over
      expect(calculator(rule).over_by).to eq(10)
      expect(calculator(rule).next_due_on).to be_nil
    end

    it "counts only this period, from its start or from the rule's start", :aggregate_failures do
      expect(calculator(rule).countable_span).to eq(Date.new(2026, 9, 4)..today)
      late = create(:rule, :rate, amount: 100, category: create(:category, user: user), starts_on: Date.new(2026, 9, 7))
      expect(calculator(late).countable_span).to eq(Date.new(2026, 9, 7)..today)
    end
  end

  describe "a fund rule" do
    let(:rule) { create(:rule, :keeps_unspent, amount: 60, category: groceries, starts_on: Date.new(2026, 8, 1)) }

    it "adds the amount every period and keeps what is unspent", :aggregate_failures do
      # Periods since Aug 1: Jul 24, Aug 7, Aug 21, Sep 4 = four.
      expect(calculator(rule).claim).to eq(240)
      expect(calculator(rule).built_up).to eq(240)
      expect(calculator(rule).planned_this_period).to eq(60)
      expect(calculator(rule).standing_ask).to eq(60)
      expect(calculator(rule).target).to be_nil

      spend(100, on: Date.new(2026, 8, 25))
      expect(calculator(rule).claim).to eq(140)
      expect(calculator(rule).accrued_this_period).to eq(60)
    end

    it "never goes negative, and says over when spending outruns it", :aggregate_failures do
      spend(300, on: Date.new(2026, 9, 5))

      expect(calculator(rule).claim).to eq(0)
      expect(calculator(rule)).to be_over
      expect(calculator(rule).over_by).to eq(60)
    end
  end

  describe "a dated one-off rule" do
    let(:rule) { create(:rule, :bill, amount: 600, anchor_date: Date.new(2026, 10, 15), category: groceries, starts_on: Date.new(2026, 8, 1)) }

    it "plans an even share per period toward the target", :aggregate_failures do
      # Six boundaries from Jul 24 to Oct 15 (Jul 24, Aug 7, Aug 21, Sep 4, Sep 18, Oct 2): $100 a period.
      expect(calculator(rule).standing_ask).to eq(100)
      expect(calculator(rule).claim).to eq(400)
      expect(calculator(rule).built_up).to eq(400)
      expect(calculator(rule).planned_this_period).to eq(100)
      expect(calculator(rule).periods_left).to eq(3)
      expect(calculator(rule).next_due_on).to eq(Date.new(2026, 10, 15))
      expect(calculator(rule).target).to eq(600)
      expect(calculator(rule)).not_to be_overdue
      expect(calculator(rule)).not_to be_settled
    end

    it "settles once paid", :aggregate_failures do
      spend(600, on: Date.new(2026, 9, 5))

      expect(calculator(rule)).to be_settled
      expect(calculator(rule).settled_on).to eq(Date.new(2026, 9, 5))
      expect(calculator(rule).claim).to eq(0)
    end

    it "is overdue past its date until paid" do
      overdue = create(:rule, :bill, amount: 100, anchor_date: Date.new(2026, 9, 1), category: create(:category, user: user), starts_on: Date.new(2026, 8, 1))

      expect(calculator(overdue)).to be_overdue
    end

    it "caps a set-aside at the target and takes it back with a negative adjustment", :aggregate_failures do
      create(:adjustment, rule: rule, amount: 500, date: Date.new(2026, 9, 5))
      expect(calculator(rule).claim).to eq(600)

      create(:adjustment, rule: rule, amount: -500, date: Date.new(2026, 9, 6))
      expect(calculator(rule).claim).to eq(400)
    end
  end

  describe "a rolling rule" do
    let(:rule) { create(:rule, :bill, amount: 180, anchor_date: Date.new(2026, 3, 1), interval_months: 6, category: groceries, starts_on: Date.new(2026, 1, 1)) }

    it "advances the due date by one interval for each target paid", :aggregate_failures do
      expect(calculator(rule).next_due_on).to eq(Date.new(2026, 3, 1))
      expect(calculator(rule)).to be_overdue

      spend(180, on: Date.new(2026, 3, 2))
      expect(calculator(rule).next_due_on).to eq(Date.new(2026, 9, 1))

      spend(180, on: Date.new(2026, 9, 2))
      expect(calculator(rule).next_due_on).to eq(Date.new(2027, 3, 1))
      expect(calculator(rule)).not_to be_overdue
    end
  end

  describe "a rule that starts in the future" do
    it "claims nothing and counts nothing yet", :aggregate_failures do
      rule = create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 10, 1))

      expect(calculator(rule).claim).to eq(0)
      expect(calculator(rule).planned_this_period).to eq(0)
      expect(calculator(rule).countable_span).to be_none
    end
  end

  describe "given rows" do
    it "uses the rows it is handed instead of querying", :aggregate_failures do
      rule = create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1))
      spend(310, on: Date.new(2026, 9, 5))

      handed = described_class.new(rule, today: today, spending: [[Date.new(2026, 9, 5), 50.to_d]], adjustments: [])
      expect(handed.claim).to eq(350)
    end
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/services/claim_calculator_spec.rb`
Expected: `uninitialized constant ClaimCalculator`.

- [ ] **Step 3: The calculator**

```ruby
# frozen_string_literal: true

# One rule's claim on main, computed from its shape, the user's period grid, its lane's spending
# and its adjustments. Spending and adjustment rows are [day, amount] pairs, queried unless handed in.
class ClaimCalculator
  PERIOD_WALK_LIMIT = 520

  Walk = Struct.new(:built_up, :raw, :planned, :paid) do
    def self.start = new(0.to_d, 0.to_d, 0.to_d, 0.to_d)
  end

  attr_reader :rule, :today

  def initialize(rule, today: rule.today, spending: nil, adjustments: nil)
    @rule = rule
    @today = today
    @spending = spending
    @adjustments = adjustments
  end

  delegate :shape, to: :rule
  def rate? = shape == :rate
  def dated? = shape == :dated
  def fund? = shape == :fund
  def allowance? = rate? || fund?

  def claim
    return 0.to_d if periods.empty?

    rate? ? rate_claim : built_up
  end

  def built_up = rate? ? 0.to_d : walk.built_up

  def planned_this_period
    return 0.to_d if periods.empty?

    rate? ? rate_per_period : walk.planned
  end

  # What the rule costs a period: its amount, or a one-off target spread to its date.
  def standing_ask
    return rate_per_period unless one_time?

    (target / periods_to_fund).round(2)
  end

  def accrued_this_period = planned_this_period + adjustments_within(current_period)
  def spent_this_period = spent_within(current_period)
  def over? = rate? ? raw_rate.negative? : walk.raw.negative?
  def raw_rate = accrued_this_period - spent_this_period
  def over_by = rate? ? -raw_rate : -walk.raw
  def next_due_on = dated? ? due_on(today, walk.paid) : nil
  def overdue? = next_due_on.present? && next_due_on < today && !settled?
  def settled? = one_time? && settled_by?(walk.paid)

  def settled_on
    return nil unless settled?

    running = 0.to_d
    countable_spending.each do |day, amount|
      running += amount
      return day if running >= target
    end
    nil
  end

  def periods_left
    due = next_due_on
    due ? periods_left_from(current_period.first, due) : nil
  end

  def target
    return @target if defined?(@target)

    @target = dated? ? rule.amount.to_d : (fund? ? nil : 0.to_d)
  end

  def window_start = periods.first&.first || current_period.first

  def counts_spending_on?(day) = day >= rule.starts_on && periods.any? { |period| period.cover?(day) }

  # The dates an adjustment may carry: from the rule's start (or the first counted period) to today.
  def countable_span
    return (today...today) if periods.empty?

    [window_start, rule.starts_on].max..[today, periods.last.last].min
  end

  private

  def user = rule.user
  def rate_claim = [raw_rate, 0.to_d].max
  def rate_per_period = rule.amount.to_d

  def walk
    @walk ||= Walk.start.tap { |state| periods.each { |period| step(state, period) } }
  end

  def step(state, period)
    state.planned = planned_for(period, state, due_on(period.first, state.paid))
    settle(state, accrued_in(state, period), spent_within(period))
  end

  def accrued_in(state, period)
    accrued = state.built_up + state.planned + adjustments_within(period)
    return accrued if fund?

    [accrued, target].min
  end

  def settle(state, accrued, spent)
    state.paid += spent
    state.raw = accrued - spent
    state.built_up = [state.raw, 0.to_d].max
  end

  def planned_for(period, state, due)
    return rate_per_period if fund?
    return 0.to_d if settled_by?(state.paid)

    gap = target - state.built_up
    return 0.to_d unless gap.positive?

    [(gap / periods_left_from(period.first, due)).round(2), gap].min
  end

  def settled_by?(paid) = one_time? && paid >= target
  def one_time? = anchor.present? && rule.interval_months.nil?
  def anchor = rule.anchor_date

  def countable_spending
    spending_rows.select { |day, _amount| counts_spending_on?(day) }.sort_by(&:first)
  end

  # A one-off is due on its date. A rolling rule's date advances one interval per target paid,
  # never past the cycle the calendar has reached.
  def due_on(date, paid)
    return nil if anchor.blank?
    return anchor if rule.interval_months.nil? || !target.positive?

    anchor + (cycles_paid_by(date, paid) * rule.interval_months).months
  end

  def cycles_paid_by(date, paid) = [(paid / target).floor, elapsed_cycles(date)].min

  def elapsed_cycles(date)
    return 0 if date < anchor

    (months_since_anchor(date) / rule.interval_months) + 1
  end

  def months_since_anchor(date)
    months = ((date.year * 12) + date.month) - ((anchor.year * 12) + anchor.month)
    date.day < anchor.day ? months - 1 : months
  end

  def periods
    @periods ||= if rule.starts_on > today
                   []
                 elsif rate?
                   [current_period]
                 else
                   walk_periods
                 end
  end

  def current_period = @current_period ||= user.period_containing(today)

  def walk_periods
    visited = []
    cursor = user.period_containing(rule.starts_on)
    while cursor.first <= today && visited.size < PERIOD_WALK_LIMIT
      visited << cursor
      cursor = user.period_containing(cursor.last + 1)
    end
    visited
  end

  def periods_left_from(from, due) = [user.period_boundaries(from: from, to: due).count, 1].max
  def periods_to_fund = periods_left_from(user.period_containing(rule.starts_on).first, anchor)

  def spent_within(period)
    spending_rows.sum(0.to_d) { |day, amount| period.cover?(day) && day >= rule.starts_on ? amount : 0.to_d }
  end

  def adjustments_within(period)
    adjustment_rows.sum(0.to_d) { |day, amount| period.cover?(day) ? amount : 0.to_d }
  end

  def spending_rows = @spending_rows ||= @spending.nil? ? query_spending : @spending
  def adjustment_rows = @adjustment_rows ||= @adjustments.nil? ? query_adjustments : @adjustments

  def query_spending
    Entry.in_lane_of(rule).since([window_start, rule.starts_on].max).pluck(:date, :amount).map { |day, amount| [day, amount.to_d] }
  end

  def query_adjustments
    rule.adjustments.pluck(:date, :amount).map { |day, amount| [day, amount.to_d] }
  end
end
```

- [ ] **Step 4: Run the spec, and the rule spec's one-off ask**

Run: `bundle exec rspec spec/services/claim_calculator_spec.rb spec/models/rule_spec.rb`
Expected: green.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A app/services/claim_calculator.rb spec/services/claim_calculator_spec.rb
git add -A
git commit -m "services: ClaimCalculator"
```

### Task 12: ClaimLedger

**Files:**
- Create: `app/services/claim_ledger.rb`, `spec/services/claim_ledger_spec.rb`

**Interfaces:**
- Produces: `ClaimLedger.new(user, today:)` with `#rules`, `#calculator_for(rule)`, `#claim_of(rule)`, `#claim_of_category(category)`, `#rules_of(category)`, `#rules_by_category`, `#total_claims`, `#total_money`, `#pot`, `#free`, `#account_ledger`; `ClaimLedger::UnknownRule`.

- [ ] **Step 1: Spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClaimLedger do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:ledger) { described_class.new(user, today: today) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let(:bread) { create(:item, category: groceries, name: "Bread") }
  let(:milk) { create(:item, category: groceries, name: "Milk") }

  before { create(:account, user: user, opening_balance: 1_000) }

  it "hands every rule a calculator fed from batched rows and agrees with the calculators", :aggregate_failures do
    bread_rule = create(:rule, :rate, amount: 100, category: groceries, item: bread, starts_on: Date.new(2026, 1, 1))
    whole_rule = create(:rule, :keeps_unspent, amount: 60, category: groceries, starts_on: Date.new(2026, 8, 1))
    create(:entry, item: bread, amount: 30, date: Date.new(2026, 9, 5))
    create(:entry, item: milk, amount: 100, date: Date.new(2026, 8, 25))
    create(:adjustment, rule: whole_rule, amount: 10, date: Date.new(2026, 9, 6))

    expect(ledger.rules).to contain_exactly(bread_rule, whole_rule)
    expect(ledger.claim_of(bread_rule)).to eq(70)
    expect(ledger.claim_of(whole_rule)).to eq(150)
    expect(ledger.claim_of(bread_rule)).to eq(ClaimCalculator.new(bread_rule, today: today).claim)
    expect(ledger.claim_of(whole_rule)).to eq(ClaimCalculator.new(whole_rule, today: today).claim)
    expect(ledger.claim_of_category(groceries)).to eq(220)
    expect(ledger.rules_of(groceries)).to contain_exactly(bread_rule, whole_rule)
    expect(ledger.total_claims).to eq(220)
    expect(ledger.pot).to eq(870)
    expect(ledger.free).to eq(650)
    expect(ledger.total_money).to eq(870)
  end

  it "loads its rows in a fixed number of queries" do
    3.times { create(:rule, :rate, category: create(:category, user: user), starts_on: Date.new(2026, 1, 1)) }
    queries = 0
    counter = ->(*) { queries += 1 }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { ledger.total_claims }

    expect(queries).to be <= 8
  end

  it "refuses a rule it does not hold" do
    expect { ledger.calculator_for(create(:rule)) }.to raise_error(ClaimLedger::UnknownRule)
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/services/claim_ledger_spec.rb`
Expected: `uninitialized constant ClaimLedger`.

- [ ] **Step 3: The ledger**

```ruby
# frozen_string_literal: true

# Every rule's calculator for one user, fed from three queries: the lanes' spending since the
# earliest window, and every adjustment in it.
class ClaimLedger
  class UnknownRule < StandardError; end

  attr_reader :user, :today

  def initialize(user, today: user.today)
    @user = user
    @today = today
  end

  def rules
    @rules ||= user.rules.includes(:item, category: :user).to_a
  end

  def claim_of(rule) = calculator_for(rule).claim

  def claim_of_category(category)
    rules_of(category).sum(0.to_d) { |rule| claim_of(rule) }
  end

  def rules_of(category) = rules_by_category.fetch(category.id, [])
  def rules_by_category = @rules_by_category ||= rules.group_by(&:category_id)

  def calculator_for(rule)
    calculators.fetch(rule) { raise UnknownRule, "#{rule.category&.name} is not one of #{user.email}'s rules" }
  end

  def total_claims = @total_claims ||= calculators.values.sum(0.to_d, &:claim)
  def total_money = account_ledger.total_money
  def pot = account_ledger.pot
  def free = pot - total_claims
  def account_ledger = @account_ledger ||= AccountLedger.new(user, today: today)

  private

  def calculators
    @calculators ||= rules.index_with do |rule|
      ClaimCalculator.new(rule, today: today, spending: spending_for(rule), adjustments: adjustments_for(rule))
    end
  end

  # The earliest day any rule's walk starts, so one query covers every lane.
  def window_start
    @window_start ||= rules.map { |rule| period_start_of(rule) }.min || current_period.first
  end

  def period_start_of(rule)
    rule.shape == :rate ? current_period.first : user.period_containing(rule.starts_on).first
  end

  def current_period = @current_period ||= user.period_containing(today)

  def spending_for(rule)
    rows = rule.item_id.present? ? item_spending[rule.item_id] : category_spending[rule.category_id]
    Array(rows).map { |_key, day, amount| [day, amount.to_d] }
  end

  def adjustments_for(rule)
    Array(adjustment_rows[rule.id]).map { |_key, day, amount| [day, amount.to_d] }
  end

  def draining
    Entry.expenses.where(categories: { user_id: user.id }).since(window_start)
  end

  def item_spending
    @item_spending ||= begin
      ids = rules.filter_map(&:item_id)
      ids.empty? ? {} : draining.where(item_id: ids).pluck(:item_id, :date, :amount).group_by(&:first)
    end
  end

  def category_spending
    @category_spending ||= begin
      ids = rules.reject { |rule| rule.item_id.present? }.map(&:category_id)
      if ids.empty?
        {}
      else
        draining.on_unruled_items.where(items: { category_id: ids })
          .pluck("items.category_id", :date, :amount).group_by(&:first)
      end
    end
  end

  def adjustment_rows
    @adjustment_rows ||= begin
      ids = rules.map(&:id)
      ids.empty? ? {} : Adjustment.where(rule_id: ids).dated_within(window_start..).pluck(:rule_id, :date, :amount).group_by(&:first)
    end
  end
end
```

- [ ] **Step 4: Run the services directory**

Run: `bundle exec rspec spec/services`
Expected: green.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A app/services/claim_ledger.rb spec/services/claim_ledger_spec.rb
git add -A
git commit -m "services: ClaimLedger"
```

### Squash checkpoint D

```bash
git reset --soft "$(cat /tmp/group_d_base)"
git commit -m "ledgers and claims: AccountLedger, ClaimCalculator, ClaimLedger

Balances, the pot, typical income; one rule's claim from its shape, the grid, its lane and its
adjustments; every rule's claim for a user from three queries."
git rev-parse HEAD > /tmp/group_e_base
```

---

## Group E: forms (spec commit 5)

### Task 13: RuleForm

**Files:**
- Create: `app/services/rule_form.rb`, `spec/services/rule_form_spec.rb`

**Interfaces:**
- Produces: `RuleForm.new(user, params = {}, rule: nil)`; `RuleForm.from(rule)` returns a Hash of the form's words; `#save` returns true or false and carries the rule's errors onto form fields; `#rule`, `#persisted?`, `#repeats?`, `#keeps?`, `#schedule`, `#rule_type`, `#amount`, `#category_id`, `#item_id`, `#interval_months`, `#anchor_date`, `#starts_on`; `RuleForm::FIELDS`, `RuleForm::SCHEDULES`.

- [ ] **Step 1: Spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe RuleForm do
  let(:user) { create(:user, :biweekly) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let(:bread) { create(:item, category: groceries, name: "Bread") }

  def form(params, rule: nil) = described_class.new(user, params, rule: rule)

  it "writes a per-period allowance, starting today unless told otherwise", :aggregate_failures do
    saved = form(category_id: groceries.id, rule_type: "usage", amount: "400", schedule: "per_period")

    expect(saved.save).to be(true)
    expect(saved.rule).to have_attributes(anchor_date: nil, interval_months: nil, keeps_unspent: false, amount: 400, starts_on: user.today)
  end

  it "writes a fund when keeps is ticked, and ignores keeps for a dated rule", :aggregate_failures do
    fund = form(category_id: groceries.id, rule_type: "usage", amount: "60", schedule: "per_period", keeps: "1")
    dated = form(category_id: groceries.id, rule_type: "bill", amount: "600", schedule: "by_date", keeps: "1", anchor_date: "2026-10-15", item_id: bread.id)

    expect(fund.save).to be(true)
    expect(fund.rule).to be_keeps_unspent
    expect(dated.save).to be(true)
    expect(dated.rule).to have_attributes(keeps_unspent: false, anchor_date: Date.new(2026, 10, 15), interval_months: nil)
  end

  it "writes an interval only when the rule repeats, and a start date when given", :aggregate_failures do
    rolling = form(category_id: groceries.id, rule_type: "bill", amount: "180", schedule: "by_date", anchor_date: "2026-10-01",
                   repeats: "1", interval_months: "6", starts_on: "2026-01-01")

    expect(rolling.save).to be(true)
    expect(rolling.rule).to have_attributes(interval_months: 6, starts_on: Date.new(2026, 1, 1))
  end

  it "refuses incoherent choices before touching the rule", :aggregate_failures do
    no_date = form(category_id: groceries.id, rule_type: "bill", amount: "1", schedule: "by_date")
    stray_interval = form(category_id: groceries.id, rule_type: "bill", amount: "1", schedule: "per_period", interval_months: "3")
    unknown = form(category_id: groceries.id, rule_type: "wish", amount: "1", schedule: "weekly")

    expect(no_date.save).to be(false)
    expect(no_date.errors[:schedule]).to include("needs the date it is first due")
    expect(stray_interval.save).to be(false)
    expect(stray_interval.errors[:schedule]).to include("does not take a number of months — tick \"repeats\" to set one")
    expect(unknown.save).to be(false)
    expect(unknown.errors[:schedule]).to include("is not one of the choices on this form")
    expect(unknown.errors[:rule_type]).to include("is not a kind of rule")
    expect(Rule.count).to eq(0)
  end

  it "carries the rule's errors onto the form's fields", :aggregate_failures do
    create(:rule, category: groceries)
    second = form(category_id: groceries.id, rule_type: "usage", amount: "10", schedule: "per_period")

    expect(second.save).to be(false)
    expect(second.errors[:item_id]).to include(Rule::CATCH_ALL_TAKEN)
    expect(form(category_id: groceries.id, rule_type: "usage", amount: "0", schedule: "per_period").tap(&:save).errors[:amount]).to be_present
  end

  it "reads an existing rule back into words and edits it", :aggregate_failures do
    rule = create(:rule, :rolling, category: groceries, amount: 180, interval_months: 6, anchor_date: Date.new(2026, 10, 1))
    words = described_class.from(rule)

    expect(words).to include(schedule: "by_date", repeats: true, interval_months: 6, anchor_date: Date.new(2026, 10, 1), keeps: false)

    edited = form(words.merge(amount: "200"), rule: rule)
    expect(edited.save).to be(true)
    expect(rule.reload.amount).to eq(200)
    expect(edited).to be_persisted
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/services/rule_form_spec.rb`
Expected: `uninitialized constant RuleForm`.

- [ ] **Step 3: The form**

```ruby
# frozen_string_literal: true

# The rule form's words, turned into a rule's columns. Two schedules: per period (which may keep
# what it doesn't spend) and by a date (which may repeat every N months).
class RuleForm
  include ActiveModel::Model

  SCHEDULES = ["per_period", "by_date"].freeze
  DEFAULT_SCHEDULE = "per_period"
  FIELDS = [:category_id, :item_id, :rule_type, :amount, :schedule, :repeats, :keeps, :interval_months, :anchor_date, :starts_on].freeze
  RULE_ERROR_FIELDS = {
    interval_months: :schedule, anchor_date: :schedule, amount: :amount, rule_type: :rule_type,
    item: :item_id, category: :category_id, starts_on: :starts_on
  }.freeze

  attr_reader :user, :rule, :anchor_date, :starts_on
  attr_accessor :category_id, :item_id, :rule_type, :amount, :schedule, :interval_months
  attr_writer :repeats, :keeps

  def initialize(user, params = {}, rule: nil)
    @user = user
    @rule = rule || Rule.new
    assign(params)
    apply_to_rule
  end

  def self.from(rule)
    schedule = rule.anchor_date.present? ? "by_date" : "per_period"
    {
      category_id: rule.category_id, item_id: rule.item_id, rule_type: rule.rule_type, amount: rule.amount,
      schedule: schedule, repeats: schedule == "by_date" && rule.interval_months.present?,
      keeps: rule.keeps_unspent, interval_months: rule.interval_months, anchor_date: rule.anchor_date,
      starts_on: rule.starts_on
    }
  end

  def save
    return false unless choices_are_coherent?

    rule.save.tap { |written| carry_rule_errors unless written }
  end

  delegate :persisted?, to: :rule

  def repeats = ActiveModel::Type::Boolean.new.cast(@repeats)
  def repeats? = repeats.present?
  def keeps = ActiveModel::Type::Boolean.new.cast(@keeps)
  def keeps? = keeps.present? && schedule != "by_date"

  def anchor_date=(value)
    @anchor_date = Rule.type_for_attribute(:anchor_date).cast(value)
  end

  def starts_on=(value)
    @starts_on = Rule.type_for_attribute(:starts_on).cast(value)
  end

  private

  def assign(params)
    params = params.to_h.symbolize_keys
    FIELDS.each { |field| public_send(:"#{field}=", params[field]) if params.key?(field) }
    @schedule = @schedule.presence&.to_s || DEFAULT_SCHEDULE
    @rule_type = @rule_type.presence&.to_s
    @starts_on ||= rule.starts_on || user.today
  end

  def apply_to_rule
    rule.assign_attributes(category_id: category_id.presence, item_id: item_id.presence, amount: amount, starts_on: starts_on, **schedule_columns)
    rule.rule_type = rule_type if rule_type_known?
  end

  def schedule_columns
    return { anchor_date: nil, interval_months: nil, keeps_unspent: keeps? } unless schedule == "by_date"

    { anchor_date: anchor_date, interval_months: (interval_months.presence if repeats?), keeps_unspent: false }
  end

  def rule_type_known? = rule_type.blank? || Rule.rule_types.key?(rule_type)

  def choices_are_coherent?
    errors.clear
    errors.add(:schedule, "is not one of the choices on this form") unless SCHEDULES.include?(schedule)
    errors.add(:rule_type, "is not a kind of rule") unless rule_type_known?
    check_schedule_fields if SCHEDULES.include?(schedule)
    errors.empty?
  end

  def check_schedule_fields
    if schedule == "by_date"
      errors.add(:schedule, "needs the date it is first due") if anchor_date.blank?
      errors.add(:schedule, "needs the number of months it comes round in") if repeats? && interval_months.blank?
    else
      errors.add(:schedule, "does not take a due date — choose \"By a date\" for a dated rule") if anchor_date.present?
      errors.add(:schedule, "does not take a number of months — tick \"repeats\" to set one") if interval_months.present?
    end
  end

  def carry_rule_errors
    rule.errors.each { |error| errors.add(form_field_for(error), error.message) }
  end

  def form_field_for(error)
    return :item_id if error.attribute == :base && error.message == Rule::CATCH_ALL_TAKEN

    RULE_ERROR_FIELDS.fetch(error.attribute, error.attribute)
  end
end
```

- [ ] **Step 4: Run the spec**

Run: `bundle exec rspec spec/services/rule_form_spec.rb`
Expected: green.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A app/services/rule_form.rb spec/services/rule_form_spec.rb
git add -A
git commit -m "services: RuleForm"
```

### Task 14: AdjustmentForm

**Files:**
- Create: `app/services/adjustment_form.rb`, `spec/services/adjustment_form_spec.rb`

**Interfaces:**
- Produces: `AdjustmentForm.new(rule:, params:, name:, today:)` with `#save`, `#adjustment`, `#skip?`, `#error_sentence`, `#rate?`, `#allowance?`, `#calculator`, `#name`. Params: `amount`, `amount_sign` (negative integer for a take-back), `date`, `skip`.

- [ ] **Step 1: Spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdjustmentForm do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let(:rate) { create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1)) }
  let(:dated) { create(:rule, :bill, amount: 600, anchor_date: Date.new(2026, 10, 15), category: groceries, starts_on: Date.new(2026, 8, 1)) }

  def form(rule, params) = described_class.new(rule: rule, params: params, name: "Groceries", today: today)

  it "tops up, reduces, and dates today by default", :aggregate_failures do
    up = form(rate, { amount: "50" })
    expect(up.save).to be(true)
    expect(up.adjustment).to have_attributes(amount: 50, date: today)

    down = form(rate, { amount: "20", amount_sign: "-1", date: "2026-09-05" })
    expect(down.save).to be(true)
    expect(down.adjustment).to have_attributes(amount: -20, date: Date.new(2026, 9, 5))
  end

  it "skips this period by writing minus what accrued", :aggregate_failures do
    skip = form(dated, { skip: "1" })

    expect(skip.skip?).to be(true)
    expect(skip.save).to be(true)
    expect(skip.adjustment.amount).to eq(-100)
  end

  it "refuses a skip with nothing accrued", :aggregate_failures do
    create(:adjustment, rule: rate, amount: -400, date: Date.new(2026, 9, 5))
    skip = form(rate, { skip: "1" })

    expect(skip.save).to be(false)
    expect(skip.error_sentence).to eq("Groceries isn't accruing anything this period, so there's nothing to skip.")
  end

  it "refuses a date outside what the rule counts", :aggregate_failures do
    last_period = form(rate, { amount: "10", date: "2026-08-30" })
    expect(last_period.save).to be(false)
    expect(last_period.error_sentence).to eq("Groceries counts this period only, up to today — pick a date between Sep 4 and Sep 9.")

    future = form(dated, { amount: "10", date: "2026-09-20" })
    expect(future.save).to be(false)
    expect(future.error_sentence).to eq("Groceries counts dates from when it started building, up to today — pick a date between Aug 1 and Sep 9.")
  end

  it "refuses a rule that has not started" do
    later = create(:rule, :rate, amount: 10, category: create(:category, user: user), starts_on: Date.new(2026, 10, 1))
    attempt = form(later, { amount: "10" })

    expect(attempt.save).to be(false)
    expect(attempt.error_sentence).to eq("Groceries hasn't started counting yet, so there's nothing to adjust.")
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/services/adjustment_form_spec.rb`
Expected: `uninitialized constant AdjustmentForm`.

- [ ] **Step 3: The form**

```ruby
# frozen_string_literal: true

# Writes one adjustment on a rule from the adjust panel: a signed amount on a date, or a skip,
# which is minus whatever accrued this period. Dates outside what the rule counts are refused.
class AdjustmentForm
  DAY = "%b %-d"

  attr_reader :rule, :name, :today, :calculator, :adjustment

  def initialize(rule:, params:, name:, today: rule.today)
    @rule = rule
    @params = params
    @name = name
    @today = today
    @calculator = rule.claim_calculator(today: today)
    @adjustment = rule.adjustments.new(amount: amount, date: chosen_date)
  end

  def save
    return false unless acceptable?

    adjustment.save
  end

  def error_sentence = adjustment.errors.full_messages.to_sentence
  def skip? = @params[:skip].present?

  delegate :rate?, :allowance?, to: :calculator

  private

  def acceptable?
    add_refusal
    adjustment.errors.empty?
  end

  def add_refusal
    return adjustment.errors.add(:base, nothing_to_skip_sentence) if nothing_to_skip?
    return unless adjustment.valid?

    refusal = date_refusal
    adjustment.errors.add(:base, refusal) if refusal
  end

  def date_refusal
    return not_counting_yet if countable_span.none?
    return if countable_span.cover?(adjustment.date)

    out_of_reach
  end

  def nothing_to_skip_sentence = "#{name} isn't accruing anything this period, so there's nothing to skip."
  def not_counting_yet = "#{name} hasn't started counting yet, so there's nothing to adjust."
  def nothing_to_skip? = skip? && !calculator.accrued_this_period.positive?
  def countable_span = @countable_span ||= calculator.countable_span

  def out_of_reach
    "#{name} #{reach_clause} — pick a date between " \
      "#{countable_span.first.strftime(DAY)} and #{countable_span.last.strftime(DAY)}."
  end

  def reach_clause
    return "counts this period only, up to today" if rate?

    "counts dates from when it started building, up to today"
  end

  def amount
    return -calculator.accrued_this_period if skip?
    return -@params[:amount].to_s.to_d.abs if @params[:amount_sign].to_i.negative?

    @params[:amount]
  end

  def chosen_date
    return today if skip?

    @params[:date].presence || today
  end
end
```

- [ ] **Step 4: Run the spec**

Run: `bundle exec rspec spec/services/adjustment_form_spec.rb`
Expected: green.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A app/services/adjustment_form.rb spec/services/adjustment_form_spec.rb
git add -A
git commit -m "services: AdjustmentForm"
```

### Task 15: EntryForm

**Files:**
- Create: `app/services/entry_form.rb`, `spec/services/entry_form_spec.rb`
- Modify: `app/models/entry.rb` (remove `accepts_nested_attributes_for :item`)

**Interfaces:**
- Produces: `EntryForm.new(user, entry, params, category_id: nil)` with `#save`, `#entry`, `#errors`. Params: `amount` (may be a formula), `date`, `description`, `item_id` (a UUID or anything else meaning none), `account_id`, `item_attributes: { name: }`.

- [ ] **Step 1: Spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntryForm do
  let(:user) { create(:user) }
  let(:main) { create(:account, user: user) }
  let(:savings) { create(:account, user: user) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let(:salary) { create(:category, :income, user: user, name: "Salary") }
  let(:bread) { create(:item, category: groceries, name: "Bread") }

  def build_form(params, entry: Entry.new, category_id: nil) = described_class.new(user, entry, params, category_id: category_id)

  it "evaluates a formula in the amount and writes the chosen item", :aggregate_failures do
    form = build_form({ amount: "12.5 * 2", date: "2026-09-05", description: "loaves", item_id: bread.id })

    expect(form.save).to be(true)
    expect(form.entry).to have_attributes(amount: 25, date: Date.new(2026, 9, 5), item: bread, account: nil)
  end

  it "creates the item by name in the given category, reusing a same-named one", :aggregate_failures do
    fresh = build_form({ amount: "3", date: "2026-09-05", item_id: "", item_attributes: { name: "Milk" } }, category_id: groceries.id)
    expect(fresh.save).to be(true)
    expect(fresh.entry.item).to have_attributes(name: "Milk", category: groceries)

    again = build_form({ amount: "4", date: "2026-09-06", item_id: "new", item_attributes: { name: "milk" } }, category_id: groceries.id)
    expect(again.save).to be(true)
    expect(again.entry.item).to eq(fresh.entry.item)
    expect(groceries.items.count).to eq(1)
  end

  it "lands income in the chosen account and spending always in main", :aggregate_failures do
    main
    pay = create(:item, category: salary, name: "Pay")
    income = build_form({ amount: "2000", date: "2026-09-05", item_id: pay.id, account_id: savings.id })
    expect(income.save).to be(true)
    expect(income.entry.account).to eq(savings)

    spend = build_form({ amount: "20", date: "2026-09-05", item_id: bread.id, account_id: savings.id })
    expect(spend.save).to be(true)
    expect(spend.entry.account).to be_nil
  end

  it "keeps a bad formula as typed so the model refuses it", :aggregate_failures do
    form = build_form({ amount: "abc", date: "2026-09-05", item_id: bread.id })

    expect(form.save).to be(false)
    expect(form.errors[:amount]).to be_present
  end

  it "edits an existing entry in place" do
    entry = create(:entry, item: bread, amount: 10)
    form = build_form({ amount: "15" }, entry: entry)

    expect(form.save).to be(true)
    expect(entry.reload.amount).to eq(15)
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/services/entry_form_spec.rb`
Expected: `uninitialized constant EntryForm`.

- [ ] **Step 3: The form**

```ruby
# frozen_string_literal: true

# The entry form's params onto an entry: a formula in the amount, an item by id or by a new name
# in the given category, and the landing account, which only income keeps.
class EntryForm
  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/i

  attr_reader :user, :entry

  def initialize(user, entry, params, category_id: nil)
    @user = user
    @entry = entry
    @params = params.to_h.deep_symbolize_keys
    @category_id = category_id
    apply
  end

  def save = entry.save

  delegate :errors, to: :entry

  private

  def apply
    entry.amount = evaluate(@params[:amount]) if @params.key?(:amount)
    entry.date = @params[:date] if @params.key?(:date)
    entry.description = @params[:description] if @params.key?(:description)
    assign_item
    assign_account
  end

  def assign_item
    id = @params[:item_id].to_s
    name = @params.dig(:item_attributes, :name).to_s.strip
    if id.match?(UUID)
      entry.item = user.items.find(id)
    elsif name.present? && @category_id.present?
      category = user.categories.find(@category_id)
      entry.item = category.items.find_by("LOWER(name) = ?", name.downcase) || category.items.build(name: name)
    end
  end

  def assign_account
    return unless @params.key?(:account_id)

    id = @params[:account_id].presence
    account = id && user.accounts.find(id)
    entry.account = entry.item&.category&.income? ? account : nil
  end

  def evaluate(raw)
    return raw if raw.blank?

    result = Dentaku::Calculator.new.evaluate(raw.to_s)
    result.is_a?(Numeric) ? result : raw
  end
end
```

Remove `accepts_nested_attributes_for :item` from `app/models/entry.rb`.

- [ ] **Step 4: Run the spec and the entry spec**

Run: `bundle exec rspec spec/services/entry_form_spec.rb spec/models/entry_spec.rb`
Expected: green.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A app/services/entry_form.rb app/models/entry.rb spec/services/entry_form_spec.rb
git add -A
git commit -m "services: EntryForm"
```

### Task 16: CadenceChange

**Files:**
- Create: `app/services/cadence_change.rb`, `spec/services/cadence_change_spec.rb`

**Interfaces:**
- Produces: `CadenceChange.new(user:, declaration:)` where `declaration` is a Hash or permitted params with `period_cadence` and `period_anchor_date`; `#offered?`, `#changing?`, `#lines` (each `rule`, `amount`, `scaled_amount`), `#apply(scale: nil)`, `#scaled?`, `#periods_per_year`, `#periods_per_year_before`.

- [ ] **Step 1: Spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CadenceChange do
  let(:user) { create(:user, :biweekly) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let!(:allowance) { create(:rule, :rate, amount: 200, category: groceries) }
  let!(:bill) { create(:rule, :one_off, amount: 500, category: create(:category, user: user)) }

  def change(cadence:, anchor: "2026-09-04") = described_class.new(user: user, declaration: { period_cadence: cadence, period_anchor_date: anchor })

  it "offers scaling when the cadence changes and per-period rules exist", :aggregate_failures do
    offered = change(cadence: "monthly")

    expect(offered).to be_changing
    expect(offered).to be_offered
    expect(offered.lines.map(&:rule)).to eq([allowance])
    expect(offered.lines.first.scaled_amount).to eq(433.33) # 200 × 26 / 12
    expect(change(cadence: "biweekly")).not_to be_offered
  end

  it "applies the declaration and, when asked, the scaling", :aggregate_failures do
    expect(change(cadence: "monthly").apply(scale: true)).to be(true)
    expect(user.reload).to be_period_monthly
    expect(allowance.reload.amount).to eq(433.33)
    expect(bill.reload.amount).to eq(500)
  end

  it "applies the declaration alone when scaling is declined", :aggregate_failures do
    applied = change(cadence: "weekly")

    expect(applied.apply(scale: false)).to be(true)
    expect(applied).not_to be_scaled
    expect(allowance.reload.amount).to eq(200)
  end

  it "saves nothing when the declaration is invalid", :aggregate_failures do
    invalid = change(cadence: "monthly", anchor: "")

    expect(invalid).not_to be_offered
    expect(invalid.apply(scale: true)).to be(false)
    expect(user.reload).to be_period_biweekly
    expect(allowance.reload.amount).to eq(200)
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/services/cadence_change_spec.rb`
Expected: `uninitialized constant CadenceChange`.

- [ ] **Step 3: The service**

```ruby
# frozen_string_literal: true

# A change of period cadence. Per-period rules may be scaled so they cost the same per year.
class CadenceChange
  Line = Data.define(:rule, :amount, :scaled_amount)

  SMALLEST_RATE = BigDecimal("0.01")

  attr_reader :user, :declaration, :periods_per_year_before

  def initialize(user:, declaration:)
    @user = user
    @declaration = declaration.to_h.symbolize_keys
    @periods_per_year_before = user.periods_per_year
  end

  def offered? = changing? && acceptable? && lines.any?
  def changing? = cadence.present? && user.period_cadence.present? && cadence != user.period_cadence
  def cadence = declaration[:period_cadence].presence
  def periods_per_year = User::PERIODS_PER_YEAR.fetch(cadence, 12)

  def lines
    @lines ||= user.rules.per_period.includes(:category).map do |rule|
      Line.new(rule: rule, amount: rule.amount.to_d, scaled_amount: scaled(rule.amount.to_d))
    end
  end

  def apply(scale: nil)
    scaling = scale && offered?
    saved = false
    ActiveRecord::Base.transaction do
      saved = user.update(declaration)
      raise ActiveRecord::Rollback unless saved

      lines.each { |line| line.rule.update!(amount: line.scaled_amount) } if scaling
    end
    @scaled = scaling && saved
    saved
  end

  def scaled? = @scaled.present?

  private

  def acceptable?
    probe = User.find(user.id)
    probe.assign_attributes(declaration)
    probe.valid?
  end

  def scaled(amount) = [(amount * periods_per_year_before / periods_per_year).round(2), SMALLEST_RATE].max
end
```

- [ ] **Step 4: Run the whole gate**

Run: `bundle exec rspec spec/models spec/services spec/helpers spec/migrations spec/system/settings spec/system/smoke_spec.rb`
Expected: green.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A app/services/cadence_change.rb spec/services/cadence_change_spec.rb
git add -A
git commit -m "services: CadenceChange"
```

### Squash checkpoint E

```bash
git reset --soft "$(cat /tmp/group_e_base)"
git commit -m "forms: RuleForm, AdjustmentForm, EntryForm, CadenceChange

Every write a screen makes, behind an object the controllers can hand params to."
```

---

## Group F: the production dump

### Task 17: Run the migrations against the 2026-09-09 dump

**Files:**
- Modify: this plan (append the receipts under "Receipts" below)

**Interfaces:**
- Consumes: the dump at `/Users/henrywu/code/SeriouslyBroke-Rails/2026-09-09T14_43Z.dir.tar.gz`, a `pg_dump` directory-format archive of the production database (`seriouslybroke`, 4 users, 3306 entries, migration version 20260630143158).

- [ ] **Step 1: Restore the dump into the development database**

The development database currently holds whatever the reference branch's server left. If that server is still running (it was started on port 3001 as PID 55967), stop it first: `kill 55967`.

```bash
mkdir -p /tmp/dump && tar -xzf /Users/henrywu/code/SeriouslyBroke-Rails/2026-09-09T14_43Z.dir.tar.gz -C /tmp/dump
export PGHOST=127.0.0.1 PGUSER=postgres PGPASSWORD=postgres
dropdb seriously_broke_development && createdb seriously_broke_development
pg_restore --no-owner --no-privileges -d seriously_broke_development "/tmp/dump/2026-09-09T14:43Z/seriouslybroke"
bin/rails db:environment:set RAILS_ENV=development
psql seriously_broke_development -tc "select count(*) from users; select count(*) from entries; select count(*) from savings_pools;"
```

Expected: 4 users, 3306 entries, 18 savings pools.

- [ ] **Step 2: Migrate and capture the receipts**

```bash
bin/rails db:migrate 2>&1 | tee /tmp/migrate.log | grep -E "^== |@"
```

Expected: both migrations run, and four receipt lines like `mingguan0809@gmail.com: 10 accounts, 57 transfers from 57 savings entries, 5 rules`. If a `Refused` error appears instead, the run rolled back: the message names the user and the assertion, and the fix belongs in the migration, not in the data.

- [ ] **Step 3: Verify through the app's own ledgers**

```bash
bin/rails runner '
User.find_each do |u|
  l = AccountLedger.new(u)
  puts [u.email, u.accounts.count, l.pot.to_s("F"), l.total_money.to_s("F"), Rule.for_user(u).count, ClaimLedger.new(u).total_claims.to_s("F")].join(" | ")
end'
```

Expected: one line per user, no exceptions. For mingguan0809@gmail.com, `total_money` equals the sum of that user's income entries minus expense entries in the dump (the migration asserted it).

- [ ] **Step 4: Record the receipts and commit**

Append the four receipt lines and the runner's four lines under **Receipts** at the end of this plan, then:

```bash
git add docs/superpowers/plans/2026-09-09-accounts-and-rules-core.md
git commit -m "docs: receipts from migrating the 2026-09-09 production dump"
```

- [ ] **Step 5: Log in**

The restored users keep production password hashes. To use the app locally after the screens plan lands: `bin/rails runner 'User.find_each { |u| u.update_columns(encrypted_password: Devise::Encryptor.digest(User, "password123")) }'`.

---

## Receipts

Filled in by Task 17.

---

## Self-review

- Spec §2: every table and constraint is in Task 3 or Task 9's tightening; every model rule is in Tasks 4-8.
- Spec §3.1: Task 10. §3.2: Tasks 11-12 (the walk, due dates, standing ask). §3.3: Task 10's `typical_income`. §3.4: Task 16.
- Spec §4: `Account.open` Task 4; `EntryForm` Task 15; `RuleForm` Task 13; `AdjustmentForm` Task 14; `apply_fill_order` Task 6; `Item.merge` Task 6; `correct_balance` Task 10.
- Spec §7: Tasks 3, 9, 17.
- Spec §8: Task 1 (drivers, DatabaseCleaner, parallel, CI). The `CLAUDE.md` rewrite and `parallel_tests` in CI's documentation are in the screens plan's last task, as spec §9 commit 10 says.
- Spec §5's presenters and controllers, §6's screens, seeds and `CategoryStats` are the screens plan.
