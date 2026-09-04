# Computed Claims: the Rules Are the Budget, Nothing Moves

**Status:** DELIVERED (2026-09-03) — plan `docs/superpowers/plans/2026-09-03-computed-claims.md`,
tasks 1–5; ledger `.superpowers/sdd/2026-09-03-computed-claims/progress.md`. §10 records every
ruling the build took, and §10.6 what it leaves open for Henry.
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

**One category, one catch-all rule** (ruling, 2026-09-03; Task 1). An ITEM-LESS rule's spending lane
is the whole category (§3.2), and a category's money is the SUM of its rules' claims — so two
item-less rules on one category each subtract the same entries, and neither is wrong on its own. A
category may therefore carry at most ONE rule that names no item, beside as many item-backed rules as
it has items, whose lanes are disjoint by construction. Enforced by
`Budget#category_may_hold_one_item_less_rule`. Rows written before this rule exist in real databases,
so readers that guard against the shape (`SuggestionEngine#attributable_rate_rules`) keep their guard.

### 3.1 Rate rule ("$400 per period on Groceries") — use-it-or-lose-it
```
claim = max(0, rate − spent_this_period)
```
Overspending drives the claim to 0 and the excess reduces free directly — the category bar shows
"over". At the period boundary the claim resets to `rate`. Nothing carries.

**`spent_this_period` is the category's spending MINUS the entries on items that carry their own
rule** (ruling, 2026-09-03; the lane partition — see §3.2). The lanes a category's rules read have to
PARTITION its spending, because the category's claim is their SUM: with the catch-all lane containing
the item-backed lanes, one $300 payment lowered two claims, Σ claims fell twice while the user's money
fell once, and `free` ROSE by $300 for having paid a bill. One spelling: `Entry.on_unruled_items`. (Roll-over, later, is
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
  category MINUS the items that carry their own rule — the §3.1 partition) — the claim drops by the
  amount spent, and accrual restarts toward the next due date.
  A fulfilment larger than the claim spills into free (the category shows "over").
- **An item-less dated rule's cycle rolls on the category's spending, never on the calendar**
  (ruling, 2026-09-03). The old `BudgetCalculator` had no fulfilment signal without an item and
  assumed every bill was paid on time; the computed model reads the category's own lane, so an
  occurrence whose money was never spent stays where it was anchored and the row reads overdue
  rather than silently re-aiming six months out.
- A dateless target (the old savings goal) is the same formula with no due date: it accrues by
  its rate if it has one, and otherwise only by positive adjustments (§3.3). **"No rate" is spelled
  as an amount of ZERO** (ruling, 2026-09-03; Task 1): every claim comes from a rule, so a goal fed
  only by hand has to BE a rule, and zero is the only honest way to say it has no standing
  contribution. `Budget` permits a zero amount for exactly that shape — the category names a target
  and the rule names neither an anchor nor an interval — and refuses it everywhere else.

**As built (Task 1), three clauses made precise:**
- **A rule accrues from the LATER of `funded_since` and its own creation** (ruling, 2026-09-03).
  `funded_since` is stamped by a category's FIRST rule, so for that rule the two dates coincide and
  nothing changes; for a rule added later they do not, and walking from the category's date would
  report a fund as already built up the moment it was saved. A rule cannot accrue before it existed.
  The birth day is read in the OWNER's zone, and a rule born mid-period accrues that WHOLE period —
  the start date only decides which period the walk opens in, and "counts in full the day the period
  opens" then applies to it like any other. A rule asked about a day before it was written walks no
  periods at all and holds nothing.
- **The accrual sum and the spending are measured over the SAME span.** Read literally — the accrual
  summed since `funded_since`, the spending only since the last fulfilment — a rule paid twice reads
  FULL the day after it was emptied. Subtracting each period's spending as the walk passes through it
  is the same sentence with the two spans made equal, and it is what makes the other two clauses true
  at once: the built-up "drops by the amount spent" (a $200 part payment leaves $400, not zero) and
  the accrual "restarts toward the next due date" because the cycle rolls on payment.
- **The clamp at zero is applied per period, not only to the final figure.** Overpaying a $600 bill
  by $100 must not put the user $100 further behind next cycle: the fund had $600 and never had
  $700, so the excess spills into free (the money left checking) and the next period starts from
  zero. The figure BEFORE that clamp is what says a category is "over".

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

## 10. As built

Every ruling taken while this was built, in the order the tasks took them. The ledger and the four
task reports beside it (`.superpowers/sdd/2026-09-03-computed-claims/`) carry the measurements.

### 10.1 The claim itself (Task 1)

1. **A rule accrues from the LATER of `funded_since` and its own birth.** `funded_since` is stamped
   by a category's FIRST rule, so for that rule the two dates coincide; for a rule added later they
   do not, and walking from the category's date would report a fund as already built up the moment
   it was saved. The birth day is read in the OWNER's zone (a rule written on a Tokyo evening is
   stored on the previous UTC day, which on a monthly grid is a different first period). A rule born
   mid-period accrues that WHOLE period — the start date only decides which period the walk opens
   in, and pro-rating would be a second, finer clock beside the period grid. A rule asked about a
   day before it was written walks no periods and holds nothing (no phantom period).
2. **One item-less rule per category** (`Budget#category_may_hold_one_item_less_rule`). An item-less
   rule's lane is the whole category and `Category#claim` is a SUM, so two of them subtract the same
   entries twice. Item-backed rules stay per item. `SuggestionEngine#attributable_rate_rules`' own
   `rules.one?` guard is kept — it is now a guard about legacy rows rather than about what the app
   can write.
3. **A dateless target rule may carry `amount = 0`** (`Budget#set_aside_only?`): the category names a
   target and the rule names neither an anchor nor an interval. Every claim comes from a rule, so a
   goal fed only by hand has to BE a rule, and zero is the only honest way to say it has no standing
   contribution. Refused in every other shape.
4. **THE LANE PARTITION.** A catch-all rule's spending lane EXCLUDES entries on items that carry
   their own rule (`Entry.on_unruled_items`, one spelling, composed by both the per-rule calculator
   and the batched ledger). Measured on the demo's own figures before the fix: a $300 bill payment
   lowered the bill's built-up AND the rate rule's claim, Σ claims fell $600 while the money fell
   $300, and `free` ROSE $300 for having paid a bill.
5. **The accrual sum and the spending are measured over the SAME span** — each period's spending is
   subtracted as the walk passes through it. Read literally (accruals since `funded_since`, spending
   since the last fulfilment) a rule paid twice reads FULL the day after it was emptied.
6. **The clamp at zero is applied per period, not only to the final figure**: overpaying a $600 bill
   by $100 spills into free and the next period starts from zero rather than $100 behind. `#over?`
   reads the PRE-clamp figure — the only reader that can tell "spent it exactly" from "spent more
   than it had".
7. **An item-less dated rule's due date is ANCHOR-PINNED**, and that reading is the law going
   forward. `BudgetCalculator` had no fulfilment signal without an item and assumed every bill was
   paid on time; the computed model reads the category's own lane, so an occurrence whose money was
   never spent stays where it was anchored and the row reads overdue. A settled one-off claims
   nothing forever (`#settled?`) — a one-off's due date never rolls.
8. **`spec/support/schema_rewind.rb` was deliberately NOT extended for `CreateAdjustments`**: it
   touches nothing any rewound `down` gives or takes away, and a dead entry there reads as a
   dependency. The file records the measurement (cutover 49, two_ledger 15, drop_the_pool_layer 18,
   green with it left out).
9. **The ledger is batched to ≤3 statements** for any number of rules (measured: 3 for eight rules,
   against 21 unbatched), by asking probe calculators for `#window_start` before it queries.

### 10.2 The writer (Task 2)

10. **Skip means "accrue nothing this period"**: the amount is `−accrued_this_period` (plan + this
    period's deltas), computed on the SERVER and dated today, so a period already topped up by $50
    is taken back by $200 and a period already skipped offers no button at all
    (`Rule#skippable?` reads the same figure). "Nothing to skip" has its own refusal, both halves.
11. **THE COUNTABLE SPAN.** A delta is accepted only where the rule's walk can count it: from the
    OPEN of the period containing the accrual start (§3.2's "counts in full the day the period
    opens" applies to the first period like any other) to `min(today, the last visited period's
    end)` — the upper bound matters because `PERIOD_WALK_LIMIT` can stop the walk short of today. An
    empty walk is an empty span with its own sentence. The refusal lives in `AdjustmentForm`, THE
    ONE TYPED DOOR, and never on the model: the walk's whole subject is summing rows from periods it
    no longer stands in, and §7's migration converts a user's history at its ORIGINAL dates.
12. **A FIRST cadence is not a change.** Until the user names a period their per-period amounts are
    denominated in the 12-a-year fallback — an assumption the app made, not something they said — so
    there is no old unit to convert from. The offer fires only for a declaration that would actually
    save, renders at 422 (nothing is written), and `#apply` computes `scale && offered?` before the
    transaction opens, so a hand-built `scale=1` scales nothing. The flash names only what was
    written.
13. **Only rules whose amount is denominated PER PERIOD scale** (`cadence == :per_period`), whatever
    the category's shape — a "$260 a month" rule already means the same thing on every grid and
    scaling it would apply the ratio twice. **Zero stays zero**: a $0 goal rule is neither offered
    nor rewritten (the `SMALLEST_RATE` floor catches a ROUNDING, never a DECLARATION).
14. **The wire takes a signed amount and the BUTTON carries the direction** (`amount_sign`), so one
    input serves top up / reduce and set aside / take back; the typed date is cast in the owner's
    zone by `ApplicationController`'s existing `around_action`, measured rather than re-parsed.

### 10.3 The screens (Task 3)

15. **A ROW PER CATEGORY, A LINE PER RULE.** §3.4's sentences are per rule and `Category#claim` is a
    sum, so a $400-a-period rate rule beside a $1,200 six-monthly bill cannot honestly print one
    figure. A single-rule category — the ordinary shape — renders exactly as before.
16. **The FIX apparatus dies with the strip's category row.** A fix was an allocation; §5 leaves the
    purpose side with no movements. §4's own remedy (spend less, or edit/adjust a rule) is what the
    shortfall arm says, with one link to /budget.
17. **The hero's noun is CLAIMED** — in checking, free, claimed, built up, spent, of. One arm lost
    its else branch as UNREACHABLE: with two terms in the cap's identity
    (`unclaimed − pot = Σ other accounts − Σ claims`), `free < 0` with `unclaimed ≥ 0` forces
    `pot < 0` and therefore another account holding money.
18. **The trouble strip renders the hero's arm table branch for branch** — the same three gates, the
    same causes — because `free < 0` is a SIGN and every sentence about it asserts a cause. The
    give-way walk is gated on `claims_outrun_the_money?` (otherwise it named categories whose money
    was sitting in a savings account two inches below), the remainder past Σ claims is named on its
    own line, and at one priority the LATER name gives way first.
19. **Overdue fires on the DATE** (`next_due_on < today`, strict), and the FUND STATE is a matter of
    COPY: `the fund is short $500.00 — this needs paying` against `it's all there — pay it and the
    fund starts again`. §3.2's catch-up floors `periods_left` at 1 for a date already past, so the
    ordinary overdue bill reads WHOLE and is waiting to be PAID; gating the trigger on the fund
    silenced the ordinary case rather than a corner of it.
20. **The Budget page's group header is `Σ its rules' claims`**, rules are ordered on the date the
    row PRINTS (not `BudgetCalculator#due_order`, which diverges on an item-less rule), and the
    rule's own sticker stays beside §3.4's figure — this is the page where a rule is edited.
21. **Every rule with a claim gets a row**, including one on a category whose `funded_since` was
    cleared afterwards: `ClaimLedger` counts it into `free`, and a claim with no row would be money
    missing from the hero with nothing on screen to explain it. The per-day pace floors its divisor
    at one — the user still has today.
22. **`today` is the OWNER's day, spelled once** (`User#today = local_day(Time.current)`, reached
    through `Category#today`/`Budget#today`), at 45 call sites. Inside a request `Date.current` was
    already owner-zoned by the `around_action` — the reader is for the job, console, seed or task
    that is not in one, where the ambient zone is UTC and the overdue trigger's sole input would be
    off by the owner's offset.

### 10.4 The deletion and the migration (Task 4)

23. **One transfer can become TWO adjustments** — one per category END (`to_category_id` positive,
    `from_category_id` negative, date verbatim): a category-to-category reallocation really did
    lower one fund and raise another, and converting one end would record half a move.
24. **The minted rule is born before the money it holds.** A target-only rule minted TODAY would
    walk no period any inherited set-aside is dated in, so its `created_at` is the earlier of the
    category's `funded_since` and the first transfer converted onto it — which lands `accrual_start`
    on `funded_since`, §7's own sentence.
25. **History is converted at its ORIGINAL date even where the walk cannot see it** (a March
    set-aside on a rate rule moves no figure — a rate rule is use-it-or-lose-it), and the migration
    counts any such row in its receipt rather than leaving it to be found.
26. **The shape is verified by `Budget`'s predicates RESTATED IN SQL, clause for clause**, not by
    calling `Budget#valid?` — a migration that reaches into today's model is a migration whose
    meaning changes when the model does. Being STRICTER than `Budget` is the failure this verifier
    has already had once (an item-backed $0 rule on a category with a target is a shape the model
    accepts).
27. **The `down` restores the SHAPE and not the rows**, and it has to: the schema rewind runs
    `CategoriesHoldTheMoney#up`, which creates `allocations`, so without an executable `down` here
    three older migration specs cannot reach the world their subjects were written for. This is the
    house's own precedent, verbatim. A re-run on a migrated database raises `PG::UndefinedTable` at
    the first `allocations` read, which is preferred to a guard that would make a second run a
    silent no-op.
28. **Dev receipts:** 60 transfers → 60 adjustments, 8 target-only rules minted, 9 `allocation`/
    `sweep` rows discarded, `allocations` dropped; the physical figure `pot + Σ accounts ==
    income − expenses` unchanged for every user, verified in raw SQL before and after.
29. **`Category#saving_toward_a_target?` is the one DISPLAY predicate** (`holder? &&
    target_amount.present?`). `#savings?` is deleted: its third clause (`budgets.none?`) had a real
    job while a waterfall existed, but under §3.3 every claim comes from a rule, so it selected
    exactly the goals claiming $0.00 — and on migrated data the dashboard's savings band rendered
    nothing at all.
30. **`Category#budgeted? = budgets.load.any?` is the one spelling of "a rule claims this
    category"**, asked by Home's period rows and by the entry form's impact card, which had painted
    a funded ruleless category red for a $0 envelope while Home called the same category unbudgeted.
31. **`#money_may_not_be_stranded` is deleted because the state it refused cannot be reached** — a
    category holds nothing now. Clearing `funded_since` is still not free (the category leaves the
    give-way order and its spending stops being counted), but that is a visible state on a screen
    that names it.
32. **The copy sweep**: fill order → GIVE-WAY order ("which gives way first when you run short"),
    "out of available" → "unbudgeted", "the rules that fill your categories" → "the rules that claim
    your money", "nothing fills it" → "spending here isn't counted against it", and the Distribute
    nav item gone. The seeds are rebuilt on rules + dated adjustments alone, every rule born on
    `demo_start` for ruling 24's reason.

### 10.5 Verified in the browser (Task 5)

A fresh throwaway walked onboarding → a rate rule, a dated rule and a goal → the Budget page's rows
→ skip, top up, set aside and take back → the hero's `free` moving by exactly those amounts →
spending past free → the shortfall arm with the give-way list and the per-day pace → a cadence
change with both answers → the overdue arm; then destroyed, with zero rows left behind. Ming's five
claims were recomputed by hand from §3 and matched the screen to the cent ($1,409.00 + $83.34 +
$144.54 + $4.99 + $26.50 = $1,668.37), and her pot read $3,039.33 in raw SQL before and after the
browsing — reading never writes. Figures, formulas and screenshots:
`.superpowers/sdd/2026-09-03-computed-claims/task-5-report.md`.

### 10.6 Open for Henry

1. **CLOSED by `2026-09-04-rules-own-the-budget` (DELIVERED).** ~~Intra-category give-way order is
   unruled.~~ Every rule now carries a **type** — bill, usage or choice — and the give-way key is
   `[type rank, category rank, rule order]`, so TYPE decides before priority does and a catch-all
   rate rule typed `choice` gives way ahead of an item-backed `bill` on the same category.
   `Budget::TYPE_RANK` is the one spelling of `choice → usage → bill`; `HomePresenter#give_way_key`
   is the one place the three terms meet.
2. **The strip's arm 1 never names money parked elsewhere, though the two can co-occur.** "Your
   rules claim more than you have" is true when `unclaimed < 0`, and a user in that state may ALSO
   be holding money outside checking; arm 3's sentence about it is reachable only when the claims do
   NOT outrun. Whether arm 1 should carry the same clause is a design call.
3. **CLOSED by `2026-09-04-rules-own-the-budget` (DELIVERED).**
   ~~`Category#saving_toward_a_target?` widens the dashboard's Savings band.~~ The predicate is
   deleted and `Category#building_rule` answers instead: the band lists the categories whose
   item-less rule **carries its unspent money over**, capped or not. "Which money is being saved" is
   a question about the SHAPE of a rule rather than about a figure on a neighbouring record — a
   goal fed by a real rate rule is on the band because it builds up, and a rate rule beside a figure
   is not because it does not. `categories.target_amount` is dropped outright.
4. **The adjust panel's "planned this period" is PRE-delta while the row above it is POST-delta.**
   On a rate rule topped up by $50 the row reads `$0.00 of $450.00` and the panel, an inch below,
   reads `$400.00 planned this period`. Both are labelled and the delta list sits between them, but
   they are two "this period" figures an inch apart. The one-line fix is `rule.accrued_this_period`
   in `budget_page/_adjust.html.erb` (it would also make the panel's figure the amount the skip
   button names); it renames a hook three specs read.
5. **The cadence confirm screen's declaration form still shows the OLD cadence.** `current_user` is
   deliberately clean on that path, so the select below the panel reads "Monthly" while the panel
   says the period is changing to biweekly — and the page carries TWO elements with `id`
   `user_period_cadence` (the pending value as a hidden field, the old value as the select). Threading
   `BudgetPagePresenter#declaration` through the offer path is the fix. *(The duplicate id was
   closed in the fix wave; the stale select remains.)*
6. **FIXED in the fix wave (`6c9fcb4`): the hero's last arm asserted "none of it is claimed"
   without asking.** Found live on Ming's Home above five rules claiming $1,668.37. The arm is now
   gated on `#anything_claimed?` and, with claims and parked money both present, names both:
   "$1,668.37 is claimed and more is parked in other accounts." The arm table is pinned in full,
   including the exact tie (Σ claims == Σ other accounts).
7. **A settled one-time bill keeps asking until its rule is deleted** (fix wave 2, `233e349`).
   The structural check prices a one-off at its STANDING ask — `amount ÷ periods from the rule's
   start through its due date`, a constant of the rule's shape — so that "your budget doesn't fit
   your income" cannot flip with this afternoon's spending. The cost of that constancy is that a
   one-off already paid still counts toward `steady_need`; the row beside it reads
   `$0.00 built up of $600.00`. Whether a fulfilled one-off should retire its standing ask (or
   its rule) is a design call.
8. **`spec/system/entries/impact_spec.rb` reads the clock lazily at eight sites** and failed once
   in a full-suite run that crossed UTC midnight (CLAUDE.md's third cause in its crossing form —
   the grid slides a day between a fixture and the request). Passes alone, every time. Freezing
   the clock for the whole file is the only real fix and touches 37 browser fixtures.
