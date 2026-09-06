# Coding Standards

This document defines the architecture, patterns, and coding conventions for the SeriouslyBroke Rails application.

## Core Domain Models

One PHYSICAL ledger, and a purpose side that is COMPUTED
(`docs/superpowers/specs/2026-09-03-computed-claims-design.md`, which supersedes the purpose-ledger
writers of `2026-08-21-two-ledger-design.md`; `2026-09-05-two-shapes-and-the-runway-design.md`
changes the `free` formula and cuts the rule shapes to two). The physical ledger says where money
sits and holds its invariant to the cent:

```
pot + Σ accounts == income − expenses          # the INVARIANT, verified in raw SQL by every migration
free = pot − Σ claims                          # the DEFINITION — nothing is conserved on the purpose side
```

A category's money is a CLAIM computed from its rules, the calendar, its spending and dated
adjustments. Nothing moves on the purpose side: there is no distribute step and no partition to
conserve, so `free` is a definition rather than a balance. The only connection between an account
and a category is that both are read from the same total — there is no account→category movement.

**`free` is CHECKING minus what the rules claim** (`2026-09-05-two-shapes` §1/§2), not total money
minus claims capped at the pot. Money in other accounts is SHOWN and never subtracted from or added
to anything: `ClaimLedger#total_money` survives as a different question, and `#unclaimed` /
`#free_cap_bound?` are gone with the cap. `free < 0` is a signal, never a refusal — the hero's red
arm and the trouble strip both say "your rules claim $X more than checking holds", and add "move
some in from your other accounts" only when the other accounts hold money.

**TWO RULE SHAPES, and there is no third** (`2026-09-05-two-shapes` §2). A rule is *every period*
(an allowance that resets with the paycheck) or *by a date* (a target, a date, optionally repeating
every N months). "Unspent money builds up / resets" is gone from the form and from the model: a
fund IS a dated rule whose `amount` is its target, and the open-ended "$X a period forever with no
target" shape is retired (an emergency fund is "$10,000 by next September"; raise the target on
arrival). `ClaimCalculator#shape ∈ {:rate, :dated}` and nothing else.

- **User** → has_many Categories (the purpose side) and Pools (physical); `default_account` is the pot; `#today` is the owner's local day (see below)
- **Category** (expense/income) → has_many Items and Budgets; an EXPENSE category with a `funded_since` COUNTS ITS OWN SPENDING from that date, and `priority` is its place in the GIVE-WAY order — who gives way first when the claims outrun the money. It carries NO figure of its own: `categories.target_amount` is dropped (`2026-09-04-rules-own-the-budget` §7), and "what is this category saving toward" is answered by its DATED rules — `Budget.saving_toward_a_date` (anchored, no interval, item-less, and not a `bill`) is the one scope the dashboard's Savings band reads. `#budgeted?` is the one spelling of "a rule claims this category"
- **Item** → has_many Entries
- **Entry** → the actual transaction record; income and expenses are the physical ledger's other writer
- **Pool** → one of the user's bank accounts (two-ledger spec §5: the envelope and goal types are deleted; the table keeps its name — the rename is §8 out-of-scope)
- **AccountMovement** → a transfer between two of a user's own accounts (physical ledger's only writer besides entries; its columns are still named `from_pool_id`/`to_pool_id`)
- **Budget** → a funding rule, owned by the expense Category whose money it claims. A category carries at most ONE item-less ("catch-all") rule, beside as many item-backed rules as it has items. SIX columns say what a rule IS (`2026-09-05-two-shapes` §2):

  ```
  amount          money  NOT NULL  what the rule puts in (per period / per month / the target)
  basis           int    NOT NULL  per_period | monthly
  interval_months int    NULL      every N months
  anchor_date     date   NULL      the due date the interval counts from
  item_id         uuid   NULL      the item this rule pays, else the whole category
  rule_type       int    NOT NULL  bill (0) | usage (1) | choice (2), default usage
  ```

  `ClaimCalculator#shape` reads ONE of those and nothing else: `:dated` if `anchor_date`, `:rate` otherwise. `#target` is `amount` for `:dated` and `0` for `:rate`, and is never nil. Every rule has a positive `amount` — `Budget#set_aside_only?` (the `amount = 0` permission) is gone with the shape that needed it
- **Adjustment** → `(rule, date, signed amount)`: a dated delta on one rule's accrual — set aside, take back, top up, reduce and skip are all this one row. It never touches accounts

**The four writers, and there are no others.** Purpose side: RULES (`Budget`, whose one typed door
is `RuleForm`) and ADJUSTMENTS (`Adjustment`, whose one typed door is `AdjustmentForm` — it refuses
a date the rule's walk cannot count). Physical side: ACCOUNT MOVEMENTS and ENTRIES.

**`RuleForm` is the rule's one typed door.** `/budgets/new?category_id=` and `/budgets/:id/edit` are
one page (`2026-09-05-two-shapes` §5) and send the USER'S WORDS — `schedule`
(`per_period` · `by_date`), `repeats` (a checkbox), `interval_months`, `anchor_date`, `rule_type`,
`amount`, `item_id` — and the form object derives `basis`, `interval_months` and `anchor_date` from
them: `per_period → basis per_period`; `by_date + !repeats → monthly, interval NULL, anchor`;
`by_date + repeats → monthly, interval N, anchor`. The mapping is spelled once, there, and never in
a controller or a view. `category_id` is not permitted on update: the category is read-only on edit.

A `monthly`-basis row with NO anchor ("$260 every month") is reachable only from a suggestion; the
form does not offer it and CONVERTS it on read-back, preserving the MONEY rather than the number —
`RuleForm.from` divides by `Budget#steady_ask`, so $260 a month opens and saves as $120.00 a period
on a biweekly grid, and `#converted_from_monthly` carries the row's monthly figure so the note under
the field can name what it was. Because the box holds per-period money on every path,
`SuggestionEngine` puts the observed per-period figure on the wire unconverted.

**Rule type decides the give-way order before priority does** (`2026-09-04-rules-own-the-budget` §3).
`Budget::TYPE_RANK` is `{ choice: 0, usage: 1, bill: 2 }` — the restaurant budget gives way before
the power bill, and the power bill before the rent — and it is deliberately NOT the enum's own order,
which is storage. `HomePresenter#give_way_key` is `[rule.type_rank, category rank,
Category.rule_order]`, and the category term is `#budgeted_categories` (sorted `[priority, name]`)
read BACKWARDS: within a type, the HIGHEST priority number gives way first, because the category that
would have been funded last is the one that goes without first.

## Custom Patterns

### Presenter Pattern (`app/presenters/`)

Uses Ruby `Data.define` for immutable value objects. Controllers instantiate presenters that pre-compute view data.

```ruby
# Controller
@presenter = WeeklyCalendarPresenter.new(user: current_user, date: params[:date])
# View
@presenter.entries_for_day(date)
```

### Calculator Pattern (`app/services/`)

Memoized service objects for computing metrics. Accessed via model method. A Category answers two
different questions — what was spent on it, and what its rules claim:

```ruby
category.calculator(date).top_items       # CategoryCalculator — spending metrics
category.claim(today:)                    # Σ its rules' claims
rule.claim_calculator(today:).built_up    # ClaimCalculator — one rule, spec §3's formulas
```

`ClaimCalculator` is the whole of §3: `#claim`, `#built_up`, `#planned_this_period`,
`#accrued_this_period`, `#spent_this_period`, `#over?`, `#overdue?`, `#next_due_on`,
`#periods_left`, `#countable_span`. Period arithmetic comes only from
`User#period_boundaries`/`#period_containing` — one spelling.

### Ledger Pattern (`app/services/`)

`ClaimLedger`, `AccountLedger` and `CategoryLedger` are the ONE reader of what they read — batched
grouped sums over the whole set a screen is about, memoized at first read and stale after any
write. A screen builds ONE ledger and threads it into every calculator it makes, rather than
letting N calculators run their own aggregates.

```ruby
ledger = ClaimLedger.new(user, today: user.today)
ledger.claim_of(rule); ledger.total_claims; ledger.free   # free = pot − Σ claims
```

- **`ClaimLedger`** → every rule's claim in ≤3 statements, plus `#total_money`, `#pot`, `#free`, `#claim_of_category`. It reads `AccountLedger` for the physical figures.
- **`AccountLedger`** → the physical ledger: `#pot`, `#balance_of`, `#income_within`.
- **`CategoryLedger`** → the ENTRY LANE ONLY (`ENTRY_CATEGORY_ID`, `ENTRY_CATEGORY_JOINS`, `ENTRY_LOCAL_DAY`) — the one spelling of "which category does this entry's spending count against, on whose calendar day". It is composed by the claim readers and by `SuggestionEngine`; it holds no money terms of its own.

**`User#today`, not `Date.current`.** Anything that reads a claim outside a request (a job, a rake
task, a console, a seed) runs under the ambient zone and would answer UTC's day about a user in
Tokyo; `User#today` is `local_day(Time.current)` — one re-zoning, read from the OWNER. Models reach
it through their own owner (`Category#today`, `Budget#today`).

### The presentation seams (`app/presenters/`)

Three screens read one rule — Home, the Budget page, the categories card — and the figures they
print have to be the same sentence. These are the seams that make that true, and a fourth type is a
drift waiting to happen (`2026-09-05-two-shapes` §3–§5):

- **`ClaimLine`** → THE row type, hoisted out of `HomePresenter`. One `Data` per rule carrying the
  calculator's answers (`built_up`/`spent`/`accrued`/`target`, `over`, `overdue`, `paid`, `paid_on`,
  `next_due_on`) plus the predicates every screen asks (`#short?`, `#trouble?`, `#bar_state`,
  `#percent`, `#name`, `#stripe_type`). `BudgetPagePresenter::Rule` and
  `CategoryBudgetPresenter::Line` were the same members under other names, and they had already
  drifted; they are deleted.
- **`ClaimRows`** → the GROUPING. Built from one `ClaimLedger`, it answers `#blocks` (give-way
  order, grouped by category), `#lines_for`, `#give_way_order`, `#period_range`. It queries nothing:
  the calculators are the caller's ledger's and the grid is `User#period_containing`. Its class
  methods `.line_for` / `.period_range_for` build one row with no ledger at all, which is how the
  rule form's preview prices an UNSAVED rule.
- **`HomePresenter#runway`** → `Runway(progress, ticks, due_total, short)`. One tick per dated rule
  due inside the period, placed by the same `Progress#percent_at` that places today's marker; a
  tick's state is `ready` or `short` and never "accruing".
- **`BudgetPagePresenter#category_rows`** → every expense category, ruled ones in PRIORITY order
  (the key dragging writes) and rule-less ones by name, each carrying the blocks' own `ClaimLine`s.
  Home shows the same rows in GIVE-WAY order; both screens say which order they are in.
- **`SuggestionEngine#by_category`** → the suggestions grouped once per render, so a page with N
  category panels still runs the engine once. `#hidden_by_category` mirrors it.
- **`RulePreview`** → the rule form's card. ONE `ClaimCalculator` on the unsaved rule answers per
  period / periods until the date / already built up / what Home will show, so the form is never a
  second arithmetic. A new rule is born TODAY (`ClaimCalculator#rule_born_on`) and reads empty
  lanes; an edit reads the rule's real history.

No presenter formats money — `number_to_currency` is ActionView's, and the row vocabulary
(`HomeHelper#shape_words` / `#figure_words` / `#when_words`) is one set of helpers read by all three
screens.

### Searchable System (Custom DSL)

Models define searchable fields, controllers apply searches automatically. See `docs/searchable-system-reference.md` for complete documentation.

```ruby
# Model
class Entry < ApplicationRecord
  include ModelSearchable
  searchable :description, label: "Description"
  searchable :item, through: :item, column: :name, label: "Item"
  searchable :category, through: [:item, :category], column: :name, label: "Category"
end

# Controller
include Searchable
entries = apply_search(entries, { q: params[:q], field: params[:field] })
```

### DateContext Concern (`app/controllers/concerns/date_context.rb`)

Session-based month/year selection. Provides `selected_month`, `selected_year`, `selected_date` helpers.

### EntryType Value Object (`app/models/entry_type.rb`)

Centralizes type configuration (label, color, sign). Use `EntryType[:expense].color` instead of hardcoding.

## View Conventions

- Standardized page header: `render 'shared/page_header'` with title, breadcrumbs, search, actions
- Use `page_header` helper for cleaner syntax
- Tailwind with custom colors from `custom.css` (check available colors before using)
- Squared edges aesthetic (avoid `rounded-lg`, `rounded-xl`)

## Key Principles

### Fat Models, Skinny Controllers

Controllers should be 5-7 lines per action. Extract logic to models, services, or presenters.

- Controllers handle HTTP concerns only: params, session, redirects, renders
- Business logic belongs in models, service objects, form objects, or dedicated classes
- Question any controller action exceeding 10-15 lines of logic
- Look for conditionals in controllers that should be model methods
- Callbacks and validations belong in models, not controllers

### Leverage Existing Code

Before writing new methods, search exhaustively for existing functionality in models, Rails built-ins, and gems.

- **Did we reinvent the wheel?** Search the codebase for existing methods, concerns, or classes that could have been used or extended
- **Could this be a configuration change instead of new code?** Rails often has built-in ways to achieve things
- **Are there existing patterns in this codebase that weren't followed?** Look at similar features for established conventions
- **Did we extend existing abstractions or create competing ones?**

### RESTful Resources

Prefer standard CRUD actions. When tempted to add custom actions, consider if a new nested resource is more appropriate.

- Resources should map to standard CRUD actions: index, show, new, create, edit, update, destroy
- Custom actions are a code smell - consider if a new resource would be more appropriate
- Nested resources should reflect domain relationships
- Avoid verb-based routes; prefer noun-based resources

### Minimal Code

Every new line must be justified. Prefer extending existing methods over creating new ones.

- Don't add features, refactor code, or make "improvements" beyond what was asked
- A bug fix doesn't need surrounding code cleaned up
- A simple feature doesn't need extra configurability
- Don't add docstrings, comments, or type annotations to code you didn't change
- Only add comments where the logic isn't self-evident

### DRY (Don't Repeat Yourself)

- Extract repeated logic into concerns, modules, or base classes
- Use partials for repeated view code
- Create helper methods for repeated view logic
- Look for similar code patterns across the diff that could be unified
- Question any copy-pasted code blocks

### Convention Over Configuration

- Follow Rails naming conventions religiously (plural controllers, singular models, snake_case files)
- Use standard directory structures - don't create custom organizational schemes without strong justification
- Leverage Rails' built-in helpers, concerns, and patterns before creating custom solutions
- Respect RESTful routing conventions
- Use Rails' form helpers, not custom form building

### Simplicity-First Frontend

Prefer the simplest solution that works. Escalate complexity only when truly needed:

1. **Pure HTML first** - Use semantic HTML elements (`<details>/<summary>` for toggles, `<dialog>` for modals, etc.)
2. **CSS next** - Many interactions can be CSS-only (`:hover`, `:focus`, transitions)
3. **Turbo Frames/Streams** - For server-rendered partial updates without full page reloads
4. **Stimulus** - Only when client-side state or DOM manipulation is unavoidable

Never reach for Stimulus or JavaScript when HTML or CSS can solve the problem. The goal is maintainable, accessible, progressively-enhanced interfaces.

## Code Organization Guidelines

### File & Method Sizing

- **Are there walls of code?** Methods exceeding 15-20 lines need scrutiny
- **Are files appropriately sized?** Not too large (god objects) nor too fragmented (over-abstraction)
- **Is the purpose of each file/class/method immediately clear from its name and structure?**
- **Would a new developer understand this code without extensive context?**

### Rails-Specific Concerns

- Are scopes used appropriately in models?
- Are callbacks used judiciously and not hiding critical business logic?
- Is N+1 query potential addressed with includes/preload/eager_load?
- Are strong parameters properly configured?
- Are validations comprehensive and in the right place?
- Is the database schema reflected properly in migrations?
