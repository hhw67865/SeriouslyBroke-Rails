# Distribution & Reallocation — Implementation Plan (2b of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The first write paths — distribute a period's money across envelopes, and move money between them.

**Architecture:** Two new services mirror the read/write split that already works: `AllocationCalculator` proposes a split and writes nothing; `AllocationCommitter` turns a proposal into `PoolMovement` rows in one transaction. The distribution screen renders a proposal, lets each line be overridden, and states what each override costs. Reallocation is the same machinery at single-row scale, and it is what finally makes Home's problem rows actionable.

**Tech Stack:** Rails 8.1, PostgreSQL (UUID PKs, `money` columns), Tailwind, RSpec, FactoryBot, Capybara.

**Spec:** `docs/superpowers/specs/2026-08-15-budgeting-ui-design.md` (§5, §7.2, §4.2)
**Domain spec:** `docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md`

## Global Constraints

- **Work on branch `feature/envelope-budgeting`. Never run `git push`.** Committing is expected; any stored project memory saying otherwise is stale.
- Commit messages **single-line**, `type/scope: description`, **no `Co-Authored-By`**. Stage explicit paths.
- `# frozen_string_literal: true` atop every Ruby file. UUID PKs; money columns `t.money "name", scale: 2`.
- **Money type.** The `money` column keeps an **Integer** for in-memory records, and an empty `sum(:amount)` returns `Integer 0` — this leaked **five times** across Plans 1 and 2a. `[x, 0.to_d].max` **does not coerce unless the clamp fires**. Coerce the *result*: `(a - b).to_d`, `sum(0.to_d)`. **Assert the type**, not only the value.
- **Never compare ids where one side may be unsaved** — `nil == nil` silently accepts. Six occurrences in Plan 1.
- **Determinism.** Any ordered read reaching a screen or a money decision sorts explicitly. The established keys are `[priority, name]` for pools and `[due_date, -amount, id]` for rules. Four nondeterminism sites were fixed in earlier plans; do not open a fifth.
- Run `bundle exec rubocop -A` before finishing. Run spec files **one at a time**.
- **Tailwind:** classes not already in the codebase need `bin/rails tailwindcss:build`. Colours from `app/assets/stylesheets/custom.css`. Use `rounded`, never `rounded-lg/xl`.
- Follow `docs/coding-standards.md`. Calculators in `app/services/`, presenters in `app/presenters/`.

## Known environmental failures — do not chase

`spec/system/pools/form_spec.rb`'s "auto-create categories" group crashes Chrome (`InvalidSessionIdError`, zero assertion failures); it is worse on untouched HEAD and green when run in focused groups. One example in `spec/system/categories/show/budget_spec.rb` does the same. Confirmed pre-existing across three plans.

## Three decisions this plan settles

### 1. The sweep is materialised, never faked in the display

Spec §7.2 says an expired rate envelope "displays as `$0` and its leftover displays in the buffer immediately, whether or not a distribution has happened." **This plan does not do that, deliberately.**

If Groceries holds $60 when its period ends, that $60 is *physically in Groceries*. Rendering `$0` would make the screen contradict the ledger — and this app's governing premise is that a pool balance is literally true, with `Σ pools == your bank balance`. A display that is right about intent and wrong about location breaks the one invariant everything else rests on.

Instead: **show the real balance, marked as belonging to a closed period.** `$60 · last period` reads honestly and creates the same pressure to distribute. The next distribution shows `swept back from Groceries $60` as its first line and moves it for real.

Same end state, no interval where the screen and the ledger disagree. **Update spec §7.2 as part of Task 1.**

### 2. Savings pools never sweep — and this is the trap most likely to bite

Domain spec §7.2: savings accumulate by definition. A dateless goal is a **rate rule on a savings pool**, so a sweep written as "every rate envelope" **drains savings goals**. Compounding it, `PoolCalculator#required` uses contribution-rate semantics for those pools while `allocated_balances` still clamps to the rule's own amount, so a $2,400/$150 goal holding $600 reports `free_amount` **$450** — money a naive sweep would take.

**Sweep eligibility is `pool_type_budget?`, never "has a rate rule".** Assert a funded savings goal survives a sweep, in both directions.

### 3. An override is not a rule change

Editing a line on the distribution screen is a **one-off** for this distribution. The rule still says $500; you chose $200 this once, and the shortfall compresses into the periods that remain. Rule editing lives on the Budget page (Plan 2c) and changes every future period. They must not look alike, and nothing in this plan may write to `budgets`.

---

## File Structure

**Created**

| file | responsibility |
| --- | --- |
| `app/services/allocation_calculator.rb` | sweep + required + priority fill → a proposal, no writes |
| `app/services/allocation_committer.rb` | proposal → `PoolMovement` rows, one transaction |
| `app/presenters/distribution_presenter.rb` | everything the distribution screen renders |
| `app/controllers/distributions_controller.rb` | `new` / `create` |
| `app/controllers/pool_movements_controller.rb` | reallocation |
| `app/views/distributions/*`, `app/views/pool_movements/*` | screens |
| `spec/services/*`, `spec/presenters/*`, `spec/system/distributions/*`, `spec/system/pool_movements/*` | tests |

**Modified**

| file | change |
| --- | --- |
| `app/services/pool_calculator.rb` | `period_closed?` for rate rules |
| `app/presenters/home_presenter.rb` | fix candidates for the attention list |
| `app/views/home/_attention.html.erb` | problems gain their fix buttons |
| `config/routes.rb` | distributions, pool movements |
| `docs/superpowers/specs/2026-08-15-budgeting-ui-design.md` | §7.2 correction |

---

## Task 1: A closed period is visible, and sweepable

**Files:** modify `app/services/pool_calculator.rb`, `app/helpers/home_helper.rb`, `app/views/home/_pool_row.html.erb`, `docs/superpowers/specs/2026-08-15-budgeting-ui-design.md`; test `spec/services/pool_calculator_spec.rb`, `spec/system/home/pools_spec.rb`

**Interfaces produced:** `PoolCalculator#period_closed?`, `#sweepable_amount`

A rate rule's period has closed when `BudgetCalculator#period_end`, **measured from the date the pool was last funded**, is before today. Measuring it from `today` instead is a no-op: `period_end` is `today.end_of_month` for a monthly rule and `next_payday - 1` for a per-paycheck one, so it is always `>= today` and the comparison is unreachable for every cadence, anchor and basis. The period being asked about is the one the money belongs to, not the one the reader is standing in.

`sweepable_amount` is what the next distribution would take back: the balance **less what live dated rules are holding**, for `pool_type_budget?` pools whose rate rules have all closed, clamped at zero.

```ruby
# A budget envelope whose rate period has ended still holds its leftover — the money
# is physically there until a distribution moves it. We say so rather than rendering
# $0, because `Σ pools == your bank balance` is the invariant everything rests on.
# Savings pools are excluded by type, not by rule shape: a dateless goal is a rate
# rule on a savings pool, and sweeping it would drain the goal (domain spec §7.2).
def compute_period_closed
  return false unless pool.pool_type_budget?

  rate_budgets = pool.budgets.reject { |b| b.anchor_date.present? }
  return false if rate_budgets.empty?
  return false if last_funded_on.nil?

  rate_budgets.all? { |b| b.calculator(today: last_funded_on).period_end < today }
end

def sweepable_amount
  return 0.to_d unless period_closed?

  [(balance - anchored_reserve).to_d, 0.to_d].max.to_d
end

# Reserved by ALLOCATION rather than by the rule's amount, so `#reserve` and
# `#free_amount` keep their single answer to "which rules is this money covering".
def anchored_reserve
  allocated_balances.sum(0.to_d) { |b, taken| live_anchored?(b) ? taken : 0.to_d }
end
```

`period_closed?` memoises `compute_period_closed`; `#all?` means the **latest** period end governs when a pool mixes bases, because sweeping at the earlier one would take money the other rule still expects and `#required` would then ask for it again.

`allocated_balances` gives a `fulfilled?` rule nothing and does not consume `remaining` on its behalf: a settled obligation holds no money, and the rules behind it in the fill order receive what it would otherwise have hoarded. This moves `#reserve` down and `#free_amount` up, and moves `PoolStatus` off `:behind` for pools that only read behind because a paid bill was hoarding an allocation. It cannot move `#required` for the settled rule itself — `BudgetCalculator#shortfall` returns `0.to_d` before it looks at `allocated` — but it does move `#required` for the pool, because the rules behind it now see more money.

The row label gains ` · last period` when `period_closed?`. Update spec §7.2 to match decision 1 above, in the spec's own voice.

**Assert both directions**, including: a savings pool with a rate rule whose period has closed is **not** sweepable; a budget envelope mixing a rate rule and a live dated rule sweeps the rate leftover and **not** the dated rule's reserve; a pool holding only a dated rule is never closed at all; and `sweepable_amount` returns `BigDecimal` on an entry-less pool.

`free_amount` and `sweepable_amount` are **not** interchangeable on a closed envelope: `free_amount` reserves every rule, `sweepable_amount` reserves only the dated ones, and that difference *is* the sweep. They coincide only at zero.

---

## Task 2: `AllocationCalculator` — the proposal

**Files:** create `app/services/allocation_calculator.rb`, `spec/services/allocation_calculator_spec.rb`

**Interfaces produced:** `AllocationCalculator.new(user:, account:, today:)` with `#sweeps`, `#total_swept`, `#available`, `#rows`, `#total_allocated`, `#leftover`, `#short?`. `Row` is namespaced inside the class as `AllocationCalculator::Row`.

Five steps, in order, mirroring spec §5:

1. **Sweep** — every `account.child_pools`' `sweepable_amount`, keeping the positive ones. No second gate: `sweepable_amount` already returns `0.to_d` unless the period is closed, and a `period_closed?` filter beside it is a second reader free to disagree with the first. `#sweeps` is keyed by the `Pool` record, so Task 3 has its `from_pool` without a second lookup.
2. **Available** — the account's current balance **plus** the sweeps (the sweep money is already inside the account's total, but not in its unallocated buffer). **Not clamped at zero.** A single account has no sibling overdraft to cancel against, so clamping would only hide a real negative; Task 4 renders a negative `#available` and `#leftover` rather than assuming a floor.
3. **Required** — `pool.calculator(today: today, net_of_sweep: true).required` per envelope in this account. The sweep is not materialised until Task 3, so a plain `#required` reads a balance that still holds the leftover and the envelope reports itself already part-funded — measured at $315 against a $400 rule, short by exactly its own sweep, every period. Not recoverable by adding the sweep back onto `required`: on a mixed envelope the live ask is $0 while the correct ask is $100.
4. **Fill** — top-down by `[priority, name]`, `funded = remaining.clamp(0.to_d, needed)`. Clamp `needed` at zero first — `goal_required` returns `[rate, remaining].min`, so a negative rule amount reaches `clamp(0.to_d, -150)`, which raises `ArgumentError` and 500s the whole distribution screen.
5. **Leftover** — what stays in the account buffer.

```ruby
Row = Struct.new(:pool, :needed, :funded, keyword_init: true) do
  def short = needed - funded
end
```

`net_of_sweep:` derives its amount from a plain twin calculator, never from `self` — computing it on `self` recurses, since `sweepable_amount` reaches `anchored_reserve` and then `balance`. **A `net_of_sweep` calculator must never be asked for `sweepable_amount` or `period_closed?`**: post-sweep it re-derives a second, smaller sweep ($400, then $100 on the mixed envelope). Task 3 reads both in one method and is where that footgun points.

**One account per proposal.** Cross-account transfers are out of scope (spec §5), so a distribution is scoped to the account whose money is being distributed. `#rows` excludes zero-need pools, matching Home's waterfall.

Assert: the sweep contributes to `available`; a savings goal is never swept; the fill order is deterministic under a priority tie; `short?` agrees with the rows.

---

## Task 3: `AllocationCommitter` — the first write path

**Files:** create `app/services/allocation_committer.rb`, `spec/services/allocation_committer_spec.rb`

```ruby
# Turns a proposal into movements. Sweeps first (envelope → account), then
# allocations (account → envelope), all inside one transaction so a failure
# leaves the ledger exactly as it was.
AllocationCommitter.new(proposal, overrides: {pool_id => amount}).call
```

Rules:
- **One transaction.** Any validation failure rolls back everything and returns a result object carrying the errors — never a partial split.
- **Sweeps are movements too**, `from: envelope, to: account`, so the ledger explains the money's whole journey.
- **Zero-amount lines are skipped** — `PoolMovement` validates `amount > 0`, and a $0 allocation is not an event.
- **Idempotence within a period:** re-running a distribution for a period that already has one **replaces** it, in the same transaction.

  This needs a column the table does not have. `pool_movements` carries only `from_pool_id`, `to_pool_id`, `amount`, `date` and `source_entry_id` — nothing distinguishes a distribution allocation from a sweep or from a manual reallocation, so "delete this period's distribution" would silently destroy reallocations the user made in the same period.

  **Add `kind` (`allocation` | `sweep` | `transfer`), defaulting to `transfer`** so existing rows and the reallocation path in Task 7 are untouched. Replacement then deletes exactly the `allocation` and `sweep` rows whose `date` falls in the period.

  Replacement rather than refusal is deliberate: a user who mistyped an override needs to redo the split, not be locked out of it.

Assert: a rollback on one bad row leaves zero movements; a re-run replaces rather than doubles; sweeps and allocations both appear; the movement amounts sum to the proposal.

---

## Task 4: The distribution screen — proposal

**Files:** create `app/presenters/distribution_presenter.rb`, `app/controllers/distributions_controller.rb`, `app/views/distributions/new.html.erb` and partials; modify `config/routes.rb`; test `spec/presenters/distribution_presenter_spec.rb`, `spec/system/distributions/proposal_spec.rb`

Two densities **chosen by the data, not a setting** (spec §5): all clear → headline, one summary line, one button. Anything short → the full table, no collapse, because a single confirm on a short distribution lets someone quietly starve the bottom rows.

The sources breakdown is required — buffer carried, income this period, swept back — because "where did this number come from" is the first question the screen must answer.

Route: `resources :distributions, only: [:new, :create]`.

### A period that has already been distributed

Task 3 found this and could not fix it from where it stood. Once a period's split has been committed, the envelopes are funded, so a freshly computed proposal asks for **nothing** — the screen would say "nothing to distribute" while the confirm button underneath it replaces the whole split and re-writes it. The screen would be stale and the action correct, which is the wrong way round.

The screen shows the period **as if its distribution had not happened**, because that is exactly what confirming does: `AllocationCommitter` deletes the period's `allocation` and `sweep` rows and only then computes the proposal it writes.

Get that from **one code path shared with the committer**, not a second one. Inside a transaction: delete the period's distributed rows, compute the proposal, `raise ActiveRecord::Rollback`. The committer runs the same delete-then-compute for real; the screen runs it and throws the deletion away. Extract the inner "delete this period's distribution, then build a fresh `AllocationCalculator`" step so both callers reach the same code, and the screen cannot drift from the action.

**Do not** instead teach `AllocationCalculator` or `PoolCalculator` to exclude a set of movements. That is a second answer to "what does this period look like undistributed", free to disagree with the committer's — the failure mode this plan has hit in every task where two readers answered one question.

A redistributed period must be **labelled as one**. Confirming replaces rather than adds, and a user who cannot see that their last split is about to be discarded cannot consent to it.

Assert both directions on the same screen: an undistributed period proposes its split, and a distributed period proposes the *same* split again rather than an empty one — pinned at the same figures, so a screen that quietly recomputed to zero cannot pass.

---

## Task 5: Overrides and their consequences

**Files:** modify the distribution views and presenter; test `spec/system/distributions/overrides_spec.rb`

Every line editable. On an override, state the consequence **only when the per-period ask actually changes** (principle 3). Editing a dateless goal shows nothing, because nothing changes.

The consequence names the mechanism, not just the number:

> You're moving **$300** onto your next period. Feb 20 will need **$800** instead of **$500** — it's the last period before Mar 1.

An override that leaves an envelope unable to recover uses the **won't make it** red, not the amber of a trade — it is an existing state, not a new one.

**This task adds no writes.** The override is held in the form and applied at confirm.

---

## Task 6: Confirm

**Files:** modify `DistributionsController#create`; test `spec/system/distributions/confirm_spec.rb`

Confirming calls `AllocationCommitter` with the overrides, redirects to Home, and says what happened. A failure re-renders with the errors and **no movements written**.

Assert the whole loop: distribute → Home shows the envelopes funded → the buffer dropped by exactly the allocated total → `Σ pools` is unchanged (money moved, none created).

That last assertion is the one that matters. **It is the invariant this entire app rests on**, and this is the first plan that can break it.

---

## Task 7: Reallocation

**Files:** create `app/controllers/pool_movements_controller.rb`, `app/views/pool_movements/new.html.erb`; test `spec/system/pool_movements/move_spec.rb`

One movement: from, to, amount. Same-account only (spec §5). The screen states the damage before you commit it:

> Car $1,340 → $1,122 — Maintenance slips to $494/$800 · +$27/period

A source that cannot afford it is shown but disabled, with the reason.

Route: `resources :pool_movements, only: [:new, :create]`.

---

## Task 8: Home's problems become actionable

**Files:** modify `app/presenters/home_presenter.rb`, `app/views/home/_attention.html.erb`; test `spec/system/home/fixes_spec.rb`

Spec §4.2 — deferred from Plan 2a because every fix is a write path. Each problem gains a **specific, clickable fix naming a source that can genuinely cover it**, linking to Task 7's screen prefilled.

`HomePresenter#fix_candidates_for(pool)` returns pools in the same account with enough free money, richest first, **excluding any pool whose own status needs attention** — proposing to rob an envelope that is itself behind is not a fix.

A problem with **no** candidate says so plainly rather than offering a dead button. That case is reachable and must be asserted.

### Home adopts the post-sweep view

`HomePresenter#waterfall` is a near-duplicate of `AllocationCalculator#fill` — same `[priority, name]` order, same clamp, same reject-after-fill, same row shape — and it differs in two ways: it spans accounts, and **it does not sweep**. So a closed envelope reads `needs $315` on Home and `needs $400` on the distribution screen: a screen disagreeing with the action it is offering, the same defect class as rendering `$0` for an envelope that still holds its money.

Home takes the distribution's view, because that is what will actually happen when the user presses the button. Both halves move together:

- `#waterfall` and `#total_required` compute `required` with `net_of_sweep: true`.
- `#available` gains `Σ sweepable_amount` across the pools it already counts.

**`#shortfall` and `#covered?` must not move at all.** Required and available both rise by the same swept total, so their difference is invariant — Home says $315 against $500 available, the distribution says $400 against $585, and both are $185 clear. Assert that invariance directly on a fixture with a closed envelope: it is the property that proves the two screens are answering the same question, and if it fails, one of the two halves was changed without the other.

Sweeps cross no account boundary, so Home may sum `sweepable_amount` over every pool it renders, orphans included, without the per-account scoping `AllocationCalculator` needs.

---

## Plan 2b Done

You can distribute a period's money and move it between envelopes, and Home's problems finally do something.

**Plan 2c**: the Budget rules page, priority ordering, the suggestion engine, the sacrifice view, and `typical_income`'s missing input.
**Plan 2d**: logging's envelope impact, the Categories change, the Reports demotion, the `basis_per_paycheck?` rename including its user-visible string, and the `/pools` index gap.
