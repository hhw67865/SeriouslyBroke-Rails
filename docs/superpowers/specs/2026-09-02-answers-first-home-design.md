# Answers-First Home: Free to Spend, and the Period as Progress

**Status:** APPROVED in chat (Henry, 2026-09-02) — "the mechanism is right but the UI hurts…
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
