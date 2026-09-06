# Two Shapes and the Runway: the model gets simpler and the screens get pictures

**Status:** DELIVERED (2026-09-05) — plan in
`docs/superpowers/plans/2026-09-05-two-shapes-and-the-runway.md`, tasks 1–5; ledger
`.superpowers/sdd/2026-09-05-two-shapes-and-the-runway/progress.md`. §10 records every ruling the
build took, §11 what it leaves open for Henry.
**Date:** 2026-09-05
**Builds on:** `2026-09-04-rules-own-the-budget-design.md` (DELIVERED — rule types, the form, targets on
rules) and `2026-09-03-computed-claims-design.md` (DELIVERED — the claim formulas). This spec removes
one shape that plan added, changes one formula, and rebuilds three screens on the mocks Henry approved
on 2026-09-05 (`claude.ai/code/artifact/a75c3e69-8da5-4ff8-83ad-2d6c46b49108`, tabs Home / Budget /
New rule form).

## 1. The rulings this encodes (Henry, 2026-09-05)

> "Why is free to spend and the number in checking the same when some is claimed? Shouldn't checking
> show the full number and free to spend is minus the claimed?"

> "I thought build up / reset isn't a thing anymore since nothing really is holding the money any
> more, right? Build up is just a higher target on a timeline longer than a period."

> "Almost all categories will have multiple rules, so we need to base the UI knowing this."

> "Expanded should just show all rules and suggestions. The new rule thing should be a form we go to."

Four consequences:

1. **Free to spend is checking minus what the rules claim.** `free = pot − Σ claims`. Money in other
   accounts is shown, never subtracted from or added to anything. The cap against total money dies.
2. **Two rule shapes.** *Every period* (an allowance that resets with the paycheck) or *by a date* (a
   target, a date, optionally repeating every N months). "Unspent money resets / builds up" leaves the
   form and the model: `budgets.carries_over` and `budgets.target_amount` are dropped — a fund IS a
   dated rule whose `amount` is its target. The open-ended "$X a period forever with no target" shape
   is retired (ruling: an emergency fund is "$10,000 by next September"; raise the target on arrival).
3. **Home is the runway + category blocks**, built for categories with several rules.
4. **Budget is the list of every category**; expanding one shows its rules and its suggestions; a
   new rule is its own page, reached from the category or from a suggestion.

## 2. The model after this spec

```
budgets: amount · basis (per_period | monthly) · interval_months · anchor_date · item_id · rule_type
categories: name · priority · funded_since · color · category_type
```

| the user writes | columns | claim |
|---|---|---|
| $400 every period | per_period, no anchor | `max(0, rate + Σadj − spent)` — §3.1 of computed-claims, unchanged |
| $260 every month | monthly, interval 1, no anchor | the same, with `steady_ask` dividing the month over the grid |
| $600 by Dec 1 (once) | monthly, interval NULL, anchor | catch-up toward `amount` by the date; settles when paid — unchanged |
| $600 by Dec 1, every 6 months | monthly, interval 6, anchor | catch-up, rolls on payment — unchanged |
| $5,000 by Jun 1, 2027 (a goal) | monthly, interval NULL, anchor | **the same one-off shape** — nothing new |

`ClaimCalculator#shape ∈ {:rate, :dated}`; `:building`, `#capped?`, the uncapped arms, and every
reader of `carries_over` go. `#target` = `amount` for `:dated`, 0 for `:rate`. `Budget#set_aside_only?`
(the `amount = 0` permission) goes — every rule has a positive amount. Adjustments are unchanged: a
dated rule takes set aside / take back / skip; a rate rule takes top up / reduce / skip.

**Free:** `ClaimLedger#free = pot − total_claims`; `#unclaimed` and `#free_cap_bound?` die. The
hero's arm table collapses to two facts — how much of checking is claimed, and (separately) how much
sits elsewhere:

| state | headline | subline |
|---|---|---|
| free ≥ 0 | free | "$X of checking is claimed by your rules." (+ ", and $Y sits in N other accounts" when any) |
| free < 0 | free, red | "Your rules claim $X more than checking holds." (+ "Move some in from your other accounts." when they hold money, else "You have spent past what you had.") |

The trouble strip's shortfall arm mirrors it: free < 0 shows the shortfall, the give-way list (type
first, then highest priority number), the per-day pace, and the "move some in" sentence when other
accounts hold money. `HomePresenter#claims_outrun_the_money?`, `#rest_in_checking?`, `#free_cap_bound?`
die; `#anything_claimed?` and `#money_parked_elsewhere?` survive as the two gates.

## 3. Home

```
Where your money stands · Thursday, September 4 · day 4 of 30
┌ In checking  $3,039.33 ┐ ┌ This period ─────────────── 27 days left ┐
│ Free to spend  $885.96 │ │  ●today   ●$143.65  ●$4.99   ●$26.50  ●$120 ●$65 │
│  ▮▮▮▮▮▮▮▮▮▮▮▮ claimed  │ │  Sep 1 ───────────────────────────── Sep 30 │
│ In 3 other accts $222k │ │  $32.81 a day is fine · $360.14 due · Electric $40 short │
└────────────────────────┘ └────────────────────────────────────────────┘
This period · 6 categories · 11 rules · $2,153.37 claimed
┌ Food & Grocery · 2 rules ··· $1,409 claimed ┐ ┌ Utilities · 3 rules ··· $171.50 claimed ┐
│ ▍Whole category   $0 of $1,409  ▬▬▬  resets Oct 1 │ │ ▍Henry's Phone  $26.50 of $26.50 ▬▬▬ Sep 17 · ready │
│ ▍Costco membership $0 of $65   ▬▬▬  Mar 3 · +$5.42 │ │ ▍Electric  $80 of $120 (red) ▬▬  Sep 20 · $40 short │
└───────────────────────────────────────────────────┘ └──────────────────────────────────────────────────┘
```

- **Money column**: In checking; Free to spend (sage tile) with a two-segment bar (free / claimed)
  and the subline from §2; In N other accounts (a smaller figure, chips with the account names).
- **Runway**: the period's span from `User#period_containing(today)`; today's marker at
  `day ÷ days`; one tick per dated rule whose `next_due_on` falls in the period, at its day, labelled
  amount + rule name; green when `claim == target` (ready), red when short (with "$X short" in the
  pace line), olive otherwise. The pace line: `free ÷ days left` ("$X a day is fine"), Σ of ticks
  ("$Y due before <period end>"), and the short ones named. Free < 0 → the pace line reads "$X a day
  less than you're spending lands the period at zero" (the existing per-day pace).
- **Category blocks**: two columns, give-way order (type rank of the category's lowest-ranked rule,
  then highest priority number first — the one sort, `HomePresenter#give_way_order`, grouped back by
  category). Block header: name, rule count, `$ claimed`. Rows: type stripe, rule name (item name or
  "Whole category"), shape words ("usage · a period", "bill · every 12 months", "choice · $5,000 by
  Jun 1, 2027"), figure (`$spent of $rate` / `$built of $target`), bar (green full, red over/short),
  when ("resets Oct 1" / "Sep 17 · ready" / "Apr 2 · +$41.67" / "Sep 20 · $40 short"). A category in
  trouble (any rule over, short or overdue) tints its header.
- **Below**: the give-way sentence, a link to the Budget page, the accounts line (unchanged).
- The trouble strip keeps its place above "This period" and its arms (§2); "over"/"overdue" rows
  read from the same `ClaimLine`s.
- At 375: money column stacks, runway keeps its ticks (labels rotate to two lines), category blocks
  one column, rows keep stripe · name · figure and drop the bar.

## 4. Budget

- **Top**: three tiles — *Your rules need* (Σ standing ask, with the segmented type bar and the
  three totals under it), *You bring in* (declared income · cadence · "change" opens the declaration
  form, which is otherwise hidden), *Left over* (green when it fits, red when it doesn't).
- **The list**: every EXPENSE category of the user (`Category.in_fill_order` plus the rule-less ones
  after), one row each: drag handle, name, rule count, one dot per rule in its type colour, `$ claimed`
  (rule-less: "$X spent in N periods", muted), a suggestion badge (count, amber) when the engine has
  anything for it, a chevron. Order = give-way order; drag reorders as today.
- **Expanded**: the rules table (stripe · name + shape words · now · progress · when · Adjust / Edit —
  the adjust panel opens inline under its row as today), then "Your entries suggest" with that
  category's suggestions (bills for its items, its rate, drift/dead for its rules) — "Write it →"
  goes to the form prefilled, "Hide" as today — then one button: **+ New rule for <category>** →
  `/budgets/new?category_id=<id>`. One category open at a time; the open one remembered per viewer
  (localStorage). Nothing else is on the page: the standalone suggestions panel, the structural-check
  prose block and the always-visible declaration form are gone (their facts live in the tiles).
- `SuggestionEngine#suggestions` is grouped by category once per render (`#by_category`); the
  page's ONE `ClaimLedger` feeds every figure; strict cost pins stay.

## 5. The rule form (its own page)

`/budgets/new?category_id=` and `/budgets/:id/edit`. Breadcrumb "Budget › <category> › New rule".
Two columns: the form, and a sticky preview card.

1. **What is this rule for, and how much?** — "Set aside **$ ___** for **[the whole category ▾ | an
   item]**". The item select lists the category's items; "the whole category" is the default and
   means "anything in <category> no other rule pays".
2. **When is it needed?** — two options with one-line meanings: **Every period** ("a spending
   allowance that resets with your paycheck") · **By a date** ("money saved up toward a day — a bill
   or a goal"), which reveals *Due <date>* and a checkbox *repeats every [N] months*. (`monthly` basis
   without a date — "$260 every month" — is reachable only from a suggestion; the form does not offer
   it, and an existing one edits as "Every period" with its amount shown per month. Ruling: the shape
   stays for existing rows; the form's second option covers what people actually write.)
3. **What kind of rule is this?** — Bill ("must be paid — gives way last") · Usage ("a need you can
   trim") · Choice ("up to you — gives way first").

**Suggestions as chips** above step 1 when the category has any; clicking one fills every blank
(Stimulus, values carried as data attributes — the server still validates); the chip reads "✓ Using
this" while the blanks match it.

**The preview** says the rule back: "*Water gets $48.20 every 2 months, next due Oct 3. Each period
sets aside its share so the money is there on the day. It's a bill, so it's the last thing to give
way.*" and under it the arithmetic: per period, periods until the date, already built up, "Home will
show …". It is rendered by the server (a Turbo Frame refreshed on change, reading `ClaimCalculator`
on the unsaved rule — one spelling of the per-period figure), so it is never a second arithmetic.

`RuleForm`'s words become `schedule ∈ {per_period, by_date}`, `repeats` (bool), `interval_months`,
`anchor_date`, `rule_type`, `amount`, `item_id`; `unspent`/`target_amount` are gone. Mapping:
`by_date + !repeats → interval NULL + anchor`; `by_date + repeats → interval N + anchor`;
`per_period → basis per_period`. Existing `monthly` rows read back as `per_period` with a note.

## 6. Migration — `20260906000000_two_shapes.rb`

1. Every rule with `carries_over = true` becomes a dated one-off: `amount = target_amount` (the
   target), `basis = monthly`, `interval_months = NULL`, `anchor_date =` the date the rule would
   reach its target at its current rate — `today + ceil((target − built_up) ÷ rate)` periods on the
   owner's grid — or one year from today when the rate is 0 (the hand-fed shape). A building rule
   with NO target (uncapped; none exist on dev — receipt) is refused by name. The old rate is kept
   in the receipts (name, old rate, new date) so the owner can correct the date on the Budget page.
2. Verify: physical invariant unchanged; every category's claim identical before and after (a dated
   rule's built-up on a date computed from the same rate reproduces the building rule's built-up —
   pinned on planted fixtures, re-derived in a comment; where rounding moves a cent, the receipt says).
3. Drop `carries_over`, `target_amount`; drop the CHECK. `down` restores the two columns and the
   CHECK — the shape only, not the data (a dated one-off written by `up` stays a dated one-off; the
   header says so). The earlier cutovers' rewind runs through it.

## 7. What dies

`budgets.carries_over`, `budgets.target_amount`, `ClaimCalculator#capped?`/`#building?`/`:building`,
`Budget#set_aside_only?`, `Budget::BUILDS_UP_THE_CATEGORY` + scope + `#builds_up_the_category?`,
`Category#building_rule`/`.fund_is_the_whole_category?`, the "unspent money" step and its Stimulus
reveal, `ClaimLedger#unclaimed`/`#free_cap_bound?`, `HomePresenter#claims_outrun_the_money?`/
`#rest_in_checking?`/`#free_cap_bound?`, the four-arm hero table, the Budget page's standalone
suggestions panel and structural-check block, the dashboard Savings band's building-rule population
(it lists one-off dated rules — "a target by a date" — instead), the "goal" and "fund" words.

## 8. Out of scope

The Entries, Categories, Calendar and Reports pages (they keep their current shape; a later pass
follows this idiom); a mobile-specific navigation; the open-ended fund shape (retired above).

## 9. Testing outline

- **Free**: `pot − Σ claims` both directions; the two hero arms × with/without other accounts; the
  strip's shortfall arm mirrors; every prior copy pin that survives keeps its figure.
- **Shapes**: the five rows of §2 through `ClaimCalculator`; `:building` unconstructible; a
  positive amount required everywhere.
- **Runway**: ticks at the right day for a biweekly and a monthly grid; ready/short/olive colours;
  the pace line both signs of free; a period with no due dates.
- **Home blocks**: give-way order across categories with mixed types; rows per shape; trouble tint;
  true-375 pin; one ledger, strict `eq` cost pins.
- **Budget list**: every expense category present (rule-less included, after the ruled ones); dots
  per rule; badge counts; expand shows rules + only that category's suggestions; "+ New rule" carries
  the category; drag still writes priority; cost pin.
- **Form**: both shapes write the right columns; repeats reveals N; suggestion chip fills the blanks
  and the preview updates; the preview's per-period figure equals `ClaimCalculator#standing_ask`;
  edit of a `monthly` row reads back; a foreign category/item 404s (kept); 375 pin.
- **Migration**: a building rule with a rate → dated with the derived date, claim identical; a
  hand-fed rule → one year; an uncapped rule refused by name; invariant unchanged; `down` round-trips.
- Seeds: the demo's goals re-declared as dated one-offs; `seeds_spec` ALONE.

## 10. As built

Every ruling taken while this was built, in the order the tasks took them. The ledger and the five
task reports beside it (`.superpowers/sdd/2026-09-05-two-shapes-and-the-runway/`) carry the
measurements.

### 10.1 The model and the migration (Task 1)

1. **The migration's frozen walk restates the RETIRED formula, and reads `steady_ask` for the
   rate.** The brief had the pre-conversion built-up read through `ClaimCalculator`; it cannot be —
   `#shape` is `anchor_date.present? ? :dated : :rate` from the same commit, so a pre-conversion
   fund reads there as a RATE rule and `#built_up` answers zero. Measured on the spec's own fixture
   ($150/period toward $1,200, $300 built up), the derivation would walk 8 periods instead of 6 and
   land the anchor two periods late. So the retired arm is restated once inside the migration and
   frozen — but the RATE it charges is `Budget#steady_ask` (via `#charged_rate`), the app's one
   spelling of "what this rule costs a period on this grid", not the raw `amount`. Reading `amount`
   converts a monthly-basis fund at 2.17× its real rate: pinned with a $260-a-month / $5,000-target
   fund on a biweekly grid — $120.00 a period, two walked periods $240, `ceil(4,760 ÷ 120)` = 40
   periods → anchor Aug 11 2027, against an anchor inside 2026 read off `amount`. The receipt prints
   the charged rate with the stated figure beside it only where the two differ.
2. **What is NOT restated is anything still alive**: the grid is `User#period_boundaries` /
   `#period_containing`, the spending lane is the same `Entry.draining` / `Entry.on_unruled_items`
   composition, the adjustments are the rule's own association.
3. **The anchor is derived on the OWNER's grid**, as the last day of the period
   `ceil((target − built up) ÷ rate)` forward from the period containing the owner's today
   (`User#today` — the migration's `today` is the run date in the owner's zone, and the receipts
   print it). A gap already closed is due at this period's close.
4. **A hand-fed fund (rate 0) gets `today + 1 year`, to the day** (`HAND_FED_HORIZON`). An UNCAPPED
   building rule (`carries_over AND target_amount IS NULL`) is refused BY NAME in the preflight,
   before the first write.
5. **"Claims identical" is checked rather than asserted, and a divergence is NAMED.**
   `#check_the_claims` re-finds every converted rule after the write, asks the LIVE `ClaimCalculator`
   for its claim on the owner's today, and names any divergence over one cent in that rule's own
   receipt line — with TWO sentences, because one would be false about half the cases: *"the target
   does not divide by the rate"*, and, for a fund whose charged rate was zero, *"a fund with no rate
   set nothing aside, and the stated horizon now asks for it"*. Pinned on $5,000 at $300/period
   (claim moved $58.80) and on the zero-rate fund (claim moved $357.14, whole line asserted with
   `eq`), with the $1,200-at-$150 fixture pinning the no-divergence direction.
6. **Dev receipts:** 16 funds converted across 4 owners, **0** preflight refusals (dev held no
   uncapped fund), the physical invariant `pot + Σ accounts == income − expenses` unchanged for
   every user. Ming owns none of the 16 and nothing of hers was written. Dev was migrated BEFORE
   ruling 1's correction and was deliberately left as migrated: `#write_the_shape` sets
   `basis = monthly` on every converted row, so a converted fund's PRE-conversion basis is
   unrecoverable after the drop. What the receipts settle is that **15 of the 16 printed
   `was $0.00 a period`** — zero is zero under either reading — and exactly ONE row had a positive
   rate ($400, on a design-review fixture account); it is the only row whose date could differ, and
   only if its basis had been `monthly`. Prod has not been migrated and takes the corrected file.
7. **`down` restores the two columns and the CHECK — the SHAPE only, not the data.** A dated one-off
   written by `up` stays a dated one-off, and the header says so. Registered LAST in
   `spec/support/schema_rewind.rb`.
8. **A dated ONE-OFF is cuttable; only a REPEATING dated rule is fixed.** `SacrificePresenter#reason_for`
   returned `:dated` on any anchor, which made a goal with a distant date the one thing the
   sacrifice screen could not offer to trim — the opposite of what it exists for, and the largest
   claim on the gap it is trying to close. `:dated` is never returned now.
9. **`Budget.saving_toward_a_date` excludes `rule_type: :bill`**, and keeps `item_id IS NULL`. The
   type clause is the classifier ("only a bill is not savings"); the lane clause keeps the scope
   single-valued per category, which `Dashboard::OverviewPresenter#savings_row`'s `#sole` requires.
   Both are pinned in both directions — the fixture plants a one-off `bill` and a `choice` goal whose
   four shape columns are EQUAL, so the exclusion cannot be an accident of the fixture.
10. **The noun for a dated rule is `bill` or `target`, decided by `rule_type`** (with the sharper
    word winning on a mixed category) — `EntryImpactPresenter#noun` is `envelope` / `bill` /
    `target`, and "the fund is short" became "$X short — this needs paying". The rendered word
    "fund" survives ONLY as a bank-account verb ("Fund account"), which is a correct sentence about
    an account.
11. **The hero's red arm gates BOTH halves on `#anything_claimed?`.** §2's table reads as an
    unconditional headline; unconditional it is false for the pure overspend ("your rules claim
    $100.00 more than checking holds" with nothing claimed).
12. **The seeds' goal dates are RELATIVE to the demo's start**, not absolute — `demo_start + 14N − 1`,
    the last day of the Nth period after the rule was written, counted from `demo_start` because
    `#standing_ask` divides by the periods from the rule's BIRTH to its due date, which makes the
    divisor exactly N and every figure a whole cent. Re-tuned so the household is plausibly rather
    than absurdly underwater: the non-goal rules already ask $2,053.42 against a declared $2,050, so
    the three goals ask $183.15, `steady_need` is $2,236.57 and the **gap is $186.57** (asserted
    `< $200`). Two goals with no named date (New Car, Retirement Supplement) are deleted rather than
    given invented ones — kept at plausible dates they put the demo at `free = −$24,568.51`.

### 10.2 Home (Task 2)

13. **A runway tick is never `accruing`, and the third colour is the RAIL's.** A rule due INSIDE this
    period either has its money (`ready`) or does not (`short`); an "accruing" tick would be a rule
    being told it still has time on the day the money is needed. `RunwayTick#state ∈ {ready, short}`,
    and the olive paints the part of the period that has not happened yet. "Still accruing" survives
    as the ROW's sentence for a rule due LATER (`Apr 2 · +$41.67`).
14. **The tick's day index is 1-based and inclusive at both ends**, and today's marker is placed by
    the same `Progress#percent_at` — one ruler, so a tick due today sits exactly on the marker.
    Verified live: a Sep 1–14 period with today Sep 5 draws the marker at `round(5/14) = 36%`,
    Electric due Sep 7 at `round(7/14) = 50%`, Internet due Sep 12 at `round(12/14) = 86%`.
15. **Today's mark is drawn LAST and same-day ticks step 6px each.** Later siblings paint over
    earlier ones in one stacking context, so document order and `z-10` say the same thing twice, and
    a `ring-1 ring-white` separates the 2px mark from whatever it stands on. The nudge is a `Hash`
    keyed by day index in the VIEW — pixels, not money, so not a `RunwayTick` member. Pinned with
    Selenium geometry (the mark's centre inside the tick's rect; two same-day ticks exactly 6px
    apart), never `evaluate_script`.
16. **`ClaimLine#short?` needs the DATE as well as the gap, and it is not a strip trigger.**
    `fund_short?` alone is true of every goal that has not finished saving. `short? = fund_short? &&
    (due_this_period || overdue?)`. The strip's own `#trouble?` (over ‖ overdue) is untouched;
    `CategoryBlock#trouble?` is wider by exactly that one state, deliberately, and both are pinned.
17. **`#pace_line` returns a `Pace` Data and `HomeHelper#pace_words` says it.** No presenter in this
    app formats money, and the sentence has to be identical in two panels at once (the runway's pace
    line and the shortfall strip's remedy).
18. **`PeriodRow` is deleted and the rule-less holder row folded into `#unbudgeted_rows`.** A row per
    CATEGORY cannot say what §3 asks for; its `budgeted?` arm printed the same string `UnbudgetedRow`
    printed, so the two are now one row type.
19. **A one-off's shape words split on the rule's TYPE** (`bill · once, Dec 1` vs
    `choice · $5,000.00 by Jun 1, 2027`), and **the goal's date carries its year while the bill's does
    not** — a goal's horizon is routinely years out and `Jun 1` alone reads as this June.
20. **Two darker text tokens, measured.** `--color-dusty-teal` #7BA3A8 is 2.75:1 on white and
    `--color-terracotta` #C4977A is 2.61:1 — both fail WCAG 1.4.3 as text. `--color-dusty-teal-dark`
    #4B7C82 (4.66:1) and `--color-terracotta-dark` #9E6440 (4.83:1) were added and are used ONLY for
    the type words; the fills are untouched (3:1 is the graphic threshold and the stripes clear it).
21. **At 375 the ticks stack one per line.** Labels positioned along the rail put two bills three
    days apart through each other; a label that has to be READ is worth more than one that has to be
    positioned. The marks stay on the rail with the full label in a `title`.
22. **`claim_figure` / `claim_schedule` survived Task 2 and died in Task 3** — they were rendered by
    two screens outside Task 2's scope, and deleting the names meant either breaking them or changing
    their copy without a ruling.

### 10.3 Budget, and the `paid` state (Task 3)

23. **`ClaimLine` and `ClaimRows` are hoisted to `app/presenters/`.** Three screens carried three
    `Data` types with the same members under different names, each promising in a comment that the
    others were kept in step by hand — and they were NOT: Home printed `$450.00 of $1,200.00` where
    the other two printed `$450.00 built up of $1,200.00`. One row type, one grouping. `ClaimRows`
    queries nothing, which is why Home's cost pin did not move.
24. **A settled one-off is `paid`: never short, never overdue, no tick, no trouble — but `#over?`
    survives.** `ClaimCalculator#settled?` is public and `#settled_on` names the settling day at no
    query cost (the spending rows are already in memory). `#overdue?` gained `&& !settled?`;
    `#fund_short?` gained `&& !paid?`; `HomePresenter#runway_ticks` excludes a paid line, which takes
    its amount out of `#due_total` by construction; `#when_words` reads `paid <date>` first and is
    nil-safe on `next_due_on` throughout. The narrowing stops at `#over?`: a $600 bill paid $700 still
    reads `over by $100.00`, because that excess left checking and hiding it would hide an overspend.
    So the row can read `paid Feb 10` while the strip reads `over by $30.00`, about the same rule, at
    once — pinned.
25. **THE BUDGET LIST IS IN PRIORITY ORDER, and Home's is in give-way order.** A type-first list
    cannot be dragged to write priority: with Rent (bill, p0) beside Fun (choice, p1) the give-way
    order draws `[Fun, Rent]` whatever the numbers say, so "move Fun down" re-rendered an identical
    page under a flash saying the order had changed — while Rent's priority had moved though the user
    never touched it. `#ruled_rows` sorts the blocks by `[priority, name]`, `apply_fill_order` takes
    the drawn order verbatim (the reversal in `#reordered_category_ids` and in
    `reorder_controller.js#submit` is deleted), and the ROWS are still the blocks' own `ClaimLine`s
    and `claimed` figure — the two screens are two readings of ONE set of rows, and only the order is
    this page's. Copy above the list: *"Drag to set which gives way first among rules of the same
    kind — choice always gives way before usage, usage before bills. Home shows them in that give-way
    order."* Cost of the ruling: two orders on two screens, both labelled.
26. **`SuggestionEngine#by_category`** groups the suggestions once per render, and
    `#hidden_by_category` mirrors it so each panel keeps its own "where did it go" answer.
    `SuggestionEngine.category_id_for(subject)` is the one public spelling of subject → category.
27. **Every closed panel is rendered and `hidden`** (expand with no round trip), which costs Ruby and
    markup but never a query — every figure comes off the page's ONE `ClaimLedger` and ONE
    `SuggestionEngine`. `hidden` rather than a class, so Capybara and a screen reader agree with the
    eye.
28. **The write-side redirects carry the category** (`budget_page_path(open: …)`, from both
    `AdjustmentsController` actions and both `SuggestionDismissalsController` actions): without it,
    pressing "Set aside" or "Hide" closes the panel it was pressed in.
29. **`?category_id=` is honoured by `BudgetsController#new`**, folded UNDER a suggestion's own
    `budget[category_id]` and scoped through `current_user.categories` — a stranger's id is a 404.
30. **"Write it →" replaces "Write this rule"**: all four accept controls open a form the user then
    saves, so the noun was a promise the button does not keep.
31. **Two pre-existing defects were found RED AT BASE and fixed**: `RuleForm#repeats` handed the view
    the raw wire string `"true"`, so `check_box` rendered UNCHECKED and an accepted repeating bill
    saved as a ONE-OFF; and `budget_proposals_spec`'s accept payload still sent the retired
    `schedule: "every_n"` / `unspent: "resets"`, so its refusal examples were passing for the wrong
    reason.

### 10.4 The rule form (Task 4)

32. **An unsaved rule is born TODAY** (`ClaimCalculator#rule_born_on`). It answered `nil` for a new
    record, and nil is not "no history" — it is "no lower bound", so the walk fell through to the
    CATEGORY's `funded_since` and priced a rule that does not exist yet against every period since
    the category started holding money. Measured: "$600 by Dec 1" written today on a category funded
    two years ago divided $600 over 58 fortnights instead of 6 — **$10.34 a period on the card
    against the $100.00 it would cost the moment it was saved.** Pinned both ways, and `created_at`
    governs, so no saved row reaches the new arm.
33. **The preview's lanes are `[]` for a new rule and real for an edit.** A rule that does not exist
    has no adjustments by construction, and the spending it WOULD read is the category's — which
    makes the card an answer about this afternoon's receipts. Stated consequence: a NEW rate rule's
    card reads `$0.00 of $400.00` where Home may show spending against it the second it is saved.
34. **"Already built up" reads the calculator on BOTH paths — a pushback on the brief's literal
    $0.00.** For a dated rule the same calculator answers `built_up == planned_this_period` on the
    day it is written (computed-claims §3.2), so a literal $0.00 would sit one line above "Home will
    show $85.00 of $85.00" off the same calculator. The second arithmetic §5 forbids is the cost of
    the literal.
35. **The preview route takes POST *and* PATCH** (`match :preview, via: [:post, :patch], on:
    :collection`). The preview is submitted by a button inside the rule form through its own
    `formaction`, so the fields previewed are exactly the fields a save would carry — and on the edit
    path that form carries Rails' `_method=patch`, which Rack applies to every POST it makes. The
    alternative was a second copy of every field, free to drift from the one the user is filling in.
36. **The preview's date always carries its year**, where the rows print `Sep 17`: the card is read
    seconds after the user typed the date, where a mistyped year is the easiest error to make and the
    one no other figure reveals.
37. **A chip with nothing to fill has no button** (a dead-rule suggestion's payload is the rule's own
    id): its sentence is why the user is on the form, and the decision stays theirs.
38. **A `monthly`-no-anchor rule CONVERTS on read-back, and what it preserves is the MONEY.**
    `RuleForm.from` divides by `Budget#steady_ask` — $260 a month opens and saves as $120.00 a period
    on a fortnight — so the number changes and the cost does not; before, the number survived and the
    cost rose 2.17× under a note that could only warn about it. Three consequences, all shipped:
    `budget_amount_hint`'s `unit:` override is DELETED (the box is per-period money on every path);
    `#converted_from_monthly` carries the ROW's monthly figure rather than `true`, because after the
    division $260.00 exists nowhere else on the page and three sentences have to name it; and
    **`SuggestionEngine#rule_unit_amount` is DELETED** — it inverted the observed per-period figure
    back into the rule's monthly column *because the box held that column raw*, so with the box now
    per-period it had become the trap itself (a drift accept wrote **3.6×** what the panel proposed).
    The identity is the correct conversion now, and a drift accept writes $200.00 a period exactly.
39. **The owner picker is deleted** (`RuleForm#category_options` / `#item_options`, `@owner_picker`,
    the Stimulus item filter, the Budget page header's "New rule" button). A bare `/budgets/new`
    redirects to the Budget page with a flash; the doors are the category panel's "+ New rule for
    &lt;category&gt;" and a suggestion's "Write it →", which are the same door.
40. **Three browser-only defects, found by driving the page and fixed**: a Rails checkbox is TWO
    inputs under one name, and `field("repeats")` found the hidden `value="0"` twin — so the interval
    field was hidden and CLEARED on every render of a repeating bill's edit form; `TagBuilder`
    JSON-encodes a `Date` in a data attribute, so `data-prefill-anchor-date` arrived as `"2026-09-06"`
    *with its quotes* and set the date input to nothing (and the chip then read "Use this" for ever,
    because its own value could never match the blank it had failed to fill); and a Stimulus action
    binds only inside its controller's element, while the chips sit ABOVE the form.

### 10.5 Verified in the browser (Task 5)

A fresh throwaway walked onboarding (two accounts, one funded, main's real balance, a biweekly
declaration) → the Budget page's rule-less rows with their suggestion badges → "+ New rule for
Utilities" → the form's chip filling every blank and flipping to "✓ Using this" → three rules written
through the form, one of each shape (every period; by a date, once; by a date, repeating) → Home's
runway with its ticks measured against the formula (marker 36%, ready tick 50%, short tick 86% on a
Sep 1–14 period), ready/short colours, and all three sentences of the pace line → a take-back
adjustment turning a ready tick short → spending past free → `free = −$898.98` with the hero's red
arm and the strip's "move some in from your other accounts" → the Budget list's rule-less
Subscriptions row → expand → "Write it →" → the form prefilled and reading "✓ Using this" → save →
Home's `free` moving by exactly the new rule's $5.33; then destroyed, with zero rows left in every
table it touched. Console clean (0 errors, 0 warnings) across Home, Budget, the form and the entries
page, for both the throwaway and Ming.

Ming's six claims were recomputed by hand from computed-claims §3 and matched the screen to the cent
($704.50 + $46.88 + $75.72 + $4.99 + $17.67 + $6.43 = **$856.19**), and `free` read
**$3,039.33 − $856.19 = $2,183.14** — where the retired capped formula would have answered the pot
itself, $3,039.33. Her pot was $3,039.33 before and after the browsing and the physical invariant
held; reading never writes. Figures, formulas and screenshots:
`.superpowers/sdd/2026-09-05-two-shapes-and-the-runway/task-5-report.md`.

### 10.6 §7's copy sweep, narrowed

§7 says "the 'goal' and 'fund' words" die. As built, what died is **goal and fund as MODEL nouns and
as a screen's own label** — the columns, the predicates, the constants, the row copy, the impact
card's noun, the dashboard band's population and the category form's placeholder. What survives, by
design and pinned: §5's own option hint on the rule form, *"By a date — money saved up toward a day —
**a bill or a goal**"*, which is the user's informal word for the shape they are choosing; and "Fund
account" on the onboarding card, which is a correct sentence about a bank account. Home's four
panels are swept for the whole retired vocabulary in one example
(`spec/system/home/money_spec.rb`), scoped to the four panels for exactly that reason.

## 11. Open for Henry

### 11.1 Deferred minors (each was found, ruled minor, and left)

1. `app/helpers/search_helper.rb:118` — the placeholder still says "Emergency Fund".
2. The 1-vs-N cost pin on Home plants RATE rules only, so a reader that ran per DATED rule would
   pass it. (The Budget page's equivalent was widened to seven rules of four shapes; Home's was not.)
3. `spec/presenters/budget_page_presenter_spec.rb:798` — an example titled "seven rules" plants five.
4. An untouched `monthly` edit renders the conversion note AND "Currently $260.00 a month." — the
   same fact twice, an inch apart.
5. The conversion note is styled `text-status-warning`, which is a warning's colour for what is now
   an explanation (ruling 38).
6. `RuleForm.per_period_amount` divides on the ROW's owner while the note names the FORM's user. The
   same person in production; they diverge only in `budget_page_helper_spec`'s fixture.
7. `RulePreview`'s "own item of another category" refusal is pinned; its positive arm (a matching
   item still prices) is not.
8. **A chip fills the amount box with the payload's raw value** — the form reads `122.0` where every
   other figure on the page reads `$122.00` (visible in `runway-form-1440.png`). It is a `number`
   input and it saves as `122.00`, so this is cosmetic; the fix is formatting the prefill, not the
   box.

### 11.2 Design consequences worth a decision

1. **A goal accrues every period, so a long-dated goal is a STANDING COST.** `$10,000 by 2033` asks
   its share of every period from today, and `Budget.steady_need` counts it — which is honest (the
   money really is being set aside) and is also why the demo had to drop two goals and re-tune the
   other three to keep the household plausible. Whether a goal should be able to say "as and when"
   is a design call; the open-ended shape this spec retired was the old answer to it.
2. **Two orders on two screens** (ruling 25). Both are labelled and both read the same rows, but a
   user who learns the Budget page's order and then looks at Home sees a different one.
3. **There is no open-ended fund.** An emergency fund must name a date; the ruling is that you raise
   the target on arrival. Nothing in the app prompts that, so an arrived fund goes on claiming its
   target with no accrual and no reminder.
4. **A settled one-off keeps its standing ask** (computed-claims §10.6.7, unchanged here): the
   structural check prices a one-off at `amount ÷ periods from its start through its due date`, a
   constant of its shape, so a paid one-off still counts toward `steady_need` while its row reads
   `paid Sep 2`.
5. **`SuggestionEngine` re-reads six rows the Budget page already holds** (statements 13–18 of its
   cost pin). Handing it the page's `ClaimLedger` is a change to what that class IS, so it is named
   in the pin rather than silently carried.
6. **Every closed panel is in the DOM** (ruling 27). For six categories that is nothing; for forty it
   is forty rules tables and forty suggestion lists. No extra queries; a Turbo frame per panel is the
   answer if it bites.
7. **A quiet period leaves the runway panel two-thirds empty at 1440.** Carried from Task 2's own
   concern and now visible on the delivery's screenshot: Ming's Sep 1–15 has ONE tick, so the panel
   is a rail, one label and two sentences beside a money column three tiles tall.
   `lg:items-start` is deliberate (stretching would put the whitespace inside the panel), but a
   period with nothing due is a large blank rectangle on the page's most-read screen.
8. **Found in Task 5's browser pass, and it is Henry's own data rather than a defect:** Ming's
   figures have MOVED since the computed-claims delivery, because she changed her own budget between
   the two — her cadence went monthly → semimonthly and her Food & Grocery rate went $1,409 → $704.50
   with it, and a sixth rule (Life Time, $180 a year) was added. So the "five claims, Σ $1,668.37"
   pinned on 2026-09-03 is now six claims and Σ $856.19. Nothing in this delivery wrote to her: every
   one of her rows was last written hours BEFORE the plan's base commit, and Task 1 already recorded
   the new figures at BASE.
