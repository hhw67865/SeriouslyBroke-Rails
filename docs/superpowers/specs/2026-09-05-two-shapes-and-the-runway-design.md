# Two Shapes and the Runway: the model gets simpler and the screens get pictures

**Status:** DRAFT — awaiting Henry's review
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
