# Logging & Tracking Rework — Implementation Plan (2d of 4, the last)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The daily path learns about envelopes — the entry form answers *can I afford this* at the moment it is wanted — and the debts the first three plans booked are paid.

**Architecture:** One new surface (the §6 impact card on the entry form) plus finishing work: the `per_paycheck→per_period` rename, the `PoolCalculator` projection split booked twice, the measured perf residues, the §8.1 Categories change, and the booked view refactor. Smallest and least risky of the four plans, deliberately last so the daily path changes only once everything it reports on is settled.

**Tech Stack:** Rails 8.1, PostgreSQL (UUID PKs, `money` columns), Tailwind, Stimulus, RSpec, FactoryBot, Capybara.

**Spec:** `docs/superpowers/specs/2026-08-15-budgeting-ui-design.md` (§6, §8.1, §2)
**Domain spec:** `docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md` (§7a leftovers: `searchable :pool`)

## Global Constraints

- **Work on branch `feature/envelope-budgeting`. Never run `git push`.** Committing is expected; any stored memory saying otherwise is stale.
- Commit messages **single-line**, `type/scope: description`, **no `Co-Authored-By`**. **Stage explicit paths, never `git add -A`** — that swept a parallel agent's work into a commit twice on this branch.
- `# frozen_string_literal: true` atop every Ruby file. `bundle exec rubocop -A` clean. Nothing may be deleted unless a task explicitly deletes it.
- **Money type.** Empty `sum(:amount)` returns `Integer 0`; `[x, 0.to_d].max` coerces only when the clamp fires. Assert types by type. Seven leaks so far.
- **The mixed-unit trap has struck five times** — a monthly amount is not a per-period amount. Any new division or client-side arithmetic names its unit.
- **Nine tautology-adjacent assertions caught.** `Pool#total` is *defined* as the sum of its parts. Every expected figure is a planted literal; equality sides independent.
- **A state asserted in neither direction produced a finding in every task of two plans.** Assert the opposite of everything you assert.
- **One reader per question.** The unified readers are law: `PoolBalanceLedger::ENTRY_POOL_ID` (the one SQL form of "which pool does this entry reach"), `Budget#steady_ask`/`steady_need`, `Budget#cadence`, `BudgetCalculator#due_order`, `ReallocationPresenter.source_order`, `pool_status_label` (with BOTH suffixes threaded — the whole-plan review just closed a disjoint-caller-sets defect), `SacrificePresenter.digits`. Before adding any reader, grep for the existing one.
- **`InvalidSessionIdError` is never environmental** (`CLAUDE.md:137` — the procedure has caught three distinct root causes). Stable first failure → missing waiting assertion; unstable → concurrent rspec (`pgrep -f "[r]spec spec/system"`). `click_*` needs a waiting assertion before any model assertion. **`Date.current` never inside `travel_to`** (two occurrences caught in 2c).
- Run spec files **one at a time**. `bin/ci`'s test steps run 0 examples.
- **Tailwind:** new classes need `bin/rails tailwindcss:build`. Colours from `custom.css`. `rounded`, never `rounded-lg/xl`.
- **Do not edit `db/seeds.rb` without reading `.superpowers/sdd/2026-08-16-distribution/seeds-report.md`** (account → state table; each demo screen is held by exactly one account). Visual checks restore the dev DB surgically with counts verified (users 1 / budgets 22 / categories 30 / pools 22 / movements 6).
- **Visual verification is mandatory on every UI task** (CLAUDE.md) — the browser has caught defects specs passed on eight separate occasions across 2b/2c. 1440px, `demo@example.com` / `password123`, report what was SEEN with figures.
- Follow `docs/coding-standards.md`. Calculators in `app/services/`, presenters in `app/presenters/`.

## Decisions this plan settles

### 1. The impact card computes no new figure and speaks no status

§6's card shows: envelope name, balance → balance-after, `left until <period end>`, a bar. Every
figure is an existing reader: balance through the calculator (ledger-backed), the bar's
denominator is the envelope's per-period claim — `Σ steady_ask` over its rules, the one
normaliser — and the date is the next `User#period_boundaries` edge. **The card renders no
status vocabulary**: `PoolStatus` is a server-side reader, and a client-side re-derivation of it
would be a second reader of the app's most-guarded question. The mockup shows figures, a bar and
a date; that is what ships. Live typing recomputes only the subtraction and the bar,
client-side, from delimiter-free figures the server printed.

### 2. Overdrawing warns and never blocks; the pool-less category is told the truth

§6: the envelope going negative says the buffer can cover it, and the button reads "Save
anyway." Nothing blocks (principle 1: entry stays single-purpose; fixes live on Home). A
category with **no** envelope gets the honest card — "no envelope — this spending isn't
budgeted" — pointing at the Budget page, in the register the suggestion engine already uses
("comes out of your buffer"). Unpooled spending leaving the tree is this branch's known
residual; the card must not pretend otherwise.

### 3. `per_paycheck` becomes `per_period`, Ruby-side only

Periods replaced paychecks in 2a; the enum still says `per_paycheck` and its predicate
(`basis_per_paycheck?`) appears across eight app files. Rename the enum **value** (the stored
integer mapping `{ monthly: 0, per_period: 1 }` is unchanged — no data migration), the
predicates, `Budget#cadence`'s `:per_paycheck` symbol, and every user-visible string that still
says "paycheck". Downstream consumers of the cadence symbol (helpers' lookup tables, the
engine's prefills) rename with it — one commit, mechanically complete, because a half-renamed
symbol is worse than either name.

### 4. The projection split: `PoolCalculator` keeps the ledger, projections move out

Booked in 2b's final review and again in 2c's: four keyword axes (`as_of:`, `today:`,
`net_of_sweep:`, `pending:`), a bespoke error class guarding one combination, and a recursive
twin inside `#balance`'s memo. The split extracts the **projection modes** (`net_of_sweep`,
`pending`) into a `PoolProjection` (name negotiable) that wraps a plain calculator and owns the
adjustment arithmetic, the twin, and `NetOfSweepError`'s refusal; `PoolCalculator` keeps the
ledger readers (`as_of:` stays — it is a ledger question, not a projection). **No figure moves;
no existing spec file is edited** — the same contract as 2c Task 1, which is the precedent that
this kind of surgery can be proven safe. If the split turns out to require touching an
assertion, stop and report rather than adjusting it.

### 5. What stays deferred, on the record

- **`/distributions/new` taking write locks on a GET**: the delete-compute-rollback render is
  load-bearing design (2b's ruling); hover-prefetch is disabled; revisiting it is structural
  and belongs to a future plan that reworks the render, not to this one.
- **`steady_ask` vs `period_end` two frames**: a monthly-basis rate rule normalises cost by
  `periods_per_year` while its *period lifecycle* closes on the calendar month. These answer
  different questions (what does it cost per period vs when does its period roll) and the
  divergence is deliberate; Task 2 records it in both comments rather than unifying two
  questions into one wrong answer.
- **The override-entries nullify residual** (an override entry whose category points nowhere
  leaves the tree): unreachable from the UI, named in `pool.rb`'s comment since 2c's close-out.
- **`BudgetCalculator#shortfall` not netting partial payments** (§7a): over-reserves, the safe
  direction. Stays deferred — omitted from this list originally; added by the final review.

## Pre-verified: already closed, no task needed

- **Reports demotion** shipped in 2a: `get "reports" → dashboard#index`, sidebar says Reports.
  Task 6 verifies order against §2 and sweeps for stray user-visible "Dashboard" strings only.
- **The `/pools` index gap** (§7a: accounts rendered with savings chrome) is closed: the index
  deliberately lists `savings_pools` only, with a comment saying so.

## File Structure

**Created**

| file | responsibility |
| --- | --- |
| `app/services/pool_projection.rb` | net-of-sweep and pending projections over a plain calculator |
| `app/presenters/entry_impact_presenter.rb` | everything the §6 card renders |
| `app/views/entries/_impact.html.erb` | the card |
| `app/javascript/controllers/app/entries/impact_controller.js` | live subtraction + bar |
| `app/helpers/digits_helper.rb` | the delimiter-free figure writer, extracted from `SacrificePresenter.digits` — one reader, now two consumers |
| `spec/presenters/entry_impact_presenter_spec.rb`, `spec/system/entries/impact_spec.rb` | tests |

**Modified**

| file | change |
| --- | --- |
| `app/models/budget.rb` + 7 app files + specs | the rename (Task 1) |
| `app/services/pool_calculator.rb`, its callers | projection split (Task 2) |
| `app/services/pool_balance_ledger.rb` callers, `app/presenters/home_presenter.rb`, `app/presenters/distribution_presenter.rb`, `app/services/allocation_calculator.rb` | perf residues (Task 3) |
| `app/views/entries/_form.html.erb`, `app/controllers/entries_controller.rb` | the card (Task 4) |
| `app/views/categories/show*`, category budget partials, `app/models/entry.rb` | §8.1 + `searchable :pool` (Task 5) |
| `app/views/shared/_sidebar.html.erb`, `app/views/home/_pool_row.html.erb`, `app/views/budget_page/_pool_group.html.erb` | nav order + the booked row/group refactor (Task 6) |

---

## Task 1: `per_paycheck` → `per_period`, everywhere at once

**Files:** modify `app/models/budget.rb`, `app/services/{budget_calculator,pool_calculator,suggestion_engine}.rb`, `app/presenters/sacrifice_presenter.rb`, `app/helpers/{budget_page_helper,sacrifices_helper,home_helper}.rb`, and every spec naming the symbol; test: the owning suites, untouched in *meaning*

**Interfaces produced:** `Budget` enum `{ monthly: 0, per_period: 1 }` (`basis_per_period?`), `Budget#cadence` returning `:per_period`.

Decision 3. One commit. Grep both spellings (`per_paycheck`, "per paycheck", "paycheck") across `app/`, `spec/`, `db/seeds.rb` — seeds may name the trait; **factories and seeds rename too**, since a stale trait name is how the old symbol creeps back. The stored integer mapping is unchanged and asserted: a rule created before the rename (integer 1 planted by SQL) reads `basis_per_period?` true. User-visible strings: whatever still says "paycheck" says "period" — and the sweep must list, in the report, every user-visible string it changed, because copy changes are what the visual check verifies.

- [ ] Rename enum value + predicates + `cadence` symbol + strings + factories/seeds traits, one commit
- [ ] Plant integer 1 by SQL, assert `basis_per_period?`; suites green with only spelling-level edits
- [ ] Visual check any screen that prints a basis string; commit

## Task 2: The projection split

**Files:** create `app/services/pool_projection.rb`; modify `app/services/pool_calculator.rb` and the projection-mode callers (`AllocationCalculator`, `DistributionPresenter`, `ReallocationPresenter`, `Budget`'s consequence path); test `spec/services/pool_projection_spec.rb` — existing spec files **not edited**

Decision 4, with its hard contract: **no figure moves, no existing spec edited**. The moved
machinery: `net_of_sweep`'s twin and refusal, `pending`'s balance adjustment, their interaction
(`sweep_adjustment` passes `pending` down into the twin — load-bearing on two callers). What
stays: the five terms + `last_funded_on` + `as_of:` + `terms:` + every plain reader.
`Pool#calculator` keeps its signature by delegating projection keywords to the new object, or
callers move to `PoolProjection` explicitly — read the call sites and pick the smaller honest
change, then say which and why. Record the decision-5 two-frames note in both comments. Measure
the three screens after (Home, `/budget`, `/distributions/new` with edits): counts unchanged.

- [ ] Extract; contract held (suites green untouched, counts unchanged, figures byte-identical on the demo screens)
- [ ] The two-frames note in both comments; commit

## Task 3: The measured perf residues

**Files:** modify `app/services/pool_calculator.rb` (`budgets_by_due_date`), `app/presenters/home_presenter.rb` (one ledger), `app/services/allocation_calculator.rb` / `app/presenters/distribution_presenter.rb` (one ledger per screen); test: existing suites untouched, counts measured

Three booked residues, one contract (no figure moves): `budgets_by_due_date` calls
`pool.budgets.includes(...)` as a relation and defeats every caller's eager load (38 queries on
Home — preload-friendly form instead); Home builds three ledgers where one spans all its pools
(~9 grouped maxima → 3); the distribution screen builds one ledger per fill (four fills with two
edits — share the *terms* across an `AllocationCalculator`'s own fills **only if** the
staleness guarantee provably survives: the committer's post-deletion re-derivation must still
build fresh — the guard examples are named in the ledger; if sharing cannot be proven safe,
take the two safe wins and report the third declined, with the reason). Measure before/after on
all four screens; expect Home ≤ ~60.

- [ ] `budgets_by_due_date` preload-friendly; measured
- [ ] One ledger on Home; measured
- [ ] Distribution-screen sharing if provably safe, else declined with reason; measured; commit

## Task 4: The impact card — §6, the plan's centrepiece

**Files:** create `EntryImpactPresenter`, `_impact.html.erb`, the Stimulus controller, `digits_helper.rb`; modify `app/views/entries/_form.html.erb`, `app/controllers/entries_controller.rb`; test presenter + `spec/system/entries/impact_spec.rb`

Decisions 1 and 2. The card renders under the amount field on new **and** edit:

- **Derived pool**: the chosen category's envelope (`categories.pool_id`; the entry override
  has no UI and stays out). Category switching re-renders the card's data (the form already
  re-renders on category choice or exposes it — read the form and its numpad controller first;
  extend the existing mechanism, do not add a second).
- **Figures**: `balance → balance − amount left`, `until <next period edge − 1 day>` (omitted
  for an undeclared user), bar = `balance_after / Σ steady_ask` clamped 0..1. On **edit**, the
  balance excludes the entry's own current amount (the ledger already counts it; the card must
  show the world as if this entry were being decided now — assert this with an edit fixture
  whose figures differ from the create case).
- **Live typing**: the controller re-reads delimiter-free figures (`digits_helper`, extracted
  from `SacrificePresenter.digits` — move the reader, point the sacrifice view at the new home,
  its suite stays green) and recomputes subtraction + bar width. `input` AND `change` events —
  the dial's close-out found values set without keystrokes dispatch only `change`.
- **Overdraw**: negative shown signed, the buffer sentence appears, submit reads "Save anyway"
  (server renders both states; JS toggles). Never blocks. `-$0.00` is not a thing (`Math.abs`
  at zero — the sacrifice dial's exact bug).
- **Pool-less category**: the honest card per decision 2. **Savings category**: the envelope is
  a goal — show contribution shape (`$X → $Y of $Z goal`) using existing goal readers; an
  income category shows no card (income lands in the account; saying so adds a concept §6
  deliberately leaves out — one comment says why).

Assert every state in both directions on planted literals; client/server agreement pinned at
shared literals (the sacrifice pattern). Visual check: type into the real numpad on the demo,
quote the card's figures for a healthy envelope, an overdraw, a pool-less category, and an
edit; console clean.

- [ ] Presenter + card + controller; `digits` extracted, one reader
- [ ] All states both directions; client/server pinned
- [ ] Visual check with figures; dev DB restored; commit

## Task 5: The Categories page's one change, and `searchable :pool` tells the truth

**Files:** modify `app/views/categories/show` budget partials, `app/models/entry.rb`; test `spec/system/categories/show/budget_spec.rb` (extended), search specs

Spec §8.1 (just written — read it): three states for the budget block, pool-covered / capped /
uncapped, each asserted in both directions on planted fixtures. The caveat sentence is **one
spelling** — reuse the Budget page's caps-not-counted phrasing (grep for it; do not write a
second). The suggestion pointer in the uncapped state renders only when the engine currently
proposes for this category — reuse the engine, do not re-derive its conditions.

`searchable :pool` (§7a): the DSL resolves `through: [:item, :category, :pool]` — strictly the
category chain, while every balance resolves through `ENTRY_POOL_ID`'s COALESCE. An entry with
its own `pool_id` (unreachable from the UI today, but seeds/factories write it) is found under
the lane it overrode *away from*. Align the search with the one reader — read
`docs/searchable-system-reference.md` for how the DSL admits a custom column/predicate, and
implement the COALESCE lane. Assert both directions: an override entry found under its own
pool, not under its category's.

- [ ] §8.1's three states, both directions each; one caveat spelling
- [ ] `searchable :pool` on the COALESCE lane, both directions
- [ ] Visual check on the demo's pool-covered and capped categories; commit

## Task 6: Nav order, the demotion sweep, and the booked row/group refactor

**Files:** modify `app/views/shared/_sidebar.html.erb`, `app/views/home/_pool_row.html.erb`, `app/views/budget_page/_pool_group.html.erb` (+ shared partial if extracted); test navbar + home/pools + budget_page/rules suites

Three finishing moves:
- **Nav order per §2** with Distribute (2b's addition, absent from the spec's table) placed
  second: Home · Distribute · Budget · Entries · Categories · Calendar · Reports — Reports
  last, as the demotion intends. Assert the order (the navbar spec already asserts positions).
- **Demotion sweep**: grep user-visible "Dashboard" — retitle strays to Reports. Report every
  string changed.
- **The booked refactor** (2c final review, declined-then-booked): Home's `_pool_row` and the
  Budget page's group shape converge on one shared row partial — the reviewer judged the group
  shape better. **Rendering must stay byte-identical on both screens** except where the shared
  shape fixes a named inconsistency — diff the rendered HTML of both pages before and after and
  list every changed byte in the report. Both label suffixes stay threaded on both callers (the
  whole-plan review's finding 1 must not regress — its examples guard this).

- [ ] Nav order + sweep, asserted
- [ ] Shared row partial, rendered-HTML diff reported, suffix examples green
- [ ] Visual check both screens; commit

---

## The Plan 3 inheritance list

Committed here so it survives the SDD directory's archiving (2c's precedent; 2d's final review
found this list living only in a gitignored ledger and ruled it a blocker).

**Perf residues, measured:**
- `account.child_pools`' budgets re-read per fill — 60 queries of the widest screen's 161
  (12 envelopes × 5 reads across four fills, plus `DistributionPresenter#envelopes`, no memo).
- Unmemoised `BudgetCalculator#paid_since_anchor` — 18 of Home's 41.
- The two-edits-on-real-rows distribution screen was 245 queries at base and had never been
  measured: Task 2's harness overrode pools with no row in the fill, so the counterfactual
  machinery never fired. Any future byte-identity contract must verify its screens contain the
  shape they claim.

**Correctness / design, deferred with reasons:**
- `PoolBalanceLedger::AsOfMismatch` has no `rescue` anywhere and must not acquire one.
- The `_impact` card's known edges: the open numpad pushes it ~300px down; `/entries/impact`
  builds one pool ledger per category change (unmeasured); a bill-shaped envelope pins its bar
  full; the client overwrites the server's initial figure on load.
- The category page's cache hole, named in `categories/show.html.erb`: an entry carrying its own
  `pool_id` override touches its category's pool, not the pool it was overridden onto.
- `shared/_pool_status`'s whitespace is load-bearing and untested.
- `/distributions/new` takes write locks on a GET (2b's delete-compute-rollback ruling —
  structural; belongs to a plan that reworks the render).
- `steady_ask` vs `period_end` two frames — deliberate, recorded in both comments.
- The override-entries nullify residual — named in `pool.rb`'s comment; unreachable from the UI.
- `BudgetCalculator#shortfall` does not net partial payments (§7a) — over-reserves, the safe
  direction.
- `_summary_card`'s savings arm still renders account-pointed savings categories with savings
  chrome (the left-column sibling of the fixed right-column card).

- A budget envelope's `target_amount` is read by nothing in the app; the pool show page prints
  it under a neutral `TARGET` label rather than dropping it. Its meaning wants a ruling
  (display marker? soft ceiling? delete?) — found by the final fix round's visual check.
- `_pool_card`'s savings arm prints `Target:` twice (pre-existing, left alone).
- The alerts-band `period_closed` thread is defensive, not curative: the drift it guards is
  unreachable today (a closed envelope's re-asking rate rules always produce a row), pinned by
  a spec that documents the reachability argument rather than prose.

**§7a's Plan 3 (cutover) list is intact in the domain spec** — reverse §6.1 steps 2 and 4 (the
step that loses data), tighten `account_matches_pool_type`, flip the `pool_type` default,
delete `savings_entries_total`, the pools unique index, the seeds teardown rewrite,
`contribution_entries`/`withdrawal_entries`/`timeline_entries`, the duplicate income validators.
Every §7a "Plan 2" item is closed; `crosses_accounts?`'s preload item was satisfied differently
(in-memory pools with `:account` eager-loaded) and is hereby explicitly closed.

## Plan 2d Done — and the conversion with it

The daily action answers *can I afford this* as it happens; the tracking pages keep their
value with the envelope truth threaded through; the rename finishes what "periods replace
paychecks" started; and the debts are paid or on the record. All four plans of the envelope
conversion are complete.
