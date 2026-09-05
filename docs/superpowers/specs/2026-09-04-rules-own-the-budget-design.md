# Rules Own the Budget: targets on rules, money that builds up, and a type on every rule

**Status:** DELIVERED (2026-09-04) — plan in `docs/superpowers/plans/2026-09-04-rules-own-the-budget.md`,
as built in §10, open questions in §11.
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

## 10. As built

Four tasks, one branch, no `main`. Every ruling below was taken during the build and is written
down here because a spec that reads like the plan is a spec nobody can trust afterwards.

### 10.1 The migration is TWO files

`db/migrate/20260905000000_rules_own_the_budget_columns.rb` adds `carries_over`, `target_amount`
and `rule_type` to `budgets` with the `budgets_positive_target_amount` CHECK, and does nothing else.
`db/migrate/20260905010000_rules_own_the_budget.rb` is §6's data half: it moves every category
target onto that category's item-less rule, mints one where there is none, types every dated rule
`bill`, verifies, and drops `categories.target_amount`.

**Why two.** The column half had already run on the test database when the data half was written,
and a migration edited after it has run cannot re-run — two files keep both environments migrated by
the ordinary path. They are also two different kinds of statement: a column added is a column
dropped, while the data half's `down` copies a figure back the other way and could only be written
once the column it copies FROM existed.

### 10.2 The shapes, and `capped?`

`ClaimCalculator#shape` is `:dated` if `anchor_date`, `:building` if `carries_over`, `:rate`
otherwise — TWO of the rule's own columns, and no reach for the category. `#capped?` is the one
predicate the two `min(…, target)` sites read, so "uncapped" is spelled once: a dated rule is always
capped (its target is its amount), a building rule only where it names a figure, and a rate rule is
neither. `#target` is **nil** for an uncapped building rule and nil is not zero — zero would make the
gap negative on the first period and plan nothing for ever.

### 10.3 The form

`RuleForm` is the rule's **one typed door**: the wire carries the user's words (`schedule`,
`unspent`, `target_amount`, `rule_type`) and the form object derives `basis`, `interval_months`,
`anchor_date` and `carries_over` from them, so the four-column mapping is spelled once.

- **Edit prefills the amount only, and the category is immutable on update.** A prefill that merged
  the whole query string let a crafted edit link re-parent a rule onto another category on save, and
  left a hidden date in a revealed input that answered 422 about an off-screen control. `category_id`
  is not permitted on update at all (§4: category read-only on edit).
- **Unspent and target are silently ignored where they cannot apply; a stray date is refused.** The
  two are answers to a question the chosen schedule does not ask, so dropping them is dropping noise;
  an `anchor_date` under a per-period schedule is a fact the user typed and is refused by name.
- **The type radio is required with no preselection.** The column's `usage` default exists for rows
  written before the column did; a form that preselected it would put an opinion in the user's mouth.

### 10.4 The give-way order

`[Budget#type_rank, category rank, Category.rule_order]`. `TYPE_RANK` is `choice → usage → bill`,
which is the reverse of the enum's storage order and cannot be the enum's own — re-numbering the
integers to make `sort_by` work would rewrite every row to express an opinion about presentation.

**Within a type, the HIGHEST priority number gives way first** (implementer pushback, accepted). The
plan sketched an ascending sort; the app's existing direction is `Category.in_fill_order` read
BACKWARDS — the category that would have been funded last is the one that goes without first — and
§3 says "category priority as today". `HomePresenter#give_way_rank` is the one place the key is
spelled (the negated index into `#budgeted_categories`), so the drag reorder survives untouched.

### 10.5 Two readers hoisted to one spelling

- `Budget::BUILDS_UP_THE_CATEGORY` — `{ item_id: nil, carries_over: true }` — derives BOTH the
  `.builds_up_the_category` scope (the dashboard's subquery) and `#builds_up_the_category?` (the
  in-memory predicate `Category#building_rule` and `CategoryBudgetPresenter` read over already-loaded
  rows). The question was spelled three times and three copies of a two-clause test is how a strip
  comes to list a set the category pages disagree with.
- **A fund's target and bar are drawn only where the building rule is the category's ONLY rule —
  on every screen** (`Category.fund_is_the_whole_category?`, one spelling; the final fix wave
  `353ec68` widened it from the entry impact card to the categories index card, the show page and
  the dashboard savings strip). On a category carrying a fund beside other rules the impact card's
  denominator is Σ `standing_ask`, the category pages print the category's Σ claims with no bar, and
  the strip prints the fund's own built-up — a bar drawn against the fund's target there would be a
  fraction of the wrong number.

### 10.6 The migration's receipts, and what it refuses

Per user and in total: **targets moved · rules minted · rules typed bill · rules typed usage**, plus
the physical invariant (`pot + Σ accounts == income − expenses`) printed unchanged for every user.

It REFUSES rather than guesses, and all five refusals fire BEFORE the first write: a target category
whose catch-all rule has a due date (`carries_over` cannot be set on a dated rule, and there is
nowhere else to put the figure); a target on a category that is not an expense (no rule may live
there); a target of zero or less (already met, or money the budget owes its owner — named here so it
is not a `PG::CheckViolation` naming no owner); a category carrying TWO item-less rules (they share
one lane, so the target has no single rule to move onto, and picking the older is a decision about
the user's money rather than a tie-break — both ids are named); and a `$0` rule that no target will
repair, which is the shape `DropTheDistribution` left behind wherever its category named no figure.
After the last write it refuses to commit a database where any figure reached no rule, or where any
rule it wrote or touched is a shape `Budget` itself would reject (the validations restated in SQL,
clause for clause).

**Dev run:** 9 targets moved onto rules, 7 rules minted and typed usage, 4 rules typed bill; every
user's physical invariant unchanged. Every receipt figure counts rows this run WROTE — `usage` is the
column's default, so an anchorless rule was already `usage` before the typing statement ran and only
the minted rules were typed usage by this file. **A re-run raises**, loudly and on purpose: `up` drops the column, so a second
run meets `PG::UndefinedColumn` on its first read rather than shrugging.

**What "the claim is identical before and after" means.** Not a comparison against the pre-migration
schema — `ClaimCalculator` already read the rule, so a goal's rule reads as a plain rate rule there.
The figure that must survive is the **computed-claims era's**: §3.2's walk capped at the CATEGORY's
figure. `spec/migrations/rules_own_the_budget_spec.rb` re-derives each from §3's formula in a comment
and plants it as a literal. One shape's claim deliberately changes, and it is the defect §6 names: an
item-backed rate rule on a goal category used to accrue toward the category's figure, and is now what
it always said it was.

### 10.7 Seeds

The demo's five goals are building rules with targets on the rule; `categories.target_amount` is
written nowhere. Every one of the 21 rules names its own type rather than taking the column default:
`bill` on Rent, Dentist, Car Insurance, Vet, Renters Insurance, Quarterly Taxes, Prescriptions and
the Emergency Fund; `usage` on Utilities/Electric, Groceries, Household Supplies, Pet Care, the
Commuter Pass, Medical Copays and the House Down Payment; `choice` on Dining Out, Holiday Gifts,
Streaming, Vacation to Europe, New Car and Retirement Supplement.

**The Electric Bill is `usage` though it has a due date**, and it is the row that keeps the type from
being a synonym for the schedule — "usage is like power bill" is Henry's own example of the word. The
migration's default types every dated rule `bill` precisely because it cannot know that.

Every headline figure survives ($7,461.00 total money, $5,561.00 pot, $10,201.34 claimed, -$2,740.34
free, $2,103.42 standing ask, $210.80 a day). **The give-way LIST changed and the headline did not**:
under priority alone it read Retirement, New Car, House Down Payment and $115.34 of Vacation; House
Down Payment is `usage` and the Emergency Fund is `bill`, so both rank behind every discretionary
rule and the walk now reads Retirement $1,050.00, New Car $525.00, Vacation $520.00 and $645.34 of
Holiday Gifts — the same total, absorbed by four `choice` rules.

## 11. Open for Henry

1. **An uncapped building rule grows without limit and nothing warns.** §2.1 row 2 is the emergency
   fund that "grows for as long as the user keeps it", and that is the declared behaviour — but its
   claim rises every period for ever, so it eats into `free` indefinitely and no screen says so. A
   fund nobody has looked at in two years is indistinguishable from one being used. Whether the
   Budget page should say anything (a "no ceiling" marker, a suggested target) is a design call.
2. **Every pre-existing rule is typed `usage`, and only the user can correct it.** §6 step 3's
   default is the widest of the three, and the Budget page prints the label so it is visible — but a
   database of thirty rules arrives with thirty of them claiming to be "a real need whose amount
   moves with how you live", and the give-way order reads that. There is no bulk retype and no
   prompt; the user meets one rule at a time on the edit form.
3. **An uncapped fund's bar on the entry form's impact card always reads full.** `EntryImpact
   Presenter#building_target` is nil for a fund that names no ceiling (§2.1 row 2), so the card falls
   back to `#steady_claim` — `Σ standing_ask`, what the rules ask of ONE period. The numerator is the
   fund's built-up, which is a walk over EVERY period since it started, so the fraction is ≥ 1 from
   the second period onward and the bar is pinned at 100% for the life of the fund. Nothing is
   arithmetically wrong; the two figures are simply denominated in different spans, and there is no
   honest one-period denominator for a multi-period accrual. The options are a bar that measures the
   period's own movement instead, or no bar at all on that arm — a design call, not a defect fix.
4. **The migration refuses a legacy anchorless `monthly` rule with `interval_months ≠ 1` after its
   writes rather than at preflight.** The five preflight refusals fire before the first write (§10.6);
   this shape is caught by the post-write restatement of `Budget#shape_must_be_valid` in SQL, which
   names the offending row and aborts the transaction. It is already invalid under that validation, so
   no rule the app can write today can reach it — only a row predating the validation could — and
   moving it forward means a sixth preflight query for a shape that may not exist in any real
   database. Whether the earlier, cheaper message is worth that query is Henry's call.
