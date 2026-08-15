# Periods & Home — Implementation Plan (2a of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace inferred paychecks with declared periods, and build the Home screen — the read-only view that answers "where do I stand?"

**Architecture:** Periods are a rename plus one new column; the money maths is untouched. On top of it, two pure-logic objects (`PoolStatus`, `HomePresenter`) carry every decision the Home view renders, so the view stays dumb and the logic is unit-testable. No write paths in this plan — Home only reads. Distribution, the Budget page, and the logging rework are Plans 2b–2d.

**Tech Stack:** Rails 8.1, PostgreSQL (UUID PKs, `money` columns), Tailwind CSS, RSpec, FactoryBot, Capybara.

**Spec:** `docs/superpowers/specs/2026-08-15-budgeting-ui-design.md` (§3, §4, §7.1, §10)
**Domain spec:** `docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md`

## Global Constraints

- **Work on branch `feature/envelope-budgeting`. Never run `git push`.**
- Commit messages are **single-line**, `type/scope: description`, **no `Co-Authored-By`**. Stage explicit paths, not `-A`.
- `# frozen_string_literal: true` atop every Ruby file.
- UUID primary keys; money columns `t.money "name", scale: 2`.
- **Money type:** the `money` column keeps an **Integer** for in-memory records. Never seed an accumulator with a Float `0.0` — start from `0.to_d`. An earlier bug in this codebase had `180/14` integer-dividing to `12`.
- **Never compare ids where one side may be unsaved.** FactoryBot's `use_parent_strategy` leaves associations unsaved under `build`, so `x_id` is nil while `x` holds an object. This defect class appeared **six times** in Plan 1. Compare records.
- Run `bundle exec rubocop -A` before finishing any task.
- Run spec files **one at a time**, never a directory or the full suite.
- **Tailwind:** any new utility class not already in the codebase requires `bin/rails tailwindcss:build`. New responsive variants especially.
- Colors come from `app/assets/stylesheets/custom.css` tokens — `--color-primary` `#C9C78B`, `--color-danger` `#ff3b30`, `--color-warning` `#ff9500`, `--color-success` `#34c759`, plus the gray scale. **Use `rounded`, never `rounded-lg/xl`** (`docs/design-standards.md`).
- Follow `docs/coding-standards.md`. Presenters live in `app/presenters/`, calculators in `app/services/`.
- **This plan adds no write paths.** Home is read-only.

## Deliberate gap against the spec

Spec §4.2 says every problem on Home carries a **specific, clickable fix**
("Take $300 from Rent"). This plan renders the problems and the waterfall but
**not the fix buttons**, because every fix is a reallocation — a write path, and
therefore Plan 2b.

That is a conscious deferral, not an oversight. Do not invent a fix UI here: a
button that reallocates would need `PoolMovement` creation, a consequence
preview, and a confirm step, all of which 2b builds properly. The attention list
without fixes is still useful on its own — it names what is wrong and when.

Similarly the structural-warning button (§9) has no destination until 2c builds
the sacrifice view.

## Known environmental failures — do not chase

`spec/system/pools/form_spec.rb`, one example in `spec/system/categories/show/budget_spec.rb`, and occasionally `account/show/preferences_card_spec.rb` / `items/edit/form_spec.rb` fail with `Selenium::WebDriver::Error::InvalidSessionIdError` — a Chrome renderer crash in teardown, zero assertion failures. Pre-existing and confirmed. Re-run once before concluding anything; never "fix" a spec to work around it.

---

## File Structure

**Created**

| file | responsibility |
| --- | --- |
| `app/services/pool_status.rb` | one pool → one of six display states |
| `app/presenters/home_presenter.rb` | standing figures, waterfall, attention list |
| `app/controllers/home_controller.rb` | the new root |
| `app/views/home/index.html.erb` | shell |
| `app/views/home/_standing.html.erb` | headline band |
| `app/views/home/_attention.html.erb` | problems + waterfall |
| `app/views/home/_account.html.erb` | account group with buffer |
| `app/views/home/_pool_row.html.erb` | one pool row |
| `spec/services/pool_status_spec.rb`, `spec/presenters/home_presenter_spec.rb` | unit |
| `spec/system/home/*.rb` | system, page-based |

**Modified**

| file | change |
| --- | --- |
| `app/models/user.rb` | period rename, `typical_income`, anchor validation |
| `app/models/pool.rb` | account target permitted, `status` entry point |
| `app/services/budget_calculator.rb` | call-site rename only |
| `app/services/pool_calculator.rb` | dateless-goal fulfilment |
| `app/controllers/pools_controller.rb` | `pool_params` widening |
| `config/routes.rb` | root → home, dashboard → /reports |
| `app/views/shared/_sidebar.html.erb` | nav reshuffle |

---

## Task 1: Periods replace paychecks

**Files:**
- Create: `db/migrate/<timestamp>_rename_pay_schedule_to_period.rb`
- Modify: `app/models/user.rb`, `app/services/budget_calculator.rb`, `spec/factories/users.rb`
- Rename: `spec/models/user_pay_dates_spec.rb` → `spec/models/user_period_boundaries_spec.rb`

**Interfaces:**
- Consumes: `User#pay_cadence`, `#pay_anchor_date`, `#pay_dates(from:, to:)` from Plan 1
- Produces: `User#period_cadence` (enum, prefix `:period`), `#period_anchor_date`, `#typical_income`, `#period_boundaries(from:, to:) -> Array<Date>`

- [ ] **Step 1: Write the failing test**

Rename the spec file, then rename every `pay_cadence:` → `period_cadence:`, `pay_anchor_date:` → `period_anchor_date:`, and `user.pay_dates` → `user.period_boundaries` throughout. All 16 existing examples must survive unchanged in behaviour. Then add:

```ruby
describe "#typical_income" do
  it "is optional" do
    expect(build(:user, typical_income: nil)).to be_valid
  end

  it "must be positive when set" do
    user = build(:user, typical_income: -100)

    expect(user).not_to be_valid
    expect(user.errors[:typical_income]).to include("must be greater than 0")
  end
end

describe "period configuration" do
  it "requires an anchor date when a cadence is set" do
    user = build(:user, period_cadence: :biweekly, period_anchor_date: nil)

    expect(user).not_to be_valid
    expect(user.errors[:period_anchor_date]).to include("is required when you set a period")
  end

  it "allows both to be blank" do
    expect(build(:user, period_cadence: nil, period_anchor_date: nil)).to be_valid
  end
end
```

That anchor validation is a **Plan 1 obligation** (domain spec §7a): without it `period_boundaries` returns `[]`, the `[count, 1].max` clamp reports "1 period before this bill", and the app demands the entire bill immediately.

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/models/user_period_boundaries_spec.rb`
Expected: FAIL — `unknown attribute 'period_cadence'`.

- [ ] **Step 3: Write the migration**

```ruby
# frozen_string_literal: true

class RenamePayScheduleToPeriod < ActiveRecord::Migration[8.1]
  def change
    rename_column :users, :pay_cadence, :period_cadence
    rename_column :users, :pay_anchor_date, :period_anchor_date
    add_column :users, :typical_income, :money, scale: 2
  end
end
```

Run: `rails db:migrate`

- [ ] **Step 4: Update the model**

In `app/models/user.rb`, rename the enum and the method. The enum prefix changes from `:pay` to `:period`:

```ruby
  enum :period_cadence, { weekly: 0, biweekly: 1, semimonthly: 2, monthly: 3 }, prefix: :period

  validates :typical_income, numericality: { greater_than: 0 }, allow_nil: true
  validates :period_anchor_date, presence: { message: "is required when you set a period" },
                                 if: :period_cadence

  # Every period boundary in [from, to], ascending. Empty unless a period is configured.
  # A period is DECLARED by the user — it is not inferred from income, so multiple jobs
  # and irregular pay are simply not a question here.
  def period_boundaries(from:, to:)
    # ... body unchanged from #pay_dates, with pay_anchor_date → period_anchor_date
  end
```

Rename the private helpers' references to `pay_anchor_date` and keep `STRIDE_DAYS` as-is.

- [ ] **Step 5: Update the one caller**

`app/services/budget_calculator.rb` calls `user.pay_dates` in `#periods_until_due` and `#pay_period_end`. Rename both to `period_boundaries`. **Do not change the arithmetic** — `periods_until_due` keeps `[count, 1].max`.

Also rename the private method `pay_period_end` → `period_end_date` for consistency, and update its caller in `#period_end`.

- [ ] **Step 6: Update the factory**

In `spec/factories/users.rb`, the `:biweekly` trait becomes:

```ruby
    trait :biweekly do
      period_cadence { :biweekly }
      period_anchor_date { Date.new(2026, 2, 6) }
    end
```

- [ ] **Step 7: Verify no stragglers**

Run: `grep -rn "pay_cadence\|pay_anchor_date\|pay_dates\|pay_period_end" app lib spec db/seeds.rb`
Expected: no output.

- [ ] **Step 8: Run the tests**

```bash
bundle exec rspec spec/models/user_period_boundaries_spec.rb
bundle exec rspec spec/models/user_spec.rb
bundle exec rspec spec/services/budget_calculator_spec.rb
bundle exec rspec spec/services/pool_calculator_spec.rb
```

Expected: PASS — `budget_calculator_spec` must still be 88 examples, unchanged.

- [ ] **Step 9: Lint and commit**

```bash
bundle exec rubocop -A
git add app db spec
git commit -m "refactor/users: periods replace inferred paychecks"
```

---

## Task 2: Buffer targets and dateless goals

**Files:**
- Modify: `app/models/pool.rb`, `app/services/pool_calculator.rb`, `app/controllers/pools_controller.rb`
- Test: `spec/models/pool_spec.rb`, `spec/services/pool_calculator_spec.rb`

**Interfaces:**
- Consumes: `Pool`, `PoolCalculator` from Plan 1
- Produces: `target_amount` valid on account pools; `PoolCalculator#required` returns `0` for a savings pool at or above its target; `pool_params` permits `pool_type`, `account_id`, `priority`

- [ ] **Step 1: Write the failing test**

Add to `spec/models/pool_spec.rb`:

```ruby
describe "buffer target" do
  it "allows a target on an account, as the buffer target" do
    expect(build(:pool, :account, target_amount: 2_000)).to be_valid
  end

  it "still allows an account with no target" do
    expect(build(:pool, :account, target_amount: nil)).to be_valid
  end
end
```

Add to `spec/services/pool_calculator_spec.rb`:

```ruby
describe "dateless savings goals" do
  let(:goal_user) { create(:user, :biweekly) }
  let(:account) { create(:pool, :account, user: goal_user) }
  let(:vacation) do
    create(:pool, :savings_pool, user: goal_user, account: account, target_amount: 2_400)
  end
  let(:today) { Date.new(2026, 2, 6) }

  before { create(:pool_budget, :per_paycheck_rate, pool: vacation, amount: 150) }

  it "asks for its rate while below the target" do
    create(:pool_movement, from_pool: account, to_pool: vacation, amount: 600)

    expect(vacation.calculator(today: today).required).to eq(150)
  end

  it "stops asking once the balance reaches the target" do
    create(:pool_movement, from_pool: account, to_pool: vacation, amount: 2_400)

    expect(vacation.calculator(today: today).required).to eq(0)
  end

  it "stops asking when overfunded" do
    create(:pool_movement, from_pool: account, to_pool: vacation, amount: 2_500)

    expect(vacation.calculator(today: today).required).to eq(0)
  end

  it "does not apply the cutoff to budget pools" do
    envelope = create(:pool, :budget_pool, user: goal_user, account: account, target_amount: nil)
    create(:pool_budget, :per_paycheck_rate, pool: envelope, amount: 150)

    expect(envelope.calculator(today: today).required).to eq(150)
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/services/pool_calculator_spec.rb`
Expected: FAIL — the second example returns `150`, not `0`.

- [ ] **Step 3: Permit a target on accounts**

In `app/models/pool.rb`, the presence validation currently reads `if: :pool_type_savings?`. That already permits a nil target on accounts, so **no change is needed** — confirm by running the new `pool_spec` examples. If they pass, note it in your report and move on. If a validation rejects a target on an account, remove that restriction only.

- [ ] **Step 4: Implement the goal cutoff**

In `app/services/pool_calculator.rb`:

```ruby
  # A dateless savings goal is a rate rule plus a pool target: it funds at its rate
  # until the balance reaches the target, then stops. No separate rule shape needed.
  def goal_reached?
    pool.pool_type_savings? && pool.target_amount.to_d.positive? && balance >= pool.target_amount.to_d
  end

  def required
    return 0.to_d if goal_reached?

    budgets_by_due_date.sum(0.to_d) { |budget| budget.calculator(today: today).required(allocated_balances[budget]) }
  end
```

Note the `0.to_d` seed on `sum` — without it an empty rule set returns `Integer 0`.

- [ ] **Step 5: Widen `pool_params`**

In `app/controllers/pools_controller.rb`, `pool_params` currently permits neither the type nor the parent. This is a **Plan 1 obligation** (domain spec §7a). Add `:pool_type`, `:account_id`, `:priority` to the permitted list. Do not change any other controller behaviour.

- [ ] **Step 6: Run the tests**

```bash
bundle exec rspec spec/models/pool_spec.rb
bundle exec rspec spec/services/pool_calculator_spec.rb
bundle exec rspec spec/system/pools/index/cards_spec.rb
```

Expected: PASS.

- [ ] **Step 7: Lint and commit**

```bash
bundle exec rubocop -A
git add app spec
git commit -m "feature/pools: buffer targets on accounts and dateless savings goals"
```

---

## Task 3: PoolStatus — the six-state vocabulary

The heart of the Home screen. Every row's wording, colour and auto-expand behaviour derives from this one object, so it is worth over-testing.

**Files:**
- Create: `app/services/pool_status.rb`, `spec/services/pool_status_spec.rb`
- Modify: `app/models/pool.rb`

**Interfaces:**
- Consumes: `PoolCalculator`, `BudgetCalculator`
- Produces: `Pool#status(today:) -> PoolStatus` with `#state` (`:overdrawn` `:overdue` `:wont_make_it` `:behind` `:left_to_spend` `:on_track`), `#amount`, `#balance`, `#due_on`, `#needs_attention?`

**The state rules, in precedence order.** First match wins:

| # | state | condition | `amount` means |
| --- | --- | --- | --- |
| 1 | `:overdrawn` | `balance < 0` | how far below zero |
| 2 | `:overdue` | any rule `overdue?` | the overdue rule's amount |
| 3 | `:wont_make_it` | a rule has a shortfall and **no period boundary falls before its due date** | the shortfall |
| 4 | `:behind` | allocated is below where a steady schedule would be by now | how far off schedule |
| 5 | `:left_to_spend` | the pool has **no anchored rules** | the balance |
| 6 | `:on_track` | everything else | the balance |

Precedence matters: an overdrawn pool that is also behind reads `overdrawn`, because that is the more urgent fact.

- [ ] **Step 1: Write the failing test**

Create `spec/services/pool_status_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PoolStatus, type: :model do
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6)) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:today) { Date.new(2026, 2, 6) }

  def envelope(name)
    create(:pool, :budget_pool, user: user, account: checking, name: name)
  end

  def fund(pool, amount)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: amount)
  end

  def spend(pool, amount, name: "Something")
    category = create(:category, :expense, user: user, name: "#{pool.name} spend", pool: pool)
    create(:entry, item: create(:item, category: category, name: name), amount: amount, date: today)
  end

  describe "precedence" do
    it "reports overdrawn ahead of everything else" do
      pool = envelope("Car")
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(pool, 100)
      spend(pool, 150)

      status = pool.status(today: today)

      expect(status.state).to eq(:overdrawn)
      expect(status.amount).to eq(50)
    end

    it "reports overdue ahead of behind" do
      pool = envelope("Insurance")
      item_category = create(:category, :expense, user: user, name: "Insurance spend", pool: pool)
      item = create(:item, category: item_category, name: "Insurance")
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6,
                           anchor_date: Date.new(2026, 2, 1), item: item)
      fund(pool, 600)

      status = pool.status(today: Date.new(2026, 2, 6))

      expect(status.state).to eq(:overdue)
      expect(status.due_on).to eq(Date.new(2026, 2, 1))
    end
  end

  describe ":wont_make_it" do
    it "fires when no period boundary falls before the due date" do
      pool = envelope("Dentist")
      create(:pool_budget, :one_time, pool: pool, amount: 300, anchor_date: Date.new(2026, 2, 14))

      status = pool.status(today: today)

      expect(status.state).to eq(:wont_make_it)
      expect(status.amount).to eq(300)
      expect(status.due_on).to eq(Date.new(2026, 2, 14))
    end

    it "does not fire when a period still arrives in time" do
      pool = envelope("Dentist")
      create(:pool_budget, :one_time, pool: pool, amount: 300, anchor_date: Date.new(2026, 3, 14))

      expect(pool.status(today: today).state).not_to eq(:wont_make_it)
    end

    it "does not fire once the rule is fully funded" do
      pool = envelope("Dentist")
      create(:pool_budget, :one_time, pool: pool, amount: 300, anchor_date: Date.new(2026, 2, 14))
      fund(pool, 300)

      expect(pool.status(today: today).state).not_to eq(:wont_make_it)
    end
  end

  describe ":behind" do
    # $600 due Mar 1, 6-month interval. Biweekly periods, so ~13 in a cycle.
    # Half the cycle elapsed ⇒ a steady schedule would hold ~$300.
    it "fires when the balance is below a steady schedule" do
      pool = envelope("Car")
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(pool, 20)

      status = pool.status(today: today)

      expect(status.state).to eq(:behind)
      expect(status.amount).to be > 0
    end

    it "does not fire when the balance is at or above the steady schedule" do
      pool = envelope("Car")
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(pool, 600)

      expect(pool.status(today: today).state).to eq(:on_track)
    end
  end

  describe ":left_to_spend" do
    it "fires for a pool with only rate rules" do
      pool = envelope("Groceries")
      create(:pool_budget, :per_paycheck_rate, pool: pool, amount: 400)
      fund(pool, 400)
      spend(pool, 160)

      status = pool.status(today: today)

      expect(status.state).to eq(:left_to_spend)
      expect(status.amount).to eq(240)
    end

    it "does not fire when the pool also has an anchored rule" do
      pool = envelope("Car")
      create(:pool_budget, :per_paycheck_rate, pool: pool, amount: 80)
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(pool, 600)

      expect(pool.status(today: today).state).not_to eq(:left_to_spend)
    end
  end

  describe "#needs_attention?" do
    it "is true for the three problem states", :aggregate_failures do
      [:overdrawn, :overdue, :wont_make_it, :behind].each do |state|
        expect(described_class::ATTENTION_STATES).to include(state)
      end
    end

    it "is false for on_track and left_to_spend", :aggregate_failures do
      expect(described_class::ATTENTION_STATES).not_to include(:on_track)
      expect(described_class::ATTENTION_STATES).not_to include(:left_to_spend)
    end
  end

  describe "an account pool" do
    it "reads as left_to_spend, since a buffer is always spendable" do
      status = checking.status(today: today)

      expect(status.state).to eq(:left_to_spend)
    end
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/services/pool_status_spec.rb`
Expected: FAIL — `uninitialized constant PoolStatus`.

- [ ] **Step 3: Write the class**

Create `app/services/pool_status.rb`:

```ruby
# frozen_string_literal: true

# Reduces a pool to exactly one display state. Every row's wording, colour and
# auto-expand behaviour on Home derives from here, so the precedence order below
# is the single place that decision lives.
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §4.4
class PoolStatus
  ATTENTION_STATES = [:overdrawn, :overdue, :wont_make_it, :behind].freeze

  attr_reader :pool, :today

  def initialize(pool, today: Date.current)
    @pool = pool
    @today = today
  end

  def state
    @state ||= if balance.negative?      then :overdrawn
               elsif overdue_budget      then :overdue
               elsif unreachable_budget  then :wont_make_it
               elsif behind_amount.positive? then :behind
               elsif anchored_budgets.empty? then :left_to_spend
               else :on_track
               end
  end

  def amount
    case state
    when :overdrawn     then -balance
    when :overdue       then overdue_budget.amount.to_d
    when :wont_make_it  then shortfall_for(unreachable_budget)
    when :behind        then behind_amount
    else balance
    end
  end

  def due_on
    case state
    when :overdue      then calculator_for(overdue_budget).due_date
    when :wont_make_it then calculator_for(unreachable_budget).due_date
    else next_due_date
    end
  end

  def balance = @balance ||= pool.calculator(today: today).balance

  def needs_attention? = ATTENTION_STATES.include?(state)

  private

  def pool_calculator = @pool_calculator ||= pool.calculator(today: today)

  def calculator_for(budget) = budget.calculator(today: today)

  def anchored_budgets
    @anchored_budgets ||= pool.budgets.select { |b| b.anchor_date.present? }
  end

  def overdue_budget
    return @overdue_budget if defined?(@overdue_budget)

    @overdue_budget = anchored_budgets.find { |b| calculator_for(b).overdue? }
  end

  # A rule nothing can save: it still has a shortfall and no period boundary
  # falls between today and its due date, so no future funding can reach it.
  def unreachable_budget
    return @unreachable_budget if defined?(@unreachable_budget)

    @unreachable_budget = anchored_budgets.find do |budget|
      calc = calculator_for(budget)
      next false unless shortfall_for(budget).positive?

      pool.user.period_boundaries(from: today + 1, to: calc.due_date).empty?
    end
  end

  def shortfall_for(budget)
    calculator_for(budget).shortfall(pool_calculator.allocated_balances[budget] || 0.to_d)
  end

  # How far below a steady schedule this pool is. A rule with N periods in its
  # full cycle and R remaining should hold amount * (N - R) / N by now.
  def behind_amount
    @behind_amount ||= anchored_budgets.sum(0.to_d) do |budget|
      calc = calculator_for(budget)
      total = periods_in_cycle(budget)
      next 0.to_d unless total.positive?

      remaining = calc.periods_until_due
      expected = budget.amount.to_d * [total - remaining, 0].max / total
      allocated = pool_calculator.allocated_balances[budget] || 0.to_d
      [expected - allocated, 0.to_d].max
    end
  end

  def periods_in_cycle(budget)
    return 0 if budget.interval_months.blank?

    calc = calculator_for(budget)
    pool.user.period_boundaries(from: calc.due_date - budget.interval_months.months, to: calc.due_date).count
  end

  def next_due_date
    anchored_budgets.map { |b| calculator_for(b).due_date }.min
  end
end
```

- [ ] **Step 4: Add the entry point**

In `app/models/pool.rb`:

```ruby
  def status(today: Date.current)
    PoolStatus.new(self, today: today)
  end
```

- [ ] **Step 5: Run the tests**

Run: `bundle exec rspec spec/services/pool_status_spec.rb`
Expected: PASS.

**If `:behind` fires where you expect `:on_track`**, check `periods_in_cycle` — a one-time rule has `interval_months` nil and must contribute `0`, not blow up.

- [ ] **Step 6: Mutation-check the precedence**

The precedence order is the whole point of this class, and a test suite can pass while the order is wrong. For each of the four `ATTENTION_STATES`, move its branch one position later in the `state` chain, re-run, and record how many examples fail. **Any mutation that kills zero examples means the precedence is untested at that position — add the example rather than leaving it.** Record the table in your report.

- [ ] **Step 7: Lint and commit**

```bash
bundle exec rubocop -A
git add app spec
git commit -m "feature/pools: added pool status vocabulary for the home screen"
```

---

## Task 4: HomePresenter

**Files:**
- Create: `app/presenters/home_presenter.rb`, `spec/presenters/home_presenter_spec.rb`

**Interfaces:**
- Consumes: `PoolStatus`, `PoolCalculator`, `User#typical_income`
- Produces: `HomePresenter.new(user:, today:)` with `#accounts`, `#pools_for(account)`, `#buffer_for(account)`, `#total_required`, `#available`, `#shortfall`, `#covered?`, `#attention_pools`, `#waterfall`, `#structurally_underwater?`, **`#status_for(pool)`**

- [ ] **Step 1: Write the failing test**

Create `spec/presenters/home_presenter_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe HomePresenter do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6), typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking", target_amount: 2_000) }
  let(:today) { Date.new(2026, 2, 6) }
  let(:presenter) { described_class.new(user: user, today: today) }

  def envelope(name, priority:)
    create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
  end

  describe "#available" do
    it "is the account's unclaimed cash" do
      income_category = create(:category, :income, user: user, pool: checking)
      create(:entry, item: create(:item, category: income_category), amount: 2_400, date: today)

      expect(presenter.available).to eq(2_400)
    end
  end

  describe "#total_required" do
    it "sums what every pool needs this period" do
      groceries = envelope("Groceries", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: groceries, amount: 400)
      gas = envelope("Gas", priority: 2)
      create(:pool_budget, :per_paycheck_rate, pool: gas, amount: 80)

      expect(presenter.total_required).to eq(480)
    end
  end

  describe "#waterfall" do
    before do
      rent = envelope("Rent", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: rent, amount: 500)
      food = envelope("Groceries", priority: 2)
      create(:pool_budget, :per_paycheck_rate, pool: food, amount: 400)
      vacation = envelope("Vacation", priority: 3)
      create(:pool_budget, :per_paycheck_rate, pool: vacation, amount: 150)

      income_category = create(:category, :income, user: user, pool: checking)
      create(:entry, item: create(:item, category: income_category), amount: 700, date: today)
    end

    it "fills top-down by priority and marks the cutoff", :aggregate_failures do
      rows = presenter.waterfall

      expect(rows.map { |r| r[:pool].name }).to eq(%w[Rent Groceries Vacation])
      expect(rows[0][:funded]).to eq(500)
      expect(rows[1][:funded]).to eq(200)
      expect(rows[2][:funded]).to eq(0)
    end

    it "records each row's shortfall", :aggregate_failures do
      rows = presenter.waterfall

      expect(rows[0][:short]).to eq(0)
      expect(rows[1][:short]).to eq(200)
      expect(rows[2][:short]).to eq(150)
    end

    it "reports the total gap" do
      expect(presenter.shortfall).to eq(350)
      expect(presenter).not_to be_covered
    end
  end

  describe "#covered?" do
    it "is true when available meets the requirement" do
      groceries = envelope("Groceries", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: groceries, amount: 100)
      income_category = create(:category, :income, user: user, pool: checking)
      create(:entry, item: create(:item, category: income_category), amount: 500, date: today)

      expect(presenter).to be_covered
      expect(presenter.shortfall).to eq(0)
    end
  end

  describe "#attention_pools" do
    it "returns only pools whose status needs attention" do
      quiet = envelope("Groceries", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: quiet, amount: 100)
      create(:pool_movement, from_pool: checking, to_pool: quiet, amount: 100)

      loud = envelope("Dentist", priority: 2)
      create(:pool_budget, :one_time, pool: loud, amount: 300, anchor_date: Date.new(2026, 2, 14))

      expect(presenter.attention_pools.map(&:name)).to eq(["Dentist"])
    end
  end

  describe "#structurally_underwater?" do
    it "is true when the rules need more than typical income" do
      big = envelope("Rent", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: big, amount: 3_000)

      expect(presenter).to be_structurally_underwater
    end

    it "is false when they fit" do
      small = envelope("Rent", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: small, amount: 500)

      expect(presenter).not_to be_structurally_underwater
    end

    it "is false when typical income is unset" do
      user.update!(typical_income: nil)
      big = envelope("Rent", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: big, amount: 3_000)

      expect(presenter).not_to be_structurally_underwater
    end
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/presenters/home_presenter_spec.rb`
Expected: FAIL — `uninitialized constant HomePresenter`.

- [ ] **Step 3: Write the presenter**

Create `app/presenters/home_presenter.rb`:

```ruby
# frozen_string_literal: true

# Everything the Home screen renders. Read-only: this plan adds no write paths.
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §4
class HomePresenter
  attr_reader :user, :today

  def initialize(user:, today: Date.current)
    @user = user
    @today = today
  end

  def accounts
    @accounts ||= user.pools.accounts.order(:name).to_a
  end

  def pools_for(account)
    all_pools.select { |pool| pool.account_id == account.id }.sort_by { |p| [p.priority, p.name] }
  end

  def buffer_for(account) = account.calculator(today: today).balance

  # Unclaimed cash across every account — what a distribution has to work with.
  def available
    @available ||= accounts.sum(0.to_d) { |account| buffer_for(account) }
  end

  def total_required
    @total_required ||= all_pools.sum(0.to_d) { |pool| pool.calculator(today: today).required }
  end

  def shortfall = [total_required - available, 0.to_d].max

  def covered? = shortfall.zero?

  # Views MUST use this rather than calling pool.status directly. PoolStatus defaults
  # to Date.current, so a bare call in a partial would compute against a different day
  # than this presenter whenever `today` is injected — and disagree silently.
  def status_for(pool)
    @statuses ||= {}
    @statuses[pool.id] ||= pool.status(today: today)
  end

  def attention_pools
    all_pools.select { |pool| status_for(pool).needs_attention? }
  end

  # Fills top-down by priority, exactly as a distribution would, so the user sees
  # who gets paid first and where the money ran out.
  def waterfall
    remaining = available
    all_pools.sort_by { |p| [p.priority, p.name] }.map do |pool|
      needed = pool.calculator(today: today).required
      funded = remaining.clamp(0.to_d, needed)
      remaining -= funded
      { pool: pool, needed: needed, funded: funded, short: needed - funded }
    end
  end

  def structurally_underwater?
    user.typical_income.present? && total_required > user.typical_income.to_d
  end

  private

  def all_pools
    @all_pools ||= user.pools.where.not(pool_type: :account).includes(:budgets).to_a
  end
end
```

- [ ] **Step 4: Run the tests**

Run: `bundle exec rspec spec/presenters/home_presenter_spec.rb`
Expected: PASS.

- [ ] **Step 5: Mutation-check the waterfall**

Change `sort_by { [p.priority, p.name] }` to `sort_by(&:priority)` alone and re-run. **Ties on priority are then resolved by database order, which is non-deterministic** — the identical defect found in Plan 1's allocation waterfall, where UUID ids decided which envelope got funded. If no example fails, add one with two pools at the same priority. Record the result.

- [ ] **Step 6: Lint and commit**

```bash
bundle exec rubocop -A
git add app spec
git commit -m "feature/home: added home presenter for standing and waterfall"
```

---

## Task 5: Routes, controller, navigation

**Files:**
- Create: `app/controllers/home_controller.rb`, `app/views/home/index.html.erb`
- Modify: `config/routes.rb`, `app/views/shared/_sidebar.html.erb`
- Test: `spec/system/home/navigation_spec.rb`

**Interfaces:**
- Consumes: `HomePresenter`
- Produces: `root` → `home#index`; `/reports` → `dashboard#index`; sidebar order Home · Entries · Categories · Calendar · Reports

- [ ] **Step 1: Write the failing test**

Create `spec/system/home/navigation_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home Navigation", type: :system do
  let(:user) { create(:user, :biweekly) }

  before { sign_in user }

  it "lands on Home at the root" do
    visit root_path

    expect(page).to have_css("h1", text: "Home")
  end

  it "keeps the dashboard reachable as Reports" do
    visit reports_path

    expect(page).to have_css("h1", text: "Reports")
  end

  it "lists Reports in the sidebar" do
    visit root_path

    expect(page).to have_link("Reports", href: reports_path)
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/system/home/navigation_spec.rb`
Expected: FAIL — `undefined local variable or method 'reports_path'`.

- [ ] **Step 3: Update routes**

In `config/routes.rb`, inside the `authenticated :user` block:

```ruby
  authenticated :user do
    root "home#index", as: :authenticated_root
  end

  get "reports", to: "dashboard#index", as: :reports
```

Leave the unauthenticated `root "pages#home"` at the bottom untouched.

**`DashboardPresenter` and every dashboard view stay exactly as they are** — this is a relocation, not a rework.

- [ ] **Step 4: Write the controller**

```ruby
# frozen_string_literal: true

class HomeController < ApplicationController
  include DateContext

  def index
    @presenter = HomePresenter.new(user: current_user, today: Date.current)
  end
end
```

Check whether `DateContext` is needed — if `Date.current` suffices, omit the include rather than carrying an unused concern.

- [ ] **Step 5: Write the shell view**

`app/views/home/index.html.erb`:

```erb
<%= page_header(title: "Home", subtitle: "Where your money stands") %>

<div class="space-y-6">
  <%= render "standing", presenter: @presenter %>
  <%= render "attention", presenter: @presenter %>
  <% @presenter.accounts.each do |account| %>
    <%= render "account", presenter: @presenter, account: account %>
  <% end %>
</div>
```

Create the three partials as empty placeholders for now — Tasks 6 and 7 fill them. An empty partial keeps this task's test green without pretending the screen is done.

- [ ] **Step 6: Update the sidebar**

In `app/views/shared/_sidebar.html.erb`, the nav arrays become:

```ruby
{ name: "Home", path: root_path, icon: "home" },
{ name: "Entries", path: entries_path, icon: "document-text" }
```
```ruby
{ name: "Categories", path: categories_path, icon: "tag" },
{ name: "Pools", path: pools_path, icon: "wallet" }
```
```ruby
{ name: "Reports", path: reports_path, icon: "chart-bar" },
{ name: "Calendar", path: calendar_path, icon: "calendar" }
```

Note "Savings Pools" becomes "Pools" — the first user-facing copy change on this branch, and it is now correct rather than premature.

- [ ] **Step 7: Run the tests**

```bash
bundle exec rspec spec/system/home/navigation_spec.rb
bundle exec rspec spec/system/navbar_spec.rb
bundle exec rspec spec/system/dashboard/index/tabs_spec.rb
```

Expected: PASS. **Dashboard specs that visit `root_path` now land on Home and will fail** — update them to visit `reports_path`. That is a required change, not a workaround; list every file you touch in your report.

- [ ] **Step 8: Lint and commit**

```bash
bundle exec rubocop -A
git add app config spec
git commit -m "feature/home: home is now the root, dashboard becomes reports"
```

---

## Task 6: The standing and attention bands

**Files:**
- Modify: `app/views/home/_standing.html.erb`, `app/views/home/_attention.html.erb`
- Test: `spec/system/home/standing_spec.rb`, `spec/system/home/attention_spec.rb`

**Interfaces:**
- Consumes: `HomePresenter#covered?`, `#shortfall`, `#total_required`, `#available`, `#attention_pools`, `#waterfall`, `#structurally_underwater?`

- [ ] **Step 1: Write the failing test**

Create `spec/system/home/standing_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home Standing", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before { sign_in user }

  def envelope(name, amount, priority: 1)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    create(:pool_budget, :per_paycheck_rate, pool: pool, amount: amount)
    pool
  end

  def deposit(amount)
    category = create(:category, :income, user: user, pool: checking)
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  it "says you're covered when the money is there", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(1_000)

    visit root_path

    expect(page).to have_content("You're covered")
    expect(page).to have_content("$600.00")
  end

  it "states the gap when you're short", :aggregate_failures do
    envelope("Groceries", 400)
    deposit(150)

    visit root_path

    expect(page).to have_content("$250.00 short")
    expect(page).to have_content("You need $400.00")
    expect(page).to have_content("You have $150.00")
  end

  it "shows the structural warning only when rules exceed typical income" do
    envelope("Rent", 3_000)

    visit root_path

    expect(page).to have_link("Your budget doesn't fit your income")
  end

  it "hides the structural warning when the budget fits" do
    envelope("Groceries", 400)

    visit root_path

    expect(page).to have_no_link("Your budget doesn't fit your income")
  end
end
```

Create `spec/system/home/attention_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home Attention", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before { sign_in user }

  it "lists a pool that can't be funded in time", :aggregate_failures do
    dentist = create(:pool, :budget_pool, user: user, account: checking, name: "Dentist", priority: 1)
    create(:pool_budget, :one_time, pool: dentist, amount: 300, anchor_date: Date.current + 3.days)

    visit root_path

    expect(page).to have_content("Dentist")
    expect(page).to have_content("won't make it")
  end

  it "says nothing needs you when every pool is quiet" do
    groceries = create(:pool, :budget_pool, user: user, account: checking, name: "Groceries", priority: 1)
    create(:pool_budget, :per_paycheck_rate, pool: groceries, amount: 400)
    create(:pool_movement, from_pool: checking, to_pool: groceries, amount: 400)

    visit root_path

    expect(page).to have_content("Nothing needs you")
  end

  it "shows the waterfall with a cutoff when short", :aggregate_failures do
    %w[Rent Groceries].each_with_index do |name, i|
      pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: i + 1)
      create(:pool_budget, :per_paycheck_rate, pool: pool, amount: 500)
    end
    category = create(:category, :income, user: user, pool: checking)
    create(:entry, item: create(:item, category: category), amount: 700, date: Date.current)

    visit root_path

    expect(page).to have_content("Where your money went")
    expect(page).to have_content("ran out here")
  end
end
```

- [ ] **Step 2: Run them and confirm they fail**

```bash
bundle exec rspec spec/system/home/standing_spec.rb
bundle exec rspec spec/system/home/attention_spec.rb
```

Expected: FAIL — the partials are empty.

- [ ] **Step 3: Write the standing partial**

`app/views/home/_standing.html.erb`:

```erb
<div class="bg-white border border-gray-200 rounded p-6">
  <% if presenter.covered? %>
    <h2 class="text-2xl font-semibold text-gray-900">You're covered</h2>
    <p class="mt-2 text-sm text-gray-600">
      <%= number_to_currency(presenter.available - presenter.total_required) %> stays in your buffer.
    </p>
  <% else %>
    <h2 class="text-2xl font-semibold text-status-danger">
      <%= number_to_currency(presenter.shortfall) %> short this period
    </h2>
    <p class="mt-2 text-sm text-gray-600">
      You need <strong><%= number_to_currency(presenter.total_required) %></strong> to stay on schedule.
      You have <strong><%= number_to_currency(presenter.available) %></strong>.
    </p>
  <% end %>

  <% if presenter.structurally_underwater? %>
    <%= link_to "Your budget doesn't fit your income", "#",
                class: "mt-4 inline-flex items-center gap-2 px-4 py-2 rounded border border-status-danger text-status-danger text-sm font-medium" %>
  <% end %>
</div>
```

The structural link points at `"#"` deliberately — the sacrifice view is Plan 2c. **Leave it as a dead link rather than inventing a destination**, and note it in your report.

Check `custom.css` for the exact status-colour class names before using `text-status-danger` — if the codebase spells them differently, match the codebase.

- [ ] **Step 4: Write the attention partial**

`app/views/home/_attention.html.erb`:

```erb
<div class="bg-white border border-gray-200 rounded">
  <div class="px-6 py-4 border-b border-gray-200">
    <h3 class="text-sm font-semibold text-gray-900">
      <% if presenter.attention_pools.any? %>
        <%= pluralize(presenter.attention_pools.size, "thing") %> need<%= "s" if presenter.attention_pools.one? %> you
      <% else %>
        Nothing needs you
      <% end %>
    </h3>
  </div>

  <% presenter.attention_pools.each do |pool| %>
    <% status = presenter.status_for(pool) %>
    <div class="px-6 py-3 border-b border-gray-100">
      <div class="flex justify-between items-baseline">
        <span class="font-medium text-gray-900"><%= pool.name %></span>
        <span class="text-sm text-status-danger"><%= pool_status_label(status) %></span>
      </div>
    </div>
  <% end %>

  <% unless presenter.covered? %>
    <div class="px-6 py-4 border-t border-gray-200">
      <p class="text-xs uppercase tracking-wide text-gray-500 mb-2">Where your money went</p>
      <% shown_cutoff = false %>
      <% presenter.waterfall.each do |row| %>
        <% if row[:short].positive? && !shown_cutoff %>
          <% shown_cutoff = true %>
          <div class="border-t-2 border-dashed border-status-danger my-2 pt-2 text-sm text-status-danger font-medium">
            — ran out here —
          </div>
        <% end %>
        <div class="flex justify-between text-sm py-1">
          <span><%= row[:pool].name %></span>
          <span><%= number_to_currency(row[:funded]) %> of <%= number_to_currency(row[:needed]) %></span>
        </div>
      <% end %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 5: Add the label helper**

In `app/helpers/application_helper.rb` — **not** `pools_helper.rb`. This app has not
set `include_all_helpers = false`, so either would resolve today, but the label is
used by Home views rather than Pools views and putting it in `ApplicationHelper`
removes the dependency on that setting entirely.

```ruby
  # Wording for each PoolStatus state. See the UI design spec §4.4.
  def pool_status_label(status)
    case status.state
    when :overdrawn    then "overdrawn #{number_to_currency(status.amount)}"
    when :overdue      then "overdue · was #{l(status.due_on, format: :short)}"
    when :wont_make_it then "won't make it · #{l(status.due_on, format: :short)}"
    when :behind       then "behind #{number_to_currency(status.amount)}"
    when :left_to_spend then "#{number_to_currency(status.amount)} left"
    else "#{number_to_currency(status.amount)} · on track"
    end
  end
```

Verify `l(date, format: :short)` is configured in this app's locale; if not, use `status.due_on.strftime("%b %-d")`.

- [ ] **Step 6: Rebuild Tailwind and run the tests**

```bash
bin/rails tailwindcss:build
bundle exec rspec spec/system/home/standing_spec.rb
bundle exec rspec spec/system/home/attention_spec.rb
```

Expected: PASS.

- [ ] **Step 7: Lint and commit**

```bash
bundle exec rubocop -A
git add app spec
git commit -m "feature/home: added standing headline and attention bands"
```

---

## Task 7: The pools band

**Files:**
- Modify: `app/views/home/_account.html.erb`, `app/views/home/_pool_row.html.erb`
- Test: `spec/system/home/pools_spec.rb`

**Interfaces:**
- Consumes: `HomePresenter#pools_for`, `#buffer_for`, `PoolStatus`, `pool_status_label`

- [ ] **Step 1: Write the failing test**

Create `spec/system/home/pools_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home Pools", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking", target_amount: 2_000) }

  before { sign_in user }

  it "groups pools under their account and shows the buffer", :aggregate_failures do
    pool = create(:pool, :budget_pool, user: user, account: checking, name: "Groceries", priority: 1)
    create(:pool_budget, :per_paycheck_rate, pool: pool, amount: 400)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: 400)

    visit root_path

    expect(page).to have_content("Checking")
    expect(page).to have_content("Groceries")
    expect(page).to have_content("$400.00 left")
  end

  it "shows a balance on an on-track pool" do
    pool = create(:pool, :budget_pool, user: user, account: checking, name: "Rent", priority: 1)
    create(:pool_budget, pool: pool, amount: 2_000, interval_months: 1,
                         anchor_date: Date.current + 2.months)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: 2_000)

    visit root_path

    expect(page).to have_content("on track")
  end

  it "auto-expands a pool that needs attention", :aggregate_failures do
    dentist = create(:pool, :budget_pool, user: user, account: checking, name: "Dentist", priority: 1)
    create(:pool_budget, :one_time, pool: dentist, amount: 300, anchor_date: Date.current + 3.days)

    visit root_path

    row = find("[data-pool-name='Dentist']")
    expect(row["data-expanded"]).to eq("true")
    expect(row).to have_content("won't make it")
  end

  it "leaves a quiet pool collapsed" do
    pool = create(:pool, :budget_pool, user: user, account: checking, name: "Groceries", priority: 1)
    create(:pool_budget, :per_paycheck_rate, pool: pool, amount: 400)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: 400)

    visit root_path

    expect(find("[data-pool-name='Groceries']")["data-expanded"]).to eq("false")
  end
end
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bundle exec rspec spec/system/home/pools_spec.rb`
Expected: FAIL — the partials are empty.

- [ ] **Step 3: Write the account partial**

`app/views/home/_account.html.erb`:

```erb
<div class="bg-white border border-gray-200 rounded">
  <div class="px-6 py-3 border-b border-gray-200 flex justify-between items-baseline">
    <span class="text-xs uppercase tracking-wide text-gray-500"><%= account.name %></span>
    <span class="text-sm text-gray-700">
      buffer <strong><%= number_to_currency(presenter.buffer_for(account)) %></strong>
      <% if account.target_amount.present? %>
        <span class="text-gray-400">of <%= number_to_currency(account.target_amount) %></span>
      <% end %>
    </span>
  </div>

  <% presenter.pools_for(account).each do |pool| %>
    <%= render "pool_row", pool: pool, presenter: presenter %>
  <% end %>
</div>
```

- [ ] **Step 4: Write the pool row**

`app/views/home/_pool_row.html.erb`:

```erb
<% status = presenter.status_for(pool) %>
<div class="px-6 py-3 border-b border-gray-100 last:border-b-0"
     data-pool-name="<%= pool.name %>"
     data-expanded="<%= status.needs_attention? %>">
  <div class="flex justify-between items-baseline">
    <span class="font-medium text-gray-900"><%= pool.name %></span>
    <span class="text-sm <%= status.needs_attention? ? 'text-status-danger font-medium' : 'text-gray-500' %>">
      <%= pool_status_label(status) %>
      <% if status.due_on.present? && !status.needs_attention? %>
        · <%= status.due_on.strftime("%b %-d") %>
      <% end %>
    </span>
  </div>

  <% if status.needs_attention? %>
    <div class="mt-2 pl-4 space-y-1">
      <% pool.budgets.select { |b| b.anchor_date.present? }.each do |budget| %>
        <div class="flex justify-between text-xs text-gray-600">
          <span><%= budget.item&.name || "Rule" %></span>
          <span><%= number_to_currency(budget.amount) %> · <%= budget.calculator.due_date.strftime("%b %-d") %></span>
        </div>
      <% end %>
    </div>
  <% end %>
</div>
```

**`data-expanded` is the auto-expand rule** (spec §4.3) — anything needing attention opens itself, so trouble is never hidden behind a chevron. This plan renders both states server-side; the click-to-toggle interaction is Plan 2b.

- [ ] **Step 5: Rebuild Tailwind and run the tests**

```bash
bin/rails tailwindcss:build
bundle exec rspec spec/system/home/pools_spec.rb
```

Expected: PASS.

- [ ] **Step 6: Run the full regression set, one file at a time**

```bash
bundle exec rspec spec/system/home/navigation_spec.rb
bundle exec rspec spec/system/home/standing_spec.rb
bundle exec rspec spec/system/home/attention_spec.rb
bundle exec rspec spec/services/pool_status_spec.rb
bundle exec rspec spec/presenters/home_presenter_spec.rb
bundle exec rspec spec/services/budget_calculator_spec.rb
bundle exec rspec spec/services/pool_calculator_spec.rb
bundle exec rspec spec/models/pool_spec.rb
bundle exec rspec spec/models/user_spec.rb
```

Expected: PASS. Then `bin/rails db:seed:replant` must complete.

- [ ] **Step 7: Visual check**

`CLAUDE.md` mandates this after any front-end change, and it was skipped in Plan 1. Using the `agent-browser` skill and the credentials in `CLAUDE.md` (`demo@example.com` / `password123`):

1. Seed a user with a period, a typical income, an account with a target, and at least one pool in each of the six states.
2. Visit `/` at 1440px. Screenshot.
3. Verify: the headline matches the data; problem rows are visibly louder than quiet ones; auto-expanded rows are the ones needing attention; the waterfall cutoff appears only when short.
4. Check the browser console for JavaScript errors.
5. `rm -f *.png` when done.

Report what you saw, not just that you looked.

- [ ] **Step 8: Lint and commit**

```bash
bundle exec rubocop -A
git add app spec
git commit -m "feature/home: added pools band grouped by account"
```

---

## Plan 2a Done

Home answers "where do I stand?" and the app opens to it. Nothing writes yet.

**Plan 2b** builds the distribution screen, the sweep materialisation, and reallocation — the first write paths.
**Plan 2c** builds the Budget rules page, priority ordering, the suggestion engine, and the sacrifice view that the structural link currently points nowhere at.
**Plan 2d** reworks logging, the Categories page, and demotes the Reports charts.
