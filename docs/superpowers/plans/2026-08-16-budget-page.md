# Budget Page & Structural Check — Implementation Plan (2c of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Budget page — where rules live, priority is set, suggestions surface, and the app says plainly when a budget cannot fit an income.

**Architecture:** One new page (`/budget`) built from the existing calculator/presenter split: a `BudgetPagePresenter` over the user's rules, a pure `SuggestionEngine` over entry history, and a what-if `SacrificePresenter` that writes nothing. Before any of that, one structural task: a batched balance ledger, because Plan 2b measured every screen paying five aggregate queries per calculator per pool and booked the fix for "before 2c adds screens on top of it."

**Tech Stack:** Rails 8.1, PostgreSQL (UUID PKs, `money` columns), Tailwind, Stimulus, RSpec, FactoryBot, Capybara.

**Spec:** `docs/superpowers/specs/2026-08-15-budgeting-ui-design.md` (§8, §9, §10, §11a)
**Domain spec:** `docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md` (§7a "Plan 2c must", plus the Plan-2 leftovers folded in below)

## Global Constraints

- **Work on branch `feature/envelope-budgeting`. Never run `git push`.** Committing is expected; any stored memory saying otherwise is stale.
- Commit messages **single-line**, `type/scope: description`, **no `Co-Authored-By`**. **Stage explicit paths, never `git add -A`** — that swept another agent's work into a commit twice on Plan 2b.
- `# frozen_string_literal: true` atop every Ruby file. UUID PKs; money columns `t.money "name", scale: 2`.
- **Money type.** The `money` column keeps an **Integer** for in-memory records, and an empty `sum(:amount)` returns `Integer 0` — six leaks so far. `[x, 0.to_d].max` **does not coerce unless the clamp fires**. Coerce the *result*. **Assert the type**, not only the value.
- **`x == x` assertions:** six found on this branch. `Pool#total` is *defined* as `account.balance + Σ children.balance` — asserting that sum against it is a tautology. Check every equality's two sides are independent.
- **A state asserted in neither direction** produced a finding in every one of Plan 2b's eight tasks. Assert the opposite of everything you assert.
- **One reader per question.** Two readers answering one question produced a defect in every 2b task. Before adding any method that answers "how much / which / whether", search for the existing answer.
- **Never compare ids where one side may be unsaved.** **Determinism:** ordered reads sort explicitly; the established keys are `[priority, name]` for pools and `[due_date, -amount, id]` for rules (extracted in Task 2 below — use the extraction).
- **`InvalidSessionIdError` is never environmental.** See `CLAUDE.md` → *Diagnosing `InvalidSessionIdError`*. Stable first failure → a missing waiting assertion; unstable → a concurrent rspec process (`pgrep -f "[r]spec spec/system"`). An example whose last action is `click_*` must make a waiting Capybara assertion before any model assertion.
- Run `bundle exec rubocop -A` before finishing. Run spec files **one at a time** — two concurrent rspec processes deadlock in DatabaseCleaner truncation.
- **Tailwind:** classes not already in the codebase need `bin/rails tailwindcss:build`. Colours from `app/assets/stylesheets/custom.css`. Use `rounded`, never `rounded-lg/xl`.
- **Do not edit `db/seeds.rb` without reading `.superpowers/sdd/2026-08-16-distribution/seeds-report.md` first.** The demo carries four accounts holding four distinct screens, one state per account; a balance change can silently retire a screen.
- **Visual verification is mandatory on every UI task** (CLAUDE.md). On Plan 2b the browser caught defects specs passed on five separate occasions. 1440px, `demo@example.com` / `password123`, report what was *seen* with figures, `rm -f *.png` after.
- Follow `docs/coding-standards.md`. Calculators in `app/services/`, presenters in `app/presenters/`.

## Decisions this plan settles

### 1. The structural check's figure is a new reader, deliberately distinct from `required`

"Your rules need $1,668 a period" is a **steady-state** figure: every rule normalised to
per-period cost (a rate rule's amount per its basis; a dated bill amortised over its interval).
`PoolCalculator#required` is **this period's** ask — catch-up, sweep, and funding state included.
They answer different questions and must not share a name. The new reader is
`Budget#steady_ask(user)` (Task 4), it is the *only* place that normalisation lives, and the
drift detector (Task 6) uses it rather than re-deriving per-period maths.

### 2. The draggable unit is the pool, not the rule

Spec §8 says "active rules, drag-ordered — this is where funding priority is set." The thing
priority actually drives is `pools.priority` — `AllocationCalculator#fill` and Home's waterfall
fill **pools** by `[priority, name]`; rules order *within* a pool by `[due_date, -amount, id]`
and are not independently orderable. So the page's top half lists **pool groups** (each showing
its rules), the group row is what drags, and dropping writes `pools.priority`. Orphan
(account-less) pools and category-mode rules render in their own section, undraggable, each
saying why.

### 3. Cuttable means "rate rule"; the sacrifice view writes nothing

A dated bill's amount is the bill's — cutting it is a lie the spec explicitly refuses ("Pretending
rent is optional would be a lie"). So: **cuttable = anchorless rules** (rate envelopes and goal
contributions), uncuttable = anchored rules, marked with the reason. The spec's mockup also marks
a rate rule ("Rent") as *fixed*; that needs a per-rule flag no schema has, and it is **out of
scope** — the plan ships without it and the spec's §11 list gains it. The sacrifice view is a
live what-if: checkboxes and cut amounts recompute totals client-side (Stimulus), nothing
persists, and each row links to the rule's real edit form. "Apply all cuts" is not built.

### 4. Suggestions are derived on read, never persisted

Spec §8: "always running", "derived from entry history". No suggestions table, no dismissed
state, no background job — the engine computes on page load from entries, exactly as every
calculator on this branch works. Cost is bounded and measured (Task 6). Accepting a suggestion
is a link to the existing pool/budget forms **prefilled** — the engine proposes, the existing
write paths dispose.

### 5. Destroying a pool re-points its movements to its account

Plan 1 flagged `dependent: :destroy` on movements ("destroying B in A→B→C restores A but
vaporises C's inflow") and 2b made it live: pools now carry real distribution history, and
`resources :pools` exposes destroy today. Ruling: **on destroy, each movement's destroyed-pool
endpoint is re-pointed to the pool's account; a movement whose two endpoints collapse to the
same pool is destroyed** (an account→B allocation becomes account→account, which is nothing).
Consequences, which the implementer must *measure*: every sibling pool's balance is unchanged
(its movement now names the account instead of the destroyed pool); the account's buffer moves
by exactly the destroyed pool's balance; `Σ pools == bank balance` holds throughout because
every movement nets to zero in-tree. History reads "from Checking buffer" where it used to name
the pool — acceptable, and honest. An account with children keeps `restrict_with_error`.

### 6. The user declares their period on the Budget page

`users.typical_income`, `period_cadence` and `period_anchor_date` have columns, validations and
readers — and **no writer anywhere in the app**. Not just income: nothing in any view or
controller lets a user set their cadence, so the entire periods system runs on seeds. All three
are declared in one place: the Budget page's structural-check block, beside the totals they
define ("a period" *is* the cadence; "you typically bring in" *is* the income). §7a names the
Budget page as income's right home; the cadence belongs beside it for the same reason. Changing
cadence re-derives every period-scoped figure on next load — everything on this branch is
derived, so this costs zero machinery; the plan accepts that historical distributions re-bucket
under new boundaries, and says so in the form's copy.

## Carried from Plan 2b's final review — deliberately NOT in this plan

- **`PoolCalculator`'s four keyword axes** (finding 8): 2c adds no fifth axis and barely touches
  the class beyond Task 1's terms injection. The split lands in 2d, where logging rework touches
  it next. Recorded here so it is not lost.
- **`/distributions/new` taking write locks on a GET**: the delete-compute-rollback render is
  load-bearing design; revisiting it is structural. Hover-prefetch is already disabled.
- **`BudgetCalculator#shortfall` not netting partial payments** (§7a): over-reserves, the safe
  direction. Stays deferred.

## File Structure

**Created**

| file | responsibility |
| --- | --- |
| `app/services/pool_balance_ledger.rb` | the five balance terms for many pools in five grouped queries |
| `app/services/suggestion_engine.rb` | entry history → suggestions (four kinds), pure, no writes |
| `app/presenters/budget_page_presenter.rb` | everything `/budget` renders |
| `app/presenters/sacrifice_presenter.rb` | the §9 what-if: cuttable rows, totals, the unwinnable case |
| `app/controllers/budget_page_controller.rb` | `show` (the page), `update_user` (income + period), `reorder` (priority) |
| `app/controllers/sacrifices_controller.rb` | `show` |
| `app/views/budget_page/*`, `app/views/sacrifices/*` | screens |
| `app/javascript/controllers/reorder_controller.js` | drag → PATCH priority |
| `app/javascript/controllers/sacrifice_controller.js` | live cut totals |
| `spec/services/*`, `spec/presenters/*`, `spec/system/budget_page/*`, `spec/system/sacrifices/*` | tests |

**Modified**

| file | change |
| --- | --- |
| `app/services/pool_calculator.rb` | accept precomputed terms (Task 1); nothing else |
| `app/models/budget.rb` | `steady_ask`, the extracted rule sort key, `Budget.for_user` |
| `app/models/user.rb` | reach pool-mode budgets |
| `app/models/pool.rb` | destroy re-pointing (Task 8) |
| `app/models/pool_movement.rb` | `source_entry` ownership validation |
| `app/presenters/home_presenter.rb` | use the ledger; the underwater button's target; the raised-after-distributing wording |
| `app/presenters/distribution_presenter.rb`, `app/presenters/reallocation_presenter.rb` | use the ledger |
| `config/routes.rb` | budget page, sacrifice view, reorder |
| `app/views/shared/` nav | Budget entry |

---

## Task 1: `PoolBalanceLedger` — five queries for any number of pools

**Files:** create `app/services/pool_balance_ledger.rb`; modify `app/services/pool_calculator.rb`, `app/presenters/home_presenter.rb`, `app/services/allocation_calculator.rb`, `app/presenters/distribution_presenter.rb`, `app/presenters/reallocation_presenter.rb`; test `spec/services/pool_balance_ledger_spec.rb` plus the existing suites unchanged

**Interfaces produced:** `PoolBalanceLedger.new(pools, as_of: nil)` → `#terms_for(pool)` returning `{income:, savings:, expense:, movements_in:, movements_out:}` (all BigDecimal); `PoolCalculator.new(..., terms: nil)` using injected terms instead of running its own aggregates.

Plan 2b's final review measured the cost as structural: **every `PoolCalculator` instance runs
five aggregate queries**, and each screen builds several distinct calculators per pool — Home
407 queries, `/distributions/new` 574 with two edits, reallocation 269. The named per-path lever
(`net_of_sweep` threading) recovers only ~25% of one path; batching the aggregates is the real
one.

The ledger runs the same five terms **grouped by pool** — one query per term for the whole set,
reproducing `PoolCalculator`'s scoping exactly, including the entries-for-pool predicate
(`entries.pool_id = X OR (entries.pool_id IS NULL AND categories.pool_id = X)`, which needs one
`LEFT JOIN` done once) and the `as_of` bound. `PoolCalculator#initialize` gains `terms:`; when
present, the five `*_total` readers return the injected figures and no aggregate runs. When
absent, behaviour is byte-identical to today — the keyword must be **provably inert by default**,
asserted as an equality against today's numbers, the same way `net_of_sweep:`'s default was
pinned.

Callers that iterate pools build one ledger and pass terms through: `HomePresenter#calculator_for`,
`AllocationCalculator` (its own calculators **and** the `net_of_sweep` twins — the twin takes the
same terms, since the sweep adjustment is computed on the same ledger world), `DistributionPresenter`,
`ReallocationPresenter#sources`. `Pool#calculator` (single-pool callers, model validations) stays
unbatched — correctness first, and a single pool is five queries either way.

Three hard requirements, in order of importance:

1. **No figure moves.** Every existing spec file passes untouched — do not edit an existing
   assertion to make this fit. If a figure moves, the ledger's scoping is wrong; find it.
2. **Types survive.** A pool with no rows in a term must get `0.to_d` from the grouped hash,
   not a missing key and not an Integer — `Hash#fetch` with a `0.to_d` default, asserted by type
   on an empty pool.
3. **Staleness rules are unchanged.** A ledger is a snapshot, stale-after-write like everything
   here. `AllocationCommitter`'s fresh-proposal-after-deletion path must build a **fresh ledger**
   after the deletion — assert that the committer's re-derivation still sees the deletion (the
   existing re-run examples cover this; they must stay green, and one of them must be named in
   the report as the guard).

**Measure and report** query counts before/after on the three screens (Home, `/distributions/new`
with and without edits, `/pool_movements/new`), same method as 2b's measurements. Expect
multiples, not percents. If a screen does not drop, say so and why.

- [ ] Ledger service + spec (grouped terms == per-pool terms on a fixture with all five term
      kinds, an empty pool, an `as_of` bound, and a pool another user owns — excluded)
- [ ] `terms:` keyword, inert by default, pinned as equality
- [ ] Thread through the four callers; all existing suites green untouched
- [ ] Measure the three screens; commit

## Task 2: One reader for a user's rules

**Files:** modify `app/models/user.rb`, `app/models/budget.rb`, `app/models/pool_movement.rb`; test `spec/models/user_spec.rb`, `spec/models/budget_spec.rb`, `spec/models/pool_movement_spec.rb`

**Interfaces produced:** `Budget.for_user(user)` (relation: category-mode ∪ pool-mode);
`User#all_budgets` delegating to it; `Budget::RULE_ORDER` (the `[due_date, -amount, id]` sort,
extracted); `PoolMovement` validating `source_entry` ownership.

§7a: `User has_many :budgets, through: :categories` reaches only category-mode rules, and
`BudgetsController#set_budget` (`current_user.budgets.find`) therefore 404s every pool-mode rule
— which is every rule the Budget page manages. One relation answers it:

```ruby
# Budget
scope :for_user, ->(user) {
  where(category_id: user.categories.select(:id))
    .or(where(pool_id: user.pools.select(:id)))
}
```

`BudgetsController#set_budget` moves to `Budget.for_user(current_user).find(params[:id])`.
Assert in both directions: a pool-mode rule is findable, another user's rule (both modes) raises
`RecordNotFound`.

**The rule sort key is written out five times** (2b's final fix round counted them:
`PoolCalculator#budgets_by_due_date`, `HomePresenter#dated_rules_for`,
`DistributionPresenter#next_dated_rule`, `ReallocationPresenter#holder_for`,
`PoolStatus#anchored_budgets`). Extract once — a class method taking the calculator context it
needs — and point all five at it, the same way `ReallocationPresenter.source_order` was
extracted. No behaviour change; the five suites stay green untouched.

**`PoolMovement#source_entry` ownership** (§7a): validate the entry belongs to the same user as
the pools. Assert both directions.

- [ ] `Budget.for_user` + controller change + both-direction specs
- [ ] `RULE_ORDER` extraction, five call sites, suites untouched
- [ ] `source_entry` validation + specs; commit

## Task 3: The Budget page — active rules, grouped by pool, in fill order

**Files:** create `app/presenters/budget_page_presenter.rb`, `app/controllers/budget_page_controller.rb`, `app/views/budget_page/show.html.erb` + partials; modify `config/routes.rb`, nav partial; test `spec/presenters/budget_page_presenter_spec.rb`, `spec/system/budget_page/rules_spec.rb`

**Interfaces produced:** `BudgetPagePresenter.new(user:, today:)` → `#pool_groups` (pools by
`[priority, name]`, each with its rules by `RULE_ORDER`, each rule carrying its `steady_ask`
placeholder until Task 4), `#orphan_rules` (category-mode + account-less pools, with reasons);
route `get "budget" => "budget_page#show"`; nav gains **Budget** between Distribute and Entries.

The top half of §8: every active rule, under its pool, in the order money actually fills. Each
rule row: name (item/category/pool), amount with basis, next due date for anchored rules, edit
link to the existing `budgets/edit`. Each pool group: name, priority position, its envelope
state via the existing row vocabulary (`pool_status_label` — one vocabulary, do not invent a
second). A brand-new user (no rules) sees the empty top half with one sentence pointing at the
bottom half — assert that state; it is the first screen every real user meets.

Use the Task 1 ledger for any balance the page shows. Visual check per Global Constraints —
this page has never existed, so the check is the design review: squared edges, `custom.css`
colours, spacing against `docs/design-standards.md`.

- [ ] Presenter + specs (grouping, both orders asserted on fixtures where name/id order differ,
      orphan section, empty state)
- [ ] Route, nav, view; system spec; visual check; commit

## Task 4: The structural check block, and the user finally declares their period

**Files:** modify `app/models/budget.rb`, `app/presenters/budget_page_presenter.rb`, `app/controllers/budget_page_controller.rb`, budget page views; test `spec/models/budget_steady_ask_spec.rb`, `spec/system/budget_page/structural_check_spec.rb`

**Interfaces produced:** `Budget#steady_ask(user)` (BigDecimal per-period steady cost);
`BudgetPagePresenter#rules_need`, `#typical_income`, `#leftover`, `#underwater?`;
`PATCH /budget/user` permitting exactly `typical_income`, `period_cadence`, `period_anchor_date`.

`steady_ask`, the one normaliser (decision 1):

```ruby
# Per-period steady-state cost of this rule — what it claims from a typical
# paycheck, not what it asks this period (that is PoolCalculator#required).
def steady_ask(user)
  return (amount / periods_per_interval(user)).round(2) if anchor_date.present?
  basis_per_paycheck? ? amount.to_d : (amount * 12 / user.periods_per_year).round(2)
end
```

— where `periods_per_interval` and `periods_per_year` derive from the user's cadence (weekly 52,
biweekly 26, semimonthly 24, monthly 12; a dated rule's interval in months → periods). A
one-time rule (no `interval_months`) amortises over the periods between today and its anchor,
minimum 1, and reports `0.to_d` once fulfilled — assert each shape, and assert the type on all
of them. The mixed-unit trap here is the exact bug 2b's Task 1 fix round found in `per_period_rate`
(a monthly amount treated as per-paycheck asked 2× the rate); pin a monthly-basis rule under a
biweekly user at the figure that catches it.

The block renders the three lines from §8 plus the declaration form: income, cadence, anchor
date, editable in place, one `PATCH`. `underwater?` = `typical_income.present? && rules_need >
typical_income`. Sacrifice button appears **only** then (§9): assert all three states — no
income declared (no button, block invites declaring), covered (no button), underwater (button).
The form's copy states that changing the cadence re-derives every figure immediately, including
how history buckets into periods (decision 6).

`HomePresenter#structurally_underwater?` already reads `typical_income` — after this task it can
be true in production for the first time. Check Home's standing band renders that branch sanely
(it has been unreachable code until now); its button wiring is Task 9's.

- [ ] `steady_ask` with every rule shape asserted both directions and by type
- [ ] Block + form + `PATCH` (permit exactly three params; assert a fourth is refused)
- [ ] Three button states asserted; visual check; commit

## Task 5: Priority is set by dragging

**Files:** create `app/javascript/controllers/reorder_controller.js`; modify `app/controllers/budget_page_controller.rb`, budget page views, `config/routes.rb`; test `spec/system/budget_page/reorder_spec.rb`, `spec/requests/budget_page_spec.rb`

**Interfaces produced:** `PATCH /budget/reorder` taking `pool_ids: [...]` (the new order,
account-scoped), writing `priority: index` in one transaction.

The drag writes `pools.priority` (decision 2). Server side: verify every id belongs to the
signed-in user **and** all to the same account (cross-account priority is meaningless — the fill
is per-account), inside one transaction, `422` with nothing written otherwise — assert the
refusal leaves every priority untouched (both directions: the count *and* a pinned unchanged
row). Stimulus drag with buttons fallback (▲▼) so the reorder is reachable without JS and
system-testable without synthetic drag events; test through the buttons, and assert the new
order changes **the fill**: after moving a pool up, `AllocationCalculator#rows` funds it first —
that is the assertion that makes this a money feature rather than a list widget. Ties: new
priorities are dense (0,1,2…), so the `[priority, name]` tie-break stops mattering for ordered
pools — assert a pool *outside* the dragged account keeps its priority.

- [ ] Endpoint + guards, both directions
- [ ] Drag + fallback buttons; fill-order assertion; visual check; commit

## Task 6: `SuggestionEngine` — four detectors over entry history

**Files:** create `app/services/suggestion_engine.rb`; test `spec/services/suggestion_engine_spec.rb`

**Interfaces produced:** `SuggestionEngine.new(user:, today:)` → `#suggestions`, each a
`Suggestion` value: `kind` (`:dated_bill | :rate | :drift | :dead_rule`), `subject` (item or
category or budget), `amount` (BigDecimal), `detail` (the sentence's parts: observed figures,
periods, interval, `guessed: true/false`), `prefill` (params for Task 7's links). Deterministic
order: `[kind_rank, amount desc, subject id]`.

Pure derivation (decision 4). The detectors, with the spec's rules made concrete — these
thresholds are the plan's ruling; if measurement shows one produces nonsense on the demo data,
build it as written, measure, then correct with evidence, per this branch's standing method:

- **Dated bill** — an item with **≥ 2** expense entries, amounts within 25% of each other,
  gaps of ~equal whole months (±7 days), **no budget**: propose an anchored rule. Amount = the
  **highest** observed (§8: safer, over-reserves). Interval = the median gap in months. Next
  due = last occurrence + interval. A **single** entry ≥ $100 on an otherwise entry-less item
  with no budget: propose with `interval_months: 12`, `guessed: true` — the spec's "guessed
  interval flagged as a guess".
- **Rate** — a `Category.budgetable` (expense, no pool) with entries in **≥ 3 of the user's
  last 6 complete periods**: propose a rate rule at the **mean** per-period spend across the
  periods it appeared in, rounded up to the nearest dollar. Highest-observed is for bills;
  a rate is a flow, and proposing the max would over-reserve every grocery-shaped category.
  The sentence carries "currently comes out of your buffer" — that is *why* the category
  qualifies (no pool holds it).
- **Drift** — an existing rate rule whose covered spend over the last **4 complete periods**
  averages ≥ 10% **and** ≥ $10 away from the rule's per-period figure (`steady_ask` — Task 4's
  reader, not a re-derivation): report rule figure, observed average, period count. Both
  directions: over-spend drifts up, under-spend drifts down; assert each.
- **Dead rule** — an **item-backed** rule whose item has **zero** expense entries in the last
  3 complete periods but at least one before that: report when it stopped. An item that never
  had entries is not dead, it is new — assert it does not fire.

"Complete period" means `User#period_boundaries` — the existing reader; a user with no cadence
declared has no periods, and the engine returns `[]` (assert it — the Budget page renders
before Task 4's declaration exists for a user). Every amount `BigDecimal`, asserted by type.
For every detector, assert the near-miss in the other direction: 2 of 6 periods does not fire
rate; 9% drift does not fire; an item with a budget does not fire dated-bill; entries 2 periods
ago do not fire dead. **Measure the engine's query count** on the demo user and report it —
this page must not become the new most-expensive screen; group per detector, no N+1 over items.

- [ ] Engine + value object, deterministic order
- [ ] Four detectors, each with fire and near-miss asserted
- [ ] No-cadence and empty-history states; types; query count measured; commit

## Task 7: Suggestions render, and accepting one prefills the real forms

**Files:** modify `app/presenters/budget_page_presenter.rb`, budget page views; test `spec/system/budget_page/suggestions_spec.rb`

The bottom half of §8. Each suggestion renders its sentence from `detail` — the four example
shapes in the spec are the copy targets — and an accept link: dated bill/rate → the existing
new-pool/new-budget forms prefilled from `prefill` (the forms already accept these params after
2a's fix; verify, do not fork them); drift → the rule's edit form with the observed figure
prefilled and the current one shown; dead rule → the rule's edit form (the user decides between
deleting and keeping — the page does not delete). A guessed interval says "guess" in the
sentence (assert it, and assert its absence on a measured one). Suggestions cannot be dismissed
— there is deliberately no dismiss control (§8); assert the section renders all suggestions the
engine returns, and the empty state ("nothing to suggest") when it returns none.

Follow one accept end to end in the visual check: suggestion → prefilled form → create → the
rule appears in the top half and the suggestion disappears on reload (it now has a budget —
assert that direction in the system spec too: creating the rule retires the suggestion).

- [ ] Rendering, four kinds + guess flag both directions + empty state
- [ ] Accept links land prefilled; created rule retires its suggestion
- [ ] Visual check end to end; commit

## Task 8: Destroying a pool no longer corrupts its neighbours

**Files:** modify `app/models/pool.rb`; test `spec/models/pool_destroy_spec.rb`

Decision 5. `before_destroy` (on budget/savings pools): re-point each movement's
destroyed-endpoint to `account`, destroying any movement that collapses to account→account.
Accounts with children keep `restrict_with_error`; an account-less orphan pool's movements can
only be same-user transfers, which re-point to the counterparty's account — if the orphan has
movements and no account exists to receive them, block destroy with a reason (assert it).

Assert with a chain the §7a note describes, measured not asserted-by-definition: account→B $100
(allocation), B→C $60 (transfer), B holding $40. Destroy B: C's balance **unchanged** at $60
and its movement now reads from-account; the buffer **rises by exactly $40**; the account→B
movement is gone; `Σ pools == bank balance` pinned against the fixture's planted literal before
and after (not against `Pool#total`'s own parts — tautology #7 otherwise). Both directions: an
account with children still refuses.

Check the pools UI's delete affordance renders the outcome honestly (its confirm copy should
say the money returns to the buffer) — small copy change if needed.

- [ ] Re-pointing + collapse + guards, chain fixture measured
- [ ] Conservation pinned against planted literals; UI copy; commit

## Task 9: Home's underwater branch goes live, and the sacrifice view

**Files:** create `app/presenters/sacrifice_presenter.rb`, `app/controllers/sacrifices_controller.rb`, `app/views/sacrifices/show.html.erb`, `app/javascript/controllers/sacrifice_controller.js`; modify `app/presenters/home_presenter.rb`, Home standing band view, `config/routes.rb`; test `spec/presenters/sacrifice_presenter_spec.rb`, `spec/system/sacrifices/show_spec.rb`, `spec/system/home/standing_spec.rb`

**Interfaces produced:** `SacrificePresenter.new(user:, today:)` → `#gap` (rules_need −
typical_income — the same two readers as Task 4, **not** a re-derivation), `#cuttable_rows`
(anchorless rules: name, current, floor 0), `#fixed_rows` (anchored, with reason),
`#unwinnable?` (Σ cuttable < gap); route `get "sacrifice" => "sacrifices#show"`.

§9. The what-if: each cuttable row a checkbox + amount input (defaulting to current), Stimulus
recomputes "Cutting frees / Still underwater" live from the DOM — client-side arithmetic over
figures the presenter printed, no requests. **The unwinnable case is stated plainly** (spec:
no false comfort): when every cuttable dollar still leaves a gap, the page opens saying so,
with the number. Assert both directions — winnable shows the dial, unwinnable shows the
statement, pinned at figures that differ. Rows link to the rules' edit forms; nothing here
writes (decision 3).

Home: the standing band's underwater branch (reachable since Task 4) gains the permanent button
to `/sacrifice` (§9: visible only when underwater — both directions asserted, and this is the
second reader of `underwater?`, so it must *be* Task 4's reader, exposed, not a recomputation).
Plus the §8 rough-edge wording: a `behind` row whose pool has a rule updated **after** the
period's latest distribution says `— you raised this rule after distributing`. Derived: compare
the rule's `updated_at` against the period's latest `PoolMovement.distributed` date for that
account, through the existing calculators' data, no new column. Assert both directions (raised
after → clause; raised before / no distribution → no clause, with the positive pair on the same
screen per the Capybara trap).

Visual check: declare a low income on the demo (through the Task 4 form, then restore it and
say so), watch Home grow the button, follow it, dial two cuts, quote the totals moving.

- [ ] Presenter + unwinnable both ways
- [ ] View + live dial; row links
- [ ] Home button both ways; raised-after-distributing wording both ways
- [ ] Visual check with figures; dev DB restored; commit

---

## Plan 2c Done

The Budget page exists: rules visible in fill order and draggable, the period and income
declared at last, suggestions surfacing drift the moment it happens, and the app saying
plainly — with a screen, not a shrug — when the budget cannot fit the income.

**Plan 2d** (last): logging's envelope impact, the Categories change, Reports demotion, the
`basis_per_paycheck?` rename including its user-visible string, the `/pools` index gap,
`searchable :pool`, and `PoolCalculator`'s keyword-axes split.
