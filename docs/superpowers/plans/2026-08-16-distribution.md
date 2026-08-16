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

A rate rule's period has closed when `BudgetCalculator#period_end` is before today. `sweepable_amount` is what the next distribution would take back: the pool's balance, but **only for `pool_type_budget?` pools whose rate rules have all closed**, and never more than the balance.

```ruby
# A budget envelope whose rate period has ended still holds its leftover — the money
# is physically there until a distribution moves it. We say so rather than rendering
# $0, because `Σ pools == your bank balance` is the invariant everything rests on.
# Savings pools are excluded by type, not by rule shape: a dateless goal is a rate
# rule on a savings pool, and sweeping it would drain the goal (domain spec §7.2).
def period_closed?
  return false unless pool.pool_type_budget?

  rate_budgets = pool.budgets.reject { |b| b.anchor_date.present? }
  return false if rate_budgets.empty?

  rate_budgets.all? { |b| b.calculator(today: today).period_end < today }
end

def sweepable_amount
  return 0.to_d unless period_closed?

  [balance, 0.to_d].max.to_d
end
```

The row label gains ` · last period` when `period_closed?`. Update spec §7.2 to match decision 1 above, in the spec's own voice.

**Assert both directions**, including: a savings pool with a rate rule whose period has closed is **not** sweepable; a budget envelope mixing a rate rule and an anchored rule is not sweepable while the anchored rule is live; and `sweepable_amount` returns `BigDecimal` on an entry-less pool.

---

## Task 2: `AllocationCalculator` — the proposal

**Files:** create `app/services/allocation_calculator.rb`, `spec/services/allocation_calculator_spec.rb`

**Interfaces produced:** `AllocationCalculator.new(user:, account:, today:)` with `#sweeps`, `#available`, `#rows`, `#total_allocated`, `#leftover`, `#short?`

Five steps, in order, mirroring spec §5:

1. **Sweep** — `account.child_pools.select(&:period_closed?)`, each contributing `sweepable_amount`.
2. **Available** — the account's current balance **plus** the sweeps (the sweep money is already inside the account's total, but not in its unallocated buffer).
3. **Required** — `pool.calculator(today:).required` per envelope in this account.
4. **Fill** — top-down by `[priority, name]`, `funded = remaining.clamp(0.to_d, needed)`.
5. **Leftover** — what stays in the account buffer.

```ruby
Row = Struct.new(:pool, :needed, :funded, keyword_init: true) do
  def short = needed - funded
end
```

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

---

## Plan 2b Done

You can distribute a period's money and move it between envelopes, and Home's problems finally do something.

**Plan 2c**: the Budget rules page, priority ordering, the suggestion engine, the sacrifice view, and `typical_income`'s missing input.
**Plan 2d**: logging's envelope impact, the Categories change, the Reports demotion, the `basis_per_paycheck?` rename including its user-visible string, and the `/pools` index gap.
