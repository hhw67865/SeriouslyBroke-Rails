# Categories Hold the Money: the Two-Ledger Model

**Status:** DRAFT — awaiting Henry's review
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
