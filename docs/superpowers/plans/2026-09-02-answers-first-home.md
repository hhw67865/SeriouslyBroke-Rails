# Answers-First Home Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Home answers the four questions (in checking / free to spend / where in the period / spent per category) instead of showing the two-ledger system.

**Architecture:** Presentation-only over the delivered mechanism: one new derived figure (`free`, composed from existing readers), a hero card replacing the standing band, spent-of-planned bars replacing the categories band, a conditional trouble strip replacing the attention band, accounts collapsed to a line. Plus the two approved ride-alongs (sidebar contrast, suggestion gating).

**Tech Stack:** Rails 8.1, RSpec/Capybara, Tailwind, existing readers (`AccountLedger`, `CategoryLedger`, `AllocationCalculator`, `HoldingCalculator`/`HoldingStatus`, `Budget.steady_need`).

**Spec:** `docs/superpowers/specs/2026-09-02-answers-first-home-design.md` — §3's one-spelling rule for `remaining_plan` is the binding constraint.

## Global Constraints

- **No mechanism changes**: no tables, columns, writers, or ledger arithmetic. `free = min(pot, available − remaining_plan)` composes EXISTING readers; `remaining_plan` must share its period-ask spelling with the Budget page / waterfall (one reader per question — a reviewer finding a re-derivation is a defect).
- Home's user-facing words: *in checking, free, set aside, spoken for, spent, of*. "Available" only on Distribute/Budget; "buffer"/"unclaimed" die everywhere (grep app/views + helpers; update pinned copy in specs, figures preserved).
- The hero renders in EVERY state (no branch back to "covered/uncovered" headlines); negative figures render red and honest, never clamped.
- Trouble strip: absent when nothing is true — no permanent placeholder.
- All prior session disciplines: single-line commits, explicit paths, never push; spec files one at a time, `pgrep -f "[r]spec"` quiet first, seeds_spec ALONE; rubocop -A clean (re-run specs after); planted literals both directions; `Date.current` never lazily inside travel_to; dev DB real data (mingguan0809@gmail.com only; throwaway signups for browser work); Tailwind rebuild for new classes; design-standards.md + the NEW tokens (post-design-wave `custom.css`) bind all styling.

---

### Task 1: `free` and the hero card

**Files:** `app/presenters/home_presenter.rb` (new `#in_checking`, `#free_to_spend`, `#free_cap_bound?`, `#remaining_plan`; the standing-band methods retire), `app/views/home/_hero.html.erb` (new, replaces `_standing.html.erb`), `app/views/home/index.html.erb`; specs: `spec/presenters/home_presenter_spec.rb`, `spec/system/home/hero_spec.rb` (successor of `standing_spec.rb` — carry surviving examples, name deletions).

**Interfaces:** Produces `HomePresenter#free_to_spend` (BigDecimal, signed), `#in_checking` (= `AccountLedger#pot`), `#remaining_plan` (Σ over the SAME per-category ask the consumed `AllocationCalculator` rows carry — ground in `#rows`' needed/funded before writing; if the ask lives on `HoldingCalculator#required`, consume that, but ONE spelling, stated in a comment with the shared reader named), `#period_progress` (reuse `#period_range` + day arithmetic from the existing period reader). Consumes: everything already memoized on the presenter — no new queries beyond one ledger call if unavoidable (query-cost pin in the house idiom).

- [ ] Spec-first: the §9 archetypes (fresh user; mid-period budgeter with planted figures asserting `min` both ways and the cap subline; negative free; negative pot red) + the one-spelling example (free's remaining_plan equals the Budget page's figure for the same fixtures, read through both entry points).
- [ ] Implement; hero copy per spec §2; period bar reuses the range reader; both-breakpoint check in browser as a throwaway.
- [ ] Collateral: whole `spec/system/home/` one at a time. Commit: `feat/home: in checking, free to spend, and the period as a bar`.

### Task 2: The period section, the trouble strip, the accounts line

**Files:** `app/views/home/_this_period.html.erb` (replaces `_categories.html.erb`), `_trouble.html.erb` (replaces `_attention.html.erb`), `_accounts_line.html.erb` (+ keep `_account.html.erb` for the expansion), `home_presenter.rb` (`#period_rows` — spent/planned per holder via existing calculators; unbudgeted-with-spending rows; `#troubles` — the strip's triggers), `home_helper.rb`; specs: `home/this_period_spec.rb`, `home/trouble_spec.rb` (successors of `categories_spec`/`attention_spec` — carry figures, name deletions), `home/accounts_spec.rb`.

**Interfaces:** Produces `Row`-style objects with `spent`, `planned`, `over?`; `#troubles` (typed: overdraft / overdrawn category / overdue bill / undistributed period — each from an existing reader). Consumes Task 1's hero (renders above). Rules: spent-this-period from the period-bounded expense read the calculators already own (no new date arithmetic); sort trouble-first then fill order; zero-spend unbudgeted rows absent; savings keep target bars; onboarding cards still surface top-level while incomplete; the expansion holds today's account cards unchanged.

- [ ] Spec-first per §9 (bars, over state, absence cases, each trouble trigger both directions, strip ABSENT when clean, accounts line + expansion). Implement. Both breakpoints in browser. Collateral: whole `spec/system/home/`, `spec/presenters/home_presenter_spec.rb`. Commit: `feat/home: spent-of-planned bars, trouble only when true, accounts as one line`.

### Task 3: Vocabulary sweep + sidebar + suggestion gating

**Files:** grep-driven: every view/helper printing "buffer"/"unclaimed" (Distribute's flash, Budget's leftover clause — reword to "available" there, Home words on Home); `custom.css` (sidebar gradient light end darkened until white wordmark + 70% eyebrows ≥4.5:1 at every stop — compute and report the ratios); `app/services/suggestion_engine.rb` (gating: drift/dead need 2+ full periods of user history — define "history start" from the earliest entry via an existing reader; dated bills need 2+ occurrences of the item; self-disclaimed one-occurrence guesses render with secondary weight — view + helper), `budget_page/_suggestion*.erb`; specs: `suggestion_engine_spec.rb` (gating both directions: day-old sees zero drift/dead; 2+ periods unlocks; occurrence threshold), affected copy pins.

- [ ] Sweep + implement + measure sidebar ratios. Collateral: `budget_page/suggestions_spec.rb`, `seeds_spec.rb` ALONE (the seeds' detector figures may shift with gating — the seeds have long history so likely stable; if a figure moves, the cause must be named). Commit: `feat/design: one word for free money, a readable sidebar, and suggestions that wait for history`.

### Task 4: Verification + docs

- [ ] Browser as a fresh throwaway (full onboarding → the hero at each stage) and as Ming (real data; her hero figures cross-checked by SQL: in-checking = pot, free per §3). Screenshots Home 1440 + 375 left at repo root, named.
- [ ] The two previously-unseen states rebuilt on the throwaway: empty-budget-with-spending (now the hero's honest negative — the old copy question is CLOSED by design), and the not-in-fill-order band (unchanged this plan — confirm it still renders sanely beside the new Home).
- [ ] Docs: spec → DELIVERED with as-built; `design-standards.md` gains the new token ratios if it lists colors; grep CLAUDE.md (likely no change). Full `spec/system/home/` + `spec/presenters/` sweep. Commit: `docs/home: delivered — four questions, four answers`.

## Self-review
- §2→T1, §3→T1 (one-spelling constraint carried), §4/§5/§6→T2, §7→T3, §9→each task's spec list. No placeholders; interfaces named; the only new arithmetic (`min`, Σ max(0, ask−given)) is specified where it lives.
