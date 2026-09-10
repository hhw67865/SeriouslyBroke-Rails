# Accounts and Rules: the direct path from main

Henry, 2026-09-09: the `feature/envelope-budgeting` branch reached a design worth keeping after
many turns, and the code carries the turns. This spec describes that end state as if it had been
the goal from the start, so it can be built from `main` in one straight line. The old branch is a
read-only reference until it is deleted. Nothing in it is merged.

## 1. What the app is after this spec

A user has **accounts** (bank accounts; one of them is main), **categories** (expense or income)
with **items** under them, and **entries** (money in or out, dated, on an item). Money moves
between accounts as **transfers**. A category may carry **rules** that say what it is allowed or
meant to spend; each rule has a computed **claim** on main. **Adjustments** are dated, signed
corrections to a rule's claim. Everything shown about money is derived at read time from those
tables.

What is gone from `main`: savings pools and the savings category type. What is gone from the
reference branch: suggestions, the pool vocabulary, opening-balance categories and entries, income
routing through transfers, the category's funding date, the rule's `basis` column, typed income.

## 2. The model

All ids are UUIDs. Money columns are Postgres `money`, scale 2. Dates are `date` columns; no table
about money stores a time of day. `created_at` / `updated_at` on every table.

| table | columns |
|---|---|
| users | Devise columns, `name`, `theme`, `ming_mode`, `timezone`, `main_account_id` (nullable, FK accounts, nullify on delete), `period_cadence` (weekly 0, biweekly 1, semimonthly 2, monthly 3; nullable), `period_anchor_date` (nullable) |
| accounts | `user_id`, `name`, `opening_balance` (default 0, not null), `opened_on` (nullable) |
| transfers | `from_account_id`, `to_account_id`, `amount`, `date` |
| categories | `user_id`, `name`, `category_type` (expense 0, income 1), `color` (nullable), `tracked` (default true), `priority` (integer, default 0), `regular` (boolean, default true) |
| items | `category_id`, `name`, `description` |
| entries | `item_id`, `account_id` (nullable, FK accounts), `amount`, `date`, `description` |
| rules | `category_id`, `item_id` (nullable), `rule_type` (bill 0, usage 1, choice 2), `amount`, `starts_on`, `anchor_date` (nullable), `interval_months` (nullable), `keeps_unspent` (default false) |
| adjustments | `rule_id`, `amount`, `date` |

Database constraints, each mirrored by a model validation:

- accounts: unique `(user_id, lower(name))`.
- categories: unique `(user_id, lower(name))`; `priority >= 0`.
- transfers: `amount > 0`; `from_account_id <> to_account_id`.
- entries: `amount > 0`.
- rules: `amount > 0`; `interval_months > 0` when present; `NOT (keeps_unspent AND anchor_date IS NOT NULL)`; `interval_months IS NULL OR anchor_date IS NOT NULL`; unique `item_id` where not null; unique `category_id` where `item_id IS NULL` (one item-less rule per category).
- adjustments: `amount <> 0`.
- users: `period_anchor_date` required when `period_cadence` is set (model only).

Model-level rules that cannot be a constraint: an account, a transfer's two accounts, an entry's
account, a rule's category and item, and a user's main account all belong to the same user (the
main account carries a plain foreign key that nullifies on delete; the ownership check is the
model's). An
item's rule belongs to the item's category. Only expense categories carry rules. `regular` means
something only on income categories. An expense entry has no account (it leaves main); an income
entry may name an account, and no account means main. Main is not deletable while it is main.

### 2.1 Meanings

- **Account.** `opening_balance` is what the account held on `opened_on`, before any entry or
  transfer. Both are set when the account is opened and corrected by editing the account.
  Correcting the balance means setting `opening_balance` so that the balance today equals the typed
  figure; nothing else moves. Deleting an account deletes its transfers and sends its income
  entries to main, so what it held returns to the pot.
- **Entry.** Dated to the calendar day the user means. Income lands in `account` or main; expense
  leaves main.
- **Transfer.** A hand move between two of the user's accounts, dated when it happened.
- **Category.** `priority` is its place in the fill order: money fills categories from 0 upward,
  so when money is short the highest number gives way first. `tracked` keeps it on or off the
  spending screens. `regular` on an income category means
  its entries count toward typical income.
- **Rule.** The lane a rule speaks for is its item's entries when `item_id` is set, else the
  category's entries on items that have no rule of their own. `starts_on` is the first day whose
  spending counts. The shapes are in §3.2.
- **Adjustment.** A signed delta on a rule's claim, dated inside a period the rule counts.

## 3. Money

### 3.1 Balances

```
balance(account) = opening_balance
                 + Σ income entries landing in it
                 − Σ expense entries (main only)
                 + Σ transfers in − Σ transfers out
pot              = balance(main)                  (0 with no main account)
total_money      = Σ balance over the user's accounts
free             = pot − Σ claim over the user's rules
```

`AccountLedger` computes every account's balance for a user in a fixed number of queries.

### 3.2 Claims

The user's **period grid** is `User#period_containing(date)` as built on the reference branch: with
a cadence and anchor, weekly and biweekly stride from the anchor, monthly on the anchor's day,
semimonthly on the anchor's day and that day plus or minus fifteen; without a cadence, the calendar
month. `periods_per_year` is 52, 26, 24 or 12.

A rule has one of three **shapes**, decided by two columns:

| shape | columns | claim |
|---|---|---|
| rate | no `anchor_date`, `keeps_unspent` false | `max(0, amount + Σadj(P0) − spent(P0))` over the current period `P0` only |
| fund | no `anchor_date`, `keeps_unspent` true | the walk below with no target: each period adds `amount`, keeps what is unspent |
| dated | `anchor_date` set | the walk below toward `target = amount`, once when `interval_months` is null, rolling otherwise |

The **walk** visits every period from the one containing `starts_on` through `P0`, in order,
carrying `built_up`, `paid`. A rule whose `starts_on` is after today visits no period and claims
nothing yet.

```
planned(P)  = fund:  amount
              dated: 0 if settled, else min(round((target − built_up) / periods_left(P.first, due)), target − built_up)
accrued(P)  = built_up + planned(P) + Σadj(P)          (dated: capped at target)
raw(P)      = accrued(P) − spent(P)
paid       += spent(P)
built_up    = max(raw(P), 0)
claim       = built_up after P0
```

For a dated rule, `due` is `anchor_date` when one-off. When rolling it is `anchor_date` advanced by
`interval_months × cycles`, where `cycles = min(floor(paid / target), cycles elapsed by that date)`.
`settled` means one-off and `paid ≥ target`. `overdue` means the next due date is before today and
not settled. `over` means `raw` of the current period is negative; `over_by` is its magnitude.
`periods_left(from, due)` counts period boundaries between the two, at least 1. The walk is capped
at 520 periods.

`spent(P)` sums the rule's lane's entries dated in `P` and on or after `starts_on`.

**Standing ask**, what a rule costs per period, used to compare rules to income:

```
rate or fund       : amount
dated, one-off     : target / periods from the period containing starts_on to anchor_date
dated, rolling     : amount × 12 / (periods_per_year × interval_months)
rules_need         = Σ standing ask
```

`ClaimCalculator` does the arithmetic for one rule given its spending and adjustment rows.
`ClaimLedger` loads every rule, its spending and its adjustments for a user in a fixed number of
queries and hands each calculator its rows. Nothing else computes a claim.

### 3.3 Typical income

Typical income is derived, never typed. Take the complete periods before `P0` that begin on or
after the user's earliest entry; take the last two of them; typical income is the mean of income
entries in **regular** income categories over those periods. One complete period gives that
period's figure. None gives nil, which the screens show as "not enough history yet". The
comparison of `rules_need` to typical income needs a declared cadence, because per-period amounts
have no meaning without a grid.

### 3.4 Cadence change

Changing `period_cadence` offers to scale every rate and fund rule's amount by
`periods_per_year_before / periods_per_year_after`, floored at one cent. Scaling is offered on the
first declaration too, since a rule written before any cadence was set is a monthly figure.

## 4. Writing

- **Account.open(user, name:, balance:)** creates the account with `opening_balance = balance` and
  `opened_on` = the day before the user's earliest entry, else today; makes it main when the user
  has none. Editing an account renames it or corrects its balance (§2.1).
- **EntryForm** takes what the entries controller does today: evaluates a formula in the amount
  field with Dentaku, creates the item by name when no id was chosen, and applies the chosen account
  to income entries.
- **RuleForm** as on the reference branch: fields `category_id`, `item_id`, `rule_type`, `amount`,
  `schedule` (per_period or by_date), `repeats`, `keeps`, `interval_months`, `anchor_date`,
  `starts_on`. It writes `anchor_date` only for by_date, `interval_months` only when repeating,
  `keeps_unspent` only for per_period. Its `starts_on` defaults to today. There is no `basis` and
  no monthly conversion.
- **AdjustmentForm** as on the reference branch: top up, reduce, set aside, take back, skip; refuses
  a date outside the span the rule counts.
- **Category.apply_fill_order** as on the reference branch, writing `priority`.
- **Item.merge** and **Item#move_to_category** as on main.

## 5. Components

```
models      User Account Transfer Category Item Entry Rule Adjustment
services    AccountLedger ClaimCalculator ClaimLedger RuleForm AdjustmentForm EntryForm
            CadenceChange CategoryStats
presenters  HomePresenter BudgetPagePresenter ClaimRows ClaimLine CategoryBudgetPresenter
            EntryImpactPresenter SacrificePresenter RulePreview DashboardPresenter (+ dashboard/*)
            MonthlyCalendarPresenter WeeklyCalendarPresenter
controllers Home Accounts Entries Items Categories Categories::Items Rules BudgetPage Adjustments
            Sacrifices Settings Calendar Dashboard Pages Users::Registrations
```

`CategoryStats` is main's `CategoryCalculator` renamed: month and year-to-date totals for the
reports page. `ModelSearchable` and the `Searchable` controller concern stay as on main.

Routes:

```
resources :accounts, only: [:create, :edit, :update, :destroy]
resources :entries, except: [:show] { collection { get :impact } }
resources :items, only: [:edit, :update, :destroy]
resources :categories (+ categories/items merge, move; toggle_tracked; update_tracked)   as main
resources :rules, only: [:new, :create, :edit, :update, :destroy] { collection { match :preview, via: [:post, :patch] } }
get   "budget"          => "budget_page#show"
patch "budget/user"     => "budget_page#update"
patch "budget/reorder"  => "budget_page#reorder"
resources :adjustments, only: [:create, :destroy]
get   "sacrifice"       => "sacrifices#show"
resource :settings, only: [:show] { patch :toggle_theme; patch :toggle_ming_mode }
get "reports" => "dashboard#index";  get "calendar";  get "calendar/week";  root
```

Controllers are thin: find the record through `current_user`, hand params to a form object or a
model method, redirect or re-render. A controller that re-renders another page's view uses a
small concern for that page's state, not inheritance.

Timezone handling is one method, `User#today`, which turns `Time.current` into the user's calendar
day. Stored dates are days already.

## 6. Screens

The views, Stimulus controllers and helpers are taken from the reference branch at commit
`4ee68de` and adapted to the names above. They are not redesigned. The pages:

- **Home**: accounts with balances and an add-account form, free to spend, this period's progress,
  the trouble strip, the give-way list, the runway.
- **Budget** (`/budget`): tiles, category rows with their rules and adjustments, reorder; the
  income tile's "change" links to Your income (`/budget/income`), which holds the period and the
  income categories in one form.
- **Rule form** (`/rules/new`, `/rules/:id/edit`): the two schedules, the keeps checkbox, the live
  preview. No suggestion chips.
- **Sacrifice**: what would have to give when rules need more than typical income.
- **Entries**, **Items**, **Categories** and the category page's holdings card: as on the reference
  branch, without the suggestion pointer. The entry form offers the account on income entries. The
  category form offers the regular flag on income categories.
- **Calendar**, **Reports**, **Settings**: as on main, with the settings rename.

Everything about suggestions is absent: no engine, no dismissals, no partials, no badges.

## 7. Migration

Two migrations, in order. The first only adds; the second converts the data and then removes and
tightens, so every step that reads old data runs while the old columns still exist. Both have a
`down` that rebuilds a development database at `main`'s schema without data.

### 7.1 Schema, additive

Creates `accounts`, `transfers`, `adjustments`. Renames `budgets` to `rules` and adds `item_id`,
`rule_type` (default usage), `starts_on` (nullable until 7.2 fills it), `anchor_date`,
`interval_months`, `keeps_unspent`. Adds `main_account_id`, `period_cadence`,
`period_anchor_date` to `users`; `priority`, `regular` to `categories`; `account_id` and
`day` (a date, nullable until 7.2 fills it) to `entries`. Adds every §2 constraint that does not
depend on data: uniqueness, positive amounts, distinct transfer accounts, non-zero adjustments,
the rule shape checks, the partial unique indexes on rules.

### 7.2 Data, then tightening

Per user, in one transaction, ordered by `created_at`:

1. Every entry's `day` becomes the calendar day of its `date` timestamp in the user's timezone,
   UTC when none is set. Every later step reads `day`.
2. Create the main account, named `Checking` (suffixed `Checking 2`, … on a name clash), opening
   balance 0, `opened_on` = the day before the user's earliest entry, else the run date. Set
   `users.main_account_id`.
3. Each savings pool becomes an account: same name (suffixed on a clash), `opened_on` = its
   `start_date` or the main account's `opened_on`, opening balance 0. Target amounts are dropped.
4. Each savings category with no pool becomes an account named after the category, same rules.
5. Each entry in a savings category becomes a transfer from main into that category's account
   (the pool's account, or the one minted in step 4), same amount, same day. Then the savings
   categories, their items and their entries are deleted.
6. A pool's balance was its contributions less the spending of its linked expense categories from
   its `start_date`, so that spending goes back to main: each entry in an expense category linked
   to a pool, dated on or after the pool's `start_date` (every entry when the pool has none),
   becomes a transfer from the pool's account to main, same amount, same day. Then each expense or
   income category linked to a pool loses the link. `priority` is 0 and `regular` is true for
   every category.
7. Each rule (the renamed budgets) gets `starts_on` = its creation day in the user's timezone;
   `rule_type` usage, no anchor, no interval, `keeps_unspent` false are already the defaults.

After every user: drop `entries.date`, rename `day` to `date`, make it and `rules.starts_on`
`NOT NULL`; drop `rules.prorated`, `categories.savings_pool_id` and `savings_pools`; add a check
that `categories.category_type IN (0, 1)`.

Before the tightening it asserts, per user, and raises on any failure so the transaction rolls
back:

- `Σ balance over the user's accounts == Σ income entries − Σ expense entries` as they stood before
  the run, to the cent.
- each account that came from a savings pool or category holds exactly its savings entries less
  the pool spending returned to main.
- no entry, item or category references a savings type or a pool.
- every rule satisfies §2's constraints.

It prints one receipt line per user: accounts made, transfers written, entries deleted,
reimbursements written, rules written.

Verified by a migration spec that builds a `main`-shaped fixture covering every step above,
including name clashes, a user with no entries, a pool with no categories, a savings category with
no pool, and a user in a non-UTC timezone with an entry near midnight. The run against the
2026-09-09 production dump is part of the implementation plan; its receipts are recorded in the
plan's completion notes.

## 8. Testing

Coverage stays; time goes. Measured on the reference branch: a presenter example costs 26 ms, a
browser example 1.7 s, of which about 1 s is Chrome being restarted after every example.

- **One browser per process.** The per-example driver quit is gone. Capybara resets the session.
- **Logic lives in fast specs.** Every figure, state, formula and validation is proven in model,
  service and presenter specs. A system spec proves each page renders its figures once, and every
  real interaction: forms, the rule preview, the adjust panel, the entry impact card, the 375px
  layouts.
- **Rack::Test by default; Chrome on demand.** System specs that read a page or submit a plain form
  use the in-process driver. Examples that need JavaScript are tagged `:js`.
- **Transactional tests only.** DatabaseCleaner is removed; Rails shares the connection with the
  server thread in system tests.
- **Directories run whole, and in parallel.** `bundle exec rspec spec/models` is the unit of work
  locally; CI runs the suite with `parallel_tests`. `CLAUDE.md`'s one-file-at-a-time rule and its
  flake diagnostics are replaced by this section's rules.
- **No `sleep`.** Waiting assertions only.

Target: the whole suite under five minutes on this machine.

Spec layout as on main and the `system-test-writer` skill: page-based directories under
`spec/system`, `spec/models`, `spec/services`, `spec/presenters`, `spec/requests`, one
`spec/migrations/accounts_and_rules_spec.rb`.

## 9. Commits

Ten, each green on the specs it adds:

1. Settings: the settings page and its routes rename from Account.
2. Schema and models: both migrations' schema half, the eight models, factories, model specs.
3. Data migration and its spec.
4. Ledgers and claims: `AccountLedger`, `ClaimCalculator`, `ClaimLedger`, specs.
5. Forms: `RuleForm`, `AdjustmentForm`, `EntryForm`, `CadenceChange`, `Account.open`, specs.
6. Accounts and home: controller, presenter, views, JS, system and request specs.
7. Entries, items, categories: controllers, presenters, views, specs.
8. Budget page, rules, adjustments, sacrifice: controllers, presenters, views, specs.
9. Calendar and reports: `CategoryStats`, presenters, views, specs.
10. Seeds, `CLAUDE.md`, docs, CI: seeds for the new model, the testing rules, `parallel_tests`.

## 10. Out of scope

- Suggestions of any kind. A later feature branch.
- Any change to how the screens look.
- Merging or cleaning the reference branch. It is deleted once this branch is on `main`.
- Spending from an account other than main.

## 11. Glossary: reference branch to this spec

| reference branch | here |
|---|---|
| `Pool`, `pools`, `pool_type` | `Account`, `accounts` |
| `AccountMovement`, `from_pool_id`, `to_pool_id`, `kind`, `source_entry_id` | `Transfer`, `from_account_id`, `to_account_id` |
| `Budget`, `budgets`, `basis`, `BudgetsController`, `/budgets` | `Rule`, `rules`, `RulesController`, `/rules` |
| `users.default_account_id`, `typical_income` | `users.main_account_id`; typical income derived |
| `categories.funded_since`, `BudgetProposal`, `start_holding` | `rules.starts_on` |
| `Category::OPENING_NAMES`, `entries.opening_account_id`, `AccountOpening` | `accounts.opening_balance`, `opened_on` |
| `Entry#route_income_to!`, `routed_account` | `entries.account_id` |
| `CategoryLedger`, `ENTRY_LOCAL_DAY` | `entries.date` is a date |
| `CategoryCalculator` | `CategoryStats` |
| `BankAccountsController`, `/bank_accounts` | `AccountsController`, `/accounts` |
| `AccountsController` (settings), `resource :account` | `SettingsController`, `resource :settings` |
| `SuggestionEngine`, `SuggestionDismissal`, chips, pointers, badges | nothing |
