# Savings and Claims Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add savings targets as the second claimant on checking, restructure the claim code so rules and savings are peers, and turn the Accounts page into the Savings page.

**Architecture:** A `SavingsTarget` row is a promise on an account (a fixed amount a period, or a share of an income item). `SavingsCalculator` walks the user's periods and returns the account's claim, the mirror of `ClaimCalculator` for a rule. `ClaimLedger` produces one `Claim` list from both, and every screen reads that list. Income always lands in checking; entries lose their account; adjustments become polymorphic over rule and account.

**Tech Stack:** Rails 8.1, PostgreSQL, Hotwire (Turbo + Stimulus), Tailwind, simple_form, RSpec + Capybara + FactoryBot.

**Spec:** `docs/superpowers/specs/2026-09-11-savings-and-claims-design.md`. The "what" is `docs/decisions.md`. Read both.

## Global Constraints

- Every migration is made with `bin/rails generate migration <Name>` and does one thing. The two September files (`20260910000000_accounts_and_rules_schema.rb`, `20260910000001_accounts_and_rules_data.rb`) are deleted; nothing has run in production.
- Money columns are Postgres `money` scale 2; dates are `date`; ids are UUIDs.
- One word for a source's per-period cost: `ask`. The sums are `budget` and `savings`. Held amounts are `budget_claim`, `savings_claim`, `claimed`. `free = pot − claimed`. The words `steady_ask`, `standing_ask`, `steady_need`, `rules_need`, `total_claims` do not survive.
- The verb for money between accounts is **transfer** on every screen.
- `Adjust` sits beside the claim figure on every screen.
- Give-way order: choice 0, usage 1, savings 2, bill 3.
- Savings bar colour: `--color-sage-800` (`#63612F`), via new utility classes `.bg-savings` and `.text-savings` in `app/assets/tailwind/custom.css`.
- Tests: logic in model/service/presenter specs; a system spec proves a page renders its figures once and each real interaction. Rack::Test unless `:js` is needed. No `sleep`. Run the touched directory with `bundle exec rspec spec/<dir>` and `bundle exec rubocop -A` before every commit; `bundle exec parallel_rspec spec` before the last commit.
- Commit messages follow the repo's `type/area: sentence` style and end with the attribution lines the session gives you.
- Never read the wall clock inside `travel_to`; fixtures use fixed dates. The biweekly grid anchored 2026-02-06 puts Sep 9 in Sep 4 – Sep 17; the two complete periods behind it are Aug 7 – Aug 20 and Aug 21 – Sep 3.

---

## File Structure

**Created**
- `db/migrate/*_create_accounts.rb` … `*_convert_pools_to_accounts.rb` (16 files, Task 1)
- `app/models/savings_target.rb` — one promise row on an account
- `app/services/savings_calculator.rb` — one account's claim and ask
- `app/services/account_form.rb` — name, balance, mode and target rows in one save
- `app/presenters/savings_presenter.rb`, `app/presenters/savings_line.rb` — the Savings page
- `app/controllers/savings_controller.rb`, `app/controllers/concerns/savings_page_state.rb`
- `app/views/savings/{show,_checking,_accounts,_row,_adjust,_drawer,_transfer_form,_add_account_form}.html.erb`
- `app/views/accounts/_target_fields.html.erb`
- `app/javascript/controllers/app/account/targets_controller.js`
- `spec/factories/savings_targets.rb`, `spec/models/savings_target_spec.rb`, `spec/services/savings_calculator_spec.rb`, `spec/services/account_form_spec.rb`, `spec/presenters/savings_presenter_spec.rb`, `spec/system/savings/{index,transfer,adjust}_spec.rb`, `spec/system/accounts/edit_spec.rb`, `spec/requests/savings_spec.rb`

**Modified**
- Models: `account.rb`, `adjustment.rb`, `rule.rb`, `item.rb`, `entry.rb`, `category.rb`, `user.rb`
- Services: `income_measure.rb`, `account_ledger.rb`, `claim_calculator.rb`, `claim_ledger.rb`, `adjustment_form.rb`, `entry_form.rb`, `sacrifice_cuts.rb`
- Presenters: `home_presenter.rb`, `budget_page_presenter.rb`, `sacrifice_presenter.rb`, `entry_impact_presenter.rb`, `rule_preview.rb`
- Controllers: `accounts_controller.rb`, `transfers_controller.rb`, `adjustments_controller.rb`, `sacrifices_controller.rb`, `entries_controller.rb`
- Views: `budget_page/_tiles`, `budget_page/_adjust`, `budget_page/_category_open`, `home/_money`, `home/_this_period`, `home/_shortfall`, `sacrifices/show`, `rules/_preview`, `entries/_form`, `shared/_sidebar`
- JS: `app/sacrifice/dial_controller.js`, `app/entry/form_controller.js`
- Helpers: `home_helper.rb`, `budget_page_helper.rb`, `sacrifices_helper.rb`
- `config/routes.rb`, `db/seeds.rb`, `app/assets/tailwind/custom.css`
- Docs: `docs/decisions.md`, `docs/coding-standards.md`, `CLAUDE.md`

**Deleted**
- `db/migrate/20260910000000_accounts_and_rules_schema.rb`, `db/migrate/20260910000001_accounts_and_rules_data.rb`
- `app/presenters/accounts_presenter.rb`, `app/views/accounts/{index,_spending,_set_aside,_row,_drawer,_move_money_form,_add_account_form}.html.erb`
- `spec/presenters/accounts_presenter_spec.rb`, `spec/system/accounts/index_spec.rb`, `spec/migrations/accounts_and_rules_data_spec.rb`

---

### Task 1: One clean set of migrations

**Files:**
- Delete: `db/migrate/20260910000000_accounts_and_rules_schema.rb`, `db/migrate/20260910000001_accounts_and_rules_data.rb`, `spec/migrations/accounts_and_rules_data_spec.rb`
- Create: sixteen migrations via the generator, in the order below
- Create: `spec/migrations/convert_pools_to_accounts_spec.rb` (the old data spec, renamed)
- Modify: `db/schema.rb` (regenerated by `db:migrate`)

**Interfaces:**
- Produces: tables `accounts` (+`keeps_extra`), `transfers`, `savings_targets`, `adjustments` (`source_type`, `source_id`), `rules`; `entries.date` as a date with no `account_id`.

- [ ] **Step 1: Read the two September migrations once, then delete them and their spec**

```bash
git rm db/migrate/20260910000000_accounts_and_rules_schema.rb db/migrate/20260910000001_accounts_and_rules_data.rb
git mv spec/migrations/accounts_and_rules_data_spec.rb spec/migrations/convert_pools_to_accounts_spec.rb
```

- [ ] **Step 2: Generate the sixteen migrations in this order** (one command each, so the timestamps ascend)

```bash
for name in CreateAccounts CreateTransfers AddMainAccountToUsers AddPeriodToUsers AddPriorityToCategories AddRegularToCategories AddUniqueNameToCategories AddDayToEntries AddPositiveAmountToEntries RenameBudgetsToRules AddItemToRules AddShapeToRules CreateAdjustments AddKeepsExtraToAccounts CreateSavingsTargets ConvertPoolsToAccounts; do
  bin/rails generate migration "$name"; sleep 1
done
```

(The `sleep 1` is the only sleep in this plan; it keeps generator timestamps distinct.)

- [ ] **Step 3: Fill each file's `change` with exactly this**

`*_create_accounts.rb`:
```ruby
class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.money :opening_balance, scale: 2, null: false, default: 0
      t.date :opened_on
      t.timestamps
    end
    add_index :accounts, "user_id, lower(name)", unique: true, name: "index_accounts_on_user_id_and_lower_name"
  end
end
```

`*_create_transfers.rb`:
```ruby
class CreateTransfers < ActiveRecord::Migration[8.1]
  def change
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
end
```

`*_add_main_account_to_users.rb`:
```ruby
class AddMainAccountToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :main_account, type: :uuid, foreign_key: { to_table: :accounts, on_delete: :nullify }
  end
end
```

`*_add_period_to_users.rb`:
```ruby
class AddPeriodToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :period_cadence, :integer
    add_column :users, :period_anchor_date, :date
  end
end
```

`*_add_priority_to_categories.rb`:
```ruby
class AddPriorityToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :priority, :integer, null: false, default: 0
    add_check_constraint :categories, "priority >= 0", name: "categories_priority_non_negative"
  end
end
```

`*_add_regular_to_categories.rb`:
```ruby
class AddRegularToCategories < ActiveRecord::Migration[8.1]
  def change
    add_column :categories, :regular, :boolean, null: false, default: true
  end
end
```

`*_add_unique_name_to_categories.rb`:
```ruby
class AddUniqueNameToCategories < ActiveRecord::Migration[8.1]
  def change
    add_index :categories, "user_id, lower(name)", unique: true, name: "index_categories_on_user_id_and_lower_name"
  end
end
```

`*_add_day_to_entries.rb` (nullable on purpose; the data migration fills it and renames it):
```ruby
class AddDayToEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :entries, :day, :date
  end
end
```

`*_add_positive_amount_to_entries.rb`:
```ruby
class AddPositiveAmountToEntries < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :entries, "amount > 0::money", name: "entries_positive_amount"
  end
end
```

`*_rename_budgets_to_rules.rb`:
```ruby
class RenameBudgetsToRules < ActiveRecord::Migration[8.1]
  def change
    rename_table :budgets, :rules
  end
end
```

`*_add_item_to_rules.rb`:
```ruby
class AddItemToRules < ActiveRecord::Migration[8.1]
  def change
    add_reference :rules, :item, type: :uuid, foreign_key: true, index: false
    add_index :rules, :item_id, unique: true, where: "item_id IS NOT NULL", name: "index_rules_on_item_id_unique"
    add_index :rules, :category_id, unique: true, where: "item_id IS NULL", name: "index_rules_one_item_less_per_category"
  end
end
```

`*_add_shape_to_rules.rb`:
```ruby
class AddShapeToRules < ActiveRecord::Migration[8.1]
  def change
    change_table :rules, bulk: true do |t|
      t.integer :rule_type, null: false, default: 1
      t.date :starts_on
      t.date :anchor_date
      t.integer :interval_months
      t.boolean :keeps_unspent, null: false, default: false
    end
    add_check_constraint :rules, "amount > 0::money", name: "rules_positive_amount"
    add_check_constraint :rules, "interval_months IS NULL OR interval_months > 0", name: "rules_positive_interval"
    add_check_constraint :rules, "NOT (keeps_unspent AND anchor_date IS NOT NULL)", name: "rules_keeping_never_dates"
    add_check_constraint :rules, "interval_months IS NULL OR anchor_date IS NOT NULL", name: "rules_interval_needs_a_date"
  end
end
```

`*_create_adjustments.rb` (polymorphic from the start):
```ruby
class CreateAdjustments < ActiveRecord::Migration[8.1]
  def change
    create_table :adjustments, id: :uuid do |t|
      t.string :source_type, null: false
      t.uuid :source_id, null: false
      t.money :amount, scale: 2, null: false
      t.date :date, null: false
      t.timestamps
    end
    add_index :adjustments, [:source_type, :source_id]
    add_index :adjustments, :date
    add_check_constraint :adjustments, "amount <> 0::money", name: "adjustments_non_zero_amount"
    add_check_constraint :adjustments, "source_type <> 'Account' OR amount < 0::money", name: "adjustments_accounts_only_reduce"
  end
end
```

`*_add_keeps_extra_to_accounts.rb`:
```ruby
class AddKeepsExtraToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :keeps_extra, :boolean, null: false, default: true
  end
end
```

`*_create_savings_targets.rb`:
```ruby
class CreateSavingsTargets < ActiveRecord::Migration[8.1]
  def change
    create_table :savings_targets, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :item, type: :uuid, foreign_key: true, index: false
      t.money :amount, scale: 2
      t.decimal :percent, precision: 5, scale: 2
      t.date :starts_on, null: false
      t.timestamps
    end
    add_index :savings_targets, :account_id, unique: true, where: "item_id IS NULL", name: "index_savings_targets_one_fixed_per_account"
    add_index :savings_targets, [:account_id, :item_id], unique: true, where: "item_id IS NOT NULL", name: "index_savings_targets_one_share_per_item"
    add_check_constraint :savings_targets,
                         "(item_id IS NULL AND amount IS NOT NULL AND percent IS NULL) OR (item_id IS NOT NULL AND percent IS NOT NULL AND amount IS NULL)",
                         name: "savings_targets_one_figure"
    add_check_constraint :savings_targets, "amount IS NULL OR amount > 0::money", name: "savings_targets_positive_amount"
    add_check_constraint :savings_targets, "percent IS NULL OR (percent > 0 AND percent <= 100)", name: "savings_targets_percent_range"
  end
end
```

`*_convert_pools_to_accounts.rb`: paste the whole body of the deleted `20260910000001_accounts_and_rules_data.rb` from git (`git show HEAD:db/migrate/20260910000001_accounts_and_rules_data.rb`) and make exactly these edits:
  - `class AccountsAndRulesData` → `class ConvertPoolsToAccounts`
  - In `down`, the line `change_column_null :rules, :starts_on, true` stays; everything else stays as it was. Nothing in it touches adjustments or `entries.account_id`, so nothing else changes.

- [ ] **Step 4: Rename the migration spec's target**

In `spec/migrations/convert_pools_to_accounts_spec.rb` replace the `require` line and the describe:
```ruby
require Rails.root.glob("db/migrate/*_convert_pools_to_accounts.rb").sole

# ...unchanged comment...
RSpec.describe ConvertPoolsToAccounts do
```

- [ ] **Step 5: Rebuild every database**

```bash
bin/rails db:drop db:create db:migrate
RAILS_ENV=test bin/rails db:drop db:create db:migrate
bundle exec rake parallel:drop parallel:create parallel:prepare
```
Expected: `db/schema.rb` regenerates with `savings_targets`, `accounts.keeps_extra`, `adjustments.source_type/source_id`, no `entries.account_id`, no `rules.prorated`, no `savings_pools`.

- [ ] **Step 6: Run the migration spec**

Run: `bundle exec rspec spec/migrations`
Expected: PASS (the examples plant main-shaped rows, run `down` then `up`).

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/schema.rb spec/migrations
git commit -m "chore/migrations: one generator-made migration per change, savings and polymorphic adjustments from the start"
```

Note: model specs will fail from here until Task 2 lands (`Adjustment` still says `belongs_to :rule`, `Entry` still names an account). That is expected; Tasks 2 and 3 restore green.

---

### Task 2: The models

**Files:**
- Create: `app/models/savings_target.rb`, `spec/models/savings_target_spec.rb`, `spec/factories/savings_targets.rb`
- Modify: `app/models/account.rb`, `app/models/adjustment.rb`, `app/models/rule.rb`, `app/models/item.rb`, `app/models/user.rb`, `spec/factories/adjustments.rb`, `spec/models/adjustment_spec.rb`, `spec/models/account_spec.rb`

**Interfaces:**
- Produces: `SavingsTarget#target?`, `#share?`, `#words`, `#ask(typical_income:)`; `Account#savings?`, `#keeps_extra?`, `has_many :savings_targets`, `has_many :adjustments, as: :source`; `Adjustment belongs_to :source, polymorphic`; `Rule has_many :adjustments, as: :source`; `Item has_many :savings_shares`; `User has_many :savings_targets, through: :accounts`.

- [ ] **Step 1: Write the target factory**

`spec/factories/savings_targets.rb`:
```ruby
# frozen_string_literal: true

FactoryBot.define do
  # A fixed $200 a period since the start of the year, on a fresh savings account. The :share
  # trait swaps that for 10% of a fresh income item of the same user.
  factory :savings_target do
    account { association :account, :savings }
    amount { 200 }
    percent { nil }
    item { nil }
    starts_on { Date.new(2026, 1, 1) }

    trait :share do
      amount { nil }
      percent { 10 }
      item { association :item, :income, user: account.user }
    end
  end
end
```

The accounts factory makes the first account main; a target on main is refused, so every target spec creates a checking account first. Add this to `spec/factories/accounts.rb` under the existing factory, inside the block:
```ruby
    trait :savings do
      before(:create) { |account| create(:account, user: account.user) if account.user.main_account_id.blank? }
    end
```

- [ ] **Step 2: Write the failing model spec**

`spec/models/savings_target_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SavingsTarget do
  let(:user) { create(:user) }
  let!(:checking) { create(:account, user: user, name: "Checking") }
  let(:emergency) { create(:account, user: user, name: "Emergency") }
  let(:paycheck) { create(:item, :income, user: user, name: "Paycheck") }

  it "is a fixed target when it names no item, and a share when it does", :aggregate_failures do
    fixed = create(:savings_target, account: emergency, amount: 200)
    share = create(:savings_target, :share, account: emergency, item: paycheck, percent: 10)

    expect(fixed).to be_target
    expect(fixed.words).to eq("$200.00 a period")
    expect(share).to be_share
    expect(share.words).to eq("10% of Paycheck")
  end

  it "keeps the one figure its item implies", :aggregate_failures do
    fixed = build(:savings_target, account: emergency, amount: 200, percent: 5)
    share = build(:savings_target, :share, account: emergency, item: paycheck, percent: 10, amount: 50)

    expect(fixed).to be_valid
    expect(fixed.percent).to be_nil
    expect(share).to be_valid
    expect(share.amount).to be_nil
    expect(build(:savings_target, account: emergency, amount: nil)).not_to be_valid
    expect(build(:savings_target, :share, account: emergency, item: paycheck, percent: nil)).not_to be_valid
  end

  it "refuses checking, another user's item, an expense item, and a percent past 100 across accounts", :aggregate_failures do
    expect(build(:savings_target, account: checking)).not_to be_valid
    expect(build(:savings_target, :share, account: emergency, item: create(:item, :income))).not_to be_valid
    expect(build(:savings_target, :share, account: emergency, item: create(:item, :expense, user: user))).not_to be_valid

    create(:savings_target, :share, account: emergency, item: paycheck, percent: 60)
    other = create(:account, user: user, name: "Brokerage")
    expect(build(:savings_target, :share, account: other, item: paycheck, percent: 40)).to be_valid
    expect(build(:savings_target, :share, account: other, item: paycheck, percent: 41)).not_to be_valid
  end

  it "allows one fixed row per account and one share per item per account", :aggregate_failures do
    create(:savings_target, account: emergency)
    create(:savings_target, :share, account: emergency, item: paycheck)

    expect(build(:savings_target, account: emergency)).not_to be_valid
    expect(build(:savings_target, :share, account: emergency, item: paycheck)).not_to be_valid
  end

  it "asks its amount, or its percent of the item's typical income", :aggregate_failures do
    expect(build(:savings_target, amount: 200).ask).to eq(200)
    expect(build(:savings_target, :share, percent: 10).ask(typical_income: 3_400)).to eq(340)
    expect(build(:savings_target, :share, percent: 10).ask(typical_income: nil)).to eq(0)
  end
end
```

- [ ] **Step 3: Run it to see it fail**

Run: `bundle exec rspec spec/models/savings_target_spec.rb`
Expected: FAIL, `uninitialized constant SavingsTarget`.

- [ ] **Step 4: Write the model**

`app/models/savings_target.rb`:
```ruby
# frozen_string_literal: true

# One promise that a savings account is owed money from checking: a fixed amount a period when it
# names no item, or a share of an income item's entries when it does. Each row counts from its
# own starts_on.
class SavingsTarget < ApplicationRecord
  belongs_to :account, touch: true
  belongs_to :item, optional: true

  before_validation :keep_one_figure

  validates :starts_on, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }, if: :target?
  validates :percent, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, if: :share?
  validates :account_id, uniqueness: { conditions: -> { where(item_id: nil) }, message: "already has a fixed target" }, if: :target?
  validates :item_id, uniqueness: { scope: :account_id, message: "already feeds this account" }, if: :share?
  validate :account_is_savings
  validate :item_is_the_users_income
  validate :item_is_not_over_shared

  delegate :user, to: :account

  scope :fixed, -> { where(item_id: nil) }
  scope :shares, -> { where.not(item_id: nil) }

  def target? = item_id.nil?
  def share? = !target?

  # What this row costs a period: its amount, or its percent of what the item typically brings in.
  def ask(typical_income: nil)
    return amount.to_d if target?

    (percent.to_d / 100 * typical_income.to_d).round(2)
  end

  def words
    return "#{ActiveSupport::NumberHelper.number_to_currency(amount)} a period" if target?

    "#{percent.to_d.to_s("F").sub(/\.0+\z/, "")}% of #{item.name}"
  end

  private

  def keep_one_figure
    target? ? self.percent = nil : self.amount = nil
  end

  def account_is_savings
    errors.add(:account, "checking never carries a savings target") if account&.main?
  end

  def item_is_the_users_income
    return if item.blank? || account.blank?

    errors.add(:item, "must be one of your income items") unless item.user_id == account.user_id && item.category.income?
  end

  def item_is_not_over_shared
    return if item.blank? || percent.blank?

    taken = SavingsTarget.shares.where(item_id: item_id).where.not(id: id).sum(:percent).to_d
    errors.add(:percent, "would take #{item.name} past 100% across your accounts") if taken + percent.to_d > 100
  end
end
```

- [ ] **Step 5: Wire the associations**

`app/models/account.rb`: add after `has_many :transfers_out ...` and remove `has_many :entries, dependent: :nullify`:
```ruby
  has_many :savings_targets, dependent: :destroy
  has_many :adjustments, as: :source, dependent: :destroy
  accepts_nested_attributes_for :savings_targets, allow_destroy: true, reject_if: :all_blank
```
and add after `def main? ...`:
```ruby
  def savings? = !main?

  def claim_calculator(today: user.today, **rows) = SavingsCalculator.new(self, today: today, **rows)
```
(`SavingsCalculator` arrives in Task 5; nothing calls this until then.)

`app/models/adjustment.rb`, whole file:
```ruby
# frozen_string_literal: true

# A signed delta on one claim source's accrual, dated inside a period it counts. The source is a
# rule or a savings account; an account only ever reduces, since with no ceiling saving more is
# just transferring more.
class Adjustment < ApplicationRecord
  belongs_to :source, polymorphic: true, touch: true

  validates :amount, presence: true, numericality: { other_than: 0 }
  validates :date, presence: true
  validate :accounts_only_reduce

  scope :dated_within, ->(range) { where(date: range) }
  scope :on_rules, ->(ids) { where(source_type: "Rule", source_id: ids) }
  scope :on_accounts, ->(ids) { where(source_type: "Account", source_id: ids) }

  delegate :user, to: :source

  def rule? = source_type == "Rule"
  def account? = source_type == "Account"

  private

  def accounts_only_reduce
    return unless account? && amount.to_d.positive?

    errors.add(:amount, "can only reduce what savings is owed")
  end
end
```

`app/models/rule.rb`: change `has_many :adjustments, dependent: :destroy` to
```ruby
  has_many :adjustments, as: :source, dependent: :destroy
```

`app/models/item.rb`: add after `has_one :rule, dependent: :destroy`:
```ruby
  has_many :savings_shares, class_name: "SavingsTarget", dependent: :destroy
```

`app/models/user.rb`: add after `has_many :rules, through: :categories`:
```ruby
  has_many :savings_targets, through: :accounts
```

`spec/factories/adjustments.rb`, whole file:
```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :adjustment do
    source { association :rule }
    amount { 100 }
    date { Date.current }

    trait :release do
      amount { -100 }
    end

    trait :on_account do
      source { association :account, :savings }
      amount { -50 }
    end
  end
end
```

- [ ] **Step 6: Update the adjustment and account specs**

In `spec/models/adjustment_spec.rb` replace every `rule:` keyword with `source:` (`create(:adjustment, rule: x)` → `create(:adjustment, source: x)`) and add:
```ruby
  it "lets an account only reduce", :aggregate_failures do
    account = create(:account, :savings)

    expect(build(:adjustment, source: account, amount: -50)).to be_valid
    expect(build(:adjustment, source: account, amount: 50)).not_to be_valid
  end
```

In `spec/models/account_spec.rb` add inside the top-level describe:
```ruby
  it "keeps extra by default and knows it is savings when it is not main", :aggregate_failures do
    checking = create(:account, user: user)
    savings = create(:account, user: user)

    expect(savings).to be_keeps_extra
    expect(savings).to be_savings
    expect(checking).not_to be_savings
  end
```

- [ ] **Step 7: Run the model specs**

Run: `bundle exec rspec spec/models/savings_target_spec.rb spec/models/adjustment_spec.rb spec/models/account_spec.rb spec/models/rule_spec.rb`
Expected: PASS. (`spec/models/entry_spec.rb` and `item_spec.rb` still fail on the account column; Task 3.)

- [ ] **Step 8: Commit**

```bash
bundle exec rubocop -A app/models spec/models spec/factories
git add app/models spec/models spec/factories
git commit -m "feat/savings: a savings target is a promise on an account, and an adjustment's source is a rule or an account"
```

---

### Task 3: Income always lands in checking

**Files:**
- Modify: `app/models/entry.rb`, `app/models/category.rb`, `app/models/item.rb`, `app/services/entry_form.rb`, `app/controllers/entries_controller.rb`, `app/views/entries/_form.html.erb`, `app/javascript/controllers/app/entry/form_controller.js`, `app/presenters/accounts_presenter.rb`, `app/views/accounts/_row.html.erb`, `app/views/accounts/_set_aside.html.erb`
- Test: `spec/models/entry_spec.rb`, `spec/models/item_spec.rb`, `spec/services/entry_form_spec.rb`, `spec/requests/entries_spec.rb`, `spec/system/entries/form_spec.rb`, `spec/presenters/accounts_presenter_spec.rb`, `spec/system/accounts/index_spec.rb`

**Interfaces:**
- Produces: `Entry` with no `account` association, no `landing_account`, no `latest_per_account`.

- [ ] **Step 1: Strip the model**

`app/models/entry.rb`: remove `belongs_to :account, optional: true`, the two `validate :account_is_the_users` / `:only_income_lands_in_an_account` lines, the `latest_per_account` scope, the `landing_account` method, and the two private methods. The private section becomes empty; delete `private` too.

`app/models/category.rb`: remove `after_update :entries_return_to_main_when_no_longer_income` and the private method of that name.

`app/models/item.rb`: in `merge`, replace
```ruby
    landed = target.category.income? ? {} : { account_id: nil }
```
with nothing, and `source.entries.update_all(landed.merge(item_id: target.id))` with `source.entries.update_all(item_id: target.id)`. In `move_to_category` delete the line `entries.update_all(account_id: nil) unless target_category.income?`.

- [ ] **Step 2: Strip the form, controller, view and JS**

`app/services/entry_form.rb`: delete `assign_account` and its call in `apply`; change the class comment's last clause to end at "in the given category."

`app/controllers/entries_controller.rb`: in `prefill_from` drop `account: @prefilled_from.account`; in `load_options` delete `@accounts = ...`; in `entry_params` drop `:account_id`.

`app/views/entries/_form.html.erb`: delete the whole `<div class="form-group mt-5" data-app--entry--form-target="account" ...>` block (the "Lands in" field and its hint).

`app/javascript/controllers/app/entry/form_controller.js`: remove `"account"` from `static targets`, and delete the method that toggles `this.accountTarget.hidden` (around line 70–76) together with any call to it. Keep the income-ids value if anything else reads it; if nothing does, delete the value declaration too.

- [ ] **Step 3: Drop the "income last landed" column from the old accounts page** (it is deleted in Task 8; this keeps the suite green until then)

`app/presenters/accounts_presenter.rb`: remove `income_words` from `Row`, from `row_for`, the `income_words` method and `latest_income`. `app/views/accounts/_row.html.erb`: delete the `<td ... data-account-income=...>` cell. `app/views/accounts/_set_aside.html.erb`: delete the `<th>Income last landed</th>` header and change the footer `colspan="2"` to `colspan="1"`.

- [ ] **Step 4: Fix the specs**

- `spec/models/entry_spec.rb`: delete every example about `account`, `landing_account` or `latest_per_account`.
- `spec/models/item_spec.rb`: delete assertions that entries lose or keep an `account_id` on merge/move.
- `spec/services/entry_form_spec.rb`, `spec/requests/entries_spec.rb`, `spec/system/entries/form_spec.rb`: delete examples and assertions that mention "Lands in", `account_id` or `account:`.
- `spec/presenters/accounts_presenter_spec.rb`: drop `account: ally` from the entry line and the `income_words` assertion.
- `spec/system/accounts/index_spec.rb`: drop any `data-account-income` assertion and any `account:` argument.

- [ ] **Step 5: Run the touched directories**

Run: `bundle exec rspec spec/models spec/services/entry_form_spec.rb spec/requests/entries_spec.rb spec/system/entries spec/presenters/accounts_presenter_spec.rb spec/system/accounts`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
bundle exec rubocop -A
git add -A app spec
git commit -m "feat/entries: income always lands in checking, so an entry has no account"
```

---

### Task 4: Typical income of one item

**Files:**
- Modify: `app/services/income_measure.rb`, `app/services/account_ledger.rb`
- Test: `spec/services/income_measure_spec.rb`, `spec/services/account_ledger_spec.rb`

**Interfaces:**
- Produces: `IncomeMeasure.new(user, category_ids: nil, item_ids: nil, today:)`; `AccountLedger#typical_income_of_item(item_id)` → `BigDecimal` (0 when nil), `#typical_income_of_items(ids)` → `{ id => BigDecimal }`.

- [ ] **Step 1: Failing specs**

Append to `spec/services/income_measure_spec.rb` (use the file's existing `user`/`today` lets; add if absent: `let(:user) { create(:user, :biweekly) }`, `let(:today) { Date.new(2026, 9, 9) }`):
```ruby
  it "measures one item over the same two periods" do
    salary = create(:category, :income, user: user)
    paycheck = create(:item, category: salary, name: "Paycheck")
    bonus = create(:item, category: salary, name: "Bonus")
    [Date.new(2026, 8, 7), Date.new(2026, 8, 25)].each do |on|
      create(:entry, item: paycheck, amount: 1_000, date: on)
      create(:entry, item: bonus, amount: 500, date: on)
    end

    expect(described_class.new(user, item_ids: [paycheck.id], today: today).typical).to eq(1_000)
    expect(described_class.new(user, category_ids: [salary.id], today: today).typical).to eq(1_500)
  end
```

Append to `spec/services/account_ledger_spec.rb`:
```ruby
  it "answers typical income per item, zero for an item with no history", :aggregate_failures do
    salary = create(:category, :income, user: user)
    paycheck = create(:item, category: salary)
    [Date.new(2026, 8, 7), Date.new(2026, 8, 25)].each { |on| create(:entry, item: paycheck, amount: 1_000, date: on) }
    quiet = create(:item, category: salary)

    expect(ledger.typical_income_of_item(paycheck.id)).to eq(1_000)
    expect(ledger.typical_income_of_items([paycheck.id, quiet.id])).to eq(paycheck.id => 1_000, quiet.id => 0)
  end
```
(If that spec's `ledger` is not built with `today: Date.new(2026, 9, 9)` and a `:biweekly` user, add such lets for this example.)

- [ ] **Step 2: Run to see them fail**

Run: `bundle exec rspec spec/services/income_measure_spec.rb spec/services/account_ledger_spec.rb`
Expected: FAIL on `unknown keyword: :item_ids` and `undefined method 'typical_income_of_item'`.

- [ ] **Step 3: Implement**

`app/services/income_measure.rb`:
```ruby
  attr_reader :user, :category_ids, :item_ids, :today

  def initialize(user, category_ids: nil, item_ids: nil, today: user.today)
    @user = user
    @category_ids = category_ids
    @item_ids = item_ids
    @today = today
  end
```
and replace `income_within`:
```ruby
  def income_within(range)
    scope = Entry.incomes.where(categories: { user_id: user.id }, date: range)
    scope = scope.where(categories: { id: category_ids }) if category_ids
    scope = scope.where(item_id: item_ids) if item_ids
    scope.sum(:amount).to_d
  end
```

`app/services/account_ledger.rb`: replace `balance_of` body and the income helpers so income is one sum into checking:
```ruby
  def balance_of(account)
    raise NotAnAccount, "#{account.name} belongs to another user" unless account.user_id == user.id

    account.opening_balance.to_d + income_into(account) - expenses_from(account) +
      transfers_in(account) - transfers_out(account)
  end

  # Typical income of one item over the same two complete periods, zero with no history.
  def typical_income_of_item(item_id)
    typical_by_item[item_id] ||= IncomeMeasure.new(user, item_ids: [item_id], today: today).typical.to_d
  end

  def typical_income_of_items(item_ids) = item_ids.index_with { |id| typical_income_of_item(id) }
```
private:
```ruby
  def income_into(account) = main?(account) ? total_income : 0.to_d
  def total_income = @total_income ||= user_entries(Entry.incomes).sum(:amount).to_d
  def typical_by_item = @typical_by_item ||= {}
```
Delete `income_by_account`.

- [ ] **Step 4: Run and commit**

Run: `bundle exec rspec spec/services/income_measure_spec.rb spec/services/account_ledger_spec.rb`
Expected: PASS.
```bash
bundle exec rubocop -A app/services spec/services
git add app/services spec/services
git commit -m "feat/income: typical income can be asked of one item, and income is one sum into checking"
```

---

### Task 5: SavingsCalculator

**Files:**
- Create: `app/services/savings_calculator.rb`, `spec/services/savings_calculator_spec.rb`

**Interfaces:**
- Consumes: `SavingsTarget#ask`, `Account#keeps_extra?`, `User#period_containing`, `AccountLedger#typical_income_of_item`.
- Produces: `SavingsCalculator.new(account, today:, targets: nil, transfers: nil, income: nil, adjustments: nil, typical_income_by_item: nil)` with `#claim`, `#ask`, `#owed_this_period`, `#accrued_this_period`, `#arrived_this_period`, `#countable_span`, `#periods`, `#start`. Rows: `transfers` and `adjustments` are `[[Date, BigDecimal]]`; `income` is `{ item_id => [[Date, BigDecimal]] }`.

- [ ] **Step 1: Failing spec**

`spec/services/savings_calculator_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

# Biweekly anchored Feb 6: Sep 9 sits in Sep 4 – Sep 17. A target since Aug 7 has walked three
# periods by Sep 9 (Aug 7–20, Aug 21–Sep 3, Sep 4–17).
RSpec.describe SavingsCalculator do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let!(:checking) { create(:account, user: user, name: "Checking", opening_balance: 5_000) }
  let(:account) { create(:account, user: user, name: "Emergency") }
  let(:paycheck) { create(:item, :income, user: user, name: "Paycheck") }

  def calculator(**rows) = described_class.new(account, today: today, **rows)

  def move(amount, on) = create(:transfer, from_account: checking, to_account: account, amount: amount, date: on)

  it "owes the fixed amount every period and nets what arrived, keeping extra", :aggregate_failures do
    create(:savings_target, account: account, amount: 200, starts_on: Date.new(2026, 8, 7))
    move(500, Date.new(2026, 8, 10))

    expect(calculator.periods.size).to eq(3)
    expect(calculator.owed_this_period).to eq(200)
    expect(calculator.claim).to eq(100)
    expect(calculator.countable_span).to eq(Date.new(2026, 8, 7)..today)
  end

  it "asks fresh every period when extra is not kept, and carries a shortfall", :aggregate_failures do
    account.update!(keeps_extra: false)
    create(:savings_target, account: account, amount: 200, starts_on: Date.new(2026, 8, 7))
    move(500, Date.new(2026, 8, 10))
    move(100, Date.new(2026, 8, 25))

    expect(calculator.claim).to eq(300)
  end

  it "owes a share of the item's entries in each period, from the share's own start", :aggregate_failures do
    create(:savings_target, :share, account: account, item: paycheck, percent: 10, starts_on: Date.new(2026, 8, 21))
    create(:entry, item: paycheck, amount: 2_000, date: Date.new(2026, 8, 10))
    create(:entry, item: paycheck, amount: 2_000, date: Date.new(2026, 8, 25))
    create(:entry, item: paycheck, amount: 3_000, date: Date.new(2026, 9, 8))

    expect(calculator.owed_this_period).to eq(300)
    expect(calculator.claim).to eq(500)
  end

  it "sums a fixed target and a share into one claim and one ask", :aggregate_failures do
    create(:savings_target, account: account, amount: 200, starts_on: Date.new(2026, 9, 4))
    create(:savings_target, :share, account: account, item: paycheck, percent: 10, starts_on: Date.new(2026, 9, 4))
    create(:entry, item: paycheck, amount: 1_000, date: Date.new(2026, 9, 8))

    expect(calculator.claim).to eq(300)
    expect(calculator(typical_income_by_item: { paycheck.id => 3_400.to_d }).ask).to eq(540)
  end

  it "applies an adjustment to the period it is dated in", :aggregate_failures do
    create(:savings_target, account: account, amount: 200, starts_on: Date.new(2026, 8, 21))
    create(:adjustment, source: account, amount: -150, date: Date.new(2026, 9, 6))

    expect(calculator.accrued_this_period).to eq(50)
    expect(calculator.claim).to eq(250)
  end

  it "claims nothing with no target or a start in the future, and ignores transfers before the start", :aggregate_failures do
    expect(calculator.claim).to eq(0)
    expect(calculator.countable_span).to eq(today...today)

    create(:savings_target, account: account, amount: 200, starts_on: Date.new(2026, 9, 20))
    expect(calculator.claim).to eq(0)

    account.savings_targets.delete_all
    create(:savings_target, account: account, amount: 200, starts_on: Date.new(2026, 9, 4))
    move(1_000, Date.new(2026, 8, 1))
    expect(calculator.claim).to eq(200)
  end

  it "takes its rows when handed them" do
    target = create(:savings_target, account: account, amount: 200, starts_on: Date.new(2026, 8, 21))
    handed = calculator(targets: [target], transfers: [[Date.new(2026, 8, 22), 150.to_d]], income: {}, adjustments: [])

    expect(handed.claim).to eq(250)
  end
end
```

- [ ] **Step 2: Run to see it fail**

Run: `bundle exec rspec spec/services/savings_calculator_spec.rb`
Expected: FAIL, `uninitialized constant SavingsCalculator`.

- [ ] **Step 3: Write the calculator**

`app/services/savings_calculator.rb`:
```ruby
# frozen_string_literal: true

# One savings account's claim on checking: what its targets owe over the periods since the earliest
# start, less what arrived by transfer, floored the way keeps_extra says. Rows are [day, amount]
# pairs (income keyed by item id), queried unless handed in.
class SavingsCalculator
  PERIOD_WALK_LIMIT = 520

  attr_reader :account, :today

  def initialize(account, today: account.user.today, targets: nil, transfers: nil, income: nil, adjustments: nil,
                 typical_income_by_item: nil)
    @account = account
    @today = today
    @targets = targets
    @transfers = transfers
    @income = income
    @adjustments = adjustments
    @typical_income_by_item = typical_income_by_item || {}
  end

  def targets = @targets ||= account.savings_targets.includes(:item).to_a
  def start = @start ||= targets.map(&:starts_on).min

  def claim
    return 0.to_d if periods.empty?

    account.keeps_extra? ? [accrued_total - arrived_total, 0.to_d].max : carried
  end

  # What the account costs a period: every target's ask, a share's against its item's typical income.
  def ask = targets.sum(0.to_d) { |target| target.ask(typical_income: typical_income_of(target.item_id)) }

  def owed_this_period = periods.empty? ? 0.to_d : owed_in(current_period)
  def accrued_this_period = periods.empty? ? 0.to_d : accrued_in(current_period)
  def arrived_this_period = periods.empty? ? 0.to_d : arrived_in(current_period)

  # The dates an adjustment may carry: from the earliest start to today.
  def countable_span
    return (today...today) if periods.empty?

    start..today
  end

  def periods
    @periods ||= start.nil? || start > today ? [] : walk_periods
  end

  private

  def user = account.user
  def current_period = @current_period ||= user.period_containing(today)

  def walk_periods
    visited = []
    cursor = user.period_containing(start)
    while cursor.first <= today && visited.size < PERIOD_WALK_LIMIT
      visited << cursor
      cursor = user.period_containing(cursor.last + 1)
    end
    visited
  end

  def accrued_total = periods.sum(0.to_d) { |period| accrued_in(period) }
  def arrived_total = periods.sum(0.to_d) { |period| arrived_in(period) }

  def carried
    periods.reduce(0.to_d) { |carry, period| [carry + accrued_in(period) - arrived_in(period), 0.to_d].max }
  end

  def owed_in(period)
    targets.sum(0.to_d) do |target|
      next 0.to_d if target.starts_on > period.last

      target.target? ? target.amount.to_d : share_owed(target, period)
    end
  end

  def share_owed(target, period)
    landed = sum_within(income_rows.fetch(target.item_id, []), period, from: target.starts_on)
    (landed * target.percent.to_d / 100).round(2)
  end

  def accrued_in(period) = owed_in(period) + sum_within(adjustment_rows, period)
  def arrived_in(period) = sum_within(transfer_rows, period, from: start)

  def sum_within(rows, period, from: nil)
    rows.sum(0.to_d) { |day, amount| period.cover?(day) && (from.nil? || day >= from) ? amount : 0.to_d }
  end

  def typical_income_of(item_id)
    return nil if item_id.nil?

    @typical_income_by_item[item_id] ||= AccountLedger.new(user, today: today).typical_income_of_item(item_id)
  end

  def transfer_rows = @transfer_rows ||= @transfers.nil? ? query_transfers : @transfers
  def income_rows = @income_rows ||= @income.nil? ? query_income : @income
  def adjustment_rows = @adjustment_rows ||= @adjustments.nil? ? query_adjustments : @adjustments

  def query_transfers
    return [] if start.nil?

    account.transfers_in.where(date: start..).pluck(:date, :amount).map { |day, amount| [day, amount.to_d] }
  end

  def query_income
    ids = targets.filter_map(&:item_id)
    return {} if ids.empty? || start.nil?

    Entry.where(item_id: ids, date: start..).pluck(:item_id, :date, :amount)
      .group_by(&:first)
      .transform_values { |rows| rows.map { |_id, day, amount| [day, amount.to_d] } }
  end

  def query_adjustments = account.adjustments.pluck(:date, :amount).map { |day, amount| [day, amount.to_d] }
end
```

- [ ] **Step 4: Run and commit**

Run: `bundle exec rspec spec/services/savings_calculator_spec.rb`
Expected: PASS.
```bash
bundle exec rubocop -A app/services/savings_calculator.rb spec/services/savings_calculator_spec.rb
git add app/services/savings_calculator.rb spec/services/savings_calculator_spec.rb
git commit -m "feat/savings: an account's claim walks its targets against what arrived"
```

---

### Task 6: One claim list, one vocabulary

**Files:**
- Modify: `app/services/claim_ledger.rb`, `app/services/claim_calculator.rb`, `app/models/rule.rb`, `app/presenters/home_presenter.rb`, `app/presenters/budget_page_presenter.rb`, `app/presenters/sacrifice_presenter.rb`, `app/presenters/entry_impact_presenter.rb`, `app/presenters/rule_preview.rb`, `app/presenters/accounts_presenter.rb`, `app/controllers/sacrifices_controller.rb`, `app/services/sacrifice_cuts.rb`, `app/views/rules/_preview.html.erb`, `app/views/home/_money.html.erb`, `app/views/home/_this_period.html.erb`, `app/views/budget_page/_tiles.html.erb`, `app/views/sacrifices/show.html.erb`
- Test: `spec/services/claim_ledger_spec.rb`, `spec/services/claim_calculator_spec.rb`, `spec/models/rule_spec.rb`, `spec/presenters/home_presenter_spec.rb`, `spec/presenters/budget_page_presenter_spec.rb`, `spec/presenters/accounts_presenter_spec.rb`, `spec/services/sacrifice_cuts_spec.rb`, `spec/system/budget_page/tiles_spec.rb`, `spec/seeds_spec.rb`

**Interfaces:**
- Produces: `ClaimLedger::Claim` (`source`, `name`, `kind`, `claim`, `ask`, `cuttable`, `#rank`, `#rule?`, `#account?`); `ClaimLedger#claims`, `#rule_claims`, `#account_claims`, `#savings_accounts`, `#budget`, `#savings`, `#budget_claim`, `#savings_claim`, `#claimed`, `#free`, `#calculator_for(source)`; `Rule#ask(today:)`; `ClaimCalculator#ask`. Presenters expose `budget`, `savings`, `claimed` where they had `rules_need`/`total_claims`. Behaviour is unchanged for a user with no targets.

- [ ] **Step 1: Failing ledger spec**

Replace the first example of `spec/services/claim_ledger_spec.rb` with these two, and change `total_claims` to `claimed` anywhere else in the file:
```ruby
  it "hands every rule a calculator fed from batched rows and agrees with the calculators", :aggregate_failures do
    bread_rule, whole_rule = seed_grocery_rules

    expect(ledger.rules).to contain_exactly(bread_rule, whole_rule)
    expect(ledger.claim_of(bread_rule)).to eq(70).and eq(ClaimCalculator.new(bread_rule, today: today).claim)
    expect(ledger.claim_of(whole_rule)).to eq(150).and eq(ClaimCalculator.new(whole_rule, today: today).claim)
    expect(ledger.claim_of_category(groceries)).to eq(220)
    expect(ledger.budget_claim).to eq(220)
    expect(ledger.claimed).to eq(220)
    expect(ledger.pot).to eq(870)
    expect(ledger.free).to eq(650)
    expect(ledger.budget).to eq(160)
  end

  it "lists savings claims beside rule claims, in give-way order, and sums both", :aggregate_failures do
    bread_rule, whole_rule = seed_grocery_rules
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
    create(:rule, :rate, :bill, amount: 50, category: create(:category, user: user, name: "Rent"), starts_on: Date.new(2026, 1, 1))

    expect(ledger.savings_accounts).to eq([emergency])
    expect(ledger.claims.map { |claim| [claim.name, claim.kind, claim.claim] })
      .to eq([["Groceries", :usage, 150], ["Bread", :usage, 70], ["Emergency", :savings, 200], ["Rent", :bill, 50]])
    expect(ledger.savings).to eq(200)
    expect(ledger.savings_claim).to eq(200)
    expect(ledger.claimed).to eq(470)
    expect(ledger.free).to eq(400)
    expect(ledger.calculator_for(emergency)).to be_a(SavingsCalculator)
    expect(ledger.claims.find(&:account?).cuttable).to be(true)
    expect(ledger.claims.find { |c| c.name == "Rent" }.cuttable).to be(true)
  end
```
The whole-category rule is named by its category ("Groceries"): Milk's spending lands on it, but a claim's name is the rule's item or, failing that, its category. Within one kind the larger claim comes first.

Change the query-count example's bound from `5` to `8`.

- [ ] **Step 2: Run to see it fail**

Run: `bundle exec rspec spec/services/claim_ledger_spec.rb`
Expected: FAIL on `undefined method 'budget_claim'`.

- [ ] **Step 3: Rewrite the ledger**

`app/services/claim_ledger.rb`:
```ruby
# frozen_string_literal: true

# Every claim on checking for one user, fed in a fixed number of queries: each rule's lane spending
# and adjustments, and each savings account's targets, transfers in, share income and adjustments.
class ClaimLedger
  class UnknownSource < StandardError; end

  KIND_RANK = { choice: 0, usage: 1, savings: 2, bill: 3 }.freeze

  # One claim as every screen reads it. `source` is a Rule or an Account.
  Claim = Data.define(:source, :name, :kind, :claim, :ask, :cuttable) do
    def rank = KIND_RANK.fetch(kind)
    def rule? = source.is_a?(Rule)
    def account? = source.is_a?(Account)
    def cuttable? = cuttable
  end

  attr_reader :user, :today

  def initialize(user, today: user.today)
    @user = user
    @today = today
  end

  def rules = @rules ||= user.rules.includes(:item, category: :user).to_a

  # Every non-main account carrying a target, with its targets loaded.
  def savings_accounts
    @savings_accounts ||= user.accounts.where(id: SavingsTarget.select(:account_id))
      .where.not(id: user.main_account_id).includes(savings_targets: :item).order(:name).to_a
  end

  def claim_of(rule) = calculator_for(rule).claim
  def claim_of_category(category) = rules_of(category).sum(0.to_d) { |rule| claim_of(rule) }
  def rules_of(category) = rules_by_category.fetch(category.id, [])
  def rules_by_category = @rules_by_category ||= rules.group_by(&:category_id)

  def calculator_for(source)
    calculators.fetch(source) { raise UnknownSource, "#{source.class} #{source.id} is not one of #{user.email}'s claim sources" }
  end

  def claims = @claims ||= (rule_claims + account_claims).sort_by { |claim| give_way_key(claim) }
  def rule_claims = @rule_claims ||= rules.map { |rule| rule_claim(rule) }
  def account_claims = @account_claims ||= savings_accounts.map { |account| account_claim(account) }

  def budget = @budget ||= rule_claims.sum(0.to_d, &:ask)
  def savings = @savings ||= account_claims.sum(0.to_d, &:ask)
  def budget_claim = @budget_claim ||= rule_claims.sum(0.to_d, &:claim)
  def savings_claim = @savings_claim ||= account_claims.sum(0.to_d, &:claim)
  def claimed = budget_claim + savings_claim
  def free = pot - claimed

  delegate :total_money, :pot, to: :account_ledger
  def account_ledger = @account_ledger ||= AccountLedger.new(user, today: today)

  private

  def rule_claim(rule)
    calculator = calculator_for(rule)
    Claim.new(source: rule, name: rule.item&.name || rule.category.name, kind: rule.rule_type.to_sym,
              claim: calculator.claim, ask: calculator.ask, cuttable: rule.cadence != :every_n)
  end

  def account_claim(account)
    calculator = calculator_for(account)
    Claim.new(source: account, name: account.name, kind: :savings, claim: calculator.claim, ask: calculator.ask, cuttable: true)
  end

  # Kind first; then, among rules, the category lowest in the fill order gives way first.
  def give_way_key(claim)
    [claim.rank, claim.rule? ? -claim.source.category.priority : 0, -claim.claim, claim.name]
  end

  def calculators = @calculators ||= rule_calculators.merge(account_calculators)

  def rule_calculators
    rules.index_with do |rule|
      ClaimCalculator.new(rule, today: today, spending: spending_for(rule), adjustments: rule_adjustments_for(rule))
    end
  end

  def account_calculators
    savings_accounts.index_with do |account|
      SavingsCalculator.new(
        account,
        today: today,
        targets: account.savings_targets.to_a,
        transfers: rows_of(transfer_rows, account.id),
        income: share_income_rows,
        adjustments: rows_of(account_adjustment_rows, account.id),
        typical_income_by_item: typical_income_by_item
      )
    end
  end

  def rows_of(grouped, key) = Array(grouped[key]).map { |_key, day, amount| [day, amount.to_d] }

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

  def rule_adjustments_for(rule) = rows_of(rule_adjustment_rows, rule.id)

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

  def rule_adjustment_rows
    @rule_adjustment_rows ||= begin
      ids = rules.map(&:id)
      ids.empty? ? {} : Adjustment.on_rules(ids).dated_within(window_start..).pluck(:source_id, :date, :amount).group_by(&:first)
    end
  end

  # Savings rows. Every account's walk starts at its own earliest target; one query from the
  # earliest of those covers them all, and each calculator ignores what precedes its own start.
  def savings_start = @savings_start ||= savings_accounts.flat_map(&:savings_targets).map(&:starts_on).min

  def transfer_rows
    @transfer_rows ||= begin
      ids = savings_accounts.map(&:id)
      ids.empty? ? {} : Transfer.where(to_account_id: ids, date: savings_start..).pluck(:to_account_id, :date, :amount).group_by(&:first)
    end
  end

  def share_item_ids = @share_item_ids ||= savings_accounts.flat_map(&:savings_targets).filter_map(&:item_id).uniq

  def share_income_rows
    @share_income_rows ||= if share_item_ids.empty?
                             {}
                           else
                             Entry.where(item_id: share_item_ids, date: savings_start..).pluck(:item_id, :date, :amount)
                               .group_by(&:first).transform_values { |rows| rows.map { |_id, day, amount| [day, amount.to_d] } }
                           end
  end

  def account_adjustment_rows
    @account_adjustment_rows ||= begin
      ids = savings_accounts.map(&:id)
      ids.empty? ? {} : Adjustment.on_accounts(ids).pluck(:source_id, :date, :amount).group_by(&:first)
    end
  end

  def typical_income_by_item = @typical_income_by_item ||= account_ledger.typical_income_of_items(share_item_ids)
end
```

- [ ] **Step 4: One word, ask**

`app/models/rule.rb`: delete `self.steady_need` entirely; rename `steady_ask` to `ask` (the body's `claim_calculator(today: today).standing_ask` becomes `.ask`).

`app/services/claim_calculator.rb`: rename `standing_ask` to `ask`; its last line `rule.steady_ask(today: today)` becomes `rule.ask(today: today)`.

`app/presenters/rule_preview.rb`: `delegate :ask, :periods_left, :built_up, to: :calculator`. `app/views/rules/_preview.html.erb` line 24: `preview.ask`.

`app/presenters/entry_impact_presenter.rb` line 76: `def steady_claim = calculators.sum(0.to_d, &:ask)`.

`app/services/sacrifice_cuts.rb`: `rule.steady_ask(today: today)` → `rule.ask(today: today)`.

`app/presenters/budget_page_presenter.rb`: replace `rules_need` with `budget`, backed by the ledger:
```ruby
  def budget = claim_ledger.budget
```
and in `tiles`, `need: budget`; in `type_overview` `.standing_ask` → `.ask`. `leftover = typical_income && (typical_income - budget)`; `underwater? = ... budget > typical_income`. (Task 10 adds savings to these.)

`app/presenters/home_presenter.rb`: `delegate :claimed, :budget, to: :claim_ledger`; delete `def rules_need ...` and `delegate :total_claims`; every `total_claims` → `claimed`; `rules_need > income` → `budget > income`.

`app/presenters/sacrifice_presenter.rb`: `def budget = ledger.budget` replacing `rules_need`; `gap = budget - typical_income.to_d`; `claim: rule.ask(today: today)`.

`app/controllers/sacrifices_controller.rb`: `fresh.rules_need` → `fresh.budget`.

`app/presenters/accounts_presenter.rb`: `def claimed = home.claimed`.

Views: `app/views/home/_money.html.erb` and `_this_period.html.erb`: `presenter.total_claims` → `presenter.claimed`. `app/views/budget_page/_tiles.html.erb`: unchanged (reads `tiles.need`; Task 10 reshapes it). `app/views/sacrifices/show.html.erb`: `@presenter.rules_need` → `@presenter.budget`.

- [ ] **Step 5: Update the specs that spell the old names**

```bash
grep -rln "rules_need\|total_claims\|steady_ask\|standing_ask\|steady_need" spec app
```
In each: `rules_need` → `budget`, `total_claims` → `claimed`, `steady_ask`/`standing_ask` → `ask`, `Rule.steady_need(user, today: today)` → `ClaimLedger.new(user, today: today).budget`. Expected list: `spec/models/rule_spec.rb`, `spec/presenters/accounts_presenter_spec.rb`, `spec/presenters/budget_page_presenter_spec.rb`, `spec/presenters/home_presenter_spec.rb`, `spec/seeds_spec.rb`, `spec/services/claim_calculator_spec.rb`, `spec/services/sacrifice_cuts_spec.rb`, `spec/system/budget_page/tiles_spec.rb`. Run the grep again afterwards; it must print nothing.

- [ ] **Step 6: Run and commit**

Run: `bundle exec rspec spec/services spec/models spec/presenters spec/system/budget_page/tiles_spec.rb spec/system/sacrifices spec/system/home spec/seeds_spec.rb`
Expected: PASS.
```bash
bundle exec rubocop -A
git add -A app spec
git commit -m "refactor/claims: one claim list for rules and savings, and one word for what a source asks"
```

---

### Task 7: Forms on a source

**Files:**
- Create: `app/services/account_form.rb`, `spec/services/account_form_spec.rb`
- Modify: `app/services/adjustment_form.rb`, `app/controllers/adjustments_controller.rb`, `app/controllers/accounts_controller.rb`, `app/models/account.rb`, `app/views/budget_page/_adjust.html.erb`
- Test: `spec/services/adjustment_form_spec.rb`, `spec/requests/adjustments_spec.rb`, `spec/models/account_spec.rb`

**Interfaces:**
- Produces: `AccountForm.new(account, params)#save` → bool, `#account`, `#errors`; `AdjustmentForm.new(source:, params:, name:, today:)` with `#savings?`; `AdjustmentsController` reads `source_type` + `source_id`; `Account#revise` is gone (`Account#correct_balance` stays).

- [ ] **Step 1: Failing account form spec**

`spec/services/account_form_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountForm do
  let(:user) { create(:user, :biweekly) }
  let!(:checking) { create(:account, user: user, name: "Checking", opening_balance: 1_000) }
  let(:emergency) { create(:account, user: user, name: "Emergency", opening_balance: 500) }
  let(:paycheck) { create(:item, :income, user: user, name: "Paycheck") }

  def form(account, params) = described_class.new(account, params)

  it "renames, corrects the balance, sets the mode and writes target rows together", :aggregate_failures do
    saved = form(emergency, {
      name: "Emergency fund", balance: "650", keeps_extra: "0",
      savings_targets_attributes: {
        "0" => { item_id: "", amount: "200", starts_on: "2026-09-04" },
        "1" => { item_id: paycheck.id, percent: "10", starts_on: "2026-09-04" }
      }
    }).save

    expect(saved).to be(true)
    emergency.reload
    expect(emergency.name).to eq("Emergency fund")
    expect(emergency.balance).to eq(650)
    expect(emergency).not_to be_keeps_extra
    expect(emergency.savings_targets.map(&:words)).to contain_exactly("$200.00 a period", "10% of Paycheck")
  end

  it "removes a row marked for destruction" do
    target = create(:savings_target, account: emergency)

    form(emergency, { savings_targets_attributes: { "0" => { id: target.id, _destroy: "1" } } }).save

    expect(emergency.savings_targets.reload).to be_empty
  end

  it "writes nothing when a row is refused", :aggregate_failures do
    saved = form(emergency, {
      name: "Renamed",
      savings_targets_attributes: { "0" => { item_id: paycheck.id, percent: "150", starts_on: "2026-09-04" } }
    }).save

    expect(saved).to be(false)
    expect(emergency.reload.name).to eq("Emergency")
    expect(emergency.errors.full_messages.join).to include("100%")
  end

  it "refuses a balance that is not a number without renaming", :aggregate_failures do
    saved = form(emergency, { name: "Renamed", balance: "abc" }).save

    expect(saved).to be(false)
    expect(emergency.reload.name).to eq("Emergency")
  end
end
```

- [ ] **Step 2: Run to see it fail**

Run: `bundle exec rspec spec/services/account_form_spec.rb`
Expected: FAIL, `uninitialized constant AccountForm`.

- [ ] **Step 3: Write the form and retire `Account#revise`**

`app/services/account_form.rb`:
```ruby
# frozen_string_literal: true

# The account form's params onto an account: name, mode, target rows and a balance correction, all
# landing together or not at all. A refused figure costs no rename.
class AccountForm
  attr_reader :account

  def initialize(account, params)
    @account = account
    @params = params.to_h.deep_symbolize_keys
  end

  delegate :errors, to: :account

  def save
    assign
    return false unless balance.blank? || numeric?(balance)

    Account.transaction do
      next false unless account.save
      next true if balance.blank?
      next true if account.correct_balance(balance)

      raise ActiveRecord::Rollback
    end || false
  end

  private

  def balance = @params[:balance]

  def assign
    account.name = @params[:name] if @params.key?(:name)
    account.keeps_extra = @params[:keeps_extra] if @params.key?(:keeps_extra)
    account.savings_targets_attributes = @params[:savings_targets_attributes] if @params.key?(:savings_targets_attributes)
  end

  def numeric?(typed)
    return true if BigDecimal(typed.to_s, exception: false)

    account.errors.add(:opening_balance, "is not a number")
    false
  end
end
```

`app/models/account.rb`: delete `revise` and the private `numeric?`; keep `correct_balance`. In `spec/models/account_spec.rb` delete the `describe "#revise"` block (its cases now live in the form spec).

`app/controllers/accounts_controller.rb` `update`:
```ruby
  def update
    if AccountForm.new(@account, account_params).save
      redirect_to accounts_path, notice: "#{@account.name} updated."
    else
      render :edit, status: :unprocessable_content
    end
  end
```
and `account_params`:
```ruby
  def account_params
    params.expect(account: [:name, :balance, :keeps_extra, { savings_targets_attributes: [[:id, :item_id, :amount, :percent, :starts_on, :_destroy]] }])
  end
```
(`accounts_path` becomes `savings_path` in Task 8.)

- [ ] **Step 4: Failing adjustment form spec additions**

In `spec/services/adjustment_form_spec.rb` change `form` to `described_class.new(source: rule, params: params, name: "Groceries", today: today)` and add:
```ruby
  describe "on a savings account" do
    let!(:checking) { create(:account, user: user, name: "Checking") }
    let(:emergency) { create(:account, user: user, name: "Emergency") }

    before { create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 8, 21)) }

    def savings_form(params) = described_class.new(source: emergency, params: params, name: "Emergency", today: today)

    it "reduces and skips, always negative", :aggregate_failures do
      down = savings_form({ amount: "50", amount_sign: "-1" })
      expect(down.save).to be(true)
      expect(down.adjustment).to have_attributes(source: emergency, amount: -50, date: today)

      skip = savings_form({ skip: "1" })
      expect(skip.save).to be(true)
      expect(skip.adjustment.amount).to eq(-150)
    end

    it "refuses a top-up and a date before the first start", :aggregate_failures do
      up = savings_form({ amount: "50", amount_sign: "1" })
      expect(up.save).to be(false)
      expect(up.error_sentence).to eq("Emergency can take more any time — there's nothing to top up.")

      early = savings_form({ amount: "50", amount_sign: "-1", date: "2026-08-01" })
      expect(early.save).to be(false)
      expect(early.error_sentence).to eq("Emergency counts from when its first target started, up to today — pick a date between Aug 21 and Sep 9.")
    end
  end
```

- [ ] **Step 5: Rewrite the adjustment form**

`app/services/adjustment_form.rb`:
```ruby
# frozen_string_literal: true

# Writes one adjustment on a claim source — a rule or a savings account — from its adjust panel: a
# signed amount on a date, or a skip, which is minus whatever accrued this period. Dates outside
# what the source counts are refused; an account only ever reduces.
class AdjustmentForm
  DAY = "%b %-d"

  attr_reader :source, :name, :today, :calculator, :adjustment

  def initialize(source:, params:, name:, today: source.user.today)
    @source = source
    @params = params
    @name = name
    @today = today
    @calculator = source.claim_calculator(today: today)
    @adjustment = source.adjustments.new(amount: amount, date: chosen_date)
  end

  def save
    return false unless acceptable?

    adjustment.save
  end

  def error_sentence = adjustment.errors.full_messages.to_sentence
  def skip? = @params[:skip].present?
  def savings? = source.is_a?(Account)
  def rate? = !savings? && calculator.rate?
  def allowance? = !savings? && calculator.allowance?

  private

  def acceptable?
    add_refusal
    adjustment.errors.empty?
  end

  def add_refusal
    return adjustment.errors.add(:base, nothing_to_skip_sentence) if nothing_to_skip?
    return adjustment.errors.add(:base, nothing_to_top_up_sentence) if savings? && adjustment.amount.to_d.positive?
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
  def nothing_to_top_up_sentence = "#{name} can take more any time — there's nothing to top up."
  def not_counting_yet = "#{name} hasn't started counting yet, so there's nothing to adjust."
  def nothing_to_skip? = skip? && !calculator.accrued_this_period.positive?
  def countable_span = @countable_span ||= calculator.countable_span

  def out_of_reach
    "#{name} #{reach_clause} — pick a date between " \
      "#{countable_span.first.strftime(DAY)} and #{countable_span.last.strftime(DAY)}."
  end

  def reach_clause
    return "counts from when its first target started, up to today" if savings?
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

- [ ] **Step 6: The controller reads a source**

`app/controllers/adjustments_controller.rb`:
```ruby
# frozen_string_literal: true

class AdjustmentsController < ApplicationController
  include BudgetPageState
  include SavingsPageState

  # Where each source is found, through current_user: a foreign id is not found rather than refused.
  SOURCE_SCOPES = {
    "Rule" => ->(user) { Rule.for_user(user) },
    "Account" => ->(user) { user.accounts }
  }.freeze

  def create
    source = scoped_source
    return head :unprocessable_content if source.nil?

    form = AdjustmentForm.new(source: source, params: params, name: name_for(source), today: current_user.today)
    if form.save
      redirect_to back_to(source), notice: confirmation(form)
    else
      refuse(source, form.error_sentence)
    end
  end

  def destroy
    adjustment = Adjustment.find(params[:id])
    raise ActiveRecord::RecordNotFound unless adjustment.user == current_user

    source = adjustment.source
    adjustment.destroy
    redirect_to back_to(source), notice: removal(adjustment, source)
  end

  private

  def scoped_source
    scope = SOURCE_SCOPES[params[:source_type]]
    scope&.call(current_user)&.find(params[:source_id])
  end

  def name_for(source) = source.is_a?(Rule) ? helpers.rule_name(source) : source.name
  def back_to(source) = source.is_a?(Rule) ? budget_page_path(open: source.category_id) : savings_path

  def refuse(source, message)
    source.is_a?(Rule) ? refuse_on_budget_page(message) : refuse_on_savings_page(message)
  end

  def confirmation(form)
    money = helpers.number_to_currency(form.adjustment.amount.abs)
    name = form.name
    negative = form.adjustment.amount.negative?
    return "Skipped this period for #{name} — #{money} less #{form.savings? ? "owed" : "set aside"}." if form.skip?
    return "Reduced what #{name} is owed by #{money} this period." if form.savings?

    if form.allowance?
      negative ? "Reduced #{name} by #{money} this period." : "Topped up #{name} by #{money} this period."
    else
      negative ? "Took back #{money} from #{name}." : "Set aside #{money} for #{name}."
    end
  end

  def removal(adjustment, source)
    money = helpers.number_to_currency(adjustment.amount.abs)
    name = name_for(source)
    negative = adjustment.amount.negative?
    return "Removed the #{money} reduction on #{name}." if source.is_a?(Account)

    if source.claim_calculator(today: current_user.today).allowance?
      negative ? "Removed the #{money} reduction on #{name}." : "Removed the #{money} top-up on #{name}."
    else
      negative ? "Removed the #{money} taken back from #{name}." : "Removed the #{money} set aside for #{name}."
    end
  end
end
```

`SavingsPageState` does not exist until Task 8. For this task create a stub at `app/controllers/concerns/savings_page_state.rb`:
```ruby
# frozen_string_literal: true

# The Savings page's state, for the controllers that render it after a write. Filled in with the page.
module SavingsPageState
  extend ActiveSupport::Concern

  private

  def refuse_on_savings_page(message)
    redirect_to savings_path, alert: message
  end
end
```
and add the route now so `savings_path` resolves: in `config/routes.rb` add `get "savings" => "savings#show", as: :savings` above `resources :accounts`. (No controller yet; nothing hits it before Task 8.)

`app/views/budget_page/_adjust.html.erb`: replace both `<%= hidden_field_tag :rule_id, line.rule.id %>` with
```erb
      <%= hidden_field_tag :source_type, "Rule" %>
      <%= hidden_field_tag :source_id, line.rule.id %>
```
and change the `<summary>` text from `Adjust` to `Adjust what's owed now`, so the disclosure reads as a change to the claim beneath which it sits.

- [ ] **Step 7: Request spec**

In `spec/requests/adjustments_spec.rb` replace `rule_id: rule.id` with `source_type: "Rule", source_id: rule.id` (three places; the foreign-rule one too) and add:
```ruby
  it "reduces a savings account and comes back to the savings page", :aggregate_failures do
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: user.period_containing(user.today).first)

    post adjustments_path, params: { source_type: "Account", source_id: emergency.id, amount: "50", amount_sign: "-1" }

    expect(response).to redirect_to(savings_path)
    expect(emergency.adjustments.sole.amount).to eq(-50)
  end

  it "refuses an unknown source type" do
    post adjustments_path, params: { source_type: "User", source_id: user.id, amount: "50" }

    expect(response).to have_http_status(:unprocessable_content)
  end
```

- [ ] **Step 8: Run and commit**

Run: `bundle exec rspec spec/services/account_form_spec.rb spec/services/adjustment_form_spec.rb spec/requests/adjustments_spec.rb spec/models/account_spec.rb spec/system/budget_page/adjustments_spec.rb`
Expected: PASS.
```bash
bundle exec rubocop -A
git add -A app spec config
git commit -m "feat/forms: an account form writes its targets, and an adjustment lands on a rule or an account"
```

---

### Task 8: The Savings page

**Files:**
- Create: `app/controllers/savings_controller.rb`, `app/presenters/savings_presenter.rb`, `app/presenters/savings_line.rb`, `app/views/savings/show.html.erb`, `_checking.html.erb`, `_accounts.html.erb`, `_row.html.erb`, `_adjust.html.erb`, `_drawer.html.erb`, `_transfer_form.html.erb`, `_add_account_form.html.erb`, `spec/presenters/savings_presenter_spec.rb`, `spec/requests/savings_spec.rb`, `spec/system/savings/index_spec.rb`, `spec/system/savings/transfer_spec.rb`, `spec/system/savings/adjust_spec.rb`
- Modify: `app/controllers/concerns/savings_page_state.rb`, `app/controllers/accounts_controller.rb`, `app/controllers/transfers_controller.rb`, `config/routes.rb`, `app/views/shared/_sidebar.html.erb`, `app/views/accounts/edit.html.erb` (breadcrumb + cancel link), `spec/requests/accounts_spec.rb`, `spec/requests/transfers_spec.rb`
- Delete: `app/presenters/accounts_presenter.rb`, `app/views/accounts/{index,_spending,_set_aside,_row,_drawer,_move_money_form,_add_account_form}.html.erb`, `spec/presenters/accounts_presenter_spec.rb`, `spec/system/accounts/index_spec.rb`

**Interfaces:**
- Consumes: `ClaimLedger#claims/#savings_accounts/#calculator_for/#claimed/#budget_claim/#savings_claim/#free/#pot`, `Transfer.latest_per_account`, `Adjustment.on_accounts`.
- Produces: `SavingsPresenter` (`checking`, `checking_balance`, `claimed`, `budget_claim`, `savings_claim`, `free`, `accounts`, `rows`, `savings_total`, `owed_total`, `today`); `SavingsLine`; routes `savings_path`; controllers redirect to `savings_path`.

- [ ] **Step 1: Failing presenter spec**

`spec/presenters/savings_presenter_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SavingsPresenter do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let!(:checking) { create(:account, user: user, name: "Checking", opening_balance: 4_000) }
  let(:presenter) { described_class.new(user: user, today: today) }
  let(:ledger) { ClaimLedger.new(user, today: today) }

  it "reads checking's figures off the ledger", :aggregate_failures do
    create(:rule, :rate, amount: 400, category: create(:category, user: user), starts_on: Date.new(2026, 1, 1))
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))

    expect(presenter.checking).to eq(checking)
    expect(presenter.checking_balance).to eq(4_000)
    expect(presenter.budget_claim).to eq(400)
    expect(presenter.savings_claim).to eq(200)
    expect(presenter.claimed).to eq(600)
    expect(presenter.free).to eq(3_400)
  end

  it "builds one line per savings account, targeted or not", :aggregate_failures do
    emergency = create(:account, user: user, name: "Emergency", opening_balance: 500)
    joint = create(:account, user: user, name: "Joint", opening_balance: 2_000)
    paycheck = create(:item, :income, user: user, name: "Paycheck")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 8, 21))
    create(:savings_target, :share, account: emergency, item: paycheck, percent: 10, starts_on: Date.new(2026, 8, 21))
    create(:transfer, from_account: checking, to_account: emergency, amount: 150, date: Date.new(2026, 8, 28))
    create(:adjustment, source: emergency, amount: -20, date: Date.new(2026, 9, 6))

    lines = presenter.rows.index_by(&:name)
    expect(lines.keys).to eq(["Emergency", "Joint"])
    expect(lines["Emergency"]).to have_attributes(balance: 650, claim: 230, accrued: 180)
    expect(lines["Emergency"].target_words).to eq("$200.00 a period, plus 10% of Paycheck")
    expect(lines["Emergency"].mode_words).to eq("keeps extra")
    expect(lines["Emergency"].since).to eq(Date.new(2026, 8, 21))
    expect(lines["Emergency"].moved_words).to eq("+$150.00 in on Aug 28")
    expect(lines["Emergency"].adjustments.map(&:amount)).to eq([-20])
    expect(lines["Emergency"]).to be_transferable
    expect(lines["Joint"]).not_to be_targeted
    expect(lines["Joint"].claim).to eq(0)
    expect(presenter.savings_total).to eq(2_650)
    expect(presenter.owed_total).to eq(230)
  end
end
```

- [ ] **Step 2: Run to see it fail**

Run: `bundle exec rspec spec/presenters/savings_presenter_spec.rb`
Expected: FAIL, `uninitialized constant SavingsPresenter`.

- [ ] **Step 3: Write the line and the presenter**

`app/presenters/savings_line.rb`:
```ruby
# frozen_string_literal: true

# One savings account's row on the Savings page: its balance, what it is owed, and the words for
# its targets. Every figure comes off one SavingsCalculator from one ClaimLedger.
SavingsLine = Data.define(:account, :balance, :claim, :accrued, :countable_span, :targets, :moved_words, :adjustments) do
  delegate :name, to: :account

  def targeted? = targets.any?
  def transferable? = claim.positive?
  def skippable? = accrued.positive?
  def target_words = targets.map(&:words).join(", plus ")
  def mode_words = account.keeps_extra? ? "keeps extra" : "asks every period"
  def since = targets.map(&:starts_on).min
end
```

`app/presenters/savings_presenter.rb`:
```ruby
# frozen_string_literal: true

# The Savings page: checking with what claims it, and every other account with what it is owed.
# Reads through one ClaimLedger; the row facts cost two queries whatever the row count.
class SavingsPresenter
  attr_reader :user, :today

  def initialize(user:, today: user.today)
    @user = user
    @today = today
  end

  def checking = user.main_account
  def checking_balance = ledger.pot
  delegate :claimed, :budget_claim, :savings_claim, :free, to: :ledger
  def typical_income = ledger.account_ledger.typical_income

  def accounts = @accounts ||= user.accounts.order(:name).to_a
  def savings_accounts = accounts.reject(&:main?)
  def rows = @rows ||= savings_accounts.map { |account| line_for(account) }
  def savings_total = rows.sum(0.to_d, &:balance)
  def owed_total = rows.sum(0.to_d, &:claim)

  private

  def ledger = @ledger ||= ClaimLedger.new(user, today: today)
  def targeted = @targeted ||= ledger.savings_accounts.index_by(&:id)

  def line_for(account)
    calculator = targeted.key?(account.id) ? ledger.calculator_for(targeted.fetch(account.id)) : nil
    SavingsLine.new(
      account: account,
      balance: ledger.account_ledger.balance_of(account),
      claim: calculator&.claim || 0.to_d,
      accrued: calculator&.accrued_this_period || 0.to_d,
      countable_span: calculator&.countable_span || (today...today),
      targets: calculator&.targets || [],
      moved_words: moved_words(account),
      adjustments: adjustments_this_period.fetch(account.id, [])
    )
  end

  def moved_words(account)
    touch = latest_transfer[account.id]
    return "—" if touch.blank?

    "#{touch.in? ? "+" : "−"}#{currency(touch.amount)} #{touch.in? ? "in" : "out"} on #{touch.date.strftime("%b %-d")}"
  end

  def latest_transfer = @latest_transfer ||= Transfer.latest_per_account(savings_accounts.map(&:id))

  def adjustments_this_period
    @adjustments_this_period ||= Adjustment.on_accounts(savings_accounts.map(&:id))
      .dated_within(user.period_containing(today)).order(:date, :created_at).group_by(&:source_id)
  end

  def currency(amount) = ActiveSupport::NumberHelper.number_to_currency(amount)
end
```

- [ ] **Step 4: Routes, controller, concern, sidebar**

`config/routes.rb`: `resources :accounts, only: [:create, :edit, :update, :destroy]` (drop `:index`); the `get "savings"` line from Task 7 stays.

`app/controllers/concerns/savings_page_state.rb`:
```ruby
# frozen_string_literal: true

# The Savings page's state, for savings#show and for the controllers that render it after a refusal
# from one of its forms: a drawer opens from `params[:open]`, a preselected transfer, or a refusal.
module SavingsPageState
  extend ActiveSupport::Concern

  private

  def assign_savings_state(new_account: nil, new_account_balance: nil, open_add_account: false, transfer: nil, open_transfer: false)
    @presenter = SavingsPresenter.new(user: current_user, today: current_user.today)
    @new_account = new_account || current_user.accounts.new
    @new_account_balance = new_account_balance
    @open_add_account = open_add_account || params[:open] == "add"
    @transfer = transfer || Transfer.new
    @transfer_to = params[:to]
    @open_transfer = open_transfer || params[:to].present? || params[:open] == "transfer"
  end

  def refuse_on_savings_page(message)
    flash.now[:alert] = message
    assign_savings_state
    render "savings/show", status: :unprocessable_content
  end
end
```

`app/controllers/savings_controller.rb`:
```ruby
# frozen_string_literal: true

class SavingsController < ApplicationController
  include SavingsPageState

  def show = assign_savings_state
end
```

`app/controllers/accounts_controller.rb`: delete `index` and `assign_index_state`; include `SavingsPageState`; `create` becomes
```ruby
  def create
    account = Account.open(current_user, name: account_params[:name], balance: account_params[:balance].presence || 0)
    return redirect_to savings_path, notice: "#{account.name} added." if account.persisted?

    assign_savings_state(new_account: account, new_account_balance: account_params[:balance], open_add_account: true)
    render "savings/show", status: :unprocessable_content
  end
```
Every `accounts_path` in the file → `savings_path`. The form's options load for `edit` and for a refused `update` (Task 9 renders them):
```ruby
  before_action :load_form_options, only: [:edit, :update]

  def edit; end
```
and privately:
```ruby
  def load_form_options
    @income_items = current_user.items.incomes.order(:name)
    @typical_income = SavingsPresenter.new(user: current_user, today: current_user.today).typical_income
  end
```

`app/controllers/transfers_controller.rb`:
```ruby
# frozen_string_literal: true

class TransfersController < ApplicationController
  include SavingsPageState

  def create
    attrs = transfer_params
    transfer = Transfer.move(user: current_user, from_id: attrs[:from_account_id], to_id: attrs[:to_account_id],
                             amount: attrs[:amount], date: attrs[:date])
    return redirect_to savings_path, notice: moved_notice(transfer) if transfer.persisted?

    assign_savings_state(transfer: transfer, open_transfer: true)
    @transfer_to = transfer.to_account_id
    render "savings/show", status: :unprocessable_content
  end

  private

  def transfer_params = params.expect(transfer: [:from_account_id, :to_account_id, :amount, :date])

  def moved_notice(transfer)
    "Transferred #{helpers.number_to_currency(transfer.amount)} from #{transfer.from_account.name} to #{transfer.to_account.name}."
  end
end
```

`app/views/shared/_sidebar.html.erb`: `{ name: "Accounts", path: accounts_path, icon: "wallet" }` → `{ name: "Savings", path: savings_path, icon: "banknotes" }`.

`app/views/accounts/edit.html.erb`: breadcrumb `{ label: "Accounts", url: accounts_path }` → `{ label: "Savings", url: savings_path }`; Cancel link → `savings_path`; subtitle `"Account"` → `@account.main? ? "Spending account" : "Savings account"`.

- [ ] **Step 5: The views**

Move the drawer and the two forms: `git mv app/views/accounts/_drawer.html.erb app/views/savings/_drawer.html.erb`, `git mv app/views/accounts/_add_account_form.html.erb app/views/savings/_add_account_form.html.erb`, `git mv app/views/accounts/_move_money_form.html.erb app/views/savings/_transfer_form.html.erb`. Then `git rm app/views/accounts/index.html.erb app/views/accounts/_spending.html.erb app/views/accounts/_set_aside.html.erb app/views/accounts/_row.html.erb app/presenters/accounts_presenter.rb spec/presenters/accounts_presenter_spec.rb spec/system/accounts/index_spec.rb`.

`app/views/savings/_transfer_form.html.erb` (the moved file, edited): header comment "TRANSFER MONEY"; locals `presenter`, `transfer`, `transfer_to`; `presenter.spending.id` → `presenter.checking.id`; `move_to || presenter.set_aside.first&.account&.id` → `transfer_to || presenter.savings_accounts.first&.id`; the submit label `"Move"` → `"Transfer"`; the intro sentence: "Between your own accounts. A transfer is not spending and not income; it changes two balances and nothing else."

`app/views/savings/_add_account_form.html.erb`: the intro `<p>` reads "New accounts are savings, not spending."

`app/views/savings/show.html.erb`:
```erb
<% content_for :title, "Savings" %>

<%= page_header(title: "Savings",
                subtitle: "Checking is what you spend from. Every other account is savings, and each one can say what it is owed.") %>

<div class="space-y-4 lg:space-y-6" data-controller="shared--drawer">
  <%= render "savings/checking", presenter: @presenter %>

  <%= render "savings/accounts", presenter: @presenter %>

  <%= render layout: "savings/drawer", locals: { name: "transfer", title: "Transfer money", open: @open_transfer } do %>
    <%= render "savings/transfer_form", presenter: @presenter, transfer: @transfer, transfer_to: @transfer_to %>
  <% end %>

  <%= render layout: "savings/drawer", locals: { name: "add", title: "Add an account", open: @open_add_account } do %>
    <%= render "savings/add_account_form", account: @new_account, balance: @new_account_balance %>
  <% end %>
</div>
```

`app/views/savings/_checking.html.erb`:
```erb
<%# CHECKING — tinted apart from everything else: income lands here, and the budget and savings
    both claim from it. Local: `presenter` (SavingsPresenter). %>
<div class="bg-[#FBFBF3] border border-brand rounded p-4 lg:p-6" data-checking>
  <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
    <h2 class="text-lg font-semibold text-gray-900"><%= presenter.checking.name %></h2>
    <span class="bg-brand-dark text-white text-[11px] uppercase tracking-wide font-semibold px-2 py-0.5 rounded">
      Spending account
    </span>
  </div>

  <p class="mt-1 text-sm text-gray-700">
    Income lands here. Your budget and your savings both claim from it.
  </p>

  <div class="mt-4 grid grid-cols-1 sm:grid-cols-3 gap-4">
    <div>
      <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Balance</p>
      <p class="mt-1 text-3xl font-semibold tabular-nums text-gray-900" data-checking-balance>
        <%= number_to_currency(presenter.checking_balance) %>
      </p>
    </div>
    <div>
      <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Claimed</p>
      <p class="mt-1 text-xl font-semibold tabular-nums text-gray-900" data-checking-claimed>
        <%= number_to_currency(presenter.claimed) %>
      </p>
      <dl class="mt-1.5 max-w-52 space-y-0.5 text-xs text-gray-600">
        <div class="flex justify-between"><dt>Budget</dt><dd class="tabular-nums font-medium text-gray-900" data-checking-budget-claim><%= number_to_currency(presenter.budget_claim) %></dd></div>
        <div class="flex justify-between"><dt>Savings</dt><dd class="tabular-nums font-medium text-gray-900" data-checking-savings-claim><%= number_to_currency(presenter.savings_claim) %></dd></div>
      </dl>
    </div>
    <div>
      <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Free to spend</p>
      <p class="mt-1 text-xl font-semibold tabular-nums <%= presenter.free.negative? ? "text-status-danger" : "text-gray-900" %>"
         data-checking-free>
        <%= number_to_currency(presenter.free) %>
      </p>
    </div>
  </div>

  <div class="mt-4">
    <%= link_to "Edit name or balance", edit_account_path(presenter.checking), class: "btn btn-secondary" %>
  </div>
</div>
```

`app/views/savings/_accounts.html.erb`:
```erb
<%# SAVINGS ACCOUNTS — every account but checking, each with what it is owed. Transfer money and
    Add an account open in drawers from the heading's buttons. Local: `presenter`. %>
<div class="bg-white border border-gray-200 rounded p-4 lg:p-6" data-savings-accounts>
  <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
    <div>
      <h2 class="text-sm font-semibold text-gray-900">Savings accounts</h2>
      <p class="mt-1 text-sm text-gray-600">
        Each account can be owed a fixed amount a period, a share of an income item, or both. A
        transfer from checking pays what it is owed.
      </p>
    </div>
    <div class="flex flex-col items-stretch sm:items-end gap-2">
      <% if presenter.rows.any? %>
        <p class="text-sm text-gray-700 tabular-nums shrink-0" data-savings-total>
          <strong><%= number_to_currency(presenter.savings_total) %></strong>
          across <%= pluralize(presenter.rows.size, "account") %>
        </p>
      <% end %>
      <div class="grid grid-cols-2 gap-2 sm:flex sm:justify-end">
        <%= link_to "Transfer money", savings_path(open: "transfer"), class: "btn btn-secondary",
                    data: { drawer: "transfer", action: "click->shared--drawer#open" } %>
        <%= link_to "Add an account", savings_path(open: "add"), class: "btn btn-primary",
                    data: { drawer: "add", action: "click->shared--drawer#open" } %>
      </div>
    </div>
  </div>

  <% if presenter.rows.empty? %>
    <p class="mt-4 text-sm text-gray-600" data-savings-empty>No savings accounts yet. Add one to start.</p>
  <% else %>
    <div class="mt-4 overflow-x-auto">
      <table class="w-full text-sm">
        <thead class="hidden sm:table-header-group">
          <tr class="border-b border-gray-200 text-left text-xs font-medium uppercase tracking-wide text-gray-500">
            <th class="py-2 pr-3">Account</th>
            <th class="py-2 px-3 text-right">Balance</th>
            <th class="py-2 px-3 text-right">Owed now</th>
            <th class="py-2 px-3">Last transfer</th>
            <th class="py-2 pl-3"><span class="sr-only">Actions</span></th>
          </tr>
        </thead>
        <tbody class="block sm:table-row-group divide-y divide-gray-100">
          <% presenter.rows.each do |row| %>
            <%= render "savings/row", row: row, presenter: presenter %>
          <% end %>
        </tbody>
        <tfoot class="block sm:table-footer-group">
          <tr class="block sm:table-row border-t border-gray-200 font-semibold text-gray-900">
            <td class="block sm:table-cell sm:py-2 sm:pr-3">Total</td>
            <td class="block sm:table-cell sm:py-2 sm:px-3 sm:text-right tabular-nums" data-savings-footer><%= number_to_currency(presenter.savings_total) %></td>
            <td class="block sm:table-cell sm:py-2 sm:px-3 sm:text-right tabular-nums" data-owed-footer><%= number_to_currency(presenter.owed_total) %></td>
            <td class="hidden sm:table-cell" colspan="2"></td>
          </tr>
        </tfoot>
      </table>
    </div>
  <% end %>
</div>
```

`app/views/savings/_row.html.erb`:
```erb
<%# ONE SAVINGS ACCOUNT. Locals: `row` (SavingsLine), `presenter`. The Adjust disclosure lives in
    the owed cell, because an adjustment is a change to what is owed now. Its panel opens in a
    full-width row beneath. %>
<tr class="block sm:table-row py-3 sm:py-2" data-account-row="<%= row.name %>">
  <td class="block sm:table-cell sm:py-2 sm:pr-3 sm:align-top">
    <div class="flex items-baseline justify-between gap-3 sm:block">
      <span class="font-medium text-gray-900"><%= row.name %></span>
      <span class="tabular-nums sm:hidden"><%= number_to_currency(row.balance) %></span>
    </div>
    <% if row.targeted? %>
      <div class="text-xs text-gray-600" data-account-targets><%= row.target_words %></div>
      <div class="text-xs text-gray-400"><%= row.mode_words %> · since <%= row.since.strftime("%b %-d") %></div>
    <% else %>
      <div class="text-xs text-gray-400" data-account-untargeted>
        No savings target · <%= link_to "set one", edit_account_path(row.account), class: "text-brand-dark hover:text-brand underline" %>
      </div>
    <% end %>
  </td>
  <td class="hidden sm:table-cell sm:py-2 sm:px-3 sm:align-top text-right tabular-nums <%= row.balance.negative? ? "text-status-danger" : "text-gray-900" %>">
    <%= number_to_currency(row.balance) %>
  </td>
  <td class="block sm:table-cell sm:py-2 sm:px-3 sm:align-top sm:text-right" data-account-owed="<%= row.name %>">
    <span class="sm:hidden text-xs text-gray-500">Owed now </span>
    <% if !row.targeted? %>
      <span class="text-gray-400">—</span>
    <% elsif row.transferable? %>
      <span class="font-semibold tabular-nums text-gray-900"><%= number_to_currency(row.claim) %></span>
    <% else %>
      <span class="font-medium text-status-success">On pace</span>
    <% end %>
    <% if row.targeted? %>
      <details class="mt-1 sm:text-right" data-adjust="<%= row.name %>">
        <summary class="cursor-pointer text-xs font-medium text-brand-dark hover:text-brand">Adjust</summary>
      </details>
    <% end %>
  </td>
  <td class="block sm:table-cell sm:py-2 sm:px-3 sm:align-top text-gray-700" data-account-moved="<%= row.name %>">
    <span class="sm:hidden text-xs text-gray-500">Last transfer </span><%= row.moved_words %>
  </td>
  <td class="block sm:table-cell sm:py-2 sm:pl-3 sm:align-top">
    <div class="mt-2 flex flex-wrap items-center gap-3 sm:mt-0">
      <% if row.transferable? %>
        <%= button_to "Transfer #{number_to_currency(row.claim)}",
                      transfers_path,
                      params: { transfer: { from_account_id: presenter.checking.id, to_account_id: row.account.id,
                                            amount: row.claim, date: presenter.today } },
                      class: "btn btn-primary h-8 px-3 text-xs",
                      form: { class: "inline-block" },
                      data: { transfer_owed: row.name } %>
      <% end %>
      <%= link_to "Edit", edit_account_path(row.account), class: "text-xs font-medium text-brand hover:text-brand-dark",
                  data: { account_edit: row.name } %>
      <% confirm = "Delete #{row.name}? Its targets, adjustments and transfers are deleted with it, so the money " \
                   "they moved goes back to checking — and whatever it was opened with goes with it. This cannot be undone." %>
      <%= button_to "Delete", account_path(row.account), method: :delete,
                    class: "text-xs font-medium text-gray-500 hover:text-status-danger transition-colors",
                    form: { class: "inline-block leading-none", data: { turbo_confirm: confirm } },
                    data: { account_delete: row.name } %>
    </div>
  </td>
</tr>
<% if row.targeted? %>
  <tr class="block sm:table-row" data-adjust-row="<%= row.name %>">
    <td class="block sm:table-cell sm:pb-3" colspan="5">
      <%= render "savings/adjust", row: row %>
    </td>
  </tr>
<% end %>
```

The `<details>` in the owed cell and the panel row beneath are tied by a tiny Stimulus-free trick: the panel row is `hidden` unless the details is open. Use the existing `shared--toggle` controller if it toggles `hidden` on a target; otherwise give the `<details>` a `data-action="toggle->shared--toggle#sync"`. **Simpler and what this plan specifies:** put the whole panel inside the `<details>` in the owed cell, and let the cell grow. Replace the empty `<details>…</details>` above with:
```erb
      <details class="mt-1 text-left" data-adjust="<%= row.name %>">
        <summary class="cursor-pointer text-xs font-medium text-brand-dark hover:text-brand sm:text-right">Adjust</summary>
        <%= render "savings/adjust", row: row %>
      </details>
```
and delete the second `<tr data-adjust-row>` block.

`app/views/savings/_adjust.html.erb`:
```erb
<%# One savings account's period, reduced. Local: `row` (SavingsLine). Reduce and Skip only: with
    no ceiling, saving more is just transferring more. %>
<div class="mt-2 w-full max-w-xl rounded border border-gray-200 bg-gray-50 px-3 py-3 space-y-3 text-left">
  <p class="text-xs text-gray-600" data-adjust-owed>
    <%= number_to_currency(row.accrued) %> owed this period
  </p>

  <%= form_with url: adjustments_path, method: :post, class: "space-y-2" do %>
    <%= hidden_field_tag :source_type, "Account" %>
    <%= hidden_field_tag :source_id, row.account.id %>
    <%= hidden_field_tag :amount_sign, "-1" %>

    <div class="flex flex-wrap items-end gap-2">
      <div>
        <%= label_tag "adjust-amount-#{row.account.id}", "Reduce by", class: "block text-xs text-gray-600 mb-1" %>
        <%= number_field_tag :amount, nil, id: "adjust-amount-#{row.account.id}", step: 0.01, min: 0.01, required: true,
                             placeholder: "0.00", class: "form-input w-28" %>
      </div>
      <div>
        <%= label_tag "adjust-date-#{row.account.id}", "On", class: "block text-xs text-gray-600 mb-1" %>
        <%= date_field_tag :date, nil, id: "adjust-date-#{row.account.id}", min: row.countable_span.first,
                           max: row.countable_span.last, class: "form-input" %>
      </div>
      <%= button_tag "Reduce this period", type: :submit, class: "btn btn-secondary" %>
    </div>

    <p class="text-xs text-gray-500" data-adjust-hint>
      Today unless you pick a day. Counts from <%= row.countable_span.first.strftime("%b %-d") %> to today.
      You can always transfer more; there is nothing to top up.
    </p>
  <% end %>

  <% if row.skippable? %>
    <%= form_with url: adjustments_path, method: :post do %>
      <%= hidden_field_tag :source_type, "Account" %>
      <%= hidden_field_tag :source_id, row.account.id %>
      <%= hidden_field_tag :skip, "1" %>
      <%= button_tag "Skip this period (−#{number_to_currency(row.accrued)})", type: :submit,
                     class: "btn btn-secondary w-full sm:w-auto", data: { adjust_skip: true } %>
    <% end %>
  <% end %>

  <% if row.adjustments.any? %>
    <ul class="space-y-1" data-account-changes>
      <% row.adjustments.each do |change| %>
        <li class="flex items-baseline gap-2 text-xs text-gray-600" data-change="<%= change.id %>">
          <span class="text-gray-500"><%= change.date.strftime("%b %-d") %></span>
          <span class="text-status-danger" data-change-amount><%= number_to_currency(change.amount) %></span>
          <%= button_to "Remove", adjustment_path(change), method: :delete, class: "text-brand-dark hover:text-brand underline" %>
        </li>
      <% end %>
    </ul>
  <% end %>
</div>
```

- [ ] **Step 6: Request specs**

`spec/requests/savings_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings" do
  let(:user) { create(:user, :biweekly) }

  before do
    create(:account, user: user, name: "Checking")
    sign_in user, scope: :user
  end

  it "renders the page with checking and the savings accounts", :aggregate_failures do
    create(:account, user: user, name: "Emergency")

    get savings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Spending account").and include("Emergency")
  end
end
```

`spec/requests/accounts_spec.rb`: every `accounts_path` → `savings_path`; delete any `get accounts_path` example (the index is gone). `spec/requests/transfers_spec.rb`: `redirect_to(accounts_path)` → `redirect_to(savings_path)`; `"Moved $40.00 from Checking to Savings."` → `"Transferred $40.00 from Checking to Savings."`; the refusal example's description "re-renders the accounts page" → "re-renders the savings page".

- [ ] **Step 7: System specs**

`spec/system/savings/index_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

# SAVINGS: checking as a tinted card with what claims it, every other account with what it is owed.
RSpec.describe "Savings page", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let!(:checking) { create(:account, user: user, name: "Checking", opening_balance: 4_000) }

  around { |example| travel_to(today) { example.run } }
  before { sign_in user, scope: :user }

  def row(name) = find("[data-account-row='#{name}']")

  it "shows checking's figures with the budget and savings claims beneath", :aggregate_failures do
    create(:rule, :rate, amount: 400, category: create(:category, user: user, name: "Groceries"), starts_on: Date.new(2026, 1, 1))
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))

    visit savings_path

    within("[data-checking]") do
      expect(page).to have_css("[data-checking-balance]", text: "$4,000.00")
      expect(page).to have_css("[data-checking-claimed]", text: "$600.00")
      expect(page).to have_css("[data-checking-budget-claim]", text: "$400.00")
      expect(page).to have_css("[data-checking-savings-claim]", text: "$200.00")
      expect(page).to have_css("[data-checking-free]", text: "$3,400.00")
    end
    expect(page).to have_link("Savings", href: savings_path)
  end

  it "lists each savings account with its targets, what it is owed, and its last transfer", :aggregate_failures do
    emergency = create(:account, user: user, name: "Emergency", opening_balance: 500)
    create(:account, user: user, name: "Joint", opening_balance: 2_000)
    paycheck = create(:item, :income, user: user, name: "Paycheck")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 8, 21))
    create(:savings_target, :share, account: emergency, item: paycheck, percent: 10, starts_on: Date.new(2026, 8, 21))
    create(:transfer, from_account: checking, to_account: emergency, amount: 150, date: Date.new(2026, 8, 28))

    visit savings_path

    within(row("Emergency")) do
      expect(page).to have_css("[data-account-targets]", text: "$200.00 a period, plus 10% of Paycheck")
      expect(page).to have_content("keeps extra · since Aug 21")
      expect(page).to have_css("[data-account-owed='Emergency']", text: "$250.00")
      expect(page).to have_css("[data-account-moved='Emergency']", text: "+$150.00 in on Aug 28")
      expect(page).to have_button("Transfer $250.00")
    end
    within(row("Joint")) do
      expect(page).to have_css("[data-account-untargeted]", text: "No savings target")
      expect(page).to have_link("set one", href: edit_account_path(Account.find_by!(name: "Joint")))
      expect(page).to have_no_button(/Transfer/)
    end
    expect(page).to have_css("[data-savings-total]", text: "$2,650.00 across 2 accounts")
    expect(page).to have_css("[data-owed-footer]", text: "$250.00")
  end

  it "says on pace when nothing is owed" do
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
    create(:transfer, from_account: checking, to_account: emergency, amount: 200, date: Date.new(2026, 9, 5))

    visit savings_path

    expect(row("Emergency")).to have_css("[data-account-owed='Emergency']", text: "On pace")
  end
end
```

`spec/system/savings/transfer_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings transfers", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let!(:checking) { create(:account, user: user, name: "Checking", opening_balance: 4_000) }
  let!(:emergency) { create(:account, user: user, name: "Emergency") }

  around { |example| travel_to(today) { example.run } }
  before { sign_in user, scope: :user }

  it "pays what is owed in one click", :aggregate_failures do
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
    visit savings_path

    click_button "Transfer $200.00"

    expect(page).to have_content("Transferred $200.00 from Checking to Emergency.")
    expect(page).to have_css("[data-account-owed='Emergency']", text: "On pace")
    expect(Transfer.sole).to have_attributes(from_account: checking, to_account: emergency, amount: 200, date: today)
  end

  it "transfers any amount from the drawer", :aggregate_failures do
    visit savings_path(open: "transfer")

    within("[data-drawer-name='transfer']") do
      select "Checking", from: "From"
      select "Emergency", from: "To"
      fill_in "Amount", with: "75"
      click_button "Transfer"
    end

    expect(page).to have_content("Transferred $75.00 from Checking to Emergency.")
    expect(page).to have_css("[data-account-moved='Emergency']", text: "+$75.00 in on Sep 9")
  end

  it "keeps the drawer open with the reason when a transfer is refused" do
    visit savings_path(open: "transfer")

    within("[data-drawer-name='transfer']") do
      select "Checking", from: "From"
      select "Checking", from: "To"
      fill_in "Amount", with: "75"
      click_button "Transfer"
    end

    expect(page).to have_css("[data-drawer-name='transfer'][open]", text: "must differ from the source account")
  end
end
```

`spec/system/savings/adjust_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings adjustments", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let!(:checking) { create(:account, user: user, name: "Checking", opening_balance: 4_000) }
  let!(:emergency) { create(:account, user: user, name: "Emergency") }

  around { |example| travel_to(today) { example.run } }

  before do
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 8, 21))
    sign_in user, scope: :user
  end

  it "reduces this period from the owed cell, and lists the change", :aggregate_failures do
    visit savings_path

    within("[data-adjust='Emergency']") do
      find("summary").click
      fill_in "Reduce by", with: "50"
      click_button "Reduce this period"
    end

    expect(page).to have_content("Reduced what Emergency is owed by $50.00 this period.")
    expect(page).to have_css("[data-account-owed='Emergency']", text: "$350.00")
    within("[data-adjust='Emergency']") do
      find("summary").click
      expect(page).to have_css("[data-change-amount]", text: "-$50.00")
    end
    expect(emergency.adjustments.sole.amount).to eq(-50)
  end

  it "skips the period for exactly what is owed this period", :aggregate_failures do
    visit savings_path

    within("[data-adjust='Emergency']") do
      find("summary").click
      click_button "Skip this period (−$200.00)"
    end

    expect(page).to have_content("Skipped this period for Emergency — $200.00 less owed.")
    expect(page).to have_css("[data-account-owed='Emergency']", text: "$200.00")
  end
end
```

`spec/system/accounts/` keeps whatever specs it has for `edit` (Task 9 rewrites it).

- [ ] **Step 8: Run and commit**

Run: `bundle exec rspec spec/presenters/savings_presenter_spec.rb spec/requests spec/system/savings spec/system/accounts spec/system/navbar_spec.rb spec/system/home`
Expected: PASS. If `navbar_spec` or a Home spec asserts the "Accounts" link or `accounts_path`, change it to "Savings" / `savings_path`. `app/views/home/_manage_accounts.html.erb` links `accounts_path`; change it to `savings_path` and its copy from "accounts" to "savings".
```bash
bundle exec rubocop -A
git add -A app spec config
git commit -m "feat/savings: the Savings page — checking with its claims, each account with what it is owed, and a one-click transfer"
```

---

### Task 9: The account form with target rows

**Files:**
- Create: `app/views/accounts/_target_fields.html.erb`, `app/javascript/controllers/app/account/targets_controller.js`, `spec/system/accounts/edit_spec.rb`
- Modify: `app/views/accounts/edit.html.erb`

**Interfaces:**
- Consumes: `AccountForm` (Task 7), `@income_items`, `@typical_income` (Task 8's `edit`).

- [ ] **Step 1: Failing system spec**

`spec/system/accounts/edit_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

# The account form: name and balance as before, then what the account is owed as a list of rows,
# each a fixed amount or a share of an income item, and the keeps-extra choice.
RSpec.describe "Account edit", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let!(:checking) { create(:account, user: user, name: "Checking", opening_balance: 4_000) }
  let!(:emergency) { create(:account, user: user, name: "Emergency", opening_balance: 500) }
  let!(:paycheck) { create(:item, :income, user: user, name: "Paycheck") }

  around { |example| travel_to(today) { example.run } }
  before { sign_in user, scope: :user }

  it "saves a fixed target and the mode without JavaScript", :aggregate_failures do
    visit edit_account_path(emergency)

    within("[data-target-row]", match: :first) do
      select "A fixed amount", from: "Source"
      fill_in "A period", with: "200"
      fill_in "Since", with: "2026-09-04"
    end
    choose "Ask every period"
    click_button "Save account"

    expect(page).to have_content("Emergency updated.")
    expect(page).to have_css("[data-account-targets]", text: "$200.00 a period")
    expect(emergency.reload).not_to be_keeps_extra
  end

  it "adds a share row, switches the figure field with the source, and removes a row", :aggregate_failures, :js do
    create(:savings_target, account: emergency, amount: 200)
    visit edit_account_path(emergency)

    click_button "Add another"
    within(all("[data-target-row]").last) do
      select "Paycheck", from: "Source"
      expect(page).to have_field("Share")
      expect(page).to have_no_field("A period")
      fill_in "Share", with: "10"
    end
    click_button "Save account"

    expect(page).to have_css("[data-account-targets]", text: "$200.00 a period, plus 10% of Paycheck")

    visit edit_account_path(emergency)
    within("[data-target-row]", match: :first) { click_button "Remove" }
    click_button "Save account"

    expect(page).to have_css("[data-account-targets]", text: "10% of Paycheck")
    expect(emergency.savings_targets.reload.map(&:words)).to eq(["10% of Paycheck"])
  end

  it "shows what percent of typical income a fixed amount is", :aggregate_failures do
    salary = create(:category, :income, user: user)
    [Date.new(2026, 8, 7), Date.new(2026, 8, 25)].each { |on| create(:entry, item: create(:item, category: salary), amount: 2_000, date: on) }
    create(:savings_target, account: emergency, amount: 200)

    visit edit_account_path(emergency)

    expect(page).to have_css("[data-target-hint]", text: "That's 10% of what you typically bring in.")
  end

  it "refuses a share past 100% and keeps the typed rows", :aggregate_failures do
    visit edit_account_path(emergency)

    within("[data-target-row]", match: :first) do
      select "Paycheck", from: "Source"
      fill_in "Share", with: "150"
    end
    click_button "Save account"

    expect(page).to have_content("would take Paycheck past 100%")
    expect(page).to have_field("Share", with: "150")
  end
end
```

- [ ] **Step 2: Run to see it fail**

Run: `bundle exec rspec spec/system/accounts/edit_spec.rb`
Expected: FAIL, no field "Source".

- [ ] **Step 3: The fields partial**

`app/views/accounts/_target_fields.html.erb`:
```erb
<%# ONE TARGET ROW. Locals: `f` (fields_for builder on a SavingsTarget), `items` (the user's income
    items), `typical_income` (nil until a period completes). Both figure fields render; without
    JavaScript both show and SavingsTarget keeps the one the source implies, with it the controller
    shows one. Neither is hidden server-side, so a plain form can still be filled. %>
<% target = f.object %>
<div class="grid grid-cols-1 gap-3 rounded border border-gray-200 bg-[#FAFAF7] p-3 sm:grid-cols-[1.4fr_1fr_1fr_auto] sm:items-end"
     data-target-row
     data-app--account--targets-target="row">
  <div>
    <%= f.label :item_id, "Source", class: "form-label text-xs" %>
    <%= f.select :item_id,
                 options_for_select([["A fixed amount", ""]] + items.map { |item| [item.name, item.id] }, target.item_id),
                 {},
                 class: "form-select",
                 data: { "app--account--targets-target": "source", action: "change->app--account--targets#switch" } %>
  </div>
  <div data-app--account--targets-target="amountField">
    <%= f.label :amount, "A period", class: "form-label text-xs" %>
    <%= f.number_field :amount, step: 0.01, min: 0.01, class: "form-input tabular-nums",
                       value: target.amount && number_with_precision(target.amount, precision: 2),
                       data: { "app--account--targets-target": "amount", action: "input->app--account--targets#hint" } %>
  </div>
  <div data-app--account--targets-target="percentField">
    <%= f.label :percent, "Share", class: "form-label text-xs" %>
    <%= f.number_field :percent, step: 0.01, min: 0.01, max: 100, class: "form-input tabular-nums",
                       value: target.percent && target.percent.to_d.to_s("F").sub(/\.0+\z/, "") %>
  </div>
  <div>
    <%= f.label :starts_on, "Since", class: "form-label text-xs" %>
    <%= f.date_field :starts_on, value: (target.starts_on || current_user.today).strftime("%Y-%m-%d"), class: "form-input" %>
  </div>
  <div class="flex h-10 items-center">
    <%= f.check_box :_destroy, class: "sr-only", data: { "app--account--targets-target": "destroy" } %>
    <button type="button" class="text-xs font-medium text-gray-500 hover:text-status-danger"
            data-action="click->app--account--targets#remove">Remove</button>
  </div>
  <p class="form-hint sm:col-span-4" data-target-hint data-app--account--targets-target="hint">
    <% if target.target? && target.amount.present? && typical_income.to_d.positive? %>
      That's <%= ((target.amount.to_d / typical_income) * 100).round %>% of what you typically bring in.
    <% end %>
  </p>
</div>
```

Without JavaScript, the `Remove` button does nothing; the `_destroy` checkbox is `sr-only` so a screen reader can still tick it. That is acceptable: the `:js` example covers Remove, and the plain example never removes.

- [ ] **Step 4: The edit page**

`app/views/accounts/edit.html.erb`, replace the `<%= simple_form_for ... %>` block body:
```erb
      <%= simple_form_for @account, url: account_path(@account) do |f| %>
        <%= f.error_notification %>
        <%= f.error_notification message: f.object.errors[:opening_balance].to_sentence if f.object.errors[:opening_balance].present? %>
        <%= f.error_notification message: f.object.errors[:base].to_sentence if f.object.errors[:base].present? %>
        <% target_errors = f.object.savings_targets.flat_map { |t| t.errors.full_messages } %>
        <%= f.error_notification message: target_errors.to_sentence if target_errors.any? %>

        <%= f.input :name, label: "Account name", hint: "What your bank calls it." %>

        <%= f.input :balance,
            as: :decimal,
            label: "Balance today",
            required: false,
            input_html: { step: 0.01, value: number_with_precision(@account.balance, precision: 2) },
            hint: "Correcting the balance moves the opening balance; nothing else changes." %>

        <% unless @account.main? %>
          <fieldset class="mt-6 space-y-3"
                    data-controller="app--account--targets"
                    data-app--account--targets-typical-value="<%= @typical_income.to_d %>"
                    data-app--account--targets-index-value="<%= @account.savings_targets.size %>">
            <legend class="text-sm font-semibold text-gray-900">What this account is owed</legend>
            <p class="text-sm text-gray-600">A fixed amount a period, a share of an income item, or both. Each counts from its own start date.</p>

            <template data-app--account--targets-target="template">
              <%= f.simple_fields_for :savings_targets, SavingsTarget.new, child_index: "NEW_TARGET" do |t| %>
                <%= render "accounts/target_fields", f: t, items: @income_items, typical_income: @typical_income %>
              <% end %>
            </template>

            <div class="space-y-3" data-app--account--targets-target="rows">
              <% rows = @account.savings_targets.any? ? @account.savings_targets : [@account.savings_targets.build] %>
              <%= f.simple_fields_for :savings_targets, rows do |t| %>
                <%= render "accounts/target_fields", f: t, items: @income_items, typical_income: @typical_income %>
              <% end %>
            </div>

            <button type="button" class="btn btn-secondary" data-action="click->app--account--targets#add">Add another</button>

            <div class="mt-4 space-y-2 border-t border-gray-200 pt-4">
              <p class="form-label">When you transfer more than it is owed</p>
              <label class="flex items-start gap-2.5">
                <%= f.radio_button :keeps_extra, true, class: "form-radio mt-0.5" %>
                <span><span class="block text-sm font-medium text-gray-900">Keep the extra</span>
                  <span class="block text-xs text-gray-600">Extra counts against later periods. Transfer five periods' worth at once and nothing is owed for five periods.</span></span>
              </label>
              <label class="flex items-start gap-2.5">
                <%= f.radio_button :keeps_extra, false, class: "form-radio mt-0.5" %>
                <span><span class="block text-sm font-medium text-gray-900">Ask every period</span>
                  <span class="block text-xs text-gray-600">Every period asks for its own amount. Extra is just extra. A shortfall still carries.</span></span>
              </label>
            </div>
          </fieldset>
        <% end %>

        <div class="flex flex-col sm:flex-row sm:justify-end gap-3 mt-6">
          <%= link_to "Cancel", savings_path, class: "btn btn-secondary" %>
          <%= f.button :submit, "Save account" %>
        </div>
      <% end %>
```
The `choose "Ask every period"` in the spec matches the radio through its label text: give the second radio `id: "account_keeps_extra_false"` (simple_form does this by default) and the `<label>` wraps it, so Capybara finds it.

Because `f.input :balance` reads `@account.balance`, and a refused save leaves the account's nested targets in memory with their errors, the re-render shows the typed rows.

- [ ] **Step 5: The Stimulus controller**

`app/javascript/controllers/app/account/targets_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus"

// Target rows on the account form: add a row from the template, remove one (tick its _destroy and
// hide it), show the figure field the chosen source implies, and say what percent of typical
// income a fixed amount is.
export default class extends Controller {
  static targets = ["template", "rows", "row", "source", "amountField", "percentField", "amount", "destroy", "hint"]
  static values = { typical: Number, index: Number }

  connect() {
    this.rowTargets.forEach((row) => this.syncRow(row))
  }

  add() {
    const html = this.templateTarget.innerHTML.replace(/NEW_TARGET/g, String(this.indexValue++))
    this.rowsTarget.insertAdjacentHTML("beforeend", html)
    this.syncRow(this.rowTargets[this.rowTargets.length - 1])
  }

  remove(event) {
    const row = event.target.closest("[data-target-row]")
    const destroy = row.querySelector("[data-app--account--targets-target='destroy']")
    if (destroy) destroy.checked = true
    row.hidden = true
  }

  switch(event) {
    this.syncRow(event.target.closest("[data-target-row]"))
  }

  hint(event) {
    this.writeHint(event.target.closest("[data-target-row]"))
  }

  // A hidden field is also disabled, so only the figure the source implies is submitted.
  syncRow(row) {
    const share = row.querySelector("[data-app--account--targets-target='source']").value !== ""
    const amountField = row.querySelector("[data-app--account--targets-target='amountField']")
    const percentField = row.querySelector("[data-app--account--targets-target='percentField']")
    amountField.hidden = share
    percentField.hidden = !share
    amountField.querySelector("input").disabled = share
    percentField.querySelector("input").disabled = !share
    this.writeHint(row)
  }

  writeHint(row) {
    const hint = row.querySelector("[data-app--account--targets-target='hint']")
    const share = row.querySelector("[data-app--account--targets-target='source']").value !== ""
    const amount = parseFloat(row.querySelector("[data-app--account--targets-target='amount']").value)
    if (share || !this.typicalValue || !Number.isFinite(amount) || amount <= 0) {
      hint.textContent = ""
      return
    }
    hint.textContent = `That's ${Math.round((amount / this.typicalValue) * 100)}% of what you typically bring in.`
  }
}
```

- [ ] **Step 6: Run, rebuild CSS, commit**

```bash
bin/rails tailwindcss:build
bundle exec rspec spec/system/accounts spec/requests/accounts_spec.rb
```
Expected: PASS. (`sm:grid-cols-[1.4fr_1fr_1fr_auto]` and `bg-[#FAFAF7]` are new utilities, hence the rebuild.)
```bash
bundle exec rubocop -A
git add -A app spec
git commit -m "feat/savings: the account form writes what the account is owed, row by row"
```

---

### Task 10: The Budget tiles and Home read savings

**Files:**
- Modify: `app/presenters/budget_page_presenter.rb`, `app/views/budget_page/_tiles.html.erb`, `app/helpers/budget_page_helper.rb`, `app/helpers/home_helper.rb`, `app/assets/tailwind/custom.css`, `app/presenters/home_presenter.rb`, `app/views/home/_money.html.erb`, `app/views/home/_shortfall.html.erb`, `app/views/home/_this_period.html.erb`, `app/controllers/sacrifices_controller.rb`
- Test: `spec/presenters/budget_page_presenter_spec.rb`, `spec/system/budget_page/tiles_spec.rb`, `spec/presenters/home_presenter_spec.rb`, `spec/system/home/money_spec.rb`, `spec/system/home/trouble_spec.rb`

**Interfaces:**
- Produces: `BudgetPagePresenter#savings`, `#tiles` with `budget`, `savings`, `where` (= budget + savings), `segments` (savings first); `HomePresenter#savings`, `Uncovered` carrying a `ClaimLedger::Claim`.

- [ ] **Step 1: Failing presenter specs**

In `spec/presenters/budget_page_presenter_spec.rb` add to the tiles example (after the existing `rule_on` calls and income):
```ruby
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 300, starts_on: Date.new(2026, 9, 4))
    presenter = described_class.new(user: user, today: today)

    expect(presenter.savings).to eq(300)
    expect(presenter.leftover).to eq(800)
    expect(presenter.tiles).to have_attributes(budget: 900, savings: 300, where: 1_200)
    expect(presenter.tiles.segments.first).to have_attributes(type: :savings, amount: 300, percent: 25)
```
(Adjust the `900`/`1_100` figures of that example to whatever it uses; the deltas are `savings: 300`, `leftover` down by 300.) Replace `need: 900` in the existing `have_attributes` with `budget: 900`.

In `spec/presenters/home_presenter_spec.rb` line 36 change `u.category.name` to `u.name`, and add:
```ruby
  it "counts savings in claimed and free, and puts a savings claim in the give-way list between usage and bills", :aggregate_failures do
    create(:account, user: user, name: "Checking", opening_balance: 100) unless user.main_account
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 300, starts_on: user.period_containing(today).first)
    create(:rule, :rate, :bill, amount: 50, category: create(:category, user: user, name: "Rent"), starts_on: Date.new(2026, 1, 1))
    create(:rule, :rate, :choice, amount: 40, category: create(:category, user: user, name: "Fun"), starts_on: Date.new(2026, 1, 1))
    presenter = described_class.new(user: user, today: today)

    expect(presenter.claimed).to eq(390)
    expect(presenter.uncovered_claims.map { |u| [u.name, u.kind] }).to eq([["Fun", :choice], ["Emergency", :savings], ["Rent", :bill]])
  end
```
(If the spec's `user` already has a main account with a different balance, set the amounts so `free` is negative: the shortfall must exceed 340 for all three to appear. Use `opening_balance: 0` on checking for this example, or adjust.)

- [ ] **Step 2: Presenters**

`app/presenters/budget_page_presenter.rb`:
```ruby
  Tiles = Data.define(:budget, :savings, :segments, :income, :cadence, :leftover, :declared, :fits) do
    def declared? = declared
    def fits? = fits
    def where = budget + savings
  end
```
`tiles`: `budget: budget, savings: savings, …`. Add `def savings = claim_ledger.savings`. `leftover = typical_income && (typical_income - savings - budget)`. `underwater? = declared? && history? && budget + savings > typical_income`. `segments`:
```ruby
  def segments
    parts = [[:savings, savings]] + type_overview
    total = parts.sum { |(_type, amount)| amount }
    return [] unless total.positive?

    parts.reject { |(_type, amount)| amount.zero? }
      .map { |(type, amount)| Segment.new(type: type, amount: amount, percent: ((amount / total) * 100).round.clamp(0, 100)) }
  end
```

`app/helpers/budget_page_helper.rb`: `TYPE_HEADINGS = { "savings" => "Savings", "bill" => "Bills", "usage" => "Usage", "choice" => "Choice" }.freeze`.
`app/helpers/home_helper.rb`: `STRIPE_FILLS = { savings: "bg-savings", bill: "bg-brand-dark", usage: "bg-dusty-teal", choice: "bg-terracotta" }.freeze` and `TYPE_TEXT` gains `savings: "text-savings"`.
`app/assets/tailwind/custom.css`, after `.bg-dusty-teal { … }`:
```css
.bg-savings {
  background-color: var(--color-sage-800);
}

.text-savings {
  color: var(--color-sage-800);
}
```
`--color-sage-800` is defined in `application.css`'s `:root`; both files share the cascade, so it resolves.

`app/presenters/home_presenter.rb`:
```ruby
  Uncovered = Data.define(:claim_row, :amount) do
    delegate :name, :kind, :claim, to: :claim_row
    def whole? = amount >= claim
  end
```
`uncovered_claims` walks `claim_ledger.claims` (already in give-way order):
```ruby
  def uncovered_claims
    @uncovered_claims ||= begin
      remaining = short? ? shortfall : 0.to_d
      claim_ledger.claims.each_with_object([]) do |row, list|
        break list unless remaining.positive?
        next unless row.claim.positive?

        taken = [row.claim, remaining].min
        list << Uncovered.new(claim_row: row, amount: taken)
        remaining -= taken
      end
    end
  end
```
`delegate :claimed, :budget, :savings, to: :claim_ledger`; `structurally_underwater?` compares `budget + savings > income`. Delete the `give_way_order` delegation only if nothing else uses it (`runway_ticks` does; keep it).

- [ ] **Step 3: Views**

`app/views/budget_page/_tiles.html.erb`: reorder to income, where it goes, leftover. Tile 1 is the existing income tile unchanged. Tile 2 (`data-tile="where"`):
```erb
  <div class="col-span-2 bg-white border border-gray-200 rounded p-4 sm:col-span-1 sm:px-5 sm:py-4" data-tile="where">
    <h2 class="text-xs font-semibold uppercase tracking-wide text-gray-500">Where it goes</h2>
    <p class="mt-1 text-xl font-semibold text-gray-900 tabular-nums" data-tile-figure>
      <%= number_to_currency(presenter.tiles.where) %> <span class="block text-sm font-normal text-gray-500 md:inline">a period</span>
    </p>
    <% if presenter.tiles.segments.any? %>
      <div class="mt-3 flex h-2 overflow-hidden rounded bg-gray-100" data-type-bar>
        <% presenter.tiles.segments.each do |segment| %>
          <div class="<%= type_fill(segment.type) %>" style="width: <%= segment.percent %>%;" data-type-band="<%= segment.type %>"></div>
        <% end %>
      </div>
      <p class="mt-2 flex flex-wrap items-baseline gap-x-2 gap-y-1 text-xs text-gray-700">
        <% presenter.tiles.segments.each_with_index do |segment, index| %>
          <% unless index.zero? %><span class="text-gray-400" aria-hidden="true">·</span><% end %>
          <span data-type-total="<%= segment.type %>">
            <span class="text-gray-500"><%= rule_type_heading(segment.type) %></span>
            <span class="font-medium text-gray-900 tabular-nums"><%= number_to_currency(segment.amount) %></span>
          </span>
        <% end %>
      </p>
    <% end %>
    <p class="mt-2 text-xs text-gray-500" data-tile-split>
      Savings <span class="tabular-nums text-gray-900"><%= number_to_currency(presenter.tiles.savings) %></span> ·
      Budget <span class="tabular-nums text-gray-900"><%= number_to_currency(presenter.tiles.budget) %></span>
    </p>
  </div>
```
Tile 3 keeps `data-tile="leftover"`; its heading becomes "That leaves"; the verdict sentences become "Your savings and your budget fit what you bring in." / "Your savings and your budget ask for more than you bring in."; the empty-state sentence "…this will say whether your savings and budget fit."

`app/views/home/_money.html.erb`: aria-label → `"… of <%= main_name %> claimed"`; the subline `claimed by your rules` → `claimed by your budget and savings`; the negative sentence `Your rules claim` → `Your budget and savings claim`.
`app/views/home/_shortfall.html.erb`: headline `Your rules claim` → `Your budget and savings claim`; the list item:
```erb
        <li class="flex justify-between items-baseline gap-4 text-sm text-gray-600" data-uncovered-claim="<%= uncovered.name %>">
          <span><%= uncovered.name %> · <%= uncovered.kind == :savings ? "savings" : rule_label(uncovered.claim_row.source) %></span>
```
and the remainder sentence `past everything the rules claim` → `past everything that is claimed`.
`app/views/home/_this_period.html.erb`: unchanged beyond Task 6's `claimed`.
`app/controllers/sacrifices_controller.rb` `landing_for`: `"Your rules now need …"` → `"Your savings and budget now need #{helpers.number_to_currency(fresh.budget + fresh.savings)} a period."` (SacrificePresenter gains `savings` in Task 11; add `def savings = ledger.savings` to it now).

- [ ] **Step 4: System specs**

`spec/system/budget_page/tiles_spec.rb`: `tile("need")` → `tile("where")`; the heading assertions "Your rules need" → "Where it goes"; verdict strings as above; add:
```ruby
  it "puts savings first in the bar and in the split line", :aggregate_failures do
    a_period_of_income(2_000)
    rule_on("Groceries", amount: 400)
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 100, starts_on: Date.new(2026, 9, 4))

    visit budget_page_path

    within(tile("where")) do
      expect(page).to have_css("[data-tile-figure]", text: "$500.00")
      expect(page).to have_css("[data-type-band='savings']", visible: :all)
      expect(all("[data-type-band]").first["data-type-band"]).to eq("savings")
      expect(page).to have_css("[data-type-total='savings']", text: "$100.00")
      expect(page).to have_css("[data-tile-split]", text: "Savings $100.00 · Budget $400.00")
    end
    expect(tile("leftover")).to have_css("[data-tile-figure]", text: "$1,500.00")
  end
```
`spec/system/home/money_spec.rb` and `trouble_spec.rb`: update the sentences changed above (grep for "claimed by your rules" and "Your rules claim").

- [ ] **Step 5: Run, rebuild CSS, commit**

```bash
bin/rails tailwindcss:build
bundle exec rspec spec/presenters spec/system/budget_page spec/system/home
```
Expected: PASS.
```bash
bundle exec rubocop -A
git add -A app spec
git commit -m "feat/budget: the tiles say where income goes, savings first, and Home's free is net of savings"
```

---

### Task 11: The sacrifice page lists savings targets

**Files:**
- Modify: `app/presenters/sacrifice_presenter.rb`, `app/services/sacrifice_cuts.rb`, `app/controllers/sacrifices_controller.rb`, `app/views/sacrifices/show.html.erb`, `app/javascript/controllers/app/sacrifice/dial_controller.js`, `app/helpers/sacrifices_helper.rb`
- Test: `spec/presenters/sacrifice_presenter_spec.rb`, `spec/services/sacrifice_cuts_spec.rb`, `spec/requests/sacrifices_spec.rb`, `spec/system/sacrifices/show_spec.rb`

**Interfaces:**
- Produces: `SacrificePresenter#savings`, `#gap = budget + savings − income`, `#target_rows` (`TargetRow`: `target`, `ask`, `income`, `#name`, `#share?`, `#claim_param`, `#percent_param`, `#income_param`); `SacrificeCuts.new(user, cuts:, target_cuts:, today:)`.

- [ ] **Step 1: Failing specs**

`spec/presenters/sacrifice_presenter_spec.rb`, add:
```ruby
  it "lists each savings target as its own row and counts savings in the gap", :aggregate_failures do
    rule_on("Fun", :choice, amount: 300)
    emergency = create(:account, user: user, name: "Emergency")
    paycheck = create(:item, :income, category: salary, name: "Paycheck")
    [Date.new(2026, 8, 7), Date.new(2026, 8, 25)].each { |on| create(:entry, item: paycheck, amount: 500, date: on) }
    create(:savings_target, account: emergency, amount: 400, starts_on: Date.new(2026, 9, 4))
    create(:savings_target, :share, account: emergency, item: paycheck, percent: 10, starts_on: Date.new(2026, 9, 4))

    expect(presenter.savings).to eq(450)
    expect(presenter.gap).to eq(300 + 450 - 1_500)
    expect(presenter).not_to be_underwater
    rule_on("Rent", :bill, amount: 1_200)
    fresh = described_class.new(user: user, today: today)
    expect(fresh).to be_underwater
    expect(fresh.target_rows.map { |row| [row.name, row.ask, row.share?] })
      .to eq([["Emergency · $400.00 a period", 400, false], ["Emergency · 10% of Paycheck", 50, true]])
    expect(fresh.target_rows.last.income).to eq(500)
    expect(fresh.cuttable_total).to eq(300 + 1_200 + 450)
  end
```
(The `salary` category's typical income is 1,000 + 500 = 1,500 once Paycheck's entries land in it.)

`spec/services/sacrifice_cuts_spec.rb`, change `cuts_for` to `described_class.new(user, cuts: map, target_cuts: {}, today: today)` and add:
```ruby
  it "writes a lower amount on a fixed target and a lower percent on a share", :aggregate_failures do
    create(:account, user: user, name: "Checking")
    emergency = create(:account, user: user, name: "Emergency")
    fixed = create(:savings_target, account: emergency, amount: 400)
    share = create(:savings_target, :share, account: emergency, percent: 10)

    service = described_class.new(user, cuts: {}, target_cuts: { fixed.id => "250", share.id => "8" }, today: today)

    expect(service.apply).to be(true)
    expect(service.count).to eq(2)
    expect(fixed.reload.amount).to eq(250)
    expect(share.reload.percent).to eq(8)
  end

  it "refuses a target cut at or above its figure", :aggregate_failures do
    create(:account, user: user, name: "Checking")
    fixed = create(:savings_target, account: create(:account, user: user), amount: 400)

    service = described_class.new(user, cuts: {}, target_cuts: { fixed.id => "400" }, today: today)

    expect(service.apply).to be(false)
    expect(service.errors.full_messages.join).to include("below")
  end
```

- [ ] **Step 2: Presenter**

`app/presenters/sacrifice_presenter.rb`, add:
```ruby
  TargetRow = Data.define(:target, :ask, :income) do
    def share? = target.share?
    def name = "#{target.account.name} · #{target.words}"
    def claim_param = DigitsHelper.digits(ask)
    def percent_param = target.percent.to_d.to_s("F").sub(/\.0+\z/, "")
    def income_param = DigitsHelper.digits(income)
  end

  def savings = @savings ||= ledger.savings
  def gap = @gap ||= budget + savings - typical_income.to_d

  def target_rows
    @target_rows ||= ledger.savings_accounts.flat_map(&:savings_targets).map { |target| target_row(target) }
      .sort_by { |row| [-row.ask, row.name] }
  end

  def cuttable_total = @cuttable_total ||= cuttable_rows.sum(0.to_d, &:claim) + target_rows.sum(0.to_d, &:ask)
  def rows_total = rows.sum(0.to_d, &:claim) + target_rows.sum(0.to_d, &:ask)

  private

  def target_row(target)
    income = target.share? ? ledger.account_ledger.typical_income_of_item(target.item_id) : 0.to_d
    TargetRow.new(target: target, ask: target.ask(typical_income: income), income: income)
  end
```
(Keep `budget = ledger.budget` from Task 6; remove the older `cuttable_total`/`rows_total`.)

- [ ] **Step 3: Cuts**

`app/services/sacrifice_cuts.rb`: `initialize(user, cuts:, target_cuts: {}, today: user.today)` storing `@target_cuts = target_cuts.to_h`; in `apply` build `lines + target_lines` and write both:
```ruby
  def apply
    written = false
    ActiveRecord::Base.transaction do
      lines = @cuts.filter_map { |rule_id, typed| line_for(rule_id, typed) }
      targets = @target_cuts.filter_map { |target_id, typed| target_line_for(target_id, typed) }
      raise ActiveRecord::Rollback if errors.any? || nothing_dialled?(lines + targets)

      lines.each { |line| line.fetch(:rule).update!(amount: line.fetch(:amount)) }
      targets.each { |line| line.fetch(:target).update!(line.fetch(:attributes)) }
      @count = lines.size + targets.size
      written = true
    end
    written
  end
```
and:
```ruby
  # nil for a row left at its figure. A fixed target takes the typed amount, a share the typed percent.
  def target_line_for(target_id, typed)
    target = user.savings_targets.find(target_id)
    current = target.share? ? target.percent.to_d : target.amount.to_d
    return nil if positive_number?(typed) && typed.to_s.to_d == current
    return { target: target, attributes: nil } unless target_check?(target, current, typed)

    { target: target, attributes: target.share? ? { percent: typed.to_s.to_d } : { amount: typed.to_s.to_d } }
  end

  def target_check?(target, current, typed)
    name = "#{target.account.name}'s #{target.share? ? "share" : "target"}"
    if !positive_number?(typed)
      errors.add(:base, "#{name} cut needs a positive #{target.share? ? "percent" : "amount"}")
    elsif typed.to_s.to_d > current
      errors.add(:base, "#{name} cut must be below what it asks for now")
    end
    errors.empty?
  end
```
`nothing_dialled?`'s message becomes "Dial a rule or a savings target down to cut it first".

`app/controllers/sacrifices_controller.rb`: `SacrificeCuts.new(current_user, cuts: dialled_cuts, target_cuts: dialled_target_cuts, today: …)`; `def dialled_target_cuts = params.permit(target_cuts: {})[:target_cuts].to_h`; `@typed_targets = dialled_target_cuts`; the saved sentence `"Saved — #{helpers.pluralize(cuts.count, "cut")}."`; `refusal_for`'s second sentence "Your savings and budget already fit what you bring in, so there's nothing here to cut."

- [ ] **Step 4: The view and the dial**

`app/views/sacrifices/show.html.erb`:
- Subtitle: "Your savings and your budget ask for more than you bring in. This is what would have to give."
- The figures line: "Your budget is <strong data-figure="budget">…</strong> and your savings take <strong data-figure="savings">…</strong>. You typically bring home …". Keep `data-figure="rules-need"` renamed to `budget`.
- The existing list section's heading becomes "Your budget"; its intro sentence ends "Choices give way first, then usage. A bill is what it is."
- After the fixed rows and before the totals block, add a second section inside the same form:
```erb
    <div class="px-6 py-4 border-y border-gray-200 mt-2">
      <h3 class="text-sm font-semibold text-gray-900">Your savings</h3>
      <p class="mt-1 text-sm text-gray-500">One row per target. Lower a fixed amount, or lower a share's percent. Savings gives way after usage and before bills.</p>
    </div>
    <% @presenter.target_rows.each do |row| %>
      <div class="px-6 py-3 border-b border-gray-100 flex flex-wrap items-center gap-x-4 gap-y-2"
           data-sacrifice-target="<%= row.target.id %>"
           data-app--sacrifice--dial-target="row"
           data-claim="<%= row.claim_param %>"
           data-kind="<%= row.share? ? "percent" : "amount" %>"
           data-percent="<%= row.percent_param %>"
           data-income="<%= row.income_param %>">
        <input type="checkbox" id="cut-target-<%= row.target.id %>" class="form-checkbox" aria-label="Cut <%= row.name %>"
               data-app--sacrifice--dial-target="toggle" data-action="change->app--sacrifice--dial#recompute">
        <label class="flex-1 min-w-40 text-sm font-medium text-gray-900" for="cut-target-amount-<%= row.target.id %>"><%= row.name %></label>
        <span class="text-sm text-gray-600 tabular-nums" data-role="claim"><%= number_to_currency(row.ask) %> a period</span>
        <div class="flex items-center gap-2">
          <span class="text-sm text-gray-500">cut to</span>
          <input type="number" id="cut-target-amount-<%= row.target.id %>" class="form-input w-28 tabular-nums"
                 step="<%= row.share? ? 1 : 0.01 %>" min="0" <%= "max=100" if row.share? %>
                 name="target_cuts[<%= row.target.id %>]"
                 value="<%= @typed_targets&.dig(row.target.id.to_s) || (row.share? ? row.percent_param : row.claim_param) %>"
                 aria-label="Cut <%= row.name %> to"
                 data-app--sacrifice--dial-target="amount"
                 data-action="input->app--sacrifice--dial#recompute change->app--sacrifice--dial#recompute">
          <% if row.share? %><span class="text-sm text-gray-500">%</span><% end %>
        </div>
        <span class="text-sm text-gray-600 tabular-nums w-32 text-right" data-role="row-frees">
          frees <span data-app--sacrifice--dial-target="rowFrees"><%= number_to_currency(0) %></span>
        </span>
        <%= link_to "Edit the target", edit_account_path(row.target.account), class: "btn btn-secondary whitespace-nowrap" %>
      </div>
    <% end %>
```
The rule rows keep their `name="cuts[…]"` inputs. Add `data-kind="amount"` to each rule row so the dial treats every row alike.

`app/javascript/controllers/app/sacrifice/dial_controller.js`, replace `freedBy`:
```javascript
  // Cutting TO a figure. An amount row frees `claim - typed`; a percent row frees the difference
  // between its percent and the typed percent, of its item's typical income. Clamped into
  // [0, claim]. An unchecked row frees nothing whatever is typed in it.
  freedBy(row) {
    const toggle = this.fieldFor(row, "toggle")
    if (!toggle.checked) return 0

    const claim = this.cents(parseFloat(row.dataset.claim))
    const typed = parseFloat(this.fieldFor(row, "amount").value)
    const kept = row.dataset.kind === "percent"
      ? this.cents((Number.isFinite(typed) ? typed : 0) / 100 * parseFloat(row.dataset.income))
      : this.cents(typed)

    return Math.min(Math.max(claim - kept, 0), claim)
  }
```

`app/helpers/sacrifices_helper.rb`: unchanged.

- [ ] **Step 5: System and request specs**

In `spec/system/sacrifices/show_spec.rb` add:
```ruby
  it "lists each savings target in its own section and dials a share by percent", :aggregate_failures, :js do
    rate_rule("Fun", 300)
    create(:rule, :rolling, :bill, category: category("Rent"), amount: 2_000, anchor_date: Date.new(2026, 10, 1), interval_months: 1, starts_on: Date.new(2026, 1, 1))
    emergency = create(:account, user: user, name: "Emergency")
    paycheck = create(:item, :income, category: salary, name: "Paycheck")
    [Date.new(2026, 8, 7), Date.new(2026, 8, 25)].each { |on| create(:entry, item: paycheck, amount: 500, date: on) }
    create(:savings_target, account: emergency, amount: 400, starts_on: Date.new(2026, 9, 4))
    create(:savings_target, :share, account: emergency, item: paycheck, percent: 10, starts_on: Date.new(2026, 9, 4))

    visit sacrifice_path

    expect(page).to have_css("[data-figure='savings']", text: "$450.00")
    within("[data-sacrifice-target='#{SavingsTarget.shares.sole.id}']") do
      expect(page).to have_content("Emergency · 10% of Paycheck")
      expect(page).to have_css("[data-role='claim']", text: "$50.00 a period")
      find("input[type='checkbox']").check
      find("input[name='target_cuts[#{SavingsTarget.shares.sole.id}]']").fill_in(with: "6")
      expect(page).to have_css("[data-role='row-frees']", text: "frees $20.00")
    end
    expect(page).to have_css("[data-figure='frees']", text: "$20.00 a period")
  end

  it "saves a target cut" do
    rate_rule("Fun", 300)
    create(:rule, :rolling, :bill, category: category("Rent"), amount: 2_000, anchor_date: Date.new(2026, 10, 1), interval_months: 1, starts_on: Date.new(2026, 1, 1))
    fixed = create(:savings_target, account: create(:account, user: user, name: "Emergency"), amount: 400, starts_on: Date.new(2026, 9, 4))

    visit sacrifice_path
    find("input[name='target_cuts[#{fixed.id}]']").fill_in(with: "250")
    click_button "Save these cuts"

    expect(page).to have_content("Saved — 1 cut.")
    expect(fixed.reload.amount).to eq(250)
  end
```
Update any existing assertion on `data-figure="rules-need"` to `budget`, and the "Your rules already fit" sentence in `spec/requests/sacrifices_spec.rb` to "Your savings and budget already fit".

- [ ] **Step 6: Run and commit**

Run: `bundle exec rspec spec/presenters/sacrifice_presenter_spec.rb spec/services/sacrifice_cuts_spec.rb spec/requests/sacrifices_spec.rb spec/system/sacrifices`
Expected: PASS.
```bash
bundle exec rubocop -A
git add -A app spec
git commit -m "feat/sacrifice: savings targets are their own section, cut by amount or by percent"
```

---

### Task 12: Seeds, docs, and the whole suite

**Files:**
- Modify: `db/seeds.rb`, `spec/seeds_spec.rb`, `docs/decisions.md`, `docs/coding-standards.md`, `CLAUDE.md`

- [ ] **Step 1: Seeds**

In `db/seeds.rb`:
- Header comment: "four accounts, income landing in checking, every rule shape, savings targets, transfers, and adjustments."
- `reset!`: `[Adjustment, SavingsTarget, Rule, Transfer, Entry, Item, Category, Account, User].each(&:delete_all)`.
- `create_accounts!`:
```ruby
  def create_accounts!
    @checking = Account.open(@user, name: "Checking", balance: 1_800)
    @ally = Account.open(@user, name: "Ally Savings", balance: 4_200)
    @brokerage = Account.open(@user, name: "Brokerage", balance: 12_750)
    Account.open(@user, name: "Health Savings", balance: 900)
    @brokerage.update!(keeps_extra: false)
  end
```
- Add `create_savings_targets!` to `plant` after `create_rules!`:
```ruby
  def create_savings_targets!
    @ally.savings_targets.create!(amount: 150, starts_on: @demo_start)
    @ally.savings_targets.create!(item: @paycheck, percent: 5, starts_on: @demo_start)
    @brokerage.savings_targets.create!(item: @paycheck, percent: 15, starts_on: periods_ago(4))
  end
```
- `log_biweekly_entries`: `log(@contract, 400, payday + 3, "Invoice") if cycle.even?` (no account).
- `log`: `def log(holder, amount, on, description = nil) = holder.entries.create!(amount: amount, date: on, description: description)`.
- `create_transfers_and_adjustments!`:
```ruby
  def create_transfers_and_adjustments!
    (1..13).each { |cycle| Transfer.create!(from_account: @checking, to_account: @ally, amount: 250, date: periods_ago(13 - cycle) + 1) }
    Transfer.create!(from_account: @checking, to_account: @brokerage, amount: 300, date: @today - 7)
    Adjustment.create!(source: Rule.find_by!(category: @vacation, item_id: nil), amount: 250, date: @today - 3)
    Adjustment.create!(source: Rule.find_by!(category: @dining, item_id: nil), amount: -20, date: @today - 1)
    Adjustment.create!(source: @ally, amount: -50, date: @today - 2)
  end
```
- `report`: add `#{SavingsTarget.count} savings targets`.

`spec/seeds_spec.rb`: whatever it asserts about accounts/rules, add `expect(SavingsTarget.count).to eq(3)` and remove any `account:`-based expectation.

Run: `bin/rails db:seed:replant && bundle exec rspec spec/seeds_spec.rb`
Expected: seeds plant; PASS.

- [ ] **Step 2: Docs**

`docs/decisions.md`: remove every `**(planned)**` / `**(planned: …)**` marker and the sentence "Sections marked **(planned)** are decided but not yet in code." Read each marked line once more: the sentence must still be true of the code.

`docs/coding-standards.md`: in the model list add `- **SavingsTarget** → one promise on a savings Account: a fixed amount a period, or a share of an income Item` and `- **Adjustment** → a signed delta on a Rule's or an Account's claim`; where services are listed add `SavingsCalculator` beside `ClaimCalculator` and note that `ClaimLedger#claims` is the one list every screen reads.

`CLAUDE.md`: nothing about credentials changes. Under "Browser Login Credentials" nothing changes. Add under Documentation's decisions bullet nothing new.

- [ ] **Step 3: The whole suite, then the visual check**

```bash
bundle exec rubocop
bundle exec parallel_rspec spec
```
Expected: rubocop clean; every example passes.

Then the Quick Visual Check from `CLAUDE.md`: with `bin/dev` on port 3001 (`PORT=3001 bin/dev`), log in as `demo@example.com` / `password123`, and screenshot `/savings`, `/accounts/<ally id>/edit`, `/budget`, `/sacrifice` (the demo household is underwater after these seeds only if its budget plus savings exceeds ~$2,250 a period; if it is not, note that the page redirects and screenshot the Budget tiles' verdict instead) and `/`. Check the console for errors. `rm -f *.png` afterwards.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs/savings: seeds carry targets, and the decisions file describes what is built"
```

---

## Self-Review

**Spec coverage.** §2.1 schema → Task 1. §2.2 meanings → Tasks 2, 3. §3.1 balances → Task 4. §3.2 savings claim → Task 5. §3.3 ask/budget/savings/leftover → Tasks 6, 10, 11. §3.4 claim list → Task 6. §3.5 renames → Task 6. §4 AccountForm, AdjustmentForm, EntryForm, SacrificeCuts, one-click transfer → Tasks 7, 3, 11, 8. §5 components and routes → Tasks 7, 8. §6 screens → Tasks 8, 9, 10, 11, 3. §7 migrations → Task 1. §8 testing → each task. §9 commits → the twelve commits here are finer than the spec's seven; the spec's grouping is preserved in order. §10 out of scope → nothing here builds it.

**Placeholders.** None; every code step carries its code. Two steps say "delete the examples that mention X" (Task 3 Step 4, Task 6 Step 5) with a grep to find them, which is the complete instruction.

**Type consistency.** `SavingsTarget#ask(typical_income:)` (Task 2) is what `SavingsCalculator#ask` (Task 5) and `SacrificePresenter#target_row` (Task 11) call. `ClaimLedger::Claim` fields (Task 6) are what `HomePresenter::Uncovered` (Task 10) delegates to. `AdjustmentForm.new(source:, …)` (Task 7) is what `AdjustmentsController` (Task 7) and the request spec call. `SavingsPageState#assign_savings_state` (Task 8) is what `AccountsController#create`, `TransfersController#create` and `SavingsController#show` call, and Task 7's stub of `refuse_on_savings_page` is replaced by the real one in Task 8. `Account#claim_calculator` (Task 2) is what `AdjustmentForm` calls for an account. `savings_path` exists from Task 7 on.
