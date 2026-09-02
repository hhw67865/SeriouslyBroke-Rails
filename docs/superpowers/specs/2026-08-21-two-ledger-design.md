# Categories Hold the Money: the Two-Ledger Model

**Status:** DELIVERED 2026-09-02 (plan `docs/superpowers/plans/2026-08-21-two-ledger.md`, tasks
1–9; ledger `.superpowers/sdd/2026-08-21-two-ledger/progress.md`). §10 below records where the
build differs from this text, the rulings taken during it, and what it leaves open.
**Date:** 2026-08-21
**Supersedes the pool structure of:** `2026-08-14-envelope-budgeting-design.md` and the account
half of `2026-08-18-main-account-design.md` (which survives intact as the physical ledger).

## 1. The ruling this encodes (Henry, 2026-08-21)

Envelopes and categories were always one idea wearing two names — the suggestion flow's own
"write this rule" manufactured a same-named envelope and wired the category to it. Henry's
ruling: **delete the pool layer entirely.** Accounts and categories are separate things,
connected by nothing but movements; categories themselves hold money, carry rules, and carry
savings targets. "The only connection between an account and a category is the movement."

## 2. The model: two ledgers over the same total

```
PHYSICAL LEDGER — where money sits           PURPOSE LEDGER — what money is for
  POT (= main checking)                        AVAILABLE (money with no job yet)
    = income − expenses − Σ moves to accts       = income − unfunded spending − Σ allocations
  ACCOUNTS — movement-fed ONLY;                CATEGORIES — hold money:
    income and expenses never touch them;        holdings = allocations in/out − spending
    each mirrors its bank statement              counted from the category's funding start

INVARIANT (both partitions of one total, each to the cent):
  pot + Σ accounts  ==  income − expenses  ==  available + Σ category holdings
```

- **Entries touch both ledgers.** Income raises the pot and raises available. An expense
  lowers the pot, and on the purpose side drains **its category** if that category has
  started holding money, otherwise drains **available** (the start-date rule, inherited and
  re-anchored — §4).
- **Movements touch exactly one ledger each.** Account movements (pot ↔ account) are the
  physical ledger's only writer besides entries. Allocations (available ↔ category) are the
  purpose ledger's only writer besides entries. There is no account→category movement:
  allocating money is an act of intention, not of location, so it moves nothing physical —
  which is why "any account's money can back any category" is automatic rather than a feature.
- **Paying from a savings account is not a thing** (Henry): in reality you transfer
  savings→checking first, and recording THAT movement is the whole story. No "paid from"
  field on entries; the pot is where cash leaves.

## 3. What categories become

- `Category` gains the envelope's whole job: **holdings** (computed, ledger-style — never a
  stored balance), **rules** (`budgets.category_id` replaces `budgets.pool_id`; a rule may
  still anchor on an `item` for dated bills — the item carries the recurring timing),
  **`target_amount`** (a savings category is just a category with a target and typically no
  refill rule), **`priority`** (the distribute waterfall's order), and **`funded_since`**
  (§4). The `expense`/`income` enum stays; only expense categories hold money.
- **Savings by movement**: contributing is available→category; withdrawing is
  category→available; the entry vocabulary stays purely income/expense (unchanged since the
  cutover — this model keeps that ruling).
- Multi-category envelopes are **gone** — one category, one budget line. (The old power
  feature; Henry's whole point is that nobody was living in it.)

## 4. The start-date rule, re-anchored

A category's spending counts against its holdings **from `funded_since` onward** — the date
it first got a rule or an allocation, stamped explicitly at that moment (user-editable on the
category). Earlier spending drains available on the purpose ledger (and the pot on the
physical one, as all spending does). This is the same read-side law delivered in the
main-account plan — same timezone discipline, same one-reader requirement — with the pool
table's `start_date` replaced by the category's own column. Ming's healed Food & Grocery
stays healed: her envelope's start date becomes the category's `funded_since` in the
migration.

## 5. What dies

- The `pools` table's budget and savings rows, `Pool` model branches for them, envelope CRUD,
  the Pools page's goals index (savings render with the other categories), the
  connect/disconnect category manager, `Category#pool_must_be_reachable` and the whole
  re-pointing hazard class (there is nothing to re-point), the orphan apparatus (already
  dead), and the category↔envelope name-twinning.
- `pools` survives ONLY as accounts. A later cosmetic pass may rename the table; this plan
  does not.
- `pool_movements` becomes `movements` in shape: each side is the pot/available root, an
  account, or a category. (Mechanism — polymorphic sides vs. paired nullable FKs — is the
  plan's decision, not the spec's; the invariant in §2 is the acceptance test either way.)

## 6. What survives untouched

The physical ledger is the main-account plan as delivered: main-as-pot, movement-fed
accounts, income routing (the routing movement IS the alignment movement), the onboarding
cards (add account, fund with real balance, one-time opening correction), and the period
machinery. The distribute waterfall survives with categories as its fill targets.

## 7. Migration (local prod copy; Ming's data live)

Per user, all-or-nothing, self-verified in the cutover's discipline: each budget-pool folds
into its connected category (holdings' movement history retargeted, rule re-parented,
`start_date` → `funded_since`) — a budget-pool with two+ categories or zero categories
ABORTS with named rows (none exist on the real data; the shape must be refused, not guessed
at); each savings pool becomes a new savings category carrying its name, target, priority and
holdings; accounts and all entries untouched; both §2 invariants verified by raw SQL before
commit, against pre-migration totals.

## 8. Out of scope

- Renaming the `pools` table / "Pool" class (accounts-only after this; cosmetic).
- A "paid from" convenience on entries (ruled unnecessary — §2).
- Dated-bill creation from the hand-made rule form (separate small task, already flagged).
- Multi-currency, shared budgets, everything the app doesn't already claim.

## 9. Testing outline

- **The invariant, both ledgers**, raw-SQL on planted fixtures: after income, expense
  (funded and unfunded categories), allocation, account movement, and a savings
  contribution+withdrawal — each partition equals income − expenses to the cent.
- **The re-anchored start-date rule**: pre-`funded_since` spending drains available, not the
  category; boundary day timezone-pinned (Tokyo idiom from the main-account plan).
- **Migration**: cutover-spec discipline — planted legacy shapes, sabotage arms (multi-category
  envelope refused with names), Σ verified against independent SQL, idempotence.
- **Screens**: Budget page drives rules on categories; distribute fills categories by
  priority; Home shows the physical ledger; savings categories show target progress.

## 10. As built (2026-09-02)

Delivered across nine tasks, `0e829ed..` on `feature/envelope-budgeting`. §2's invariant is the
acceptance test and it holds on the restored production copy: for Ming, by raw SQL scoped to her
email, `available 225,584.20 + Σ holdings 0.00` == `pot 3,039.33 + Σ accounts 222,544.87` ==
`income 586,654.80 − expenses 361,070.60` == **225,584.20**, to the cent.

### Where the build differs from this text

- **Accounts lost target semantics entirely.** §6's parked buffer-marker question (inherited from
  `2026-08-18-main-account-design.md` §6: "how the account header labels its number is a separate
  open question") is answered **no**: `pools.target_amount` and `pools.start_date` are dropped, the
  account header says `balance now $X` and nothing else, and a target is now a property only a
  CATEGORY can carry. There is no account-level buffer marker and no plan for one.
- **The reallocation screen's route is `/allocations/new`**, not a movements route. §5 said
  `pool_movements` "becomes `movements` in shape"; in the build the purpose ledger got its own
  table (`allocations`, paired nullable `from_category_id`/`to_category_id` with NULL = the root)
  and the physical one kept its own (`account_movements`), so the two ledgers never share a writer
  — which is what makes "allocating money moves nothing physical" structural rather than checked.
- **`account_movements` kept the `from_pool_id` / `to_pool_id` column names.** Renaming them is
  the `pools`→`accounts` table rename in miniature and §8 puts that out of scope; the columns are
  account-only by constraint (`pools_are_accounts`, `account_movements_are_transfers`). Residue,
  recorded so the next reader does not mistake it for a surviving category link.
- **Two-level goal classification** (Task 7 ruling). CHROME — the heading, the target bar, the
  word "Goal" — keys on `saving_toward_a_target?` (target-positive), so a category with a target
  reads as a goal everywhere. STATUS stays schedule-aware: a dated goal is `on_track`/`behind`, a
  dateless one is "saving". "Goal · on track" is a deliberate pairing, not a disagreement between
  two readers.
- **Savings never sweep, full stop** (Task 3 ruling, MED-1). A target-positive category never
  period-closes and never sweeps, whatever mix of rate and anchored rules it carries — the pool
  era's rule, restated on the column. The cost is deliberate and visible: a user who wants a
  target-bearing envelope SWEPT must clear its target. Corollary residue: an ordinary envelope
  given a decorative target takes the goal path and hoards instead of sweeping.
- **A future `funded_since` is refused by validation** (Task 7 ruling, LOW-1). A future start is
  scheduling, which nothing in the app supports; accepting one silently created a fund-now,
  spend-counts-later trap. Set the date on the day. The migration tolerates a future value that
  already exists — the validation is new on an old column.
- **`AllocationCalculator#available` is NOT the figure to check §2's invariant with.** It adds
  `total_swept` — money the categories still HOLD, since nothing moves until the user confirms the
  distribution — so `#available + Σ holdings` overstates bank truth by exactly the swept amount.
  The conservation figure is `CategoryLedger#available`. The hazard is warned in the reader itself
  (`app/services/allocation_calculator.rb`), measured on the demo seeds at $1,900.00 vs $1,775.00.
- **A rule may only be owned by a category that can hold money** (Task 5 ruling, MED-1). Two
  guards: `Budget` refuses a rule on an income category outright, and the Budget page's fill-order
  list is populated with exactly what `Category.apply_fill_order` accepts (holders with rules).
  A rule on an expense category that is not yet funded renders in the "Not in the fill order"
  band rather than in an unorderable group.
- **A `funded_since` PRESENCE check is not a second reader of the start-date rule** (Task 5
  ruling). The one-reader law governs the DAY COMPARISON — "does this expense fall on or after the
  category's funding date", which `CategoryLedger::ENTRY_CATEGORY_ID` spells in SQL and
  `Category#counts_spending_on?` mirrors in Ruby, and nothing else may spell. `funded_since.present?`
  asks a different question — "has this category started holding money at all" — and answering it
  cannot disagree with the comparison, so no spelling of it breaks the law. **The count is at least
  six, not three** (final fix wave, M-3 — the Task 5 note listed only the ones that branch may have
  written). Ruby: `Category#holder?` (`category.rb:267`), `Category#start_holding`
  (`category.rb:291`), `Category#money_may_not_be_stranded` (`category.rb:498`). SQL:
  `Category.in_fill_order` (`category.rb:140`), `DashboardPresenter#buffer_funded_expenses` /
  `#enveloped_expenses` (`dashboard_presenter.rb:183,185`), `Dashboard::OverviewPresenter
  #savings_categories` (`overview_presenter.rb:108`). `SuggestionEngine#starts_holding?`
  (`suggestion_engine.rb:417`) is not on the list: it CALLS `#holder?`, which is the shape the rest
  of them could take. That is the whole of the finding — a CODE-QUALITY point, not a law breach —
  and the SQL half cannot take it at all, which is why it stays a point rather than a task.
- **The MAIN account is not deletable while it is main** (final fix wave, C-1). Main is on one side
  of every `AccountMovement` the app writes (`Entry#route_income_to!` and
  `AccountFundingsController#build_movement` both put `user.default_account` on `from_pool`), so
  `dependent: :destroy` over its movements did not take its own transfers — it took every transfer
  there is, nullified `users.default_account_id`, and left `pot + Σ accounts == 0` against an
  untouched purpose ledger. §2 broken by a button. `Pool#main_account_is_not_deletable` halts the
  destroy with a sentence on `:base`, Home renders no Delete on main's card, and the one escape is
  the USER's own deletion (`destroyed_by_association`), where nothing is stranded because everything
  goes. Model-level only: `delete` still walks past it, which the spec records.
- **§4's "or an allocation" is now written, and clearing the date is refused over money** (final fix
  wave, I-1). §4 defines `funded_since` as "the date it first got a rule OR AN ALLOCATION" and only
  the rule path (`BudgetProposal`) ever stamped it; `AllocationsController#create` now stamps it too,
  in one transaction with the allocation, through `Category#start_holding` — the app's one spelling
  of the stamp, shared by both callers. The other end is `Category#money_may_not_be_stranded`, which
  refuses a cleared `funded_since` while the category's holdings are non-zero (three aggregate
  queries, on that one transition and no other) and names the figure and the door. Between them there
  is no live path into "money in a category no reader looks at"; the category show page renders that
  state honestly anyway, for rows planted past the model.
- **There is a THIRD day comparison, and it is blessed** (final fix wave, M-4). `Category
  #funding_start_is_not_in_the_future` (`category.rb:460-462`) compares `funded_since` against the
  owner's day through `Category#local_day` — the same re-zoning `ENTRY_CATEGORY_ID` does with its two
  `AT TIME ZONE`s. It is NOT a second reader of the start-date rule and does not breach the
  one-reader law: that law governs "does THIS EXPENSE fall on or after the funding date", and this
  asks "is the funding date itself in the future", a question about one column and no entry. It goes
  through `#local_day` precisely so the two cannot disagree about where a day begins. Recorded
  because grepping for `funded_since` beside a date comparison finds it, and the next reader should
  not have to re-derive that it is legal.
- **§9's migration idempotence was not delivered, by ruling** (final fix wave, M-6). §9's testing
  outline promised "cutover-spec discipline — planted legacy shapes, sabotage arms, Σ verified
  against independent SQL, **idempotence**", and Task 1 ruled the DDL-first migrations NOT
  re-runnable — their first act is DDL, so a second run meets a schema the first one already changed
  and there is nothing coherent for it to assert. The audit property idempotence was standing in for
  is bought a different way instead: each migration's `#verify!` is callable on its own against a
  live database, which is how the dev receipts on the restored production copy were produced and what
  the migration specs' sabotage arms use. Everything else on §9's migration line — planted legacy
  shapes, sabotage arms, Σ against independent SQL — was delivered
  (`spec/migrations/cutover_spec.rb`, `two_ledger_spec.rb`, `drop_the_pool_layer_spec.rb`).
- **`app/services/` reads `HoldingCalculator` / `HoldingStatus` / `HoldingProjection`, reached by
  `Category#holding_calculator` and `Category#status`.** Bare `Category#calculator` still belongs
  to `CategoryCalculator` (spending metrics) — the two are different questions and the names say so.

### Open — deliberately not done here

- **The `pool_`-named helper residue.** `HomeHelper#pool_status_label` / `#pool_state_label` /
  `#pool_rule_label` / `#pool_problem_label` and `BudgetPageHelper#pool_balance_clause` all render
  CATEGORY status now. Renaming them is a mechanical sweep across every screen and its specs for
  zero behavior, and it belongs with the table rename below rather than smeared across nine tasks.
- **The `pools` table / `Pool` class → `accounts` / `Account` rename**, and with it
  `account_movements`' two column names. §8 put it out of scope and it stays there: cosmetic,
  large, and safer as one pass than as a tail on this one.
- **The picker-path error lift** on the reallocation form would swallow a `:category` error
  reachable only by planted or legacy data (Task 5, deferred minor).
- **Copy questions carried to Henry's browser pass, both UNSEEN on real data** (Task 9): the
  "You're covered this period" headline paired with a NEGATIVE available (Ming's available is
  positive, so the pairing never rendered — the law that gates it,
  `projected_buffer.negative? ⟺ available.negative?`, is stated at `HomePresenter:311`), and the
  live look of the "Not in the fill order"
  band (Ming has no ruled non-holder: all five of her rules sit on funded categories).
