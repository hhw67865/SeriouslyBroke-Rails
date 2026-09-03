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
built_up         = Σ over periods since funded_since of (planned_accrual + Σ adjustments in that period) − spent_since_last_fulfilment
built_up         = clamp(built_up, 0, target)
claim         = built_up
planned_accrual(this period) = (target − built_up_before_this_period) / periods_remaining_until_due
```
- The per-period accrual is the **catch-up formula**, recomputed every period from what is still
  owed and how many periods are left. Underfund one period and the next periods' accrual rises to
  land the target on time — automatically.
- Once `built_up == target` the claim stops growing; free stops being reduced; the money sits as a
  $5,000 label on checking until the expense happens.
- **Fulfilment** = an expense on the rule's item (or, for an item-less dated rule, on the
  category) — the claim drops by the amount spent, and accrual restarts toward the next due date.
  A fulfilment larger than the claim spills into free (the category shows "over").
- A dateless target (the old savings goal) is the same formula with no due date: it accrues by
  its rate if it has one, and otherwise only by positive adjustments (§3.3).

### 3.3 Adjustments — dated, signed, as many as you like (Henry, 2026-09-03)
An **adjustment** is a record `(rule, date, signed amount)`: "on Sep 12, −$158 from the car
fund"; "on Sep 20, +$100 into groceries"; "+$500 into Vacation". **Every claim comes from a rule and
every adjustment targets a rule** — a savings goal is a rule with a target (and optionally a rate).
It is a DELTA on the accrual of whatever period contains its date, not an override:
```
accrued(P) = planned(P) + Σ adjustments dated inside P
```
- Skip a period = an adjustment of −planned dated today. Reduce, top up, raid, set aside — same row.
- A negative adjustment larger than the period's planned accrual dips into prior savings (that IS a
  release); the catch-up formula raises later periods to recover the due date.
- **Period-cadence changes are free**: an adjustment lives at a date, so on any grid it lands in the
  period containing that date and sums with its neighbors; nothing is re-keyed and −$158 means −$158
  on either grid. (Rate rules still need a human on a cadence change — see §3.5.)
- Rate rules take the same delta: `claim = max(0, rate + Σ adjustments this period − spent)`.
- This ONE table replaces the purpose-side `allocations` transfers (§5): set-asides and releases are
  simply positive and negative adjustments on the goal's rule.

### 3.4 What a category shows
- Budgeted (rate): `spent of rate` this period, over in red.
- Dated: `built_up of target · next due <date> · $X per period` — the bar is progress toward the
  target.
- Unbudgeted with spending: `spent $X` (unchanged).

### 3.5 Cadence changes
Dated rules are time-proportional (the catch-up formula re-plans on whatever grid exists), so
switching cadence leaves "built_up so far" where it was. Rate rules are per-period by definition, so
on a cadence change the app OFFERS to scale every rate rule ("monthly → biweekly: halve these six
amounts?") — one confirm, the user's choice.

## 4. Free below zero

`free < 0` is the signal, never a refusal. The trouble strip shows the shortfall and, in reverse
priority order, which claims are uncovered ("Car repair is short $120; Groceries has $90 left for 18
days"). Priority keeps its job as the **give-way order**. The remedy is spending less for the rest of
the period or editing/adjusting a rule (§3.3); the app suggests the per-day pace that lands the
period at zero.

## 5. What survives as a movement

Nothing on the purpose side moves. Set-asides and releases ARE adjustments (§3.3) — the
`allocations` table has no purpose-side writer left and is dropped in the migration. Income routing
and account funding (physical, `account_movements`) are untouched.

## 6. What dies

The Distribute screen and its whole apparatus: `AllocationCalculator`, `AllocationCommitter`,
`DistributionPresenter`, the waterfall, the `allocation`/`sweep` kinds, `DistributionClock`, the
"undistributed period" trouble, `Category.in_fill_order`'s fill semantics (priority survives as
give-way order), the answers-first hero's `remaining_plan` (spoken-for merges into the claim),
and the `funded_since` stamp-on-allocation (rules and set-asides still stamp it — accrual start).

## 7. Migration (real data)

Existing `allocation`/`sweep` rows were distribution mechanics: DELETE them (their effect is now
computed). Existing purpose-side `transfer` rows (set-asides/releases) are CONVERTED to adjustments
(the category's rule — minting a target-only rule for a goal that has none — same date, signed by direction); the `allocations` table is then dropped. Rules and
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
