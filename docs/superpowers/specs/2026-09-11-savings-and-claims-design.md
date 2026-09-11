# Savings and Claims: two promises on checking

Henry, 2026-09-11. The accounts-and-rules spec of 2026-09-09 built the claim system with rules as
its only claimant. This spec adds the second claimant, savings, and restructures the claim code so
that neither is special. It supersedes §3.2, §4, §5 and §6 of that spec where they overlap. The
"what" is in `docs/decisions.md`; this file is the "how".

## 1. What the app is after this spec

Checking carries two kinds of promise. A **rule** on an expense category says what it may spend,
and entries drain its claim. A **savings target** on a savings account says what the account is
owed, and transfers into it drain its claim. Both are claims on checking; claimed is their sum;
free is checking minus claimed. Income always lands in checking, and money reaches a savings
account only by a transfer the user makes. The Accounts page becomes the Savings page.

## 2. The model

Conventions as before: UUID ids, Postgres `money` scale 2, `date` columns, timestamps everywhere.

### 2.1 Changes

| table | change |
|---|---|
| accounts | add `keeps_extra` (boolean, not null, default true) |
| savings_targets | new: `account_id`, `item_id` (nullable), `amount` (money, nullable), `percent` (decimal 5,2, nullable), `starts_on` (date, not null) |
| adjustments | `source_type` (string) + `source_id` (uuid), polymorphic, both not null; no `rule_id` |
| entries | never gains `account_id` |

Constraints, each mirrored by a validation:

- savings_targets: `(item_id IS NULL AND amount IS NOT NULL AND percent IS NULL) OR (item_id IS NOT NULL AND percent IS NOT NULL AND amount IS NULL)`; `amount > 0` when present; `percent > 0 AND percent <= 100` when present; unique `account_id` where `item_id IS NULL`; unique `(account_id, item_id)` where `item_id IS NOT NULL`.
- adjustments: `amount <> 0` stays; `source_type <> 'Account' OR amount < 0`; index on `(source_type, source_id)`.

Model-level rules that cannot be a constraint: a target's account is the user's and is not main;
a share's item is an income item of the same user; one item's percents across the user's accounts
sum to at most 100; an adjustment's source belongs to the user; an adjustment on an account is
negative.

### 2.2 Meanings

- **SavingsTarget.** `target?` when `item_id` is nil, `share?` otherwise. `starts_on` is the first
  day it counts, defaulting to today on create and left alone when amount or percent is edited.
- **Account#keeps_extra.** True: extra moved in carries against later periods (a minimum). False:
  every period asks fresh; extra is just extra. A shortfall carries in both.
- **Adjustment.** `belongs_to :source, polymorphic: true`. The source is a `Rule` or an `Account`.
- **Entry.** Has no account. Income lands in checking; expenses leave it.
- **Account** loses `has_many :entries`. Deleting an account deletes its targets, its adjustments
  and its transfers, as now.

## 3. Money

### 3.1 Balances

```
balance(account) = opening_balance
                 + Σ income entries        (checking only)
                 − Σ expense entries       (checking only)
                 + Σ transfers in − Σ transfers out
pot              = balance(checking)
```

`AccountLedger` loses `income_by_account`; income is one sum into checking.

### 3.2 The savings claim

`SavingsCalculator` computes one account's claim. It is handed the account, the user's period
grid, the account's targets, the transfers into it, the income entries on its shares' items, and
its adjustments, all as rows, and returns `claim`, `ask`, `owed_this_period`,
`accrued_this_period`, and `countable_span`.

Let `start` be the earliest `starts_on` among the account's targets. Walk every period from the
one containing `start` through the current period `P0`. An account with no targets, or whose
`start` is after today, visits no period and claims nothing.

```
owed(P)     = Σ over target rows with starts_on ≤ P.last:   amount
            + Σ over share rows with starts_on ≤ P.last:    percent/100 × Σ entries on the item dated in P and ≥ starts_on
accrued(P)  = owed(P) + Σadj(P)
arrived(P)  = Σ transfers in dated in P and ≥ start

keeps_extra true  : claim = max(0, Σ accrued(P) − Σ arrived(P))          over all visited P
keeps_extra false : carry = 0; for each P: carry = max(0, carry + accrued(P) − arrived(P)); claim = carry
```

`accrued_this_period` is `accrued(P0)`, what Skip takes back. `countable_span` is
`start..today`. The walk is capped at 520 periods, like the rule walk.

### 3.3 Ask, budget, savings, leftover

One word for what a source costs per period: `ask`.

```
rule.ask           = amount                      (rate, fund)
                   = target / periods to date     (dated, one-off)
                   = amount × 12 / (periods_per_year × interval_months)   (dated, rolling)
target.ask         = amount                                  (target row)
                   = percent/100 × typical income of the item  (share row)
account.ask        = Σ ask over its targets

budget             = Σ rule.ask
savings            = Σ account.ask
leftover           = typical_income − savings − budget
budget_claim       = Σ rule claims
savings_claim      = Σ account claims
claimed            = budget_claim + savings_claim
free               = pot − claimed
```

Typical income of an item is `IncomeMeasure` over that item's entries in the same two complete
periods typical income uses. `IncomeMeasure` takes `item_ids:` as well as `category_ids:`.

### 3.4 The claim list

`ClaimLedger` produces one list for a user, in a fixed number of queries:

```ruby
Claim = Data.define(:source, :name, :kind, :claim, :ask, :cuttable)
# source   a Rule or an Account
# kind     :bill, :usage, :choice, or :savings
# cuttable false for a rolling bill, true otherwise
```

Give-way rank: choice 0, usage 1, savings 2, bill 3. The ledger exposes `claims`, `rule_claims`,
`account_claims`, `budget`, `savings`, `budget_claim`, `savings_claim`, `claimed`, `free`, and
`calculator_for(source)`. Home's give-way list, the sacrifice rows, the Savings page's checking
panel and the Budget tiles read `claims` and never `rules`.

### 3.5 Renames

| now | becomes |
|---|---|
| `Rule#steady_ask`, `ClaimCalculator#standing_ask` | `#ask` on both |
| `Rule.steady_need` | gone; `ClaimLedger#budget` |
| `*_presenter#rules_need` | `#budget` |
| `ClaimLedger#total_claims`, `HomePresenter#total_claims` | `#claimed` |
| `AccountsPresenter` (`spending`, `set_aside`) | `SavingsPresenter` (`checking`, `savings`) |
| `HomePresenter#in_checking` | stays |
| `SacrificePresenter#rules_need` | `#budget`; `#gap = budget + savings − typical_income` |

The sacrifice dial's JavaScript is unchanged: it reads per-row claims and a gap.

## 4. Writing

- **AccountForm** replaces `Account#revise`: name, balance today, `keeps_extra`, and a list of
  target rows via `accepts_nested_attributes_for :savings_targets, allow_destroy: true`. Each row
  is `item_id` (blank for a target row), `amount` or `percent`, and `starts_on`. A row keeps the
  figure its item implies (`SavingsTarget` blanks the other before validation) and refuses a
  missing one, an item that is not the user's income item, a percent that would take the item
  past 100, and any target on checking. A rename and a balance correction land
  together or not at all, as now.
- **AdjustmentForm** takes `source:` instead of `rule:` and asks the source's calculator for
  `accrued_this_period` and `countable_span`. On an account it accepts only `skip` or a negative
  amount; a positive amount is refused with "you can move more any time — there's nothing to top
  up." The date rule is the same: inside `countable_span`.
- **EntryForm** drops the account parameter. `EntriesController` stops permitting `account_id`
  and prefilling an account.
- **Item.merge / move_to_category** drop the account-nulling branch.
- **SacrificeCuts** takes `target_cuts:` beside `cuts:`, keyed by target id. A fixed target is
  written the typed amount; a share the typed percent. A figure at or above the current one is
  refused, and a row left at its figure is untouched, as for rules.
- **Transfer.move** is unchanged in code. On the page the verb is transfer. A savings row's
  "Transfer $520.00" button is a `button_to` that posts to `transfers#create` with the account as
  `to`, checking as `from`, the claim as `amount` and today as `date`: one click, no form. The
  notice reads "Transferred $520.00 from Checking to Emergency fund". The "Transfer money" drawer
  stays for any other amount or pair of accounts.

## 5. Components

```
models      Account (+keeps_extra, has_many :savings_targets, has_many :adjustments, as: :source)
            SavingsTarget  Adjustment (polymorphic source)  Item (+has_many :savings_shares)
            Entry (−account)  Rule  Transfer  Category  User
services    AccountLedger  ClaimCalculator  SavingsCalculator  ClaimLedger  IncomeMeasure (+items)
            AccountForm  AdjustmentForm  EntryForm  RuleForm  CadenceChange  SacrificeCuts
presenters  HomePresenter  SavingsPresenter  BudgetPagePresenter  SacrificePresenter
            ClaimRows  ClaimLine  SavingsLine  (others unchanged)
controllers Savings  Accounts (create edit update destroy)  Transfers  Adjustments  (others unchanged)
```

Routes:

```
get      "savings"  => "savings#show"
resources :accounts, only: [:create, :edit, :update, :destroy]
resources :transfers, only: [:create]
resources :adjustments, only: [:create, :destroy]     # params: source_type, source_id
```

`AdjustmentsController` whitelists `source_type` to `Rule` and `Account`, finds the source through
`current_user`, and redirects back to the Budget page (rule) or the Savings page (account). A
`SavingsPageState` concern mirrors `BudgetPageState` for the controllers that re-render the
Savings page after a refusal: `accounts#create`, `transfers#create`, `adjustments#create`.

The sidebar entry "Accounts" becomes "Savings" at `savings_path`. Every `accounts_path` redirect
becomes `savings_path`.

## 6. Screens

- **Savings** (`/savings`): the checking panel at the top with balance, claimed (with "budget" and
  "savings" as two lines beneath), and free. Then one row per savings account: name, balance, its
  targets in words ("$200 a period, plus 10% of Paycheck", or "no savings target"), owed now, last
  transferred, a one-click Transfer button naming the owed amount (hidden when owed is zero), Edit,
  Delete. The Adjust disclosure sits inside the "owed now" cell, under the figure, and opens the
  panel (amount, Reduce, "Skip this period (−$X)") in a full-width row beneath. On the Budget page
  the rule row's Adjust moves to the same place, under its claim figure. The "income last landed" column is gone. Drawers for
  Transfer money and Add an account as now.
- **Account form** (`/accounts/:id/edit`, and the add drawer for name and balance only): name,
  balance today, the keeps-extra choice as two radios each with one sentence, and the target rows
  with an add-row button. A target row's amount shows "that's N% of what you typically bring in"
  as a hint when typical income is known. A Stimulus controller adds and removes rows and toggles
  amount versus percent on whether an item is chosen.
- **Budget** (`/budget`): the tiles read "You bring in X. Savings take Y. Your budget is Z. That
  leaves W." The bar's first segment is savings, then bill, usage, choice. Underwater means
  `budget + savings > typical_income`. Everything below the tiles is unchanged.
- **Sacrifice** (`/sacrifice`): the gap is `budget + savings − typical_income`. Two sections. "Your
  budget" holds the rules' rows as today. "Your savings" holds one row per savings target, named
  "<account> · $200 a period" or "<account> · 10% of Paycheck". A fixed target's dial is an amount
  input; a share's dial is a percent input whose freed figure is `(percent − typed) / 100 × the
  item's typical income`. Both carry an "Edit the target" link to the account form. The dial
  controller gains a `data-kind` per row so it can read a percent row against its item's income.
- **Home**: free, the give-way list and the trouble strip read the claim list, so savings claims
  appear in give-way order and free is net of savings. "Your budget doesn't fit your income" fires
  on `budget + savings > typical_income`. No layout change.
- **Entries**: the income form loses "Lands in".

## 7. Migrations

Production is at the June schema. Nothing from this branch has run there, so the PR ships one
clean set of migrations and the two September files are replaced. Each is made with the Rails
generator and does one thing. In order:

```
CreateAccounts                    accounts table, unique (user_id, lower(name))
CreateTransfers                   transfers table, checks, date index
AddMainAccountToUsers             main_account_id, FK nullify
AddPeriodToUsers                  period_cadence, period_anchor_date
AddPriorityToCategories           priority, check >= 0
AddRegularToCategories            regular
AddUniqueNameToCategories         unique (user_id, lower(name))
AddDayToEntries                   day (nullable, filled by the data migration)
AddPositiveAmountToEntries        check amount > 0
RenameBudgetsToRules
AddItemToRules                    item_id, partial unique indexes
AddShapeToRules                   rule_type, starts_on, anchor_date, interval_months, keeps_unspent, checks
CreateAdjustments                 polymorphic source from the start, checks, index
AddKeepsExtraToAccounts           keeps_extra
CreateSavingsTargets              §2.1 columns, checks, partial unique indexes
ConvertPoolsToAccounts            the data migration: stamps days, converts each user, verifies, tightens
```

`ConvertPoolsToAccounts` is the September data migration unchanged in substance: it fills `day`,
mints accounts and transfers per user, stamps `starts_on`, verifies each user's books, then drops
the old timestamp date, `prorated`, `savings_pool_id` and `savings_pools`, and adds the two-types
check. It is the only migration that reads data.

Nothing adds `entries.account_id`, and adjustments never carry `rule_id`, so there is no backfill
and no drop. No preflight.

## 8. Testing

As in the accounts-and-rules spec §8. New coverage:

- `spec/services/savings_calculator_spec.rb`: both modes; target rows, share rows and both; a
  shortfall carrying; extra carrying or not; a start in the future; adjustments; the 520 cap.
- `spec/services/claim_ledger_spec.rb`: the claim list's order, kinds and cuttability; budget,
  savings, claimed, free with both sources.
- `spec/services/income_measure_spec.rb`: item-based typical income.
- `spec/models/savings_target_spec.rb` and `spec/models/adjustment_spec.rb`: every validation in
  §2.1 and §2.2.
- `spec/services/account_form_spec.rb` and `adjustment_form_spec.rb`: the refusals in §4.
- `spec/presenters/savings_presenter_spec.rb`, `budget_page_presenter_spec.rb`,
  `sacrifice_presenter_spec.rb`, `home_presenter_spec.rb`: the figures of §3.3 and §6.
- `spec/system/savings/*`: the page's figures once; the one-click Transfer writes the row and the claim drops to zero; adjust reduce and skip; the
  account form's rows (`:js`); add and delete an account.
- `spec/system/budget_page/tiles_spec.rb`, `spec/system/sacrifices/*`, `spec/system/home/*`: the
  savings figures and rows.
- `spec/migrations/convert_pools_to_accounts_spec.rb`: the data migration, as before.

## 9. Commits

Seven, each green on the specs it adds:

1. Schema and models: the migrations of §7, `SavingsTarget`, `Account#keeps_extra`, polymorphic
   `Adjustment`, factories, model and migration specs.
2. Calculators and ledger: `SavingsCalculator`, `ClaimLedger`'s claim list, `IncomeMeasure` by
   item, the §3.5 renames, specs.
3. Forms: `AccountForm`, `AdjustmentForm` on a source, `EntryForm` without an account, specs.
4. Savings page: `SavingsController`, `SavingsPresenter`, `SavingsLine`, views, the target-rows
   Stimulus controller, `SavingsPageState`, route and sidebar rename, system specs.
5. Budget tiles and Home: the savings figures, the bar segment, the give-way list from the claim
   list, specs.
6. Sacrifice: savings rows, the new gap, specs.
7. Docs: `decisions.md` loses its planned markers; `CLAUDE.md` and `coding-standards.md` name the
   Savings page and the claim list; seeds gain a target and a share.

## 10. Out of scope

- Writing transfers automatically, on income or at a period boundary.
- A percentage of typical income as a target.
- A top-up adjustment on savings.
- Versioning a target's edits.
- Spending from any account other than checking.
- A "saved this period" figure on the Savings page. The formula is in `decisions.md` §2 and the
  ledger can answer it in one clause when a screen wants it.
- Suggestions.
