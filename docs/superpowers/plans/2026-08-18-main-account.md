# Main Account Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The main account becomes the source all money flows from: the ledger's start-date rule sends pre-envelope history there, income routes through it, and onboarding trues every account up to its real bank balance.

**Architecture:** One SQL expression (`PoolBalanceLedger::ENTRY_POOL_ID`) changes meaning and every reader moves with it; two small controllers put account funding and the one-time correction on Home; the entry form gains an income-destination picker whose write is an ordinary linked movement.

**Tech Stack:** Rails 8.1, PostgreSQL (money columns, UUID PKs), RSpec/Capybara/FactoryBot, simple_form, Tailwind.

**Spec:** `docs/superpowers/specs/2026-08-18-main-account-design.md` — read it first; every task argues from it.

## Global Constraints

- `Σ pools == bank truth` (per user, to the cent) must hold after every task; assert it with raw SQL in the specs that touch money location.
- One reader per question: `ENTRY_POOL_ID` is the ONLY spelling of "which pool does an entry reach"; every consumer takes the constant, never a restatement. The new joins ship as a sibling constant consumed the same way.
- The cutover migration (`db/migrate/20260817000000_cutover_to_envelope_budgeting.rb`) is FROZEN: it ran, its verifier speaks the pre-rule law and is internally consistent. Do not edit it beyond the one header comment Task 1 adds. `spec/migrations/cutover_spec.rb` must stay green untouched.
- Commit style: single line, `type/scope: description`, no Co-Authored-By, stage explicit paths (never `git add -A`). Never push. Never merge to main.
- Run spec files ONE at a time (`bundle exec rspec path`); `pgrep -f "[r]spec spec/system"` before any system run. `bin/ci` does NOT run RSpec — never cite it as test evidence.
- `Date.current` never inside `travel_to` via a lazy `let` (CLAUDE.md:147). Pool factory's `start_date` is `1.year.ago.to_date` — specs planting PRE-start entries must set `start_date` explicitly, not rely on the factory.
- Money assertions against planted literals; both directions on every rule (the entry that lands AND the entry that does not).
- `bundle exec rubocop -A` clean on every touched file before each commit. New Tailwind classes → `bin/rails tailwindcss:build`.

---

### Task 1: The start-date rule in the one reader

**Files:**
- Modify: `app/services/pool_balance_ledger.rb:81` (the constant + new sibling), `:232` (`totals` joins)
- Modify: `app/services/pool_calculator.rb:657-658` (`entries_for_pool`)
- Modify: `app/models/entry.rb:40-51` (`in_pool_named` scope)
- Modify: `app/services/suggestion_engine.rb:~575-585` (the grouped read)
- Modify: `app/views/pools/_form.html.erb` (start_date hint copy) and `db/migrate/20260817000000_cutover_to_envelope_budgeting.rb` (ONE header comment line noting its verifier speaks the pre-rule law — no code)
- Test: `spec/services/pool_balance_ledger_spec.rb` (extend), new `spec/services/start_date_rule_spec.rb`

**Interfaces:**
- Produces: `PoolBalanceLedger::ENTRY_POOL_ID` (Arel, new meaning) and `PoolBalanceLedger::ENTRY_POOL_JOINS` (frozen Array of two SQL join strings). Contract: any query reading `ENTRY_POOL_ID` MUST also `.joins(*PoolBalanceLedger::ENTRY_POOL_JOINS)` (after the existing `joins(item: :category)`).

- [ ] **Step 1: Write the failing spec** — `spec/services/start_date_rule_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# THE START-DATE RULE (main-account spec §3): an envelope or goal only counts category
# spending dated on or after the pool's start_date; earlier entries read against the user's
# main account. The envelope's date governs — never the category's connection date.
RSpec.describe "The start-date rule" do
  let(:user) { create(:user) }
  let(:main) { create(:pool, :account, user: user, name: "Main") }
  let(:envelope) do
    create(:pool, :budget_pool, user: user, account: main, name: "Food",
                                start_date: Date.new(2026, 8, 1))
  end
  let(:category) { create(:category, :expense, user: user, pool: envelope, name: "Food") }
  let(:item) { create(:item, category: category) }

  before { user.update!(default_account: main) }

  def balance(pool)
    PoolCalculator.new(pool).balance
  end

  it "sends pre-start spending to the main account, post-start to the envelope",
     :aggregate_failures do
    create(:entry, item: item, amount: 100, date: Date.new(2026, 7, 31)) # before
    create(:entry, item: item, amount: 40,  date: Date.new(2026, 8, 1))  # on the day

    expect(balance(envelope)).to eq(-40)
    expect(balance(main)).to eq(-100)
  end

  it "leaves the override lane above the rule: a pinned entry lands where it is pinned" do
    create(:entry, item: item, amount: 25, date: Date.new(2026, 7, 1), pool: envelope)

    expect(balance(envelope)).to eq(-25)
  end

  it "exempts account pools: a category on the main account has no date gate" do
    on_main = create(:category, :expense, user: user, pool: main, name: "Misc")
    create(:entry, item: create(:item, category: on_main), amount: 10,
                   date: Date.new(2020, 1, 1))

    expect(balance(main)).to eq(-10)
  end

  it "still sends a pool-less category's entries to no pool at all" do
    # Planted past the model: the required belongs_to would refuse this shape.
    loose = build(:category, :expense, user: user, pool: nil, name: "Loose")
    loose.save!(validate: false)
    create(:entry, item: create(:item, category: loose), amount: 5, date: Date.current)

    expect(balance(main)).to eq(0)
    expect(balance(envelope)).to eq(0)
  end

  it "keeps Σ pools == bank truth while relocating, by raw SQL on both sides" do
    create(:entry, item: item, amount: 100, date: Date.new(2026, 7, 31))
    create(:entry, item: item, amount: 40,  date: Date.new(2026, 8, 2))
    income = create(:category, :income, user: user, pool: main, name: "Pay")
    create(:entry, item: create(:item, category: income), amount: 500, date: Date.current)

    pool_side = user.pools.sum { |p| PoolCalculator.new(p).balance }
    bank_side = ActiveRecord::Base.connection.select_value(<<~SQL)
      SELECT SUM(CASE WHEN c.category_type = 1 THEN e.amount::numeric
                      ELSE -e.amount::numeric END)
      FROM entries e
      JOIN items i ON i.id = e.item_id
      JOIN categories c ON c.id = i.category_id
      WHERE c.user_id = '#{user.id}'
    SQL
    expect(pool_side).to eq(bank_side)
  end
end
```

- [ ] **Step 2: Run it** — `bundle exec rspec spec/services/start_date_rule_spec.rb`. Expected: the first example FAILS (both entries land in the envelope, −140), proving the rule does not exist yet.

- [ ] **Step 3: Change the constant** in `app/services/pool_balance_ledger.rb` (replacing line 81; keep the existing narrative comment and extend it with the rule):

```ruby
  # WHICH POOL AN ENTRY REACHES — the one expression, THE START-DATE RULE included
  # (main-account spec §3). In order: the entry's own pool override; else its category's pool,
  # but an envelope/goal only from its start_date onward — earlier entries fall to the user's
  # MAIN account (users.default_account_id), because that is where history physically happened.
  # Account pools have no date gate, and a pool-less category still reaches no pool: NULL,
  # never the main-account fallback, which is reserved for history displaced by a start date.
  ENTRY_POOL_ID = Arel.sql(<<~SQL.squish)
    COALESCE(
      entries.pool_id,
      CASE
        WHEN categories.pool_id IS NULL THEN NULL
        WHEN category_pools.pool_type = 0 THEN categories.pool_id
        WHEN entries.date >= category_pools.start_date THEN categories.pool_id
        ELSE category_users.default_account_id
      END
    )
  SQL

  # The two joins ENTRY_POOL_ID now needs beside the `item: :category` join every caller
  # already carries. ALIASED — `Entry.in_pool_named` joins bare `pools` itself, and a second
  # bare `pools` would be ambiguous. Every consumer of the constant consumes these with it.
  ENTRY_POOL_JOINS = [
    "LEFT JOIN pools AS category_pools ON category_pools.id = categories.pool_id",
    "INNER JOIN users AS category_users ON category_users.id = categories.user_id"
  ].freeze
```

- [ ] **Step 4: Move every consumer with it** (grep first: `grep -rn "ENTRY_POOL_ID" app/ | grep -v '#'` — the list must be exactly these four when you finish):
  - `pool_balance_ledger.rb` `totals` (line ~232): the entry-lane scopes gain `.joins(*ENTRY_POOL_JOINS)` before the `.where`. Movement-lane terms are untouched.
  - `pool_calculator.rb:657` `entries_for_pool`: add `.joins(item: :category).joins(*PoolBalanceLedger::ENTRY_POOL_JOINS)` ahead of the where (check what joins the method already carries and add only what is missing).
  - `entry.rb` `in_pool_named`: add `.joins(*PoolBalanceLedger::ENTRY_POOL_JOINS)` between the existing two joins.
  - `suggestion_engine.rb:581`: same addition on the scope feeding the `.group`.

- [ ] **Step 5: Run the new spec** — all five examples green.

- [ ] **Step 6: Flip the two sentences that now lie.** `app/views/pools/_form.html.erb`: the start_date hint reads "Where a savings goal's timeline begins. It does not filter the balance." → "When this pool starts counting its categories' spending. Earlier entries stay with your main account." Cutover migration header: append one comment line — "NOTE (2026-08-18): the app's ledger has since adopted the start-date rule (main-account spec §3); this migration's verifier deliberately speaks the pre-rule COALESCE and remains internally consistent."

- [ ] **Step 7: Collateral, one file at a time, in this order** — `spec/services/pool_balance_ledger_spec.rb`, `spec/services/pool_calculator_spec.rb`, `spec/seeds_spec.rb`, `spec/migrations/cutover_spec.rb`, `spec/system/home/pools_spec.rb`, `spec/system/pools/show/connected_categories_spec.rb`, `spec/system/budget_page/suggestions_spec.rb`. The factory's year-old `start_date` should keep most green; any failure is either a fixture whose entries predate its pool (fix the fixture's dates and say so) or a real regression (stop and fix the code). Report which.

- [ ] **Step 8: Commit** — `git add` the six files + new spec; `feat/main-account: the start-date rule — pre-envelope history reads against main`.

---

### Task 2: Guards — first account is main; categories point only at main or envelopes

**Files:**
- Modify: `app/controllers/bank_accounts_controller.rb` (auto-main), `app/models/category.rb` (validator), `app/models/user.rb` (nothing — `default_account_is_own_account` already guards type/ownership)
- Test: `spec/requests/bank_accounts_spec.rb` (extend), `spec/models/category_spec.rb` (extend)

**Interfaces:**
- Consumes: `users.default_account_id` (`User#default_account`, optional belongs_to), `Category#pool_must_belong_to_user` (the sibling validator to sit beside).
- Produces: `Category#pool_must_be_reachable` — categories on a NON-MAIN account are refused; categories on envelopes/goals require the user to have a main account (the ledger's ELSE arm reads it).

- [ ] **Step 1: Failing specs.** In `spec/requests/bank_accounts_spec.rb` add:

```ruby
    it "makes the first account the main account, and only the first", :aggregate_failures do
      user.update!(default_account: nil)
      post bank_accounts_path, params: { bank_account: { name: "First" } }
      expect(user.reload.default_account.name).to eq("First")

      post bank_accounts_path, params: { bank_account: { name: "Second" } }
      expect(user.reload.default_account.name).to eq("First")
    end
```

  In `spec/models/category_spec.rb` add (inside the validations describe):

```ruby
    describe "pool reachability (main-account spec §6)" do
      let(:main)  { create(:pool, :account, user: user, name: "Main") }
      let(:other) { create(:pool, :account, user: user, name: "Ally") }

      before { user.update!(default_account: main) }

      it "accepts the main account and refuses any other account", :aggregate_failures do
        expect(build(:category, user: user, pool: main)).to be_valid
        refused = build(:category, user: user, pool: other)
        expect(refused).not_to be_valid
        expect(refused.errors[:pool]).to include("must be your main account or an envelope inside one")
      end

      it "refuses an envelope when the user has no main account to anchor its history" do
        envelope = create(:pool, :budget_pool, user: user, account: main)
        user.update!(default_account: nil)
        expect(build(:category, user: user, pool: envelope)).not_to be_valid
      end
    end
```

- [ ] **Step 2: Run both files** — new examples FAIL (no auto-main, no validator).

- [ ] **Step 3: Implement.** `BankAccountsController#create`, success branch, before redirect:

```ruby
      # The FIRST account a user creates is their main account (spec §2) — the place income
      # lands and displaced history reads against. Later accounts never steal the role;
      # changing main is a deliberate future affordance, not a side effect of adding a bank.
      current_user.update!(default_account: pool) if current_user.default_account.blank?
```

  `app/models/category.rb`, beside `pool_must_belong_to_user`:

```ruby
  validate :pool_must_be_reachable

  # MAIN-ACCOUNT SPEC §6: non-main accounts hold money via movements only — no categories, so
  # no entries can ever land in them and their balance mirrors the real bank statement. And a
  # category on an envelope needs the user to HAVE a main account, because the start-date
  # rule's ELSE arm sends the envelope's pre-start history to users.default_account_id — a
  # NULL there silently drops those entries from Σ.
  def pool_must_be_reachable
    return if pool.blank? || user.blank?

    if pool.pool_type_account?
      return if pool == user.default_account
      errors.add(:pool, "must be your main account or an envelope inside one")
    elsif user.default_account.blank?
      errors.add(:pool, "needs a main account first — history before the envelope starts has nowhere to go")
    end
  end
```

- [ ] **Step 4: Run both files green**, then the factory-collateral sweep: `spec/models/category_spec.rb`, `spec/models/entry_spec.rb`, `spec/seeds_spec.rb`, `spec/migrations/cutover_spec.rb` (its planted legacy shapes bypass validations — must stay 49/49), and any factory fallout: if `create(:category, pool: <account>)` fixtures across the suite now fail, the factory's user must set `default_account` — check `spec/factories/users.rb`/`pools.rb` and wire the account trait to set it (`after(:create) { |p| p.user.update!(default_account: p) if p.pool_type_account? && p.user.default_account.blank? }` on the `:account` trait), then re-run the four files above. Report what the trait change touched.

- [ ] **Step 5: Commit** — `feat/main-account: first account becomes main, and categories may only point at it or an envelope`.

---

### Task 3: Income routing — record where income lands; main mirrors it out

**Files:**
- Modify: `app/models/entry.rb` (routing sync), `app/controllers/entries_controller.rb` (permit + call), `app/views/entries/_form.html.erb` (destination select)
- Test: `spec/requests/entries_routing_spec.rb` (new), `spec/system/entries/new/routing_spec.rb` (new)

**Interfaces:**
- Consumes: `Entry has_many :pool_movements, foreign_key: :source_entry_id, dependent: :destroy`; `PoolMovement` kinds `{ transfer: 0, allocation: 1, sweep: 2 }` — a ROUTING movement is `kind_transfer` + `source_entry` present (allocation/sweep movements also carry `source_entry`; kind disambiguates). Cross-account movements are legal at the model (refused only on the `:reallocation` context — `pool_movement.rb:43`).
- Produces: `Entry#route_income_to!(account_or_nil)` — idempotent sync of the one routing movement.

- [ ] **Step 1: Failing request spec** — `spec/requests/entries_routing_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# INCOME ROUTING (main-account spec §4): the entry always lands in main; choosing another
# account writes ONE mirroring movement main → account, linked by source_entry_id so edits
# and deletes find it. Expenses never route.
RSpec.describe "Entries income routing", type: :request do
  let(:user) { create(:user) }
  let(:main) { create(:pool, :account, user: user, name: "Main") }
  let(:ally) { create(:pool, :account, user: user, name: "Ally") }
  let(:income) { create(:category, :income, user: user, pool: main, name: "Pay") }
  let(:pay_item) { create(:item, category: income, name: "Paycheck") }

  before do
    user.update!(default_account: main)
    sign_in user, scope: :user
  end

  def routing_for(entry) = entry.pool_movements.kind_transfer

  it "writes the linked movement when income lands elsewhere", :aggregate_failures do
    post entries_path, params: { entry: { item_id: pay_item.id, amount: 500,
                                          date: Date.current.iso8601,
                                          destination_account_id: ally.id } }
    entry = Entry.order(:created_at).last
    movement = routing_for(entry).sole
    expect(movement.from_pool).to eq(main)
    expect(movement.to_pool).to eq(ally)
    expect(movement.amount).to eq(500)
  end

  it "writes no movement when income lands in main, and removes one on re-route",
     :aggregate_failures do
    post entries_path, params: { entry: { item_id: pay_item.id, amount: 500,
                                          date: Date.current.iso8601,
                                          destination_account_id: ally.id } }
    entry = Entry.order(:created_at).last
    patch entry_path(entry), params: { entry: { destination_account_id: main.id } }
    expect(routing_for(entry)).to be_empty
  end

  it "keeps the movement in step with an amount edit" do
    post entries_path, params: { entry: { item_id: pay_item.id, amount: 500,
                                          date: Date.current.iso8601,
                                          destination_account_id: ally.id } }
    entry = Entry.order(:created_at).last
    patch entry_path(entry), params: { entry: { amount: 750 } }
    expect(routing_for(entry).sole.amount).to eq(750)
  end

  it "refuses to route to an account that is not the user's" do
    foreign = create(:pool, :account, user: create(:user))
    post entries_path, params: { entry: { item_id: pay_item.id, amount: 500,
                                          date: Date.current.iso8601,
                                          destination_account_id: foreign.id } }
    expect(response).to have_http_status(:not_found)
  end
end
```

  (Adjust the POST param shape to whatever `entries/_form` actually submits — read `EntriesController#entry_params` first; `destination_account_id` is a NEW virtual param, never a column.)

- [ ] **Step 2: Run it — FAILS** (unknown param, no movement).

- [ ] **Step 3: Implement.** `app/models/entry.rb`:

```ruby
  # INCOME ROUTING (main-account spec §4). The entry itself always lands in main — this method
  # writes the MIRROR: one `transfer` movement main → account, carrying this entry as
  # source_entry so an edit or delete finds it (`dependent: :destroy` already covers delete).
  # Idempotent: re-routing replaces, routing to main removes. Expenses and nil route nothing.
  def route_income_to!(account)
    routing = pool_movements.kind_transfer
    return routing.destroy_all if account.blank? || account == item.category.user.default_account

    main = item.category.user.default_account
    routing.destroy_all
    pool_movements.create!(from_pool: main, to_pool: account, amount: amount,
                           date: date, kind: :transfer)
  end
```

  `EntriesController`: permit `:destination_account_id` (virtual — pop it out of `entry_params` before mass assignment), and after a successful save of an INCOME entry:

```ruby
      destination = params[:entry][:destination_account_id]
      if destination.present? && @entry.item.category.income?
        @entry.route_income_to!(current_user.pools.pool_type_account.find(destination))
      elsif @entry.item.category.income?
        @entry.route_income_to!(nil)
      end
```

  (`current_user.pools....find` 404s the foreign account — same scoping law as `categories_controller.rb`. Check the enum predicate name on Category: `income?` vs `category_type_income?` — use what the model defines.)

  `entries/_form`: a `Lands in` select of `current_user.pools.pool_type_account`, default main, rendered with the same show-when-income mechanics the impact card already uses (`/entries/impact` swaps on category change — read `app/views/entries/_impact.html.erb`'s wiring and mirror the smallest working version; if conditional rendering costs more than a day, render it always with a "(income only)" hint and note that in the report).

- [ ] **Step 4: Request spec green, then the system spec** — `spec/system/entries/new/routing_spec.rb`: one example driving the form (create income entry, choose Ally, assert Ally's Home section gains the amount and main shows the pass-through), one asserting an expense entry shows no destination select (or inert hint, per the branch taken). Follow `spec/system/entries/` house patterns.

- [ ] **Step 5: Collateral** — `spec/system/entries/new/form_spec.rb` (or nearest existing entries form spec; `ls spec/system/entries/`), `spec/requests/entries_spec.rb` if present, `spec/models/entry_spec.rb`.

- [ ] **Step 6: Commit** — `feat/main-account: income names its account and main mirrors it out`.

---

### Task 4: Onboarding step 2 — fund each account with its real balance

**Files:**
- Create: `app/controllers/account_fundings_controller.rb`, `app/views/home/_fund_account.html.erb`
- Modify: `config/routes.rb` (`resources :account_fundings, only: [:create]`), `app/views/home/_account.html.erb` (render the card inside empty non-main account sections)
- Test: `spec/requests/account_fundings_spec.rb`, extend `spec/system/home/new_account_spec.rb`

**Interfaces:**
- Consumes: `current_user.default_account` (Task 2 guarantees it after first account), cross-account `PoolMovement` legality, `HomePresenter#pools_for(account)`.
- Produces: POST `/account_fundings` with `account_funding: { account_id:, amount: }` → one `transfer` movement main → account.

- [ ] **Step 1: Failing request spec:**

```ruby
# frozen_string_literal: true

require "rails_helper"

# ONBOARDING STEP 2 (main-account spec §5): each non-main account is funded with its real
# balance by ONE movement from main — mirroring the transfers that really happened.
RSpec.describe "AccountFundings", type: :request do
  let(:user) { create(:user) }
  let(:main) { create(:pool, :account, user: user, name: "Main") }
  let(:ally) { create(:pool, :account, user: user, name: "Ally") }

  before do
    user.update!(default_account: main)
    sign_in user, scope: :user
  end

  it "moves the entered balance from main to the account", :aggregate_failures do
    post account_fundings_path,
         params: { account_funding: { account_id: ally.id, amount: 1200.50 } }

    movement = PoolMovement.order(:created_at).last
    expect(movement.from_pool).to eq(main)
    expect(movement.to_pool).to eq(ally)
    expect(movement.amount).to eq(1200.50)
    expect(movement).to be_kind_transfer
    expect(response).to redirect_to(root_path)
  end

  it "refuses funding main from itself and a foreign account", :aggregate_failures do
    post account_fundings_path,
         params: { account_funding: { account_id: main.id, amount: 10 } }
    expect(response).to have_http_status(:unprocessable_content)

    foreign = create(:pool, :account, user: create(:user))
    post account_fundings_path,
         params: { account_funding: { account_id: foreign.id, amount: 10 } }
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 2: FAIL** (no route). **Step 3: Implement:**

```ruby
# frozen_string_literal: true

# ONBOARDING STEP 2 (main-account spec §5): give a fresh account its real balance, as the
# ONE movement from main that mirrors the transfers that really happened over the years.
# A movement, not an entry: this money is not income — it already existed; it is being told
# where it lives. Inherits HomeController for the same reason BankAccountsController does:
# failure re-renders home/index.
class AccountFundingsController < HomeController
  # POST /account_fundings
  def create
    account = current_user.pools.pool_type_account.find(funding_params[:account_id])
    movement = PoolMovement.new(from_pool: current_user.default_account, to_pool: account,
                                amount: funding_params[:amount], date: Date.current,
                                kind: :transfer)

    if movement.save
      redirect_to root_path, notice: "#{account.name} funded with #{helpers.number_to_currency(movement.amount)}."
    else
      @presenter = HomePresenter.new(user: current_user, today: Date.current)
      @new_bank_account = Pool.new(user: current_user, pool_type: :account)
      flash.now[:alert] = movement.errors.full_messages.to_sentence
      render "home/index", status: :unprocessable_content
    end
  end

  private

  def funding_params
    params.expect(account_funding: [:account_id, :amount])
  end
end
```

  (Funding main-from-main fails `pools_must_differ` → the 422 branch. The card — `home/_fund_account.html.erb` — mirrors `_new_account`'s section chrome: one `simple_form_for :account_funding, url: account_fundings_path` with a hidden `account_id`, an `amount` input labeled "Real balance today", hint "One transfer from #{main.name} — match your bank statement." Render it inside `_account.html.erb` when `account != presenter.user.default_account && presenter.pools_for(account).empty? && buffer.zero?` — an unfunded, empty, non-main account is the onboarding state.)

- [ ] **Step 4: Green; system coverage** — extend `spec/system/home/new_account_spec.rb` with one example: create account via card, fund it via the new card, assert its section shows the amount and the card disappears. **Step 5: collateral** — the five `spec/system/home/*` files, one at a time. **Step 6: Commit** — `feat/main-account: onboarding funds each account with its real balance from main`.

---

### Task 5: Onboarding step 3 — the one-time main correction

**Files:**
- Create: `app/controllers/opening_balances_controller.rb`, `app/views/home/_opening_balance.html.erb`
- Modify: `config/routes.rb` (`resource :opening_balance, only: [:create]`), `app/views/home/_account.html.erb` (render under the MAIN account while no "Opening Balance" category exists)
- Test: `spec/requests/opening_balances_spec.rb`

**Interfaces:**
- Consumes: `PoolCalculator.new(main).balance` (main's current app figure), Task 2's guarantee that main exists.
- Produces: one auto-created "Opening Balance" category (+item +entry) recording `actual − app` in main; the card renders only while that category is absent (`current_user.categories.exists?(name: "Opening Balance")` is the one-time latch).

- [ ] **Step 1: Failing request spec:**

```ruby
# frozen_string_literal: true

require "rails_helper"

# ONBOARDING STEP 3 (main-account spec §5): after the other accounts are funded, main is
# wrong by exactly the untracked history. ONE ordinary entry in an auto-created
# "Opening Balance" category sets it to the real bank number — income-type when the
# correction raises main, expense-type when it lowers it. One-time by construction.
RSpec.describe "OpeningBalances", type: :request do
  let(:user) { create(:user) }
  let(:main) { create(:pool, :account, user: user, name: "Main") }

  before do
    user.update!(default_account: main)
    sign_in user, scope: :user
  end

  def app_balance = PoolCalculator.new(main.reload).balance

  it "raises main to the entered figure with an income-type correction", :aggregate_failures do
    income = create(:category, :income, user: user, pool: main, name: "Pay")
    create(:entry, item: create(:item, category: income), amount: 300, date: Date.current)

    post opening_balance_path, params: { opening_balance: { actual: 1000 } }

    expect(app_balance).to eq(1000)
    correction = user.categories.find_by(name: "Opening Balance")
    expect(correction).to be_income
    expect(correction.pool).to eq(main)
  end

  it "lowers main with an expense-type correction when the app holds too much" do
    income = create(:category, :income, user: user, pool: main, name: "Pay")
    create(:entry, item: create(:item, category: income), amount: 300, date: Date.current)

    post opening_balance_path, params: { opening_balance: { actual: 120 } }

    expect(app_balance).to eq(120)
    expect(user.categories.find_by(name: "Opening Balance")).to be_expense
  end

  it "refuses a second correction" do
    post opening_balance_path, params: { opening_balance: { actual: 100 } }
    post opening_balance_path, params: { opening_balance: { actual: 999 } }

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include("already")
    expect(app_balance).to eq(100)
  end
end
```

  (`be_income`/`be_expense` — use the Category enum's real predicates; check the model. A zero difference: write nothing, redirect with "already matches" notice — add that as a fourth example if the three above leave the branch uncovered.)

- [ ] **Step 2: FAIL.** **Step 3: Implement** `OpeningBalancesController < HomeController`: latch check first (`redirect_to root_path, alert: "Opening balance was already recorded." if current_user.categories.exists?(name: "Opening Balance")`); compute `difference = BigDecimal(params...[:actual]) - PoolCalculator.new(current_user.default_account).balance`; zero → notice, done; else inside ONE transaction create the category (`category_type: difference.positive? ? :income : :expense`, `pool: current_user.default_account`, `name: "Opening Balance"`), an item ("Initial balance"), and the entry (`amount: difference.abs, date: Date.current`). The card: amount input labeled "Main's real balance today", hint "Recorded once, as an ordinary entry you can see in your history." — rendered only for the main account and only while the latch is open.

- [ ] **Step 4: Green + collateral** (`spec/system/home/*` five files). **Step 5: Commit** — `feat/main-account: the one-time correction sets main to the real bank number`.

---

### Task 6: The period on Home

**Files:**
- Modify: `app/views/home/_standing.html.erb` (or wherever the standing band's heading renders — read it first), `app/presenters/home_presenter.rb` (expose the period range if not already there)
- Test: extend `spec/system/home/standing_spec.rb`

**Interfaces:**
- Consumes: the user's period readers (`period_cadence`, `period_anchor_date` — find the existing period-window calculator; `grep -rn "period_anchor_date" app/presenters app/services | head` and reuse ITS window, never a re-derivation).

- [ ] **Step 1: Failing spec** — in `spec/system/home/standing_spec.rb`, a user with `period_cadence: :biweekly, period_anchor_date: Date.new(2026, 8, 14)` visiting Home on a frozen date inside that period sees the range: `expect(page).to have_content("Aug 14 – Aug 27")` (match the app's existing date format — grep how the Budget page prints period dates and reuse that helper/format verbatim).
- [ ] **Step 2: FAIL.** **Step 3:** render the range in the standing band beside its existing sentence, from the presenter, using the same period-window reader the Budget page trusts. A user with NO declared period shows nothing new (assert that direction too).
- [ ] **Step 4: Green; run** `spec/system/home/standing_spec.rb` whole file. **Step 5: Commit** — `feat/main-account: home names the period it is talking about`.

---

### Task 7: Live verification on Ming + docs closure

**Files:**
- Modify: `docs/superpowers/specs/2026-08-18-main-account-design.md` (status → DELIVERED, note any drift), `docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md` (leaves-open: note the start-date rule supersedes the "pin history" idea if it is mentioned; add nothing else)
- No code except what verification forces.

- [ ] **Step 1:** `pgrep` quiet; run one-at-a-time: `spec/services/start_date_rule_spec.rb`, `spec/requests/bank_accounts_spec.rb`, `spec/requests/entries_routing_spec.rb`, `spec/requests/account_fundings_spec.rb`, `spec/requests/opening_balances_spec.rb`, `spec/seeds_spec.rb`, `spec/migrations/cutover_spec.rb`, and the five `spec/system/home/*` files. All green or stop.
- [ ] **Step 2:** Browser (dev server on :3000, login `mingguan0809@gmail.com` / `password123` — local copy only): Home shows Food & Grocery envelope NOT overdrawn (its $46,739.63 history reads against Checking under the rule — this is the bug that started the spec, verified healed on the data that surfaced it); the period renders; screenshot per CLAUDE.md's Quick Visual Check, then `rm -f *.png`.
- [ ] **Step 3:** Confirm Ming's `default_account_id` is set (it is, per the pre-plan check — re-verify) and Σ holds on her data by the raw SQL from Task 1's spec, adapted to psql.
- [ ] **Step 4:** Docs edits above; commit `docs/main-account: delivered — the rule verified on the data that demanded it`.

---

## Self-review (done at write time)

- **Spec coverage:** §3 → Task 1; §2/§6 → Task 2; §4 → Task 3; §5 steps 2–3 → Tasks 4–5; §8 → the per-task specs; period-on-Home (user request riding this plan) → Task 6; Ming heal + DELIVERED → Task 7. §6's "buffer stays a concept" needs no task (nothing changes).
- **Placeholders:** none; every code step carries real code. Two deliberate implementer-checks (entry form param shape, Category enum predicates) name exactly what to read first.
- **Type consistency:** `ENTRY_POOL_JOINS` consumed via `.joins(*...)` in Tasks 1; `route_income_to!` defined and consumed in Task 3; `account_funding`/`opening_balance` param keys match their controllers' `params.expect`.
