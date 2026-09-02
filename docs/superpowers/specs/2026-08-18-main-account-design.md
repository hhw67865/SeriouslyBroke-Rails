# The Main Account: Source, Mirrors, and the Start-Date Rule

**SUPERSEDED IN PART (2026-09-02):** the physical ledger below — main-as-pot, movement-fed mirror
accounts, income routing, the onboarding cards — survives intact and is still the reference for it.
Its envelope half does not: the start-date rule now reads `categories.funded_since`, accounts carry
no target or start date, and §6's parked buffer-marker question is answered "no". See
`2026-08-21-two-ledger-design.md` (DELIVERED), §10.
**Status:** DELIVERED 2026-08-20 (plan `docs/superpowers/plans/2026-08-18-main-account.md`, tasks
1–7; ledger `.superpowers/sdd/2026-08-18-main-account/progress.md`). §9 below records where the
build differs from this text and what it left open.
**Date:** 2026-08-18
**Builds on:** `2026-08-14-envelope-budgeting-design.md` (DELIVERED) and the fresh-start ruling
recorded in its "What Plan 3 leaves open" §3.

## 1. What this fixes

Two failures surfaced the moment real data met the delivered structure:

1. **Connecting a category to a new envelope dragged its whole history along.** Ming created a
   Food & Grocery envelope with a $1,409/period rule; the category's $46,739.63 of lifetime
   spending instantly landed in the never-funded envelope, which opened "overdrawn". The ledger
   reads an entry against whatever pool its category points at *today* — a re-point rewrites
   history's location.
2. **Accounts and categories are entangled.** Any account could hold categories and receive
   income, so nothing distinguished "where money physically is" from "what money is for", and
   nothing in the app corresponded to the number a bank statement shows.

## 2. The model (Henry's rulings, 2026-08-18)

```
MAIN ACCOUNT  (the user's real checking account — where income physically arrives)
   balance = income − expenses − movements out        ← "the source"
   └─ other ACCOUNTS   — hold money via movements ONLY; no categories ever point at them;
   │                     each mirrors a real bank account, transfer for transfer
   └─ ENVELOPES/GOALS  — live inside an account, have a start date, have categories
```

- **The main account is `users.default_account_id`, required.** One per user. It is the only
  account income lands in and the only account expense history reads against by default.
- **Non-main accounts change balance only by movement** (plus the spending of envelopes that
  live inside them — money an envelope spends leaves the account that holds the envelope).
  Their app balance mirrors their real bank balance.
- **`Σ pools == bank truth` is untouched.** Everything below is about *location*, never total.

## 3. THE START-DATE RULE (the core semantic change)

> **An envelope or goal only counts category spending dated on or after the pool's
> `start_date`. Entries dated before it read against the MAIN account.**

- **The envelope's start date governs, not the category's connection date** (ruled explicitly).
  Connecting an old category to a mid-life envelope retroactively counts that category's
  spending back to the envelope's start date — a deliberate act with an immediately visible
  effect, not a surprise.
- The ledger's landing rule becomes, in order:
  1. `entries.pool_id` override, when present (unchanged — how "paid from savings" is recorded);
  2. the category's pool, **if** the entry's date `>=` that pool's `start_date` **or** the pool
     is an account;
  3. otherwise the user's main account.
- `pools.start_date` already exists on every pool and is validated present; today it is
  documented as "does not filter the balance". That sentence inverts. This is a READ-side rule:
  no data is rewritten, no compensating movements are needed, and Ming's overdrawn envelope
  heals by itself (her grocery history predates the envelope).
- Every reader must move together or Σ splits: the COALESCE lane
  (`PoolBalanceLedger::ENTRY_POOL_ID`), the migration verifier's copy of it, and any raw SQL in
  specs. One reader, one law, as before.

## 4. Income routing

Recording income asks **which account it lands in** (defaulting to main). Under the hood, ONE
rule and ONE mirror:

- The income entry itself always lands in the main account (income categories point at main —
  this tightens the current "income must land in *an* account" to "…in *the main* account").
- Choosing another account writes an automatic movement `main → chosen account` for the full
  amount, carrying the entry as `pool_movements.source_entry_id` — the column already exists
  for exactly this shape. Editing or deleting the entry finds its movement by that link.

## 5. Onboarding (the complete flow)

1. **Create all accounts** — DELIVERED (the Home add-account card, `bb79189`). The caveat
   stands: every account income reaches must be entered.
2. **Fund each non-main account with its real balance**: a movement `main → account` per
   account, mirroring the transfers that really happened over the years.
3. **One-time main correction**: after step 2, main is wrong by exactly the untracked history.
   The user enters main's real bank balance; the app writes ONE ordinary entry for the
   difference in an auto-created "Opening Balance" category (income-type when the correction is
   positive, expense-type when negative). After this, **every account equals its bank
   statement** and Σ still equals the (corrected) bank truth.

Steps 2–3 are the unbuilt UI. Reconciliation stays ONE-TIME by ruling: after onboarding, drift
means an unrecorded transaction, and the remedy is recording it, not adjusting it away.

## 6. Structural tightenings that fall out

- **Categories may point only at envelopes, goals, or the main account.** Non-main accounts
  hold no categories. (Enforced at the model beside `pool_must_belong_to_user`; existing data
  already conforms for Ming — the reset pointed everything at Checking, her main.)
- **`users.default_account_id` becomes required** once the user has any account (it is the
  fallback the start-date rule reads). Ming's is set by the reset's shape; a guard names any
  user without one rather than guessing.
- The buffer stays a concept (Henry, parked ruling): no schema change to accounts; how the
  account header labels its number is a separate open question.
- **"Pool" → "Envelope" as user-facing vocabulary is DEFERRED** — a rename touching every
  screen, spec and table for zero behavior; revisit after onboarding ships.

## 7. Out of scope

- Ongoing/periodic reconciliation (ruled out — one-time only).
- Recurring income-split templates ("always route my paycheck this way") — the routing in §4
  is per-entry; templates remain on the deferred list.
- Multi-currency, joint accounts, anything the current app doesn't already claim.

## 8. Testing outline

- **The start-date rule**: an envelope with history-bearing category shows only post-start
  spending; pre-start entries read against main; the override lane still wins; movements
  unaffected. Both directions, planted literals, and the Σ invariant asserted against raw SQL
  on the same fixtures.
- **Income routing**: entry-with-account-choice writes entry (in main) + linked movement;
  editing amount updates both; deleting removes both; choosing main writes no movement.
- **Onboarding steps 2–3**: funding movements land; the correction entry's sign both ways;
  after completion each account's balance equals the entered figure to the cent.
- **Tightenings**: category pointed at a non-main account refused in both the model and the
  wire; the existing suite (cutover spec included) re-run — the verifier's COALESCE copy moves
  in step with the ledger's.

## 9. As built (2026-08-20): drift from this text, and what stays open

Verified live on the restored production copy against `mingguan0809@gmail.com` — the data that
demanded the spec. Her Food & Grocery envelope reads **$0.00 left**, not overdrawn: the
$46,739.63 of pre-start grocery history now reads against Checking under §3's rule, with **zero
data changed**. Σ holds to the cent (pools via `PoolCalculator` = $113,627.95 = income − expenses
by raw SQL over her entries); `default_account_id` points at Checking; Home renders the period
range, the funding card under `savings` only, the opening-balance card under Checking, and the
add-account card.

**Drift — the build is narrower or wider than the text above:**

- **§3 gained a timezone-aware comparison.** `entries.date` is a datetime in UTC and users carry
  their own zone, so `date >= start_date` is made in the USER'S LOCAL DAY (`AT TIME ZONE`, inside
  `PoolBalanceLedger::ENTRY_POOL_ID`). Without it a Tokyo evening entry read against main because
  UTC had not turned over yet.
- **§3's ordered rule gained a NULL arm.** A category whose `pool_id` is NULL (a shape the
  database still permits — see the envelope spec's leaves-open §2) resolves to main rather than
  being dropped from the query, and the joins are LEFT on the pool for exactly that reason. The
  arm exists so a user without a main account cannot silently lose entries from Σ; the Category
  validator added here prevents the state it answers for.
- **§5's one-time correction measures main's FAMILY total, not its buffer.** The difference is
  computed against `Pool#total` for main — buffer plus every envelope housed in main — because
  that is the number a bank statement shows for the physical account. Identical to the buffer for
  a user with no envelopes; right instead of wrong for an envelope-first user. **§5's step-2
  funding gate reads the same figure, for the same reason** (`HomePresenter#awaiting_funding?` →
  `Pool#total`): a waterfall routinely leaves a funded account's buffer at exactly $0 with its
  envelopes holding everything, and a buffer-only gate offered that account the "match your bank
  statement" card a second time. An account holding only an EMPTY envelope still totals zero, so
  it is still offered the card.
- **§4's routing is synced from the CATEGORY as well as from the entry.** `Category` carries an
  `after_update` that clears its entries' `kind_transfer` movements when `category_type` flips
  income → expense, because the category edit form permits that column and
  `EntriesController#sync_income_routing` only ever runs entry-side — the flip used to strand every
  mirror, leaving main debited and the destination holding a phantom.
- **§6's displaced categories always land on main.** Destroying an envelope, or disconnecting a
  category from one, re-points the category at the user's MAIN account — never at the account the
  envelope happened to live inside, which the new validator refuses. Categories pile onto main,
  which is what §3 and §6 together say should happen.

**Open questions this build leaves:**

- **§5's steps have an unenforced order.** Correcting main (step 3) BEFORE funding the other
  accounts (step 2) drains main by the funding amounts afterwards, and there is no second door:
  the correction latches once. Nothing in the app enforces or explains the sequencing today, and
  nothing puts the cards in the safe order either: `HomePresenter#accounts` is `order(:name)`, so
  a main account named late in the alphabet renders BELOW the siblings it is meant to be corrected
  before. The state is recoverable — deleting the correction entry reopens the latch — but only by
  a user who knows that.
- **§6's `default_account` requirement is still deferred, and deleting main costs more than the
  column.** `users.default_account_id` is set when the first account is created; deleting that
  account is legal and nullifies the column, leaving a user with accounts and no main. Two things
  follow, and neither is only about the nullified column:

  - **Σ breaks.** The start-date rule's ELSE arm sends every PRE-START entry to
    `users.default_account_id`, so a NULL there resolves the whole `COALESCE` to nothing and those
    entries fall out of EVERY pool — `Σ pools` drifts from bank truth by exactly their amount.
    That is the shape `spec/services/start_date_rule_spec.rb`'s no-main-account example pins,
    planted past the model because `Category#pool_must_be_reachable` refuses to create it.
  - **The other accounts collapse to zero.** `Pool` declares `movements_in` and `movements_out`
    with `dependent: :destroy`, and every non-main account was funded by ONE movement FROM main
    (§5, step 2). Destroying main destroys all of them, so each sibling's balance drops by
    whatever it was funded with — a user's savings account reads $0 against a bank that still
    holds the money.

  **What makes this narrow is `has_many :categories, dependent: :restrict_with_error`**, not any
  rule about main: an account with a category pointing at it refuses to be destroyed at all. Every
  income category must live on an account (`Category#income_must_land_in_an_account`) and that
  account must be main (`#pool_must_be_reachable`), and onboarding's own correction writes an
  "Opening Balance" category there — so anyone who has recorded income or finished onboarding
  cannot reach the destroy. The gap is a user who has done neither. Home guards the state it
  leaves (the funding gate and the opening-balance gate both require a main present) rather than
  preventing it. The tightening — refuse the destroy on main outright, or promote another account
  — is unbuilt.
- **Latch behavior, recorded as choices rather than defects:** renaming or deleting the
  "Opening Balance" category reopens the correction door (deleting the record of a correction
  deliberately reopens it), and a zero-difference correction records nothing and so leaves the
  latch open.
