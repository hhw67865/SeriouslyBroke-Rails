# Computed Claims: the Rules Are the Budget, Nothing Moves

**Status:** DRAFT — awaiting Henry's review
**Date:** 2026-09-03
**Supersedes the purpose-ledger WRITERS of:** `2026-08-21-two-ledger-design.md` (distribute, allocations
as the routine writer). The physical ledger, the entries, the rules, and the answers-first Home
(`2026-09-02`) all survive; this changes how a category's money is KNOWN.

## 1. The ruling this encodes (Henry, 2026-09-03)

> "Maybe distribution shouldn't even be a thing… the rules just create the budget for the
> categories and that all is deducted from available money. That gets rid of the annoying
> distribution step."

A category's money is a **claim computed from its rules, the calendar, and its spending** — not
a balance built by moving money. There is no distribute step, nothing to miss, and the envelope
is knowable at any instant without a single movement. Rulings: rate rules are use-it-or-lose-it by
default (roll-over is a later per-rule option); dated rules accrue from `funded_since`, never
retroactively; free money below zero is a signal that adjusts spending for the rest of the period,
never a refusal to record.

## 2. The model

```
PHYSICAL (unchanged)          PURPOSE (now computed)
  pot = checking                claim(category) = f(rules, calendar, spending, adjustments)
  accounts = mirrors            free = min( pot , total_money − Σ claims )
  total_money = income − expenses          where total_money = pot + Σ accounts

In Checking − Free  =  "where my money is going"  =  Σ claims (+ money parked elsewhere)
```

The physical ledger's invariant (`pot + Σ accounts == income − expenses`) is untouched. The
purpose side stops being a conserved partition: claims are derived, so the old
`available + Σ holdings == total` identity is replaced by the DEFINITION `free = total − Σ claims`
(capped at pot as ruled in the answers-first spec §3).

## 3. How a claim is computed

### 3.1 Rate rule ("$400 per period on Groceries") — use-it-or-lose-it
```
claim = max(0, rate − spent_this_period)
```
Overspending drives the claim to 0 and the excess reduces free directly — the category bar shows
"over". At the period boundary the claim resets to `rate`. Nothing carries. (Roll-over, later, is
the cumulative form Henry named: `max(0, periods_since_start × rate − Σ spent_since_start)`.)

### 3.2 Dated / interval rule ("$5,000 every 2 years, next due …") — accrues toward the target
```
saved         = Σ over periods since funded_since of (planned_accrual − adjustment) − spent_since_last_fulfilment
saved         = clamp(saved, 0, target)
claim         = saved
planned_accrual(this period) = (target − saved_before_this_period) / periods_remaining_until_due
```
- The per-period accrual is the **catch-up formula**, recomputed every period from what is still
  owed and how many periods are left. Underfund one period and the next periods' accrual rises to
  land the target on time — automatically.
- Once `saved == target` the claim stops growing; free stops being reduced; the money sits as a
  $5,000 label on checking until the expense happens.
- **Fulfilment** = an expense on the rule's item (or, for an item-less dated rule, on the
  category) — the claim drops by the amount spent, and accrual restarts toward the next due date.
  A fulfilment larger than the claim spills into free (the category shows "over").
- A dateless target (the old savings goal) is the same formula with no due date: it accrues by
  its rate if it has one, and otherwise only by explicit set-asides (§5).

### 3.3 "Getting by" — period adjustments (the preserved ability)
A **rule adjustment** is a small record `(rule, period, amount)` meaning "this period, accrue
this much instead" — skip (0), reduce, or top up. The catch-up formula does the rest: reduce the
car fund to $50 this period and every remaining period's accrual rises to keep the due date. This
is the one new writer, and it is a plan edit, not a money movement.

### 3.4 What a category shows
- Budgeted (rate): `spent of rate` this period, over in red.
- Dated: `saved of target · next due <date> · $X per period` — the bar is progress toward the
  target.
- Unbudgeted with spending: `spent $X` (unchanged).

## 4. Free below zero

`free < 0` is the signal, never a refusal. The trouble strip shows the shortfall and, in reverse
priority order, which claims are uncovered ("Car repair is short $120; Groceries has $90 left for 18
days"). Priority keeps its job as the **give-way order**. The remedy is spending less for the rest of
the period or editing/adjusting a rule (§3.3); the app suggests the per-day pace that lands the
period at zero.

## 5. What survives as a movement

Explicit **set-asides and releases**: "put $500 into Vacation" / "take $200 back from Car repair".
These are the only routine purpose-side writes left (`Allocation kind: transfer`, both sides category
or free) — the exception path, for goals without rules and for deliberate raids. A set-aside adds to
the category's `saved`; a release subtracts. Income routing and account funding (physical) are
untouched.

## 6. What dies

The Distribute screen and its whole apparatus: `AllocationCalculator`, `AllocationCommitter`,
`DistributionPresenter`, the waterfall, the `allocation`/`sweep` kinds, `DistributionClock`, the
"undistributed period" trouble, `Category.in_fill_order`'s fill semantics (priority survives as
give-way order), the answers-first hero's `remaining_plan` (spoken-for merges into the claim),
and the `funded_since` stamp-on-allocation (rules and set-asides still stamp it — accrual start).

## 7. Migration (real data)

Existing `allocation`/`sweep` rows were distribution mechanics: DELETE them (their effect is now
computed). `transfer` rows (set-asides, routing mirrors on the physical side) stay. Rules and
`funded_since` stay and become the accrual anchors. The physical invariant is verified unchanged
before/after by raw SQL; the purpose side is verified by recomputing every category's claim from
the formula on planted fixtures (the claim is a definition, not a conserved quantity).

## 8. Out of scope

Roll-over rate rules (later, per rule); multi-currency; anything the app doesn't already claim.

## 9. Testing outline

- Claim formulas, both directions with planted literals: rate (under / exactly / over; reset at
  boundary), dated (accrual by period; cap at target; fulfilment drops and restarts; catch-up after
  an adjustment; spill on over-fulfilment), dateless (rule vs set-aside-only), `funded_since` as
  the start (no retroactive accrual).
- Free: the cap both ways, negative with the uncovered list in reverse priority, the per-day pace.
- Adjustments: skip / reduce / top-up each change only their period; catch-up arithmetic pinned.
- Migration: allocation/sweep rows gone, transfers kept, physical Σ unchanged, claims recomputed.
- Home: the hero and bars read the claim readers; every prior copy pin that survives keeps its
  figure; the Distribute nav item and route gone.
