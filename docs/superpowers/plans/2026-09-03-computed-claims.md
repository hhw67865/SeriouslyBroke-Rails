# Computed Claims Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A category's money is a claim computed from its rules, the calendar, its spending, and dated adjustments — the distribute step and every purpose-side movement are deleted.

**Architecture:** One new reader (`ClaimCalculator`, per rule, with a batched `ClaimLedger` for screens) replaces the holding calculators and the allocation lane; one new writer (`Adjustment` — rule, date, signed amount) replaces set-asides/releases/skips; Home and Budget re-read claims; then the distribution apparatus and the `allocations` table are deleted in one migration. Physical ledger untouched.

**Tech Stack:** Rails 8.1, RSpec/Capybara, existing period readers (`User#period_boundaries`/`#period_containing`), `AccountLedger`, `CategoryLedger`'s entry lane (spending), `Budget` rules.

**Spec:** `docs/superpowers/specs/2026-09-03-computed-claims-design.md` — §3's formulas are the acceptance tests.

## Global Constraints

- **Physical invariant untouched:** `pot + Σ accounts == income − expenses` holds before/after every task (raw SQL pin where a task touches a writer; the migration verifies it).
- **Claims are definitions, pinned example-by-example**: every §3 formula case (rate under/exact/over/reset; dated accrual per period, cap, fulfilment drop+restart, catch-up after an adjustment, spill on over-fulfilment; dateless target with/without rate; `funded_since` start, no retroactive accrual) gets a planted-literal example, both directions. Period arithmetic comes ONLY from `User#period_boundaries`/`period_containing` — one spelling.
- **Adjustments never touch accounts** (no code path from `Adjustment` to `account_movements`/`Pool`); the purpose side has exactly two writers after this plan: rules and adjustments.
- Vocabulary: **built-up** (a rule's running total), never "saved"; "savings" = accounts only; Home's words stay (in checking, free, set aside → now "claimed"/"built up", spent, of). "Available"/"distribute"/"allocation" leave the app with their screens.
- Old readers stay alive until Task 4 deletes them; new code never reads `allocations`.
- All session disciplines: single-line commits, explicit paths, never push; spec files one at a time, `pgrep -f "[r]spec"` quiet, `seeds_spec` ALONE; rubocop -A + re-run; `Date.current` never lazily inside travel_to; dev DB real data (`mingguan0809@gmail.com` only; throwaway signups for browser work); Tailwind rebuild for new classes; true-375 via the CDP idiom.

---

### Task 1: `Adjustment` + `ClaimCalculator` + `ClaimLedger`

**Files:** migration `db/migrate/20260903000000_create_adjustments.rb` (table only: `rule_id` FK NOT NULL → budgets, `date` datetime NOT NULL, `amount` money NOT NULL non-zero CHECK, timestamps, indexes on rule_id/date); `app/models/adjustment.rb`; `app/models/budget.rb` (`has_many :adjustments, dependent: :destroy`; `#claim_calculator(today:)`); `app/models/category.rb` (`#claim(today:)` = Σ over its rules); `app/services/claim_calculator.rb`, `app/services/claim_ledger.rb`; factories; specs `spec/models/adjustment_spec.rb`, `spec/services/claim_calculator_spec.rb` (the §9 formula matrix), `spec/services/claim_ledger_spec.rb` (batching + one-spelling with the per-rule calculator).

**Interfaces — Produces:** `ClaimCalculator.new(rule, today:, spending: nil, adjustments: nil)` → `#claim`, `#built_up`, `#planned_this_period`, `#accrued_this_period`, `#spent_this_period`, `#over?`, `#next_due_on`, `#periods_left`; `ClaimLedger.new(user, today:)` → `#claim_of(rule)`, `#total_claims`, `#free` (= `min(pot, total_money − total_claims)`, reading `AccountLedger` for pot/total), grouped spending and adjustment sums in ≤3 statements (pinned). Spending-this-period and spending-since-fulfilment come from `CategoryLedger::ENTRY_CATEGORY_ID`'s lane (the one funded_since/timezone spelling) filtered by item for item-backed rules.

- [ ] Specs first (formula matrix), red; migrate test; implement; green; `rubocop`; commit `feat/claims: a rule's money is computed from the calendar, the entries and dated adjustments`.

### Task 2: The adjustments writer and the cadence guard

**Files:** `app/controllers/adjustments_controller.rb` (create/destroy, rule scoped via `current_user`), route `resources :adjustments, only: [:create, :destroy]`; Budget page rule row gains "Adjust this period" (skip = −planned, reduce, top up) and for target rules "Set aside / take back" (positive/negative, today-dated) — one small form partial `budget_page/_adjust.html.erb`; adjustments listed per rule (date, amount, remove); `BudgetPageController#update` (the declaration form) gains the §3.5 cadence-change offer: when cadence changes, a confirm step listing rate rules with their scaled amounts, applied on confirm. Specs: `spec/requests/adjustments_spec.rb` (ownership 404, non-zero, both signs, destroy), `spec/system/budget_page/adjustments_spec.rb` (skip lands at −planned dated today; the claim moves; cadence offer both accept/decline).

- [ ] Same rhythm; commit `feat/claims: skip, top up, set aside and take back are one dated row; cadence changes offer to scale rate rules`.

### Task 3: Home and Budget read claims

**Files:** `app/presenters/home_presenter.rb` (`free_to_spend` = `ClaimLedger#free`; `remaining_plan`/"spoken for" DIE; the hero subline arms re-derived on the new terms: parked-elsewhere / claimed / nothing-claimed — keep the cause-established discipline and the arm table); `_hero.html.erb`; `_this_period.html.erb` rows: rate → `spent of rate`, target → `built up of target · next due · $X/period`, over in red; `_trouble.html.erb`: the undistributed trigger DIES; free<0 shows the shortfall + uncovered claims in reverse priority + the per-day pace (`shortfall ÷ days left`); `budget_page` group rows show built-up/next-due/per-period from the same ledger; `SuggestionEngine`'s drift detector reads claims' spending (unchanged lane) — confirm no allocation read survives. Specs: hero/this_period/trouble/budget_page files converted (figures re-derived from the formulas and planted; deletions named), the presenter spec, one true-375 pin per changed section.

- [ ] Same rhythm; commit `feat/claims: Home and the Budget page read the claim`.

### Task 4: The deletion and the migration

**Files:** migration `db/migrate/20260903010000_drop_the_distribution.rb` — convert purpose-side `transfer` allocations to adjustments (rule = the category's rule; mint a target-only rule for a goal with none; date/sign preserved), DELETE `allocation`/`sweep` rows, verify the physical invariant unchanged by raw SQL, drop `allocations`; delete `AllocationCalculator`, `AllocationCommitter`, `DistributionPresenter`, `DistributionsController` + views + helpers + route + nav, `DistributionClock`, `Waterfall`, `Allocation` model/factory, `HoldingCalculator`/`HoldingStatus`/`HoldingProjection` (their surviving vocabulary — on track/behind/overdue — re-homed on `ClaimCalculator`), `CategoryLedger`'s allocation lane (`available` dies; the entry lane survives as the spending reader), `Category.in_fill_order`'s fill semantics (priority = give-way order, kept), `AllocationsController` + `/allocations/new` (replaced by adjustments), the `entries` impact card's allocation reads; `db/seeds.rb` rewritten (rules + adjustments, no allocations; same demo states re-derived); `spec/seeds_spec.rb`; `spec/support/schema_rewind.rb` extended; every spec still naming the dead classes (`grep -rln "Allocation\|Distribution\|Holding" spec/` must end with `spec/migrations/*` + rewind only).

- [ ] Order: migration+spec → test migrate → deletions + spec sweep → dev migrate (receipts; Ming's pot unchanged) → seeds → two commits (`feat/claims: the distribution is gone — nothing moves on the purpose side` / `chore/claims: seeds and specs speak claims`). **Do NOT run the full suite — the controller gates it after.**

### Task 5: Verification + docs

- [ ] Browser: fresh throwaway through onboarding → rules → adjustments (skip, top-up, raid) → the hero's free moving accordingly → free<0 with the uncovered list; Ming: her five rules' claims recomputed and cross-checked by hand from the formula (write the figures), pot unchanged by SQL, screenshots Home 1440 + true-375 + Budget 1440 left at repo root, named.
- [ ] Docs: spec → DELIVERED + as-built; `2026-08-21-two-ledger-design.md` and `2026-09-02-answers-first-home-design.md` get SUPERSEDED-in-part headers; `coding-standards.md` (readers: ClaimCalculator/ClaimLedger; writers: rules, adjustments, account movements, entries); CLAUDE.md if any command/flow changed. Commit `docs/claims: delivered — the rules are the budget`.

## Self-review
§2→T1 (free) + T3 (hero); §3.1–3.4→T1 formulas + T3 display; §3.3 writer→T2; §3.5→T2; §4→T3; §5/§6/§7→T4; §9→each task's spec list. Interfaces named once (T1) and consumed by name (T2–T4). No placeholders.
