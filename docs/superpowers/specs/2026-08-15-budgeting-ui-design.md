# Budgeting UI — Design

**Date:** 2026-08-15
**Status:** Approved design, pending implementation plan
**Builds on:** `docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md` (the domain model, delivered by Plan 1)

## 1. What this is

Plan 1 built the domain model with no user-facing screens. This spec covers the
UI: what the app looks like once envelope budgeting is the point of it.

The existing tracking half — Entries, Categories, Calendar, the dashboard's
charts — is good and largely survives. What it cannot do is answer the question
the app now exists for:

> Where do I stand, and what do I have to do to be alright?

Every screen below is judged against that sentence.

### 1.1 Governing principles

These emerged during design and resolve most detail questions on their own.

1. **Each screen has one job.** Entry records what happened. Home explains where
   you stand and offers fixes. Distribution allocates. Rules is where the budget
   is edited. No screen borrows another's job.
2. **A pool never renders as a cash balance unless the money is genuinely
   spendable.** Anything being saved toward a date shows progress and a date, not
   an amount you might spend.
3. **Show a consequence only when there is one.** A warning that fires on a
   normal state is noise, and teaches people to ignore warnings.
4. **Never silently move money.** The app proposes; the user confirms — with no
   exception. Sweeping a closed period's leftover and covering a deficit from the
   buffer are both *shown* before they happen and *moved* only as lines of a
   distribution the user confirmed (§7.2).
5. **Any action that shifts money forward must state what it costs later.**
6. **Nothing blocks recording reality.** Entries are facts. The app says what a
   fact cost; it never refuses one.

## 2. Navigation

The tracking pages are not bad and mostly do not change. What changes is what
comes first.

```
Home        pools — where you stand            (was: Dashboard)
Entries     the ledger                          unchanged
Categories  per-category detail                 one change, see §8
Budget      rules, priority, suggestions        NEW
Calendar    month/week grid                     unchanged
Reports     the existing charts and tabs        (was: Dashboard, demoted)
```

The dashboard is not weakened — it is relocated. It answers *what happened*,
which is a question you visit deliberately, not the first thing you should see.

## 3. Periods replace paychecks

**This is a model change, and it simplifies rather than complicates.**

Plan 1 inferred the planning rhythm from income: one `pay_cadence`, one anchor.
That breaks for anyone with two jobs or irregular income, and it was never
necessary — allocation already works off the account balance, not off an income
amount.

So the user **declares a period**, and income is untethered from it.

| | Plan 1 | now |
| --- | --- | --- |
| user declares | pay cadence + anchor | **budget period** + typical income per period |
| divisor in the maths | paychecks until due | **periods** until due |
| triggers allocation | logging an income entry | the user, whenever, against the balance |
| multiple jobs | broken | **a non-question** |
| irregular income | broken | works |

The arithmetic is unchanged — `required = shortfall / N`. Only what `N` counts
changes, from something inferred to something stated.

**A period need not align with an income event.** It is recommended, and the
detected default will align, but a period with no income in it is normal and must
never read as a crisis.

### 3.1 Schema

```ruby
users
  pay_cadence      → period_cadence       # rename, same enum
  pay_anchor_date  → period_anchor_date   # rename
  + typical_income   money, scale: 2      # NEW — user-declared, never inferred

pools
  target_amount    # now permitted on pool_type: account — the buffer target
```

`User#pay_dates(from:, to:)` becomes `User#period_boundaries(from:, to:)`. Every
calculator call site changes name only; `BudgetCalculator#periods_until_due` keeps
its shape and its 88 examples.

## 4. Home

Three stacked bands, in this order.

### 4.1 Standing — one sentence

```
You're $768 short this period
You need $1,668 to stay on schedule. You have $900. Buffer $0.
```

or, when covered:

```
You're covered through Feb 19
$1,199 stays in your buffer after this period.
```

`$1,668` is `sum(pool.required)` across all pools. This is the answer to *"how
much do I need this period to not go negative"* — stated, never derived by the
reader.

**"after this period" is load-bearing.** §4.3's account headers print a buffer
too, and it is a *different quantity*: the cash in that one account right now,
before this period's funding leaves it. Both figures are correct, neither is
derivable from the other, and the bare word "buffer" over the two of them on one
screen invites the reader to treat the per-account figures as a breakdown of this
one. The headers say `buffer now`; this sentence says `after this period`.

### 4.2 Needs you — problems, each carrying its fix

Only pools that actually end up unfunded appear here, and each names a **specific
source that can genuinely cover it**:

```
Dentist — $300 due Feb 14, and no period arrives first
This has to come from money you already have.
  [ Take $300 from Rent ]  [ Take from another pool… ]
  Rent still makes Mar 1 — you'd put in $800 next period instead of $500.
```

The fix states its own consequence (principle 5). A problem with no fix available
says so plainly rather than offering a dead button.

Below the problems, **the waterfall** — where the money went, with a visible
cutoff line, **drag-reorderable in place**:

```
1 · Rent         $500   funded
2 · Utilities     $45   funded
3 · Groceries    $355 of $400
─── ran out here ─────────────  $768 unfunded
4 · Dentist        $0 of $300
5 · Car            $0 of $273
6 · Vacation       $0 of $150
```

Reordering changes who gets funded first and takes effect immediately.

### 4.3 Pools

Grouped by account, buffer shown per account:

```
Checking                       buffer now $900.00 · target $2,000.00
```

`buffer now` is the cash sitting in that account today — see §4.1 for why the
time word cannot be dropped. `target` is the account's buffer marker (§7.1), a
health line and never a cap, and it is named rather than written as a bare
`of $2,000.00`, which reads as a denominator without saying what it measures.

**Collapsed by default; anything short, overdrawn or overdue auto-expands**, so
trouble is never hidden behind a chevron. A healthy envelope is one quiet line.

### 4.4 The row vocabulary

Six states. A pool's kind is derived from its rules — anchored rules accumulate,
rate rules reset — so the user never configures which display they get.

| state | shown as | meaning |
| --- | --- | --- |
| on track | `$1,000 · on track · Mar 1` | accumulating, current rate arrives in time. **Most pools most of the time — deliberately the quietest thing on screen.** Balance is shown. |
| behind | `behind $385 · Mar 1` | knocked off schedule. The number is *how much extra*, not the gap to target. |
| won't make it | `won't make it · Feb 14` | not enough periods remain at any rate. Only fixable by moving money. |
| left to spend | `$240 left` | a rate envelope. The only kind showing a spendable number. |
| overdrawn | `overdrawn $50` | spent money the envelope did not have. |
| overdue | `overdue · was Mar 1` | the date passed with no payment recorded. The money may still be there. |

**behind** and **won't make it** are deliberately separate: one costs more per
period, the other cannot be fixed by any amount of future funding. Collapsing
them would hide that they need different actions.

One **suffix** can attach to any of the six states: `· last period`, when the
envelope's rate period has closed and its money is still sitting there awaiting
the next distribution (§7.2). It is a fact about which period the money belongs
to, not a seventh state, so it appends rather than replaces — `$60 left · last
period`, and equally `overdrawn $80 · last period`.

## 5. Distribution

Runs about twice a month. Fast when nothing needs you, deliberate when something
does — **the same screen at two densities, chosen by the data, not by a setting.**

- **All clear** → headline, one summary line, one button.
- **Anything short or overdue** → the full waterfall, no collapse. A single
  confirm button on a short distribution would let someone quietly starve the
  bottom three envelopes.

  "Overdue" here means the red states — `overdue` and `won't make it` — on any
  pool the screen renders, and it applies **even when the pool is asking for
  nothing**: an overdue bill that is already funded is rejected from the
  waterfall's rows, and collapsing the screen to "all clear, one button" over
  the top of it would be a lie. `behind` is amber and common; including it would
  collapse the two densities into one.

```
Distribute $2,867
  Buffer carried over            $382
  Income this period           $2,400
  Swept back from Groceries, Gas  $85
  ─────────────────────────────────────
  Available                    $2,867

1  Rent        $1,000 of $2,000 · due Mar 1 · 2 periods left   [ 200.00 ]
   ↳ You're moving $300 onto your next period. Feb 20 will need
     $800 instead of $500 — it's the last period before Mar 1.
...
   Stays in buffer   $382 → $1,419 · you wanted $2,000          1,419.00

[ Confirm distribution ]  [ Reset Rent to $500 ]
```

Every line is editable. **Editing recalculates the schedule and shows the
consequence** — but only when the per-period ask actually changes. Editing a
dateless goal shows nothing, because nothing changes.

**An edit here is a one-off override for this distribution, not a rule change.**
The rule still says $500 a period; you chose to put in $200 this once, and the
shortfall compresses into the periods that remain. Changing the rule itself
happens on the Budget page (§8) and behaves differently — it changes every future
period. The two are easy to confuse and must not look alike.

An edit that leaves an envelope unable to recover (no periods remain before its
due date) uses the **won't make it** red, not the amber of a trade. It is not a
new state; the edit pushed the pool into an existing one.

Confirming writes all `PoolMovement`s in one transaction.

**Cross-account transfers are out of scope.** Money stays in one account; if the
user physically moves money to a real savings account they record that as a
change. `PoolMovement#crosses_accounts?` remains in the model, unused by the UI.

## 6. Logging an expense

The daily action, and the one most at risk from the new complexity. It keeps its
current shape: **category → item → amount**, matching today's form and its numpad.

The only thing budgeting adds is the envelope impact:

```
Groceries envelope
$240  →  $185 left                     until Feb 19
▓▓▓▓▓▓░░░░░░
```

- **The envelope is derived, never picked.** The user chooses a category as they
  do today; the pool follows. The form has fewer fields than the model has
  concepts.
- **Impact always shows** — it is the *can I afford this* answer at the moment
  it is wanted, not merely a warning.
- **Nothing blocks.** Overdrawing shows the envelope going negative and says the
  buffer can cover it. The button reads "Save anyway."
- **No schedule consequences and no fixes here.** "Next period needs $273 instead
  of $13" belongs on Home. Entry stays single-purpose (principle 1).

## 7. Buffer, sweeping, deficits

### 7.1 The buffer

The buffer is not a pool or a special object. **It is the money in an account
that no envelope has claimed** — which is why it shrinks when you overspend and
grows when you underspend, with no special logic.

`Pool#target_amount` on an account is the buffer target. It is a **health marker,
never a cap** — the buffer grows without limit, and the user chooses when to move
some to savings. The app never auto-drains it.

**The trend matters more than the level.** A $1,800 buffer falling $200 a period
is in worse shape than an $800 one climbing. `Buffer down $150 over 3 periods` is
the sentence that catches a slow bleed before it becomes a crisis.

### 7.2 Sweeping and deficits

Only **rate** envelopes reset, so only they need a rollover policy. An anchored
envelope going negative needs no new rule — its shortfall simply grows and
`required` goes up.

At period rollover, for each rate envelope:

- **Leftover sweeps back to the buffer.** Use it or lose it. Being frugal grows
  your shock absorber rather than your grocery money — the self-correcting
  property: frugal period → roomier next distribution; blown period → tighter one.
- **A deficit is covered from the buffer.** The envelope resets to zero, the
  buffer takes the hit.

**Savings pools never sweep.** Savings accumulate by definition. This is a rule
about the pool's **type**, not about the shape of its rules: a dateless goal is a
rate rule on a savings pool, so a sweep written as "every rate envelope" empties
every goal the user has. Sweep eligibility is `pool_type_budget?`, always.

**An envelope with a live dated rule sweeps only what that rule is not holding.**
Part of its balance is spoken for by a bill nobody has paid yet, so the sweep
takes the balance **less** what the live dated rules hold: the bill's reserve
stays, the expired rate rule's leftover goes. A gate instead of a subtraction —
"any live dated rule blocks the sweep" — would strand that leftover forever,
because a recurring bill is never settled and so is live in every period. What
each dated rule holds is its **allocation** (domain spec §4.3), the same earliest-due-first
split every other reader uses, so an under-funded bill reserves what it actually
has rather than what it wants. Where an envelope carries rules on different
bases, the **latest** period end governs, for the same reason.

**Sweeping and covering are computed, not scheduled.** No background job. The
sweep is derived on read and materialised at the next distribution — but the
derived half **marks** the money, it does not move it:

- **Derived on read: the envelope keeps showing its real balance, marked as
  belonging to a period that is over.** `$60 · last period`. It does *not* render
  `$0` with the leftover already counted in the buffer — the $60 is physically in
  Groceries until a distribution moves it, and `Σ pools == your bank balance` is
  the invariant this whole app rests on. A display that is right about intent and
  wrong about location breaks it, and there is no reading of the screen that
  recovers where the money actually is. The marker creates the same pressure to
  distribute without inventing a state the ledger does not agree with.
- **Materialised at the next distribution**, as its first lines — `swept back
  from Groceries $60` — so the ledger has real `PoolMovement` rows and the money
  visibly moves as part of an action the user took rather than while they were
  not looking.

Without the first half a user who skips a distribution cannot tell stale money
from this period's; without the second the movement ledger has gaps. The marked
amount and the materialised rows are the same calculation, so they cannot drift.

A **deficit** needs no new **state**: an overspent envelope already reads
`overdrawn`, which is the loudest state in the app. It still carries the
`· last period` suffix once its period has closed — the suffix is a fact about
which period the money belongs to, not about how the pool is doing, so it
attaches to `overdrawn $80 · last period` exactly as it does to a healthy row. It
sweeps nothing — there is nothing to give back — and the next distribution
refills it, the buffer taking the hit.

Chronic overspending is caught by the **buffer trend**, not by a permanently
negative envelope.

### 7.3 The account can never be over-allocated

Distribution can only hand out cash that exists — already true of the waterfall.
When pools need more than the total, there are exactly three moves and the UI
names all three: **increase the total** (move from savings back to the account),
**cut rules**, or **let something slip**.

## 8. Budget — the rules page

**Not onboarding.** A permanent page holding current rules and live proposals
together. A brand-new user sees the same page with an empty top half and a full
bottom half, which fills in as they use the app. There is no separate onboarding
flow to build or maintain.

**Top: active rules**, drag-ordered — this is where funding priority is set.
Default order is by due date. Below them, the structural check:

```
Your rules need        $1,668 a period
You typically bring in $2,400 a period
Left over               $732 → buffer
```

**Bottom: suggestions, always running**, derived from entry history:

| kind | example |
| --- | --- |
| dated bill detected | `$600 in Mar and Sep → every 6 months, next Mar 1` |
| rate detected | `Coffee — $35 a period for 6 months, currently comes out of your buffer` |
| **drift in an existing rule** | `Groceries has averaged $470 for 4 periods, your rule says $420` |
| **dead rule** | `Netflix stopped in October, the rule is still funding it` |

The last two are the reason this page is permanent rather than a wizard. Drift is
how budgets quietly stop matching reality, and a one-time setup can never catch
it.

**Suggestions cannot be dismissed** (for now). Dismissal risks hiding a real
drift, and the alternative — resurfacing after N periods — is nagging with extra
machinery.

**Detection rules:** a varying bill uses its **highest** observed amount (safer,
over-reserves). A single-occurrence item is proposed with its guessed interval
flagged as a guess.

**Rule changes apply immediately.** Everything in this design is derived, so
changing a rule recalculates on the next page load with zero machinery. Applying
"from next period" would require `effective_from` versioning and time-travel
queries in exactly the place the money maths lives.

It is also more truthful: if you decide groceries need $470 and you put in $420,
you *are* $50 short. The one rough edge — a pool flipping from *on track* to
*behind* right after a distribution — is handled with wording, not architecture:
`behind $50 — you changed a rule here after distributing`. ("Changed", not "raised":
`updated_at` cannot tell a raise from a cut, and a pool's row cannot name which of its
rules moved — the wording claims exactly what the signal knows.)

## 9. The structural check

Reallocation cannot fix a budget that does not fit an income. The app must say so
rather than let someone reallocate through six months of sinking.

A **permanently visible button appears only when typical income < rules**. It
opens the sacrifice view:

```
$468 underwater every period
Your rules need $1,668. You typically bring home $1,200.

What could you cut?
  ☑ Groceries      $400 → $300     frees $100
  ☑ Vacation       $150 → $0       frees $150   (pause)
  ☑ Gas & other     $80 → $50      frees  $30
  ☐ Dentist        $300            can't cut — dated
  ☐ Rent         $2,000            fixed
  ☐ Car insurance  $600 / 6mo      fixed
  ─────────────────────────────────────────────
  Cutting frees          $280 a period
  Still underwater       $188 a period
```

- Uncuttable rules are marked as such. Pretending rent is optional would be a lie.
- The running total updates live, so *what do I sacrifice* is dialled in rather
  than computed.
- **The unwinnable case is stated plainly.** If every available cut still leaves a
  gap, the app says so instead of offering false comfort.

## 10. Changes to Plan 1's model

| change | reason |
| --- | --- |
| `pay_cadence` → `period_cadence`, `pay_anchor_date` → `period_anchor_date` | §3 |
| `users.typical_income` added | §3, §9 — user-declared, never inferred |
| `pools.target_amount` permitted on accounts | §7.1 buffer target |
| A dateless goal is a rate rule on a savings pool with `target_amount`; `required` → 0 once the balance reaches it | no new rule shape needed |
| Cross-account transfer to-dos dropped from the UI | §5 |

Plan 1's four rule shapes are unchanged.

## 11. Out of scope

- Cross-account transfer workflow (model support exists, UI deferred)
- Seasonal rules — utilities genuinely differ Dec vs Jul; using the highest
  observed amount is the accepted approximation
- Dismissing suggestions
- Rule versioning / `effective_from`
- Forecasting beyond the next due date

## 11a. Suggested plan decomposition

This spec is too large for one implementation plan. Each of the following
produces working, testable software on its own, and they are ordered so the app
is usable earlier rather than later.

| plan | delivers | why this order |
| --- | --- | --- |
| **2a — Periods & pools UI** | the §3 rename + `typical_income`, Home (§4) read-only, pool detail, nav reshuffle | Home is the whole point, and it needs no write paths. Ships something usable immediately. |
| **2b — Distribution** | the §5 screen, overrides, consequences, sweep materialisation (§7.2), reallocation | The signature action. Depends on Home for its entry point. |
| **2c — Budget page & structural check** | §8 rules page, priority ordering, the suggestion engine, §9 sacrifice view | The suggestion engine is the largest single piece and benefits from real usage of 2a/2b first. |
| **2d — Logging & tracking rework** | §6 envelope impact, the Categories change (§8 note), Reports demotion | Smallest and least risky; deliberately last so the daily path changes only once the rest is settled. |

Plan 1's outstanding obligations (spec §7a of the domain design) fold into these:
the `pay_anchor_date` presence validation and `pool_params` widening belong in
**2a**; `searchable :pool` and the `User → pool-mode budgets` path belong in
**2d** and **2c** respectively.

Plan 2a leaves one of its own, recorded in the same place under **Plan 2c must**:
`users.typical_income` has a column, a validation and a reader
(`HomePresenter#structurally_underwater?`) but **no writer anywhere in the app** —
no form field, no permitted param, no controller. Until 2c gives it one, §9's
structural check is permanently false in production and the button that opens the
sacrifice view can never render.

## 12. Testing

Per the `system-test-writer` skill's page-based structure.

**System specs** — `spec/system/home/` (standing headline in both states, fixes
with sources, waterfall reorder, auto-expand on trouble, all six row states),
`spec/system/distributions/` (collapsed vs full by data, edit-with-consequence,
edit-into-won't-make-it, confirm writes movements atomically),
`spec/system/entries/` (envelope impact, overdraw, no schedule text present),
`spec/system/budget/` (priority drag, structural check, each suggestion kind),
`spec/system/structural/` (cut list, uncuttable marking, unwinnable case).

**The scenarios that most need coverage** are the ones the app exists for: a
period with no income in it, a bill due before the next period, a distribution
that cannot cover its obligations, an envelope overdrawn into the buffer, and a
budget that does not fit its income.
