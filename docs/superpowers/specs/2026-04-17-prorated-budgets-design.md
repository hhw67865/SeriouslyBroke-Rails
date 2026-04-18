# Prorated Budgets — Design Spec

**Date**: 2026-04-17
**Status**: Approved, ready for implementation plan

## Problem

Budgets today are lump-sum monthly caps: the user sets a total and tries not to exceed it by month-end. This works for one-time monthly expenses (rent, subscriptions) but is a poor signal for categories where spending happens continuously (groceries, gas, eating out). For those, the user wants to see whether they are on pace day-to-day — if it's April 15 and half the month is gone, am I half-way through my budget, or am I already 80% through it?

## Solution

Add an optional `prorated` boolean to `Budget`. When `true`, the budget is treated as accruing linearly across the month rather than as an upfront lump. This changes:

1. **Chart budget line**: ramps from $0 on day 1 to the full cap on the last day (instead of a flat line at the full cap).
2. **Progress bar / status color / percentage**: compares current spend against the prorated-to-today amount, not the full cap.
3. **"Over / left" text**: shows distance from pace, with "over pace" / "under pace" wording.

The full monthly cap remains visible in the breakdown (`$X / $Y_cap`) — the cap is the target, not hidden.

Proration applies only in the monthly dashboard view. YTD view continues to show flat/accumulating monthly-cap lines (proration is a within-the-month concept).

## Scope additions (discovered during design)

The `Budget#period` enum (`month` / `year`) is removed as part of this change. The project has settled on monthly budgets, and the enum complicates every calculation path. Existing yearly-period budgets are data-migrated to their monthly equivalent (`amount / 12`).

## Non-goals

- No projection lines or extrapolation numbers. The prorated line itself is the "are you on pace" signal.
- No prorated behavior in YTD view.
- No global dashboard toggle. Proration is a per-budget flag.
- No migration path for un-dividing yearly budgets (one-way simplification).

---

## Data model

### Migration 1 — remove period, convert yearly amounts

```ruby
class RemovePeriodFromBudgets < ActiveRecord::Migration[8.0]
  def up
    execute "UPDATE budgets SET amount = ROUND(amount / 12.0, 2) WHERE period = 1"
    remove_column :budgets, :period
  end

  def down
    add_column :budgets, :period, :integer, default: 0, null: false
  end
end
```

The `down` recreates the column with default 0 (`:month`). Previously-yearly rows have already had their amounts divided, so they are now correctly monthly. The column is lossy on recovery but the amounts remain meaningful.

### Migration 2 — add prorated

```ruby
class AddProratedToBudgets < ActiveRecord::Migration[8.0]
  def change
    add_column :budgets, :prorated, :boolean, default: false, null: false
  end
end
```

### `app/models/budget.rb` changes

- Remove `enum :period, { month: 0, year: 1 }`.
- Remove `:period` from `validates ... presence: true`.
- No new validations (`prorated` is a boolean with a non-null default).

### `BudgetsController#budget_params`

```ruby
params.expect(budget: [:amount, :category_id, :prorated])
```

(`:period` removed, `:prorated` added.)

---

## `CategoryCalculator` refactor

Three public methods govern the budget display: one for the cap, one for the pace, one for the chart curve.

```ruby
# Full period cap — the target the user set.
#   Monthly view, $300 budget → 300
#   YTD view, $300/mo budget, April → 300 * 4 = 1200
def effective_budget
  return nil unless monthly_budget_rate
  period == :ytd ? monthly_budget_rate * months_in_range(date_range) : monthly_budget_rate
end

# Pace reference for %, status color, over/under-pace text.
#   Non-prorated: returns effective_budget (no behavior change).
#   Prorated + monthly view: returns amount * clamped_day / days_in_month.
#   Prorated + YTD: returns effective_budget.
def budget_pace(today: Date.current)
  return nil unless monthly_budget_rate
  return effective_budget unless prorated_active?
  ramp_value(pace_day(today), @date.end_of_month.day)
end

# Hash { Date => cumulative_target_by_end_of_day } for the chart.
#   Monthly view, flat: every day => effective_budget.
#   Monthly view, prorated: day N => amount * N / days_in_month.
#   YTD view: existing monthly-accumulating behavior, unchanged.
def budget_curve
  return {} unless monthly_budget_rate
  period == :ytd ? ytd_budget_curve : monthly_budget_curve
end
```

### Private helpers

```ruby
def prorated_active?
  period == :monthly && category.budget&.prorated?
end

def pace_day(today)
  return 0 if today < @date.beginning_of_month
  return @date.end_of_month.day if today > @date.end_of_month
  today.day
end

def ramp_value(day, days_in_month)
  (monthly_budget_rate * day / days_in_month.to_f).round(2)
end

def monthly_budget_curve
  days = @date.end_of_month.day
  return @date.all_month.index_with { effective_budget } unless prorated_active?
  @date.all_month.each_with_index.each_with_object({}) do |(d, i), h|
    h[d] = ramp_value(i + 1, days)
  end
end

def ytd_budget_curve
  current = date_range.begin.beginning_of_month
  acc = 0
  {}.tap do |h|
    while current <= date_range.end
      acc += monthly_budget_rate
      h[current] = acc
      current = current.next_month
    end
  end
end
```

### Other method changes

- `monthly_budget_rate` collapses to `return nil unless category.expense? && category.budget&.amount; category.budget.amount`. The year-branch is deleted.
- `yearly_budget?` is deleted (no callers after cleanup).
- `budget_percentage` divides by `budget_pace` instead of `effective_budget`:

```ruby
def budget_percentage
  return 0 unless category.expense? && budget_pace.to_f.positive?
  (total_amount / budget_pace * 100).round
end
```

- Constructor stores `@date` (not just `@date_range`):

```ruby
def initialize(category, date = Date.current, period: :monthly)
  @category = category
  @date = date
  @period = period
  @date_range = compute_date_range(date)
end
```

### Pace clamping — invariants

The `pace_day` helper unifies past / current / future selected months into one path:

| Selected month | Relation to `today` | `pace_day` returns | `budget_pace` returns |
|---|---|---|---|
| Past | `today > end_of_month` | `days_in_month` | `effective_budget` (full cap) |
| Current | within month | `today.day` | ramp-to-today |
| Future | `today < beginning_of_month` | `0` | `0` |

For past months, `budget_pace == effective_budget`, so status/%/text are identical to non-prorated (correct — the month is over, compare to the final target). For future months, `budget_pace == 0`, so any spend shows as over pace (unusual but graceful — user is spending against a budget that hasn't started accruing).

---

## Dashboard aggregation

### `Dashboard::ExpensesPresenter#budget_line_data`

```ruby
def budget_line_data
  return {} if total_budget.zero?

  if @parent.ytd?
    budget_line_series(monthly_budget_rate, period_range, group: :month)
      .transform_keys { |d| d.strftime("%b %Y") }
  else
    sum_curves(@parent.tracked_budgetable_expense_categories.map { |cat|
      cat.calculator(@parent.date).budget_curve
    })
  end
end

def sum_curves(curves)
  curves.reduce({}) do |acc, curve|
    curve.each { |date, val| acc[date] = (acc[date] || 0) + val }
    acc
  end
end
```

Each category's curve contributes to each day's total independently — flat categories contribute their cap every day, prorated contribute a daily ramp value. The blended line starts at the sum of all flat caps and ramps up by the sum of all prorated portions, ending at the total of all caps on the last day of the month.

`sum_curves` is a private helper on the presenter.

### Stat card "Monthly Budget"

Unchanged. Continues to show `total_budget` (sum of full monthly caps). This is the target, not the pace.

### `DashboardPresenter#enrich_with_budget`

```ruby
def enrich_with_budget(entry, category, calc)
  return unless category.budgetable? && calc.effective_budget.to_f.positive?

  entry[:budget] = calc.effective_budget
  entry[:prorated] = category.budget.prorated?
  entry[:budget_percentage] = calc.budget_percentage
  entry[:over_budget] = calc.total_amount > calc.budget_pace
  entry[:budget_diff] = (calc.total_amount - calc.budget_pace).abs
end
```

- `:budget` remains the monthly cap, for `/Y` display.
- `:prorated` flags the view wording.
- `over_budget` and `budget_diff` both compare to `budget_pace`.

### N+1 check

`tracked_budgetable_expense_categories` already eager-loads `:budget, :savings_pool, items: :entries` (dashboard_presenter.rb:160). `budget_curve` only reads already-loaded data. No new queries.

---

## Views

### `app/views/budgets/_form.html.erb`

- Delete the "Budget Period" select block (lines 53-63).
- Add after the Amount field:

```erb
<div>
  <%= f.input :prorated,
      as: :boolean,
      label: "Prorate daily",
      wrapper_html: { class: "flex items-start gap-3" },
      hint: "Spread the budget evenly across the month so you can see if you're on pace day-to-day. Turn off for expenses that happen in one-time chunks (like rent or subscriptions)." %>
</div>
```

### `app/views/categories/_partials/show/_budget_card.html.erb`

- Delete the "Period" row (line 14).
- Add a "Prorated" row: `<%= category.budget.prorated? ? "Yes — tracks daily pace" : "No — flat monthly cap" %>`.

### `app/views/categories/_partials/show/_summary_card.html.erb`

- Delete the `if calc.yearly_budget?` subtext block (lines 48-52).
- Replace the four-way chart-data branch (lines 81-96) with:

```erb
<% chart_data = [{ name: "Spending", data: calculate_running_total(
     current_period == :ytd ?
       category.entries.group_by_month(:date, range: calc.date_range).sum(:amount) :
       category.entries.group_by_day(:date, range: calc.date_range).sum(:amount)
   ) }] %>
<% chart_data << { name: "Budget", data: calc.budget_curve } if calc.budget_curve.any? %>
```

`budget_curve` subsumes the old `monthly_budget_rate` checks and the `budget_line_series` helper calls.

### `app/views/dashboard/_expenses_tab.html.erb`

Breakdown text (lines 75-79) becomes:

```erb
<% if cat[:budget_percentage] %>
  <p class="text-xs font-medium <%= cat[:over_budget] ? "text-terracotta" : "text-gray-500" %>">
    <% if cat[:prorated] %>
      <%= cat[:over_budget] ? "+#{number_to_currency(cat[:budget_diff])} over pace" : "#{number_to_currency(cat[:budget_diff])} under pace" %>
    <% else %>
      <%= cat[:over_budget] ? "+#{number_to_currency(cat[:budget_diff])} over" : "#{number_to_currency(cat[:budget_diff])} left" %>
    <% end %>
  </p>
<% end %>
```

### Cache key

Bump `:expenses_v7` → `:expenses_v8` on `_expenses_tab.html.erb:2`. The breakdown shape changed (added `:prorated`) and wording changed — cached fragments must invalidate.

---

## Testing plan

### Factory — `spec/factories/budgets.rb`
- Remove `period { :month }` default, `:monthly` trait, `:yearly` trait.
- Add `trait(:prorated) { prorated { true } }`.

### Model spec — `spec/models/budget_spec.rb`
- Remove period presence test and enum definition test.
- Add: `prorated` defaults to `false`; accepts `true`; is non-null.

### Calculator spec — `spec/services/category_calculator_spec.rb` (create or extend)

Coverage matrix:

| Scenario | Method | Expected |
|---|---|---|
| Non-prorated, monthly, $300 | `effective_budget` | 300 |
| Non-prorated, YTD April, $300 | `effective_budget` | 1200 |
| Non-prorated, any | `budget_pace` | == `effective_budget` |
| Prorated, monthly, current month, today=April 15, $300 | `budget_pace(today: 2026-04-15)` | 150 |
| Prorated, monthly, past month (viewing March, today April) | `budget_pace(today: 2026-04-17)` | 300 |
| Prorated, monthly, future month (viewing May, today April) | `budget_pace(today: 2026-04-17)` | 0 |
| Prorated, YTD | `budget_pace` | == `effective_budget` |
| Non-prorated, monthly, $300 | `budget_curve` | 30 entries all = 300 |
| Prorated, monthly, 30-day month, $300 | `budget_curve` | day 1 = 10, day 15 = 150, day 30 = 300 |
| YTD, any | `budget_curve` | monthly-accumulating keys (unchanged from current behavior) |
| Prorated, current month, spent $200, today day 15 of 30 | `budget_percentage` | 133 (= 200 / 150 × 100) |

### System spec — `spec/system/dashboard/index/expenses_tab_spec.rb`
- Scenario: one prorated $300 budget + one flat $200 budget. `travel_to` April 15 of a 30-day month.
  - Prorated category spent $200 → row shows `$200 / $300` and `+$50 over pace` (pace = $150).
  - Flat category spent $50 → row shows `$50 / $200` and `$150 left`.
  - "Monthly Budget" stat = $500 (unchanged behavior).
  - Budget chart line: day 1 = $210, day 15 = $350, day 30 = $500.

### System spec — `spec/system/categories/show/summary_card_spec.rb` + `spec/system/categories/show/budget_spec.rb`
- `summary_card_spec.rb`: Prorated category on day 15 of 30 with $300 budget, $200 spent — progress bar shows 133% color (danger), status text "Budget exceeded", chart includes a ramp-shaped "Budget" series rising from $10 to $300.
- `budget_spec.rb`: Creating/editing a budget persists the `prorated` flag correctly.

### System spec — `spec/system/budgets/form_spec.rb`
- Remove the yearly-period test (line 160).
- Add: checking "Prorate daily" persists `prorated: true`; unchecking persists `false`.
- Update any other tests that reference the removed period select.

### Date injection
`budget_pace(today:)` accepts a kwarg so unit tests control "today" deterministically. System specs use `travel_to` as usual.

---

## Implementation order

Each step leaves the app in a working state.

1. **Migrations** — remove period (with data migration), add prorated.
2. **Calculator refactor** — store `@date`, simplify `monthly_budget_rate`, delete `yearly_budget?`, add `budget_pace` / `budget_curve` / helpers, update `budget_percentage`.
3. **Dashboard presenter** — `sum_curves` aggregation, enrich with `:prorated` + pace-based diff/over_budget.
4. **Views** — form, budget card, summary card, expenses tab wording, cache key bump.
5. **Controller** — permit `:prorated`, remove `:period`.
6. **Tests** — factory, model, calculator, dashboard, category show, form.
7. **Visual check + code review** — run tailwindcss:build, start server, verify flows at desktop viewport, run rails-code-reviewer agent.

## Files touched

| File | Change |
|---|---|
| `db/migrate/<ts>_remove_period_from_budgets.rb` | New |
| `db/migrate/<ts>_add_prorated_to_budgets.rb` | New |
| `app/models/budget.rb` | Remove period enum + validation |
| `app/controllers/budgets_controller.rb` | Update permitted params |
| `app/services/category_calculator.rb` | Major: add curve/pace, simplify rate, delete yearly? |
| `app/presenters/dashboard_presenter.rb` | `enrich_with_budget` uses pace, adds `:prorated` |
| `app/presenters/dashboard/expenses_presenter.rb` | `budget_line_data` uses `sum_curves` |
| `app/views/budgets/_form.html.erb` | Swap period select for prorated checkbox |
| `app/views/categories/_partials/show/_budget_card.html.erb` | Swap period row for prorated row |
| `app/views/categories/_partials/show/_summary_card.html.erb` | Delete yearly subtext, collapse chart branch |
| `app/views/dashboard/_expenses_tab.html.erb` | Wording + cache key bump |
| `spec/factories/budgets.rb` | Remove period, add prorated trait |
| `spec/models/budget_spec.rb` | Remove period tests, add prorated test |
| `spec/services/category_calculator_spec.rb` | New or extended — matrix coverage |
| `spec/system/dashboard/index/expenses_tab_spec.rb` | Add prorated scenario |
| `spec/system/categories/show/summary_card_spec.rb` | Add prorated ramp + pace-bar assertion |
| `spec/system/categories/show/budget_spec.rb` | Add prorated persistence assertion |
| `spec/system/budgets/form_spec.rb` | Remove yearly test, add prorated checkbox test |
