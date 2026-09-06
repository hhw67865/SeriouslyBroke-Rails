# Account Openings: say what each account holds, and nothing else

**Status:** APPROVED (Henry, 2026-09-06)
**Date:** 2026-09-06
**Builds on:** `2026-08-18-main-account-design.md` (the physical ledger: main = the source, other
accounts = movement-fed mirrors, the opening-day rule) — the MECHANISM is unchanged; this changes
what the user is asked.

## 1. The ruling (Henry, 2026-09-06)

> "Not many people are going to know how much TOTAL money they have and then divide it all off.
> Instead they just want to put in what their accounts are currently worth. The fact you have to get
> the ordering exactly right is bad user experience."

> "Corrections should be done on the same initial entry. Actual movements appear as adjustments
> based on time."

## 2. The model

An account has **one opening record**, dated the opening day (the day before the user's earliest
entry, else today — the existing rule in `OpeningBalancesController#opening_day`):

| account | the opening record |
|---|---|
| main (checking) | one entry of `B` in the `Opening balance` income category |
| any other account | one entry of `B` in `Opening balance` **and** one `account_movement` of `B` from main into it, same day |

Saving an account "with `B` in it" writes that record; each save is self-contained, so **order never
matters**: main first or last, the figures typed are the figures shown. `total_money` is the sum of
what the accounts were said to hold plus tracked income − expenses since. Nothing is distributed;
nothing on the purpose side moves.

**Correcting a balance edits the opening record in place** — never a second entry. The new opening
amount is `typed balance today − (what has flowed through the account since the opening day)`:
for main, `typed − (income − expenses since, excluding the opening entry) + Σ movements out − Σ
movements in`; for another account, `typed − Σ (other movements in − out)`. The record's date stays
the opening day. An account whose opening record was never written (a pre-existing account) gets
one on its first correction.

**Real transfers stay movements dated when they happened** (`account_movements`, unchanged).

## 3. The screens

- **Onboarding on Home** becomes one card, "Your accounts": a row per account — name, "what's in it
  right now" — with **+ Add an account**; the first account is main (as today). Saving a row writes
  its opening record. The "fund an account" step and the "opening correction" step die, with their
  copy and their cards (`_fund_account.html.erb`, `_opening_balance.html.erb`,
  `AccountFundingsController`, `OpeningBalancesController` — the opening-day rule moves to the new
  object).
- **Each account card** (the expander on Home) gains **Edit balance** → the same row form,
  pre-filled with today's balance; saving rewrites the opening record so the account reads the
  typed figure.
- Onboarding is complete when every account has an opening record; Home's onboarding predicates
  (`awaiting_funding?`, `awaiting_opening_balance?`) collapse to one: `awaiting_opening?`.

## 4. One object

`AccountOpening.new(user, account, balance:)` → `#save` writes or rewrites the record in one
transaction, dating it the opening day, and refuses a negative balance for a non-main account (a
mirror cannot be overdrawn by construction) while allowing one for main (an overdrawn checking
account is a fact). It is the ONLY writer of `Opening balance` entries and of opening movements;
`AccountLedger` and the invariant are untouched and pinned by raw SQL before/after every write.

## 5. Testing

- `AccountOpening`: main and non-main first saves (the record), re-saves as corrections (the same
  rows, amounts recomputed, dates unchanged), a correction after income/expenses/movements on the
  account, a pre-existing account's first correction, the negative rule, the invariant pinned.
- Order independence: three accounts saved in two different orders → identical ledger figures.
- Home: the new card; onboarding complete after the last record; Edit balance on a card; the old
  cards and copy absent (deletions named at successor heads); true-375 pin.
- Requests: ownership scoping (a stranger's account → 404), the negative refusal.
- Browser: a fresh throwaway saves three accounts out of order → Home's In checking / Elsewhere equal
  the typed figures; correct one → the figure follows, one opening row still. Ming unaffected (she is
  past onboarding; her opening rows are read, not written — pot unchanged by SQL).
