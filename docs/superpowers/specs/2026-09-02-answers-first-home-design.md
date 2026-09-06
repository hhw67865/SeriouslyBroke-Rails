# Answers-First Home: Free to Spend, and the Period as Progress

**SUPERSEDED in part by `2026-09-03-computed-claims-design.md`** (DELIVERED 2026-09-03). What died
is every reader here that named a DISTRIBUTION: `#remaining_plan` and the hero's "spoken for"
clause (it named the rest of a distribution's ask — the subline's noun is now CLAIMED, beside
built up, spent and of), the trouble strip's UNDISTRIBUTED trigger, and the FIX apparatus the
strip's category rows carried (`#fix_for`/`#fix_candidates_for`/`#fundable_by`, the fix buttons and
`/allocations/new` behind them) — a fix was an allocation, and nothing on the purpose side moves.
"Set aside" leaves the hero card with them. What SURVIVES is the whole shape of this document: the
four questions in their order, the hero card in every state, `free` capped at the pot (§3's ruling,
now `min(pot, total − Σ claims)`), the period-as-progress bar, the trouble strip and its remaining
triggers, the spent-of-planned rows in "This period" (re-cut on §3.4's per-rule sentences), and the
cause-established discipline the arm table encodes — every one of the hero's sentences is still
gated on a predicate that establishes its cause. The shortfall arm is the fix apparatus's
replacement: the figure, the give-way list in reverse priority, and the per-day pace.

**SUPERSEDED further by `2026-09-05-two-shapes-and-the-runway-design.md`** (DELIVERED 2026-09-05),
which REBUILDS this page. **The hero has TWO arms, not four**, because `free` is no longer capped:
`free = pot − Σ claims`, so the card says how much of checking is claimed and, separately, how much
sits elsewhere — `#free_cap_bound?`, `#claims_outrun_the_money?` and `#rest_in_checking?` are all
deleted, and §7's four-arm table is void. `#anything_claimed?` and `#money_parked_elsewhere?` survive
as the two gates, and the cause-established discipline this document encodes survives with them:
both halves of the negative arm are gated, so "you have spent past what you had" is unreachable while
anything is claimed. **The period-as-progress bar becomes THE RUNWAY** — the same `Progress`, now
carrying one tick per dated rule due inside the period at its own day, `ready` green or `short` red,
under a three-sentence pace line (`free ÷ days left`, `Σ due before <period end>`, and the short ones
named) whose negative-`free` arm is this document's own per-day pace. The spent-of-planned rows
become CATEGORY BLOCKS, a block per category and a row per rule, in give-way order. The trouble strip
keeps its place and its arms; its shortfall arm gained "Move some in from your other accounts."

**Status:** DELIVERED 2026-09-03 (`feature/envelope-budgeting`, commits `917ee35..` — see §10 for
the as-built and the two design calls still open for Henry).
**Was:** APPROVED in chat (Henry, 2026-09-02) — "the mechanism is right but the UI hurts…
all people care about is how much is in their checking account (not total), how much of that is
actually available free money that isn't helping a future payment or necessary for the period,
where we currently are in the period, how much have we spent on each category."
**Builds on:** `2026-08-21-two-ledger-design.md` (DELIVERED). Nothing below changes the
mechanism — this is a re-presentation of the same readers.

## 1. The reframe

Home stops showing the system (ledgers, standing/attention bands, machinery vocabulary) and
answers four questions, in order:

1. **How much is in my checking?** — the physical pot, the number their bank app shows.
2. **How much of that is FREE?** — not set aside in categories, not needed by the rest of this
   period's plan.
3. **Where are we in the period?** — a progress bar, day X of Y.
4. **What have I spent on each category?** — spent-of-planned bars, not envelope balances.

## 2. The hero card (replaces the standing band)

```
In Checking                      $3,039.33     ← AccountLedger#pot
Free to spend                    $1,240.00     ← see §3
(the rest is set aside or spoken for)
Sep 1 ●━━━━━━━━░░░░░░░░ Sep 30 · 18 days left  ← the period reader Home already has
```

- The hero exists for every user state. With nothing funded and spending recorded, "Free to
  spend" simply goes low or negative and the subline says why — this REPLACES the old
  "You're covered / Nothing is set aside yet" branch question entirely.
- A negative pot (physical overdraft) turns the "In Checking" figure red with one plain
  sentence. The old attention band's overdraft strip copy (praised in review) is the model.

## 3. "Free to spend" — the one derived number

```
free = min( pot , available − remaining_plan )
```

- `available` — `CategoryLedger#available` (money with no job).
- `remaining_plan` — what the rest of this period's rules still ask for and have not been
  given: Σ over holder categories of `max(0, this period's ask − allocated this period)`,
  from the SAME readers the Budget page's structural check and the distribute waterfall use
  (one spelling; no new period arithmetic).
- **The cap at `pot` is deliberate** (ruled): free money you'd have to transfer out of savings
  first isn't free in the moment. When the cap binds, the subline says so ("more is parked in
  other accounts").
- `free` may be negative; it renders red with the honest sentence, never clamped.
- ONE user-facing word: **free** (with "set aside" for category holdings and "spoken for" for
  the remaining plan). "Available" survives only on the Distribute and Budget screens as the
  mechanic's term; Home never says it. "Buffer" and "unclaimed" die everywhere.

## 4. "This period" — spending as progress

One section, replacing today's categories band:

```
This period · 18 days left
Groceries      ████████░░   $310 of $400
Dining out     ██████████!  $220 of $180      ← over: red bar + figure
Gas            ███░░░░░░░   $45 of $150
Subscriptions  spent $32                       ← unbudgeted: the fact, no bar, no pressure
```

- Budgeted (holder) categories: spent-this-period of planned-this-period — the INVERSE
  presentation of the same numbers the rows show today ("$90 left" becomes "$310 of $400").
  The row keeps its status vocabulary (on track / behind / overdue) as a small clause where it
  earns its place; savings goals keep the target bar they have.
- Unbudgeted expense categories WITH spending this period: name + "spent $X". Zero spending →
  not listed on Home (the Categories page remains the full index).
- Sort: trouble first (over/behind), then fill order.

## 5. Trouble, only when true

One strip between the hero and the period section, rendered ONLY when something real needs a
human: a physical overdraft, an overdrawn category, an overdue/unreachable bill, a distribute
that hasn't happened this period. No permanent "Nothing needs you" box — silence is the good
state. The fix buttons survive on the strip.

## 6. Everything else demotes

- Other accounts collapse to one quiet line ("$222,544.87 across 3 other accounts") that
  expands to today's account cards (rename/delete/funding cards live in the expansion).
  Onboarding cards still surface top-level while onboarding is incomplete.
- The distribute call-to-action lives on the trouble strip when undistributed, not as a band.
- Machinery vocabulary on Home: gone. The words are *in checking, free, set aside, spoken
  for, spent, of*.

## 7. Riding along in the same delivery (already-approved design calls)

- **Sidebar contrast**: darken the gradient's light end until the existing white wordmark and
  70%-white eyebrows pass AA at every point (recommended and approved by silence — Henry may
  override the shade).
- **Suggestion gating**: drift/dead detectors require 2+ full periods of history; dated-bill
  suggestions require 2+ occurrences of the item; self-disclaimed guesses render without
  primary-button weight.

## 8. Out of scope

- The Budget, Distribute, Categories, Entries screens keep their current structure (their
  vocabulary was just fixed; only words Home kills — "buffer", "unclaimed" — are swept there
  too if present).
- No mechanism changes: no new tables, columns, writers, or ledger arithmetic beyond §3's
  `remaining_plan` composition of existing readers.

## 9. Testing outline

- `free`'s derivation: both cap directions (pot-bound with parked savings; available-bound),
  negative free, negative pot — planted literals, and one example asserting free's inputs come
  from the SAME readers the Budget page uses (no second spelling of the period ask).
- The hero on the three archetypes: fresh user (nothing funded), mid-period budgeter, the
  empty-budget-with-spending state that killed "You're covered".
- Period bars: spent-of-planned figures, the over state, unbudgeted rows, absence of
  zero-spend unbudgeted rows.
- Trouble strip: each trigger both directions; ABSENT when all is well.
- Suggestion gating: day-old account sees zero drift/dead suggestions; 2+ periods unlocks.
- Responsive: hero and bars at 375px; screenshots at 1440 and 375.

## 10. As built

Everything above shipped. What follows is where the delivered screen departs from the letter of
this document, and why — plus the two design calls that are still Henry's to make.

### 10.1 §3's `available` is the POST-SWEEP one

§3 names `CategoryLedger#available`. `HomePresenter#free_to_spend` subtracts
`AllocationCalculator#available` instead — the same root PLUS what the next distribution sweeps
back. It has to be that one: `#remaining_plan` is the ask computed as if the sweep had already
happened (`AllocationCalculator#ask_calculator_for` exists for exactly that reason), so subtracting
a post-sweep ask from a pre-sweep root charges the user for every swept dollar twice — missing from
the left-hand side while the right-hand side already assumes it is back. The two halves have to
describe one moment. Ruled in Task 1; the invariant readers are untouched, this is presentation
arithmetic. (For Ming's real data the two figures are equal — $224,001.81 — because nothing is
sweeping this period, which is the ordinary case; the divergence only appears mid-sweep.)

### 10.2 `remaining_plan` is a RENAME, not a new reader

§3's one-spelling rule wanted the Budget page's and the waterfall's period ask. Grounding found
that sum already existed on the presenter as `#total_required`, so the delivered change is a
rename: `HomePresenter#remaining_plan = waterfall.sum(&:needed)`. The best possible outcome for the
rule — nothing new to keep in step. The cross-entry-point pin reads the **waterfall**, deliberately
NOT `Budget.steady_need`: `steady_need` is the STRUCTURAL question (what the rules claim from a
TYPICAL period) and diverges from this one in both directions on the same budget.

### 10.3 The WATERFALL BAND died with the attention band — §5's list gained it

§5 lists what the trouble strip replaces; as built, that list is one item longer. Home's
distribution waterfall ("where your money goes", the fill order, the cutoff) was the mechanic's
view of the distribution, which is the thing §1 says Home stops showing, so it went with
`_attention.html.erb` rather than surviving beside a card that answers four questions. §6's
distribute call-to-action moved onto the strip's `:undistributed` arm, where it still is.

**Reversion point, named:** the band's markup is `git show 19963aa^:app/views/home/_attention.html.erb`
(i.e. as of `72278e8`); it was removed in `19963aa`. The three readers it was the only caller of —
`#cutoff`, `#shortfall`, `#covered?` — were deleted a commit later in `3eababf` once that was
measured rather than assumed; the presenter names where each question now lives (`Waterfall.cutoff`
via `DistributionPresenter`, `waterfall.sum(&:short)`, the sign of `#free_to_spend`). Restoring the
band means restoring those three too. The mechanic's view itself was not lost: it lives on Budget
and Distribute, which is where §8 leaves those screens.

### 10.4 The trouble strip has FIVE triggers, and `:overdraft` is NON-MAIN only

§5 names four. The fifth is §9's sacrifice link, carried onto the strip from the hero when Task 2
built it. And the overdraft arm fires only for accounts that are NOT main: main's overdraft is
already the hero's red "In Checking" figure with its own sentence (§2), and a strip repeating it
would be the same fact twice on one screen. **Live-confirmed in Task 4:** a throwaway account
driven to a −$200.00 pot renders the red hero figure, "Your checking account is already spent past
zero.", and NO strip at all.

`#pool_problem_label` was deleted with the band; the strip renders `shared/_holding_status`, so
that partial's forced-suffix property is structural now and its one documented exception is gone.

### 10.5 §7's sidebar tokens, measured

The gradient is not decoration — the wordmark, every nav item and the three section eyebrows are
painted on it, and they were the worst-failing text in the app. The **70%-white eyebrow is the
binding constraint**, not the wordmark: `rgba(255,255,255,0.7)` must clear 4.5:1 against the same
background it is 70% of the way toward, a far smaller gap than solid white's.

| Stop | white wordmark | 70%-white eyebrow |
|---|---|---|
| was `#C9C78B` (light end) | 1.75 ✗ | 1.49 ✗ |
| was `#a9a76b` (dark end) | 2.49 ✗ | 1.96 ✗ |
| **now `--color-sidebar-from: #56552B`** | **7.69** ✓ | **4.75** ✓ |
| **now `--color-sidebar-to: #3A391D`** | **11.78** ✓ | **6.69** ✓ |

Other foregrounds, at the light end (the worst case): hover `bg-white/5` → white **6.74**, eyebrow
4.27; sign-out `bg-white/10` → 5.91, its `bg-white/20` hover → 4.60; the active nav item is a white
pill carrying `--color-primary-darker` at 8.81, which the darker ground only sharpens. Every
interior stop passes by construction — channel-wise interpolation is monotone in luminance, so no
stop can be lighter than the light end.

Both values are **HSL(58.4°, 34%)**, the brand sage's own hue and saturation; lightness alone moved
(67%/54% → 25%/17%). Darkened, not rehued. The tokens are the sidebar's own, so `--color-primary`
— a SURFACE everywhere else — was left alone.

*(Three of those figures — 11.78, 6.69, 6.74 — were first written as 11.65, 6.63 and 6.71, a ~1%
rounding slip corrected here and in `custom.css`. No verdict changed. `docs/design-standards.md`
lists no colour values at all, only two prose contrast checklist items, so it gained nothing.)*

### 10.6 §7's "without primary-button weight" clause is RETIRED

The clause assumed self-disclaimed guesses would survive the occurrence gate and merely need
demoting. They do not survive it: `bill_shape` returns nil below `BILL_MIN_OCCURRENCES = 2`, so
`single_occurrence_shape`, `GUESSED_MIN_AMOUNT`, `GUESSED_INTERVAL_MONTHS` and the `detail[:guessed]`
key on all four kinds are deleted, along with the view branch that printed "one payment is not a
schedule…". **Deletion superseded demotion** — a key that is a constant `false` on a money screen is
a branch waiting to be believed. Nothing self-disclaimed is left to render with any weight.

Two figures moved as a result, both single-caused and both named: `seeds_spec` `dated_bill: 6 → 3`
(three of the demo's "bills" were one-off spends) and `budget_page/suggestions_spec` 6 rows → 5.

### 10.7 OPEN — two design calls for Henry

1. **The waterfall band's departure (§10.3).** Home no longer shows where the money goes or where
   it runs out; the strip's `:undistributed` arm links to Distribute instead. This is the biggest
   single subtraction in the delivery and it was made on §1's authority, not asked for by name.
   Reversion point above.
2. **Two figures an inch apart, on purpose.** The house principle is that no two figures a reader
   could add sit next to each other. The trouble strip breaks it deliberately: an at-risk category
   prints its figure on the strip ("behind $102.68") and again on its own period row an inch below,
   because the strip is a list of *things that need you* and the section is a list of *what you
   spent* — the same category legitimately appears in both. Verified live on real data
   (`mingguan0809`, two behind categories). If the repetition reads as an error rather than as two
   answers, the fix is to drop the figure from the strip and leave the name.

*The third observation from Task 4's browser pass — the pure-overspend subline — is **CLOSED**, by
the fix in §10.8 below. It was one corner of a larger fault and was fixed with it, not separately.*

### 10.8 The hero's sublines assert CAUSES, and every gate now establishes one

The FINAL whole-plan review found the class of bug this plan existed to kill, still alive on the
card that replaced the band: three of the subline's sentences named a CAUSE and were gated on the
SIGNS of two figures, which do not carry one. The cap's identity is why:

```
available − pot  =  net moves out of main  +  what the next distribution sweeps back  −  Σ holdings
```

The cap-bound arms attributed the whole difference to the FIRST term. The third makes it true with
no second account in existence: a single-account user whose holders are collectively overdrawn read
*"The money that isn't spoken for is sitting outside checking"* above a trouble strip naming the
overdrawn category and an accounts line with nothing in it. Worked fixture: $1,000 in, $900 into
Groceries, $1,100 straight out of Groceries — pot −$100, `available` $100, nothing spoken for, cap
bound.

**As built, five arms, each gated on a predicate that establishes its sentence** (the full table,
signs × causes, is the comment above `HomePresenter#rest_in_checking?`):

| State | Cause established by | Sentence |
|---|---|---|
| plan outruns the money | `#anything_set_aside_or_spoken_for?` | "More is set aside or spoken for than you have. Anything you spend now takes you further under." |
| plan outruns the money, and neither noun is true of the account | the same, false (§10.7's third flag) | "You have spent past what you had. Anything you spend now takes you further under." |
| free negative, plan does not outrun (the cap bound on a negative pot) | `#money_parked_elsewhere?` | "The money that isn't spoken for is sitting outside checking — nothing here is free until some of it moves in." |
| the same, with no other account holding anything | the same, false | "Nothing here is free until money comes in." — true only here: with nothing elsewhere, a negative pot IS the whole of the user's cash |
| free fine, and there is a rest | `#rest_in_checking?` + `#anything_set_aside_or_spoken_for?` | "the rest is set aside or spoken for." |
| the same, with neither noun true of the account | the second, false | "the rest isn't set aside or spoken for." |
| free fine, none of it claimed | `#free_cap_bound?` + `#money_parked_elsewhere?` | "none of it is set aside or spoken for" — with "— more is parked in other accounts" only where a second account actually holds money |

**"The rest" was the last arm gated on arithmetic, and it broke the same way** (re-review round 2).
The claim was that a positive `rest` can never exceed what is set aside plus what is spoken for,
because `rest` expands to `Σ holdings + remaining_plan − moves out − swept` with both subtrahends
"≥ 0". `moves out` is a NET and goes negative: money walking INTO main raises the pot and leaves
`available` alone. $1,000 of income plus $200 walked out of an Ally that is $200 in the red is a $200
rest with nothing held and nothing asked for — and the card called it set aside. The arm asks
`#anything_set_aside_or_spoken_for?` as well now, and the corner where that is false says "the rest
isn't set aside or spoken for": the rest is there, it is not earmarked, and the card does not guess
what it is. (By elimination it is money walked in from another account; the accounts line and the
strip are where that account is named.)

Two smaller corners closed with it. **The pure overspend** (§10.7's third flag) is the second row:
nothing set aside, nothing spoken for, simply spent past zero. **The fresh signup** is the last: free
and the pot are the same figure because nothing is funded, so the card was describing a "rest" of
$0.00 — as it was on every cap-bound state, where the rest is always zero. `#money_parked_elsewhere?`
is `#other_accounts_total.positive?`, the SAME sum the accounts line prints, so the card cannot claim
money the line below it shows as absent.

Cost: the card now reads the purpose ledger (`#anything_set_aside_or_spoken_for?` asks each holder
what it is holding) when no rule is asking — four grouped aggregates, memoised, and the same four
every holding status on the screen reads. Whichever asks first pays. Pinned three ways in
`spec/presenters/home_presenter_spec.rb`'s hero-cost block.

### 10.9 §3's "only on Distribute and Budget" is three screens, and Home has two ruled exceptions

**Reports is the third.** `dashboard/_expenses_tab` heads its two lanes "Out of Available" / "Out of
an Envelope" and labels its stat cards "Tracked Available Spending". This is not drift: it is where
§3's own sweep put the word — the lane used to be "out of the buffer", and "buffer" is the word §3
retires. Reports is the mechanic's screen in the same sense Distribute is, so the noun stays; §3's
sentence is the one that was too narrow.

**The register on Reports, made one** (the review's M-2): the All tab's legend read "Out of
available" / "Out of an envelope" beside the Expenses tab's Title-Cased headings for the same two
lanes — one pair of phrases, two casings, one screen. The legend is Title-Cased to match, because it
is a LABEL beside a swatch and Reports Title-Cases every label it has. Inside a SENTENCE the word
stays lowercase — "No spending out of available", which is Budget's own convention ("Left over →
available"). Held by `spec/system/dashboard/index/all_tab_spec.rb`, whose `have_content` is
case-sensitive.

**Home says the word twice, both ruled, neither a leak:**

1. The trouble strip's fix button names AVAILABLE as a **source** — "Take $300.00 from Available" is
   `ReallocationPresenter::Root#name`, the mechanic's term on the screen that button opens, not Home
   describing the user's money. Ruled in Task 2 and carried through Task 3's sweep.
2. The post-distribute **flash** prints "$600.00 stays available."
   (`DistributionConfirmationHelper`). It lands on Home because that is where Distribute redirects,
   but it is Distribute's voice reporting what it just did — the same reason the fix button keeps its
   noun. Deliberate; recorded here rather than swept.

Both are why the page-wide dead-words pin in `hero_spec.rb` is shaped the way it is: a comfortable
user with no fix to offer and no flash. The scoped pins (the card, the "This period" section) carry
the rule everywhere else.

### 10.10 Open, recorded, not fixed

Four findings from the FINAL review that are real and were left alone, so the next reader finds them
written down rather than rediscovering them:

1. **Home's "free" and Distribute's "available" are different numbers on purpose, and nothing says
   so.** Home caps free at the pot (§3's ruled cap); Distribute hands out the whole root. A user with
   money in savings reads a smaller number on Home than the screen it links to offers to distribute.
   The cap explains it; no copy on either screen does.
2. **No whole-page query pin.** The hero and the "This period" section are each pinned; nothing pins
   what a Home render costs end to end, so a reader added to a third band would pass both.
3. **The trouble strip can name a holder the "This period" section hides.** A category overdrawn in a
   PRIOR period appears on the strip (with its "· last period" suffix) while the section, which is
   about this period, does not list it. This is the mirror of §10.7 #2: the same category legitimately
   appearing in one list and not the other, and it reads as a missing row rather than as two answers.
4. **The entry impact card says "your available money covers the difference"**
   (`entries/_impact.html.erb`) without reading a root, and it predates this plan. The rename
   sharpened it rather than caused it: "available" is now a word Home itself never says, so this card
   is the one place in the entry flow still using it in the old sense.
