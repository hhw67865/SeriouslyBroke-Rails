# The Main Account: Source, Mirrors, and the Start-Date Rule

**Status:** DRAFT — awaiting Henry's review
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
