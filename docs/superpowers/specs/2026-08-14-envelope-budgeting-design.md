# Envelope Budgeting — Design

**Date:** 2026-08-14
**Status:** **DELIVERED.** Plans 1, 2a–2d and 3 are shipped; the cutover (Plan 3, migration
`20260817000000_cutover_to_envelope_budgeting`) is complete, and the app this document describes
is the only app there is. No legacy shape survives in code or in data: every dollar sits in
exactly one pool, every category names its lane, and `Σ pools == the user's bank balance` is
verified in SQL by the migration itself before any screen displays it. §6 and §6.1 are marked
EXECUTED below; §7a's Plan-3 list is annotated item by item. What remains open is listed in §7
(out of scope) and in the two follow-ups §7a names at the end.

## 1. Motivation

The app currently **tracks** finances: you record what happened and compare it
against a monthly cap. It does not **budget** them. A `Budget` is a soft target
you can exceed without consequence, and nothing in the system anticipates a bill
that arrives every six months.

This design converts the app to paycheck-to-paycheck envelope budgeting. The
governing principle: **every dollar you own sits in exactly one pool, and a pool
only contains money because something is coming.** Money is allocated the moment
income arrives, not reconciled at month end. Overspending is possible but
immediately visible and immediately expensive.

The user's mental model is physical: pools are bank accounts and sub-accounts,
and allocation is moving money between them. The schema mirrors that literally.

## 2. Core model

Four things can happen to money, and only two record types are needed:

| event | record | net worth |
| --- | --- | --- |
| income arrives | `Entry` (income category) | changes |
| money moves between your own pools | `PoolMovement` | unchanged |
| you spend | `Entry` (expense category) | changes |
| you reallocate / sweep | `PoolMovement` | unchanged |

`Entry` means "money crossed the boundary with the outside world."
`PoolMovement` means "I moved my own money." Keeping them separate means every
existing spending query stays correct without learning to filter out plumbing.

### 2.1 Pool types

- **`account`** — a real bank account. Receives income, holds unallocated cash,
  acts as the buffer. Has no budgets and no priority. Its `account_id` is `nil`.
- **`budget`** — an envelope for anticipated spending. Has budgets (funding
  rules) and a priority. Belongs to an account.
- **`savings`** — a goal. Same mechanics as `budget`, but **never sweeps**;
  savings accumulate by definition. Belongs to an account.

### 2.2 The balance formula

Because income categories point at an account exactly the way expense categories
point at a pool, there is one formula and no special case:

```ruby
pool.balance =
    entries in my income categories      # money in from the world
  + movements where to_pool   = me       # transferred in
  - movements where from_pool = me       # transferred out
  - entries in my expense categories     # money out to the world

account.total = account.balance + account.pools.sum(&:balance)
```

`account.balance` is unallocated cash. `account.total` is what the bank says.
A mismatch is a genuine signal that something is unrecorded.

### 2.3 Why not reuse `Entry` for movements

Rejected during design. Modelling a transfer as a negative entry plus a positive
entry leaves two rows with no column joining them: deleting one destroys or
invents money, editing one lets them disagree, and a paycheck split becomes
twelve unlinked rows with no atomic undo. `PoolMovement` is that pair normalized
onto a single row — `from_pool_id` is the negative half, `to_pool_id` the
positive half.

It also avoids: a plumbing Category + Item per pool, relaxing
`Entry#amount > 0` (relied on by `top_items`, breakdown builders, and chart
sums), and flooding the calendar with ~12 phantom entries every payday.

## 3. Schema

```ruby
# RENAMED: savings_pools -> pools
create_table "pools", id: :uuid do |t|
  t.uuid    "user_id",       null: false
  t.uuid    "account_id"                             # nullable; nil <=> pool_type: account
  t.string  "name",          null: false
  t.integer "pool_type",     null: false, default: 1 # account:0 | budget:1 | savings:2
  t.integer "priority",      null: false, default: 0 # funding order (was: position)
  t.money   "target_amount", scale: 2                # savings only
  t.date    "start_date"
  t.timestamps
end
add_foreign_key "pools", "pools", column: "account_id"

# MOVED: budgets hang off pools, not categories
create_table "budgets", id: :uuid do |t|
  t.uuid    "pool_id",         null: false   # was category_id
  t.money   "amount",          null: false, scale: 2
  t.integer "interval_months"                # nullable — see 3.1
  t.date    "anchor_date"                    # nullable — see 3.1
  t.integer "basis",           null: false, default: 0  # monthly:0 | per_period:1
  t.uuid    "item_id"                        # nullable — attribution link
  t.timestamps
end
# DROPPED: budgets.prorated (paced against a cap; there is no cap anymore)

# NEW
create_table "pool_movements", id: :uuid do |t|
  t.uuid     "from_pool_id",    null: false
  t.uuid     "to_pool_id",      null: false
  t.money    "amount",          null: false, scale: 2
  t.datetime "date",            null: false
  t.uuid     "source_entry_id"                # nullable — groups a paycheck split
  t.timestamps
end

# CHANGED
categories.savings_pool_id -> pool_id   # AS BUILT: required. See decision 3 below.
categories.category_type                # drops :savings — now expense | income only
entries + pool_id :uuid                 # nullable override; falls back to category's pool
users   + pay_cadence :integer          # weekly | biweekly | semimonthly | monthly
        + pay_anchor_date :date
        + default_account_id :uuid      # -> pools; receives income when none given

# UNTOUCHED
items
```

**AS BUILT — three schema corrections (Plan 3, task 6).** The block above is the design; these
are the differences the implementation settled on, recorded here rather than left for a reader to
discover from `db/schema.rb`.

1. **`categories.pool_id` is REQUIRED, and "nil => the user's default account" is deleted.**
   That fallback was a promise nothing kept: `PoolBalanceLedger::ENTRY_POOL_ID` resolves an entry
   through `COALESCE(entries.pool_id, categories.pool_id)` with no default account anywhere, so a
   pool-less category's spending reached NOTHING while `Σ pools == bank truth` claimed otherwise —
   measured on the demo at $3,949 of income that had silently left the tree. The cutover points
   every nil at the user's default account and verifies it; `Category belongs_to :pool` (no
   `optional:`) is what stops one coming back. The column is still nullable at the database — the
   remaining tightening, named at the end of §7a.
2. **`pools` carries `CHECK ((pool_type = 0) = (account_id IS NULL))`**, which is §3.2's first two
   rules at the database. NOT NULL cannot express it: an account's `account_id` must be nil by the
   same rule that makes an envelope's mandatory.
3. **`pools` carries `UNIQUE (user_id, lower(name))`** — functional, matching the model's
   case-insensitive uniqueness, because an index on the raw column would accept a pair the model
   refuses. `budgets.category_id` and `budgets.prorated` are DROPPED
   (`20260817020000_drop_cap_era_budget_columns`); `entries.pool_id` STAYS — it is the documented
   override lane in `ENTRY_POOL_ID`'s `COALESCE`.

### 3.1 The four budget shapes

`anchor_date`, `interval_months`, and `basis` combine into exactly four valid
shapes. Everything else is a validation error.

| anchor_date | interval_months | basis | meaning |
| --- | --- | --- | --- |
| nil | nil | per_period | rate rule, resets each pay period — *"$300/paycheck for gas & other"* |
| nil | 1 | monthly | rate rule, resets each month — *"$600/mo groceries"* |
| set | N | monthly | recurring obligation — *"$800 every 6 months, next Jun 1"* |
| set | nil | monthly | one-time obligation or savings goal — never rolls |

A savings goal needs no separate math: it is the fourth shape, with
`amount = target_amount` and `anchor_date = deadline`.

### 3.2 Validations

**`Pool`**
- `pool_type: account` → `account_id` must be nil; no budgets; `priority` unused
- `pool_type: budget | savings` → `account_id` required, must reference a pool
  of type `account` belonging to the same user
- `name` unique per user
- `User#default_account` must reference a pool of `pool_type: account` owned by
  that user; it is the resolution target when a category or entry names no pool

**`Budget`**
- must match one of the four shapes in 3.1
- `basis: per_period` → `anchor_date` and `interval_months` must both be nil
- `item` must belong to a category linked to this budget's pool
- an item may be claimed by at most one budget
- pool must not be `pool_type: account`

**`Category`**
- `pool` must belong to the same user
- `category_type: income` → pool must be `pool_type: account`

**`PoolMovement`**
- `from_pool` and `to_pool` must differ and belong to the same user
- `amount` positive

## 4. Calculators

Follows the existing `app/services/` calculator pattern.

```
BudgetCalculator       # per rule  — due_date, shortfall, periods, required
PoolCalculator         # per pool  — balance, allocated_balances, free_amount, required
AllocationCalculator   # sweep + compute + fill -> a proposed split (no writes)
AllocationCommitter    # proposed split -> PoolMovements, one transaction
User#pay_dates         # cadence + anchor -> dates in a range
```

`PoolCalculator` replaces `SavingsPoolCalculator`. Its `progress_percentage`,
`remaining_amount`, and `target_amount` logic survives essentially unchanged and
now applies to budget pools too.

### 4.1 The requirement formula

```ruby
shortfall = target - allocated_balance
periods   = user.pay_dates(from: Date.current, to: due_date).count
required  = [shortfall / [periods, 1].max, 0].max
```

`periods == 0` (the bill lands before the next paycheck) clamps to 1, so
`required == shortfall`. Brutal, correct, and surfaced in red.

### 4.2 Resolving `due_date`

The cycle rolls when the bill is **paid**, not when the date passes. Rolling by
date would silently reset an unpaid obligation and lose track of money owed.

```ruby
def due_date
  return period_end if anchor_date.nil?              # rate rule
  return anchor_date if interval_months.nil?         # one-time / goal
  anchor_date + (cycles_completed * interval_months).months
end

def cycles_completed
  return elapsed_cycles if item.nil?                 # unattributed: assume paid on time
  item.entries.where(date: anchor_date..).count      # attributed: count real payments
end

# whole intervals between the anchor and today — how many times the bill has
# come due, regardless of whether it was recorded
def elapsed_cycles
  months_between(anchor_date, Date.current) / interval_months
end

def overdue? = item.present? && due_date < Date.current
```

`period_end` is the end of the rule's current period: the end of the pay period
for `basis: per_period`, the end of the calendar month for `basis: monthly`.
It is also the boundary that decides whether the pool's period has closed — a pool
sweeps as a whole, never rule by rule (see 5.2).

Deriving from entry count rather than mutating `anchor_date` matches how the
rest of the app works (`SavingsPoolCalculator` derives everything) and
self-heals when an entry is deleted or re-dated.

**The attribution ladder** — chosen per rule, all three are legitimate:

1. **Rate rule** (no anchor, no item) — no fulfillment concept. Right for
   groceries and gas.
2. **Anchored, no item** — accumulates to a date, rolls automatically. Pure
   preparedness.
3. **Anchored + item** — rolls only when an entry lands on that item, and can go
   `overdue?`. Full lifecycle: accumulating → funded → paid → reset.

### 4.3 Splitting a pool's balance across its rules

A pool has one balance and many rules. **Earliest due date fills first** — the
money you need soonest is the money that must actually be there.

```ruby
def allocated_balances
  remaining = pool.balance
  budgets.sort_by(&:due_date).index_with do |budget|
    taken = remaining.clamp(0, budget.amount)
    remaining -= taken
    taken
  end
end

def free_amount = [remaining_after_all_rules, 0].max
```

A negative pool balance gives every rule `0` and reads as deficit.

`PoolCalculator#required` is `budgets.sum(&:required)`.

### 4.4 Worked example

Pool "Car" (priority 3, in Checking), balance **$580**. Biweekly pay; today
Feb 6; next paydays Feb 20, Mar 6.

| rule | amount | interval | due | gets from balance | shortfall | periods | required |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Gas & other | $80 | rate | Feb 28 | $80 | $0 | 2 | $0 |
| Insurance | $600 | 6mo | Mar 1 | $500 | $100 | 2 | $50.00 |
| Registration | $180 | 12mo | Aug 15 | $0 | $180 | 14 | $12.86 |
| | | | | *$0 free* | | | **$62.86** |

Now log **$420 on item "New tires"** — no rule claims it, so it falls to the
catch-all and eats into the insurance reserve. Balance drops to $160:

| rule | gets | shortfall | periods | required |
| --- | --- | --- | --- | --- |
| Gas & other | $80 | $0 | 2 | $0 |
| Insurance | $80 | $520 | 2 | **$260.00** |
| Registration | $0 | $180 | 14 | $12.86 |

The pool's ask jumps from $63 to $273 with no configuration. One unexpected
expense, and the consequence appears in dollars on the next allocation screen.

## 5. The paycheck flow

There are no percentages anywhere. A savings goal with a deadline computes
`required` like any bill, and an open-ended goal is a `per_period` rule — so
savings pools sit in the same priority list as budget pools. One mechanism.

### 5.1 Five steps

```
1. SWEEP     each budget pool whose rate period has ended returns its leftover
             to the account — its balance, less what live dated rules hold
2. COMPUTE   required for every pool
3. FILL      top-down by priority until cash runs out
4. REPORT    funded / short, plus real bank transfers needed
5. CONFIRM   creates PoolMovements in one transaction
```

**Available cash is the account's balance, not the income amount:**

```
buffer carried from last period    +$382.43
income Feb 20                    +$2,400.00
swept back from closed envelopes    +$85.00
                                 ──────────
available                        $2,867.43
```

Two independent ways a paycheck gets squeezed, both visible:
- **account is low** — you spent straight from it, or last period left nothing
- **a pool went negative** — its shortfall grew, so its `required` is higher

### 5.2 Sweeping

Sweeping is per **pool**, not per rule. A pool has one balance, so there is no
rule-by-rule balance to expire; the question is how much of the one balance is
still spoken for.

**Eligibility** — the pool's rate period has closed:

- `pool_type_budget?`. This gate is by type, never by rule shape: a dateless goal
  is a rate rule on a savings pool, so "has an expired rate rule" would drain
  every goal the user has.
- The pool has at least one rate rule (`anchor_date.nil?`). No rate rule means no
  period to close — an envelope funded only against a dated bill accumulates
  toward it.
- Its rate rules have **all** closed, so the latest period end governs. Measured
  from the pool's **last funding date**, not from today: `period_end` answers
  "when does the period containing this date end", so asking it of today can
  never put the end in the past. Asking it of the date the money arrived is the
  reachable question — $60 paid in on Jul 12 sits in a period that ended Jul 23.

**Amount** — the pool's balance, less what its **live** dated rules hold. A dated
rule is live until it is settled, which only a one-time rule ever is; a recurring
bill is therefore live every period, and that is correct — the money is genuinely
spoken for. What it holds is its **allocation** (§4.3), not its amount, so an
under-funded bill reserves what it actually has. Never below zero: an overspent
envelope has nothing to give, and its deficit is the buffer's problem (UI spec
§7.2).

Blocking the whole sweep on a live dated rule instead of subtracting what it
holds would strand the rate rule's leftover permanently, since a recurring bill
is never settled.

`pool_type: savings` never sweeps.

This is self-correcting: a frugal period sweeps more back and makes the next
paycheck roomier; a blown period sweeps nothing and makes it tight.

### 5.3 Shortfall

When `sum(required) > available`, pools fill top-down by priority and the rest
show their exact gap. Two options, both legitimate:

- **Take from a pool** — opens reallocation with the damage priced per option
  (*"Car → Maintenance slips to $494/$800, +$27/paycheck"*), and pools with
  imminent obligations are flagged as unsafe sources.
- **Accept the shortfall** — allowed. Each unfunded rule's gap persists, so the
  next payday's `required` is automatically higher. Nothing to reconcile by hand.

The consequence of each choice is stated **before** it is made.

### 5.4 Cross-account transfers

```ruby
movement.crosses_accounts?   # from_pool.account_id != to_pool.account_id
```

Movements within one account are pure bookkeeping. Movements across accounts
require a real bank transfer, so the split screen ends with a short to-do list of
actual actions rather than leaving the user to work it out.

### 5.5 Editing and undo

`PoolMovement#source_entry_id` groups a split, so it is one unit:

- edit the income entry's amount → re-run steps 1–5, replace that entry's
  movements in a transaction
- delete the income entry → its movements go with it (`dependent: :destroy`)
- one line wrong → adjust on the split screen and re-confirm

A `PoolMovement` is never edited as a bare row. The two editable things are *a
paycheck's split* and *a reallocation*.

### 5.6 Routes

```ruby
resources :pools do
  resources :budgets, only: [:index, :new, :create]
  member { patch :reorder }
end
resources :budgets, only: [:edit, :update, :destroy]
resources :entries do
  resource :allocation, only: [:new, :create, :edit, :update]   # the split screen
end
resources :pool_movements, only: [:new, :create, :destroy]       # reallocation
```

Accounts are pools of `pool_type: account`, managed through `PoolsController`
with a type filter. This avoids colliding with the existing
`accounts_controller.rb`, which handles user settings.

## 6. Blast radius — **EXECUTED (Plan 3, tasks 3–5)**

Every deletion below has landed, with the greps in the task reports.
`Pool#contribution_entries` / `#withdrawal_entries` / `#timeline_entries` are gone — resolved in
task 5 rather than deferred, converted into `Pool#timeline` over movements (which also settled
§7a's "`start_date..` while `#balance` does not" item: the cutoff did not survive, because the
balance beside it has none). `categories.category_type: savings` is retired and integer 2 is
never reused; the one place it is still written down is
`CutoverToEnvelopeBudgeting::SAVINGS_CATEGORY`, a fact about the rows the migration meets.

24 spec files reference `budget` or `savings_pool`. All of the following needs
rework, not just renaming.

**Deleted**
- `SavingsPoolCalculator` → becomes `PoolCalculator`
- `Budget#category_must_be_expense`, `#category_must_not_have_pool`
- `Category#budgetable?`, `#pool_covered?`, and the `budgetable` / `pool_covered`
  scopes — every category is pool-covered now
- `Category#destroy_budget_if_not_expense`, `#destroy_budget_if_pool_linked`
- `SavingsPool#contribution_entries`, `#withdrawal_entries`
- `Entry` scopes `budgetable_expenses`, `pool_covered_expenses`
- `budgets.prorated` and all proration logic

**`CategoryCalculator`** — `budget_percentage`, `budget_pace_percentage`,
`monthly_budget_rate`, `effective_budget`, `budget_pace`, `budget_curve`,
`monthly_contribution`, and the prorated ramp helpers all lose their basis.
Budget-vs-actual becomes funded-vs-spent, computed at the pool, not the category.
What survives: `total_amount`, `top_items`, `current_month_items`,
`previous_month_*`.

**Dashboard presenters**
- `Dashboard::SavingsPresenter` — largely removed with `category_type: savings`
  (`savings_rate`, `flow_chart_data`, contribution breakdowns)
- `Dashboard::ExpensesPresenter` — `total_budget`, `budget_line_data` change
  meaning
- `Dashboard::OverviewPresenter` — `budgeted_total`, `budget_used_percentage`,
  `pool_covered_total`, `all_budgeted_categories_breakdown`
- `DashboardPresenter` — the delegation lists, `tracked_budgetable_*` /
  `tracked_pool_covered_*` loaders, and `enrich_with_budget`

**Views** — the savings tab and its five partials, `_budget_card`,
`_savings_pool_card`, `_summary_card`, `_category_card`, the whole
`savings_pools/` directory, `_filter_tabs`, `_sidebar`.

**Calendar presenters** — `MonthlyCalendarPresenter` and
`WeeklyCalendarPresenter` reference the savings category type; movements must
*not* appear on the calendar.

**Seeds** — `db/seeds.rb` (474 lines) needs a full rewrite around accounts,
pools, rules, and a pay cadence.

### 6.1 Data migration — **EXECUTED**

Shipped as `db/migrate/20260817000000_cutover_to_envelope_budgeting.rb`
(`CutoverToEnvelopeBudgeting`), with `spec/migrations/cutover_spec.rb` against four planted
legacy worlds. Two departures from the five steps below, both deliberate and both in the task 1
report:

* **Step 4 runs BEFORE step 2** — envelopes first — which is §7a's "reverse steps 2 and 4"
  warning, taken. See the annotation on that item.
* **A sixth step: budget envelopes open at ZERO.** An envelope inheriting its category's lifetime
  spending is technically true and practically a lie about the user's position, so the migration
  writes one identifiable transfer per overdrawn budget envelope (goals excluded — their balances
  are the one number the old app got right, and are asserted byte-identical across the
  entry→movement swap). This resolves §7's "opening balances" deferral for pre-cutover data,
  because this migration is the only code that will ever see it.

The migration verifies itself in raw SQL before committing — `Σ pools == bank truth` per user,
plus structural arms for pool-less categories, account-less pools, surviving caps and surviving
savings rows — and re-verifies on every run, so a second run over a database somebody has since
broken raises rather than passes.

1. Create one `account` pool per user ("Checking"), flagged default.
2. Point every existing category at it (`pool_id`).
3. For each existing `savings_pool`: set `pool_type: savings`, `account_id` to
   that account; existing linked categories keep pointing at it.
4. For each existing `Budget` on a category: create a `budget`-type pool named
   after the category, repoint the category at it, and move the budget onto the
   pool as `amount` + `interval_months: 1` + `basis: monthly`.
5. Convert every `category_type: savings` entry into a `PoolMovement` from the
   default account to the target pool, then drop the savings category type.

## 7. Out of scope

Deferred deliberately. Structure first.

- **Onboarding and opening balances.** Every pool starts at $0, which makes the
  app claim a catastrophic shortfall on day one. Needs a seeding step.
- **Rule suggestions from history** (*"you averaged $580/mo on groceries — make
  that a rule?"*). High value, but it depends on the structure being settled.
- **Recurring deposit templates** (*"always split my paycheck this way"*). A
  convenience over recording two income entries.
- **Bank reconciliation.** `account.total` should match the bank, but importing
  or comparing statements is a separate project.
- **Percentage-based allocation.** Removed from the design entirely; rules plus
  priority cover every case raised.

## 7a. Obligations carried forward from Plan 1

Recorded here because Plan 1's execution ledger is scratch and will be deleted.
Each is a decision deliberately deferred, not an oversight.

### Plan 2 (allocation flow) must

> **ALL CLOSED** as of the conversion's delivery. Eight done in Plans 2a–2d (each verified in
> Plan 3's closing audit); the preload item was resolved differently (in-memory pools with
> `:account` eager-loaded); `allocated`-netting-partial-payments stays deliberately open (it
> over-reserves, the safe direction) and is on the leaves-open list. Item-level homes are in the
> conversion-closing table in Plan 3's ledger and the 2d plan doc's inheritance list.

- **Validate `pay_anchor_date` presence when `pay_cadence` is set.** Without it
  `User#pay_dates` returns `[]`, the `[count, 1].max` clamp reports "1 paycheck
  before this bill", and the app demands the entire bill every paycheck. Highest
  value item on this list.
- **Fix `Entry`'s `searchable :pool`**, which resolves strictly through the
  category — once the override param is exposed, an entry is findable under the
  pool it overrode *away from* and not the one it landed in.
- **Give `User` a path to pool-mode budgets.** `has_many :budgets, through:
  :categories` reaches only category-mode rules, and `BudgetsController#set_budget`
  depends on it.
- **Permit `pool_type`, `account_id`, `priority`** in `pool_params`, and add the
  type filter §5.6 assumes — the pools index and savings dashboard currently list
  *all* pools, so they will render bank accounts with savings-goal chrome.
- **Constrain `PoolMovement#source_entry` to the movement's user** — an ownership
  hole that goes live with the paycheck-split writer.
- **Validate `priority`** (non-negative) alongside the reorder UI.
- **Preload `includes(from_pool: :account, to_pool: :account)`** in any view
  rendering `crosses_accounts?` over a collection.
- **Reconsider `dependent: :destroy` on `movements_out`** before reallocation
  ships: in a chain `A → B → C`, destroying B correctly restores A but vaporises
  C's inflow.
- Decide whether `allocated` nets a partial payment out of a rule's target
  (`BudgetCalculator#shortfall` currently does not — it over-reserves, the safe
  direction).

### Plan 2c (budget page & structural check) must

> **CLOSED** — the field, param and controller shipped in Plan 2c Task 4
> (`budget_page/_declaration_form`, `BudgetPageController#user_params`); the §9 branch and the
> sacrifice view are live.

- **Give `users.typical_income` a form field, a permitted param and a controller.**
  The column exists, `User` validates it, and `HomePresenter#structurally_underwater?`
  reads it — but nothing in the app can WRITE it. It is set by specs and seeds and
  nowhere else, so in production it is nil for every user, the structural check is
  permanently `false`, and the §9 warning branch on Home's standing band is
  unreachable code. That branch is the entry point to the sacrifice view, so both
  the check and the view it opens are dead until this lands. UI spec §8 puts the
  field on the Budget page beside the "Your rules need / You typically bring in"
  block, which is the right home for it: the figure is user-declared and never
  inferred (§3), and it belongs next to the total it is compared against.

### Plan 3 (cutover) must — **ALL CLOSED**

Annotated item by item. "Task N" is Plan 3's task; the commits are in
`.superpowers/sdd/2026-08-17-cutover/`.

- **Reverse §6.1 steps 2 and 4, or use `update_all`.** `Category#destroy_budget_if_pool_linked`
  destroys a category's budget the moment a `pool_id` is assigned, so pointing
  categories at pools *before* migrating budgets silently destroys every user's
  budgets. **This is the step that loses data.**
  **DONE — the shipped migration runs envelopes-first**, and belt-and-braces: it also writes
  through `update_all` and migration-local table classes throughout, so no callback and no future
  validation can fire. Both guards, because either alone would have been enough and neither is
  free to add later. Nobody needs to fear this one again (task 1).
- **Tighten `Pool#account_matches_pool_type`** to require an account for savings
  pools once the backfill lands (marked `TODO(plan-3)` in the model).
  **DONE HERE (task 6).** The `TODO(plan-3)` and `#require_account_for_budget_pools` are deleted;
  one message covers both kinds ("must be set for envelopes and goals"), and
  `CHECK ((pool_type = 0) = (account_id IS NULL))` says the same thing at the database, past the
  model. *Consequence, recorded because it is larger than the change:* an account-less pool is no
  longer expressible, so the whole ORPHAN apparatus — `Pool::REFUSALS`,
  `HomePresenter#orphan_pools` and its attention band, `BudgetPagePresenter#orphan_rules` and
  `budget_page/_orphans`, `ReallocationPresenter`'s "No account" group — is unreachable code that
  now answers empty on every database. It is KEPT, with the ~15 examples that planted the shape
  deleted and their reasons written at each site. **Deleting it is follow-up 1 below.**
- **Flip the `pools.pool_type` column default** from `2` (savings) to `1` (budget)
  per §3 — the current default exists only to preserve pre-migration rows.
  **DONE HERE (task 6)**, in `20260817010000_tighten_pool_shape`. Visible where you would expect:
  `/pools/new` opens on "Budget envelope" rather than "Savings goal".
- **Delete `PoolCalculator#savings_entries_total`** in the same commit as the
  entry→movement conversion. It becomes a no-op first, so removal cannot
  double-count during the cutover.
  **DONE (task 5)**, same-commit rule honoured — the term, its funding-date leg and the
  `#contributions` operand all went with the enum value.
- **Add `UNIQUE (user_id, lower(name))` on pools** once the backfill can dedupe.
  **DONE HERE (task 6)**, functional index `index_pools_on_user_id_and_lower_name`. The accept
  flow's reuse-by-name (`BudgetProposal::Envelope#existing`) leans on it: it finds a pool by
  `LOWER(name)` and creates one if there is none, which is a race a validation cannot win.
- **Rewrite `db/seeds.rb` teardown** for `PoolMovement` and the self-referential
  `pools.account_id` FK.
  **DONE (task 2)**, and it was a live defect rather than a precaution: `Item` before `Budget` in
  the delete loop raised `PG::ForeignKeyViolation` and left the database with zero entries. Order
  is now `[PoolMovement, Entry, Budget, Item, Category, Pool, User]`, pinned by `spec/seeds_spec.rb`.
- Resolve `Pool#contribution_entries` / `#withdrawal_entries` / `#timeline_entries`,
  which still filter on `start_date..` while `#balance` deliberately does not.
  **RESOLVED IN TASK 5, not deferred to task 6** — all three are deleted, replaced by
  `Pool#timeline` (movements in and out plus the spending of the categories pointing at the pool).
  The `start_date` cutoff did NOT survive: the balance beside it has none, and two readers of one
  question is the defect this conversion found in every task. Verified callerless in task 6.
- Merge the duplicate income validators on `Entry` and `Category`.
  **RESOLVED HERE AS "NOT DUPLICATES" (task 6), which is a decision rather than a skip.** They
  share a name and a sentence and guard different columns on different tables: `Category`'s
  polices `categories.pool_id`, `Entry`'s polices `entries.pool_id` — the per-entry override, and
  the half that WINS `COALESCE(entries.pool_id, categories.pool_id)`. An income category correctly
  pointed at Checking can still have one paycheck entry re-pointed into an envelope, and the
  category's validator never sees that write. Neither can delegate to the other; what is shared is
  the predicate (`Pool#pool_type_account?`), which is already one method. The reasoning lives at
  `Entry#income_must_land_in_an_account`.

### What Plan 3 leaves open

Follow-ups, none a defect today. The first two were created by task 6's tightening and are
larger than the task that created them; the rest were consolidated by the conversion's closing
review.

1. **Delete the orphan apparatus.** Listed above. It renders for nobody and its examples are
   gone, so it is dead code carrying no tests — kept because the shape it refuses (a destroy that
   takes money out of the pool tree) is the one thing this app must never absorb silently.
2. **`categories.pool_id NOT NULL` at the database.** `belongs_to :pool` is required in Ruby and
   the one writer that walked past it (`dependent: :nullify` on `Pool#categories`) was replaced
   with `restrict_with_error` in task 6, so nothing in the app can write a NULL. The column is
   still nullable. The cost of closing it is that `spec/migrations/cutover_spec.rb`'s central
   planting idiom — a pool-less category, the shape the migration exists to repair — would have to
   go through the schema rewind that file already uses for the other two tightenings.
3. **THE BUFFER QUESTION — an open USER decision, default implemented.** The migration zeroes
   every lifetime-overdrawn budget envelope with a transfer from its own account, which on data
   whose nominal savings exceed actual cash lands the deficit at the buffer (the demo: Checking
   opens `overdrawn $3,699.00`). The alternatives — floor the zeroing at what the buffer holds,
   or shrink savings balances to fit cash — were presented to the user and NOT yet answered; the
   code ships the "accept" default. Changing the answer costs near zero until the first real run
   (edit `#zero_the_envelopes` + relax `#envelope_failures`; "shrink" also collides with
   `#savings_drift_failures`, which pins savings to the cent). After a real run it is a repair
   migration over rows identified by (kind transfer, migration-dated, budget-pool destination,
   nil source_entry) — good but not unique; the run log prints the inserted ids as the undo list.
4. **`TightenPoolShape` can refuse a database the cutover accepted** — duplicate pool names
   (the migration never dedupes pre-existing ones) and an account carrying an `account_id`
   (repaired in neither direction of the housing step). Two pre-flight `SELECT`s in the
   cutover's verifier close it; its header's claim of full compliance is corrected in code.
5. **No repair or runbook for a cross-user `categories.pool_id`.** The verifier catches it
   (both users' Σ mismatch) but aborts the whole all-or-nothing run with an unnamed cause; a
   pre-flight naming the offending categories turns the abort into a work item.
6. **`Category` has no model-level ownership validator on `pool`** — the guard is
   controller-only (both controllers verified clean); the durable form is the validator its two
   siblings (`Entry`, `Pool`) already have, comparing records not ids.
7. **The perf/design inheritance from 2d** stands unchanged at the bottom of
   `docs/superpowers/plans/2026-08-17-logging-and-tracking.md`.

## 8. Testing

Per the `system-test-writer` skill's page-based structure.

**Unit** — `BudgetCalculator` (all four shapes, catch-up, overdue, the
attribution ladder), `PoolCalculator` (balance formula, due-date waterfall,
`free_amount`, negative balances), `User#pay_dates` (all four cadences,
3-paycheck months), `AllocationCalculator` (sweep, priority fill, shortfall),
`AllocationCommitter` (transactionality, replace-on-re-run).

**System** — `spec/system/pools/` (index with accounts and pools, show with the
rule breakdown, form, priority reorder), `spec/system/budgets/` (each of the four
shapes), `spec/system/allocations/` (happy path, shortfall with both options,
cross-account transfer callout, edit and re-confirm),
`spec/system/pool_movements/` (reallocation with consequence preview).

**Regression** — the 24 existing spec files touching `budget` or `savings_pool`
must be reworked alongside the code they cover, not deleted.

The scenarios that most need coverage are the ones the app exists for:
overspending a pool, a bill landing before the next paycheck, and accepting a
shortfall and seeing next payday's requirement rise.
