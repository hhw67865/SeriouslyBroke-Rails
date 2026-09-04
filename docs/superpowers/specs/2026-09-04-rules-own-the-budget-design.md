# Rules Own the Budget: targets on rules, money that builds up, and a type on every rule

**Status:** DRAFT — awaiting Henry's review
**Date:** 2026-09-04
**Builds on:** `2026-09-03-computed-claims-design.md` (DELIVERED). The claim formulas, the
adjustments, the physical ledger and the screens all survive; this changes WHAT A RULE CAN SAY and
moves the last budget figure off categories.

## 1. The rulings this encodes (Henry, 2026-09-04)

> "I thought the rules were what to become of the goal and budget. Even goals is a rule since u set
> a rule for that amount of money right?"

> "Rules should have a option to not give a final number but rather a number saved per period.
> This would be something that you could allow to infinitely grow and u always want to put a
> certain number into it. Adjustments probably shouldn't affect the next period."

> "Perhaps we should give rules a type between bills, usage, choice. Bills are must pays, usage is
> like power bill (can be lowered by adjusting life), choice is like a restaurant. This way we can
> also give an overview between the type as well."

> "Rules form needs to be able to set the complex rules too, not just the per period catchall."

Three consequences, one plan:

1. **A category is a name with a priority.** `categories.target_amount` moves to `budgets`; every
   "how much, by when, toward what" lives on a rule.
2. **A per-period rule chooses what happens to unspent money**: it resets (groceries — today's rate
   rule) or it builds up (an emergency fund), and a rule that builds up may name a target that caps
   it. Adjustments on a building rule touch only the period they are dated in.
3. **Every rule has a type — bill, usage or choice** — shown as an overview on the Budget page and
   used as the give-way order when free money goes below zero.

Also ruled: **no one-time concept.** A rule with a date and no interval already is one; its
fulfilment is an entry; a recurring rule that never gets spent is a funded emergency fund, which is
a good outcome. The form defaults to recurring so one-time is the deliberate choice.

## 2. The rule, as a record

```
budgets
  amount          money   NOT NULL   what the rule puts in (per period / per month / the bill)
  basis           int     NOT NULL   per_period (0) | monthly (1)                 (unchanged)
  interval_months int     NULL       every N months                             (unchanged)
  anchor_date     date    NULL       the due date the interval counts from      (unchanged)
  item_id         uuid    NULL       the item this rule pays, else the category (unchanged)
  carries_over    bool    NOT NULL   NEW  unspent money builds up (true) or resets (false)
  target_amount   money   NULL       NEW  a cap on what builds up; moved off categories
  rule_type       int     NOT NULL   NEW  bill (0) | usage (1) | choice (2)
```

`categories.target_amount` is dropped. `categories.priority` and `funded_since` stay (give-way
tie-break and accrual anchor).

### 2.1 The shapes — the whole family, on the rule's own columns

| the user writes | columns | claim (from the computed-claims formulas) |
|---|---|---|
| **$400 per period, resets** (groceries) | per_period, `carries_over false` | `max(0, rate + Σadj − spent)` this period — §3.1, unchanged |
| **$300 per period, builds up** (emergency fund) | per_period, `carries_over true`, target NULL | the §3.2 walk with **no cap**: Σ over periods of (rate + Σadj in P) − spent, clamped ≥ 0 per period |
| **$200 per period toward $5,000** (vacation) | per_period, `carries_over true`, target 5000 | the same walk, capped at the target — today's "goal", now reading the rule |
| **$0 per period toward $5,000** (fed by hand) | as above, amount 0 | accrues only by positive adjustments — today's minted shape |
| **$260 a month** (either resets or builds) | monthly, interval 1, `carries_over` either | as the two rows above, with `Budget#steady_ask` dividing the month over the grid |
| **$600 every 6 months from Dec 1** | monthly, interval 6, anchor | catch-up toward `amount` by the date — §3.2, unchanged; target IS `amount` |
| **$600 once on Dec 1** | monthly, interval NULL, anchor | catch-up, settles when paid — unchanged |

`ClaimCalculator#shape` becomes: `:dated` if `anchor_date`; `:building` if `carries_over`;
`:rate` otherwise. `#target` reads `rule.target_amount` for `:building` (nil = uncapped) and
`rule.amount` for `:dated`, exactly as now. **No formula changes** — the walk already handles a
dateless target (`planned = min(rate, gap)`, cap in `accrued_in`); an uncapped rule is the same walk
with `gap` infinite and no `min` against the target. One spelling: the calculator gains a
`capped?` predicate and the two `min(…, target)` sites read it.

**Adjustments on a building rule touch only their period** — this is already how the walk works
for a rule with no due date (there is no catch-up without a deadline: `planned_for` returns the
rate, never `gap ÷ periods_left`), so a −$150 in September leaves October asking its plain $300.
Pinned, not built. A dated rule keeps re-planning after an adjustment, as ruled on 2026-09-03.

**Validations** (`Budget`, extending `shape_must_be_valid`):
- `carries_over` requires no `anchor_date` (a dated rule's build-up is defined by its date).
- `target_amount` requires `carries_over` (a cap on money that resets is meaningless), and is > 0.
- `amount = 0` requires `carries_over && target_amount` (today's `set_aside_only?`, re-spelled on
  the rule instead of the category); everywhere else `amount > 0`.
- `rule_type` present.
- The one-catch-all-per-category rule, the item-must-belong rule and the item-claimed uniqueness
  are unchanged.

### 2.2 Cadence changes and the standing ask
- `Budget#cadence` is unchanged; a building per-period rule is `:per_period` and **scales** on a
  cadence change like any per-period rule (its amount is denominated per period). `amount 0` is
  never offered (fix-wave ruling kept).
- `ClaimCalculator#standing_ask` for `:building` = the rate (per period or divided month) —
  constant, like `:rate`. The structural check counts it.

## 3. Rule type

```
bill    — must be paid: rent, insurance, the phone bill's fixed part
usage   — a real need whose amount moves with how you live: power, groceries, fuel
choice  — discretionary: restaurants, hobbies, the vacation fund
```

**Overview** — the Budget page header, above the groups, from `steady_ask` summed by type:
`Bills $1,400.00 · Usage $600.00 · Choice $300.00 a period` (a type with no rules is omitted).
Each group row carries its rule's type as a small label. Home does not change.

**Give-way order** (computed-claims §4) becomes: **choice first, then usage, then bill**; within a
type, category priority as today (lowest first); within a category, the existing rule order. The
walk that lists uncovered claims (`HomePresenter#give_way_order`) reads the type from the rule;
`Category.in_fill_order` and the drag reorder survive as the within-type tie-break. The Budget
page's reorder copy says so ("within each type, lower rules give way first"). This closes the
open question of intra-category order: type decides before priority does.

**Which type a suggestion proposes:** dated-bill suggestions → `bill`; rate and drift suggestions →
`usage`; the accept form shows the type radio so the user confirms before writing.

## 4. The rules form writes every shape

`/budgets/new` and `/budgets/:id/edit` expose, top to bottom:

1. **Category** — select (new) / read-only (edit), as today.
2. **Pays** — "the whole category" (default) or one of the category's items — a select, new on
   both paths. (Today the item only appears when a suggestion pre-filled it.)
3. **Type** — bill / usage / choice, radio, required.
4. **Amount** — as today; its unit is named by the schedule below.
5. **How often** — radio: `per period` (default) · `every month` · `every N months, first due <date>`
   (reveals N and the date) · `once, on <date>` (reveals the date). These map to the four column
   combinations in §2.1; the shape validations produce the errors, under the field that chose.
6. **Unspent money** — shown only for `per period` / `every month`: `resets each period` (default)
   · `builds up` — and `builds up` reveals **Target** (optional; blank = grows without limit).

Edit exposes everything but the category. A shape change on an existing rule (say, a rate rule
becoming a building one) is legal: the claim is computed, so the walk simply re-runs from the
rule's accrual start under the new shape. `BudgetsController::BUDGET_FIELDS` gains the three
columns; `basis`/`interval_months`/`anchor_date` are derived server-side from the "how often"
choice by one small form object (`RuleForm`), so the wire carries the user's words, not the
columns, and the mapping is spelled once.

The declaration/accept path from suggestions keeps prefilling; the type radio and the "pays"
select render prefilled from the suggestion.

## 5. What each screen shows

- **Home period rows**: `:rate` → `spent of rate` (unchanged); `:building` uncapped → `built up
  $X · +$rate per period`; capped → `built up of target · +$rate per period` (the "next due" clause
  is only ever a dated rule's); `:dated` unchanged.
- **Budget page**: the type overview (§3); group rows read as Home's; the adjust panel is
  unchanged (skip / top up / reduce / set aside / take back apply to every shape as today).
- **Categories index/show, dashboard savings strip, entry impact card**: read the target off the
  rule instead of the category. The Savings band lists **building rules** (capped or not) — the
  question "which money is being saved" is answered by the shape, which closes the open question
  about `#saving_toward_a_target?`.
- **Category form**: the target field is deleted; the category form is name, colour, type,
  priority.

## 6. Migration (real data) — `20260905000000_rules_own_the_budget`

1. Add the three columns (`carries_over` default false, `rule_type` default `usage`, `target_amount`
   NULL).
2. For every category with `target_amount`: its item-less rule (exactly one exists for every goal
   that had set-asides — minted on 2026-09-03; for a target category with NO rule, mint one:
   `amount 0`, per_period, `carries_over true`) gets `carries_over = true, target_amount = the
   category's`. Every other anchorless rule keeps `carries_over false` (a rate rule).
3. `rule_type`: `bill` for every rule with an `anchor_date`; `usage` for everything else. The user
   reclassifies from the form; the Budget page shows the label so the default is visible.
4. Verify by raw SQL: the physical invariant untouched (this migration writes no account,
   movement or entry); **every category's claim identical before and after** (recomputed through
   `ClaimCalculator` on planted fixtures in the spec, and by count/sum receipts on dev).
5. Drop `categories.target_amount`. `down` restores the column and copies the target back from the
   rule (the earlier cutovers' rewind runs through it).

Receipts printed: rules given a target, rules minted, rules typed bill/usage.

## 7. What dies

`categories.target_amount` and its form field; `Category#saving_toward_a_target?` (replaced by a
rules-side reader); `Budget#set_aside_only?`'s category read; `ClaimCalculator#shape`'s category
read; the "the schedule itself is already set on this rule" edit form (every field is editable
now); the notion of a "goal category" in code and copy — a goal is a building rule with a target.

## 8. Out of scope

Roll-over on `:rate` rules as a separate concept (a rate rule that carries IS a building rule —
nothing further needed); per-type budgets or limits; a type on categories; anything Home does not
already show.

## 9. Testing outline

- **Shapes**: the seven rows of §2.1, each pinned through `ClaimCalculator` with planted literals
  both directions; uncapped building rule across three periods with spending and a negative
  adjustment (the next period asks the plain rate — pinned by name); capped vs uncapped at the cap.
- **Validations**: every rule in §2.1's list refused and its positive twin accepted.
- **Cadence change**: a building per-period rule scales; `amount 0` not offered.
- **Type**: the overview sums; the give-way walk with three rules of three types and a shortfall
  that splits one — choice first, bill never reached; priority ordering within a type; the Budget
  page label.
- **Form**: every "how often" × "unspent" combination writes the right columns (request spec on
  `RuleForm` + one system pass per shape); edit changes a shape and the claim re-runs; the
  suggestion accept path still prefills; 375 pin for the form.
- **Migration**: targets moved one-to-one, a target category with no rule minted, types assigned,
  claims unchanged before/after, invariant unchanged, `down` round-trips the schema.
- **Screens**: Home row copy per shape; Savings band lists building rules; impact card reads the
  rule's target; every prior copy pin that survives keeps its figure.
- Seeds: the demo's Vacation and Emergency rules re-declared as building rules; `seeds_spec` ALONE.
