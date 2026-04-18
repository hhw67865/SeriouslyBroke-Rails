# Prorated Budgets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional `prorated` boolean to `Budget` that makes the budget accrue linearly across the month (chart ramp + pace-based status), and drop the now-unused `Budget#period` enum.

**Architecture:** Single source of truth stays on `CategoryCalculator`. Two new methods — `budget_curve` (hash of `{ Date => cumulative target }` for charts) and `budget_pace(today:)` (scalar for % / status color / "over pace" text). A `sum_curves` helper on `Dashboard::ExpensesPresenter` blends per-category curves into one dashboard line. Proration applies only in monthly view; YTD is untouched. Period enum is removed and yearly amounts are data-migrated to `amount / 12`.

**Tech Stack:** Rails 8, PostgreSQL, RSpec, FactoryBot, Capybara, Chartkick, simple_form, Tailwind.

**Spec:** `docs/superpowers/specs/2026-04-17-prorated-budgets-design.md`

**Execution rules:**
- Run each spec file one at a time (per `CLAUDE.md`): `bundle exec rspec path/to/spec.rb`
- Use single-line commit messages; no `Co-Authored-By` footer
- Period removal is deferred to Task 9 so every prior commit leaves CI green

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `db/migrate/<ts>_add_prorated_to_budgets.rb` | new | Additive boolean column, default false |
| `db/migrate/<ts>_remove_period_from_budgets.rb` | new | Data-migrate yearly → monthly, drop column |
| `spec/factories/budgets.rb` | modify | Remove period defaults/traits, add `:prorated` trait |
| `app/models/budget.rb` | modify | Remove `enum :period` + presence validation |
| `app/controllers/budgets_controller.rb` | modify | Permit `:prorated`, drop `:period` |
| `app/services/category_calculator.rb` | modify | Store `@date`, simplify `monthly_budget_rate`, delete `yearly_budget?`, add `budget_curve` / `budget_pace` + helpers, update `budget_percentage` |
| `app/presenters/dashboard_presenter.rb` | modify | `enrich_with_budget` uses `budget_pace`, adds `:prorated` |
| `app/presenters/dashboard/expenses_presenter.rb` | modify | `budget_line_data` monthly branch uses `sum_curves` |
| `app/views/budgets/_form.html.erb` | modify | Swap period select for prorated checkbox |
| `app/views/categories/_partials/show/_budget_card.html.erb` | modify | Swap period row for prorated row |
| `app/views/categories/_partials/show/_summary_card.html.erb` | modify | Delete yearly subtext, replace chart-data branch with `calc.budget_curve` |
| `app/views/dashboard/_expenses_tab.html.erb` | modify | "Over pace" / "under pace" wording, cache key bump |
| `spec/models/budget_spec.rb` | modify | Drop period tests, add prorated default test |
| `spec/services/category_calculator_spec.rb` | new | Matrix coverage of pace/curve/percentage |
| `spec/system/dashboard/index/expenses_tab_spec.rb` | modify | Add prorated scenario |
| `spec/system/categories/show/summary_card_spec.rb` | modify | Add prorated ramp + pace-bar assertions |
| `spec/system/categories/show/budget_spec.rb` | modify | Add prorated persistence assertion |
| `spec/system/budgets/form_spec.rb` | modify | Replace yearly test with prorated checkbox test |

---

## Task 1: Add `prorated` column (additive migration)

**Files:**
- Create: `db/migrate/<timestamp>_add_prorated_to_budgets.rb`

- [ ] **Step 1: Generate migration**

Run:
```bash
bin/rails generate migration AddProratedToBudgets prorated:boolean
```

- [ ] **Step 2: Edit migration to set default + null constraint**

Replace the generated migration body with:

```ruby
class AddProratedToBudgets < ActiveRecord::Migration[8.0]
  def change
    add_column :budgets, :prorated, :boolean, default: false, null: false
  end
end
```

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: `add_column(:budgets, :prorated, :boolean, {default: false, null: false})` succeeds, `db/schema.rb` updates.

- [ ] **Step 4: Verify schema**

Run: `bin/rails runner "puts Budget.columns_hash['prorated'].inspect"`
Expected: output contains `type: :boolean, default: "false", null: false`.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/*_add_prorated_to_budgets.rb db/schema.rb
git commit -m "db: add prorated boolean to budgets"
```

---

## Task 2: Add `:prorated` factory trait

**Files:**
- Modify: `spec/factories/budgets.rb`

- [ ] **Step 1: Add trait to factory**

Edit `spec/factories/budgets.rb` — add a `:prorated` trait below the existing traits. After edit the file should read:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :budget do
    amount { Faker::Number.decimal(l_digits: 3, r_digits: 2) }
    period { :month }
    association :category, factory: [:category, :expense]

    trait :monthly do
      period { :month }
    end

    trait :yearly do
      period { :year }
    end

    trait :prorated do
      prorated { true }
    end
  end
end
```

(`:monthly`, `:yearly`, and the `period { :month }` default stay for now — removed in Task 9.)

- [ ] **Step 2: Verify factory loads**

Run: `bundle exec rspec spec/models/budget_spec.rb`
Expected: existing model specs still pass.

- [ ] **Step 3: Commit**

```bash
git add spec/factories/budgets.rb
git commit -m "test: add :prorated budget factory trait"
```

---

## Task 3: `CategoryCalculator#budget_curve` (TDD)

**Files:**
- Create: `spec/services/category_calculator_spec.rb`
- Modify: `app/services/category_calculator.rb`

- [ ] **Step 1: Write failing calculator spec (non-prorated flat curve + prorated ramp + YTD)**

Create `spec/services/category_calculator_spec.rb` with:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategoryCalculator do
  let(:user) { create(:user) }
  let(:category) { create(:category, :expense, user: user, name: "Groceries") }
  let(:april1) { Date.new(2026, 4, 1) }

  describe "#budget_curve" do
    context "monthly view with a flat (non-prorated) $300 budget" do
      before { create(:budget, category: category, amount: 300) }

      it "returns every day of April mapping to the full $300 cap" do
        curve = described_class.new(category.reload, april1, period: :monthly).budget_curve
        expect(curve.size).to eq(30)
        expect(curve[april1]).to eq(300)
        expect(curve[Date.new(2026, 4, 15)]).to eq(300)
        expect(curve[Date.new(2026, 4, 30)]).to eq(300)
      end
    end

    context "monthly view with a prorated $300 budget" do
      before { create(:budget, category: category, amount: 300, prorated: true) }

      it "ramps linearly from day 1 to day 30" do
        curve = described_class.new(category.reload, april1, period: :monthly).budget_curve
        expect(curve.size).to eq(30)
        expect(curve[april1]).to eq(10.0)
        expect(curve[Date.new(2026, 4, 15)]).to eq(150.0)
        expect(curve[Date.new(2026, 4, 30)]).to eq(300.0)
      end
    end

    context "YTD view (proration ignored)" do
      before { create(:budget, category: category, amount: 300, prorated: true) }

      it "returns an accumulating monthly series regardless of prorated flag" do
        curve = described_class.new(category.reload, april1, period: :ytd).budget_curve
        # Jan, Feb, Mar, Apr
        expect(curve.size).to eq(4)
        expect(curve[Date.new(2026, 1, 1)]).to eq(300)
        expect(curve[Date.new(2026, 4, 1)]).to eq(1200)
      end
    end

    context "no budget" do
      it "returns empty hash" do
        expect(described_class.new(category, april1).budget_curve).to eq({})
      end
    end
  end
end
```

- [ ] **Step 2: Run spec, verify failure**

Run: `bundle exec rspec spec/services/category_calculator_spec.rb`
Expected: failures — `NoMethodError: undefined method 'budget_curve'` (or similar, since method doesn't exist yet).

- [ ] **Step 3: Store `@date` in constructor**

Edit `app/services/category_calculator.rb`. Change the `attr_reader` line and `initialize`:

```ruby
  attr_reader :category, :date, :date_range, :period

  def initialize(category, date = Date.current, period: :monthly)
    @category = category
    @date = date
    @period = period
    @date_range = compute_date_range(date)
  end
```

- [ ] **Step 4: Add `budget_curve` public method + private helpers**

Add after `effective_budget` method (around line 41):

```ruby
  def budget_curve
    return {} unless monthly_budget_rate
    period == :ytd ? ytd_budget_curve : monthly_budget_curve
  end
```

Then in the `private` section, add:

```ruby
  def prorated_active?
    period == :monthly && category.budget&.prorated?
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

- [ ] **Step 5: Run spec, verify passes**

Run: `bundle exec rspec spec/services/category_calculator_spec.rb`
Expected: all 4 examples pass.

- [ ] **Step 6: Commit**

```bash
git add spec/services/category_calculator_spec.rb app/services/category_calculator.rb
git commit -m "calculator: add budget_curve for chart rendering"
```

---

## Task 4: `CategoryCalculator#budget_pace` + update `budget_percentage` (TDD)

**Files:**
- Modify: `spec/services/category_calculator_spec.rb`
- Modify: `app/services/category_calculator.rb`

- [ ] **Step 1: Write failing pace specs (full matrix)**

Append the following describe blocks to `spec/services/category_calculator_spec.rb` (inside the top-level `RSpec.describe CategoryCalculator do ... end`):

```ruby
  describe "#budget_pace" do
    let(:april15) { Date.new(2026, 4, 15) }
    let(:march15) { Date.new(2026, 3, 15) }
    let(:may15) { Date.new(2026, 5, 15) }

    context "non-prorated budget" do
      before { create(:budget, category: category, amount: 300) }

      it "returns effective_budget (same as cap) in monthly view" do
        calc = described_class.new(category.reload, april1, period: :monthly)
        expect(calc.budget_pace(today: april15)).to eq(calc.effective_budget)
        expect(calc.budget_pace(today: april15)).to eq(300)
      end

      it "returns effective_budget in YTD view" do
        calc = described_class.new(category.reload, april1, period: :ytd)
        expect(calc.budget_pace(today: april15)).to eq(calc.effective_budget)
        expect(calc.budget_pace(today: april15)).to eq(1200)
      end
    end

    context "prorated budget, monthly view" do
      before { create(:budget, category: category, amount: 300, prorated: true) }

      it "returns ramp-to-today when viewing the current month" do
        calc = described_class.new(category.reload, april1, period: :monthly)
        expect(calc.budget_pace(today: april15)).to eq(150.0) # 300 * 15 / 30
      end

      it "returns the full cap when viewing a past month" do
        march1 = Date.new(2026, 3, 1)
        calc = described_class.new(category.reload, march1, period: :monthly)
        # "today" is April 15 — past the end of March, so pace fully accrued
        expect(calc.budget_pace(today: april15)).to eq(300)
      end

      it "returns 0 when viewing a future month" do
        may1 = Date.new(2026, 5, 1)
        calc = described_class.new(category.reload, may1, period: :monthly)
        # "today" is April 15 — before May starts, so pace hasn't accrued
        expect(calc.budget_pace(today: april15)).to eq(0)
      end
    end

    context "prorated budget, YTD view (proration ignored)" do
      before { create(:budget, category: category, amount: 300, prorated: true) }

      it "returns effective_budget" do
        calc = described_class.new(category.reload, april1, period: :ytd)
        expect(calc.budget_pace(today: april15)).to eq(calc.effective_budget)
      end
    end

    context "no budget" do
      it "returns nil" do
        calc = described_class.new(category, april1)
        expect(calc.budget_pace(today: april15)).to be_nil
      end
    end
  end

  describe "#budget_percentage with prorated budget" do
    before { create(:budget, category: category, amount: 300, prorated: true) }

    it "divides spent by pace (not cap)" do
      item = create(:item, category: category)
      create(:entry, item: item, amount: 200, date: Date.new(2026, 4, 10))
      calc = described_class.new(category.reload, april1, period: :monthly)

      # pace on day 15 = 300 * 15 / 30 = 150. spent = 200. percentage = 200/150 * 100 = 133.
      allow(Date).to receive(:current).and_return(Date.new(2026, 4, 15))
      expect(calc.budget_percentage).to eq(133)
    end
  end
```

- [ ] **Step 2: Run spec, verify failures**

Run: `bundle exec rspec spec/services/category_calculator_spec.rb`
Expected: new examples fail (`NoMethodError: undefined method 'budget_pace'`); existing 4 examples still pass.

- [ ] **Step 3: Add `budget_pace` method + `pace_day` helper**

Edit `app/services/category_calculator.rb`. Add after `effective_budget`:

```ruby
  def budget_pace(today: Date.current)
    return nil unless monthly_budget_rate
    return effective_budget unless prorated_active?
    ramp_value(pace_day(today), @date.end_of_month.day)
  end
```

Add `pace_day` to the private section (near `ramp_value`):

```ruby
  def pace_day(today)
    return 0 if today < @date.beginning_of_month
    return @date.end_of_month.day if today > @date.end_of_month
    today.day
  end
```

- [ ] **Step 4: Update `budget_percentage` to use `budget_pace`**

Replace the existing `budget_percentage` method:

```ruby
  def budget_percentage
    return 0 unless category.expense? && budget_pace.to_f.positive?
    (total_amount / budget_pace * 100).round
  end
```

- [ ] **Step 5: Run calculator spec, verify all pass**

Run: `bundle exec rspec spec/services/category_calculator_spec.rb`
Expected: all examples pass (curve + pace + percentage).

- [ ] **Step 6: Run downstream specs that exercise `budget_percentage` via category show**

Run: `bundle exec rspec spec/system/categories/show/summary_card_spec.rb`
Expected: passes — non-prorated behavior unchanged since pace == effective_budget for non-prorated budgets.

- [ ] **Step 7: Commit**

```bash
git add spec/services/category_calculator_spec.rb app/services/category_calculator.rb
git commit -m "calculator: add budget_pace and wire into budget_percentage"
```

---

## Task 5: Dashboard presenter aggregation

**Files:**
- Modify: `app/presenters/dashboard_presenter.rb`
- Modify: `app/presenters/dashboard/expenses_presenter.rb`
- Modify: `spec/system/dashboard/index/expenses_tab_spec.rb`

- [ ] **Step 1: Write failing dashboard system spec for prorated scenario**

Append to `spec/system/dashboard/index/expenses_tab_spec.rb` (inside the top-level describe block, before the final `end`):

```ruby
  describe "prorated budget scenario", :aggregate_failures do
    let(:april15) { Date.new(2026, 4, 15) }
    let!(:groceries) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:groceries_item) { create(:item, category: groceries, name: "Weekly Shopping") }
    let!(:rent) { create(:category, :expense, user: user, name: "Rent") }
    let!(:rent_item) { create(:item, category: rent, name: "Monthly Rent") }

    before do
      create(:budget, category: groceries, amount: 300, prorated: true)
      create(:budget, category: rent, amount: 200) # not prorated
      create(:entry, item: groceries_item, amount: 200, date: Date.new(2026, 4, 10))
      create(:entry, item: rent_item, amount: 50, date: Date.new(2026, 4, 1))
      travel_to april15
      visit root_path(tab: "expenses")
    end

    after { travel_back }

    it "shows prorated row with over-pace text" do
      # Groceries pace on day 15 = 300 * 15 / 30 = 150. Spent $200. Over pace by $50.
      within(".space-y-3") do
        expect(page).to have_content("Groceries")
        expect(page).to have_content("$200.00")
        expect(page).to have_content("$300.00")
        expect(page).to have_content("+$50.00 over pace")
      end
    end

    it "shows flat (non-prorated) row with normal 'left' text" do
      within(".space-y-3") do
        expect(page).to have_content("Rent")
        expect(page).to have_content("$150.00 left")
      end
    end

    it "keeps Monthly Budget stat as full sum of caps" do
      within_stat_card("Monthly Budget") { expect(page).to have_content("$500.00") }
    end
  end
```

- [ ] **Step 2: Run the spec, verify failure**

Run: `bundle exec rspec spec/system/dashboard/index/expenses_tab_spec.rb`
Expected: the new "prorated budget scenario" group fails (no "over pace" text yet; row shows the default "over" wording or misses the prorated case).

- [ ] **Step 3: Update `enrich_with_budget` to use `budget_pace`**

Edit `app/presenters/dashboard_presenter.rb`. Replace the `enrich_with_budget` private method:

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

- [ ] **Step 4: Add `sum_curves` and update `budget_line_data` in expenses presenter**

Edit `app/presenters/dashboard/expenses_presenter.rb`. Replace the `budget_line_data` method:

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
```

Add at the bottom of the private section (before the final `end` of the class):

```ruby
    def sum_curves(curves)
      curves.reduce({}) do |acc, curve|
        curve.each { |date, val| acc[date] = (acc[date] || 0) + val }
        acc
      end
    end
```

(Note: the view layer in Task 6 will render the "over pace" wording using `entry[:prorated]`. The system spec from Step 1 will still fail on that assertion until Task 6 completes — we'll rerun after Task 6.)

- [ ] **Step 5: Run dashboard spec; only the stat/row-structure assertions should pass now**

Run: `bundle exec rspec spec/system/dashboard/index/expenses_tab_spec.rb`
Expected: the Monthly Budget stat + "$200.00"/"$300.00" row content assertions pass. The "+$50.00 over pace" assertion still fails (view wording not yet updated).

- [ ] **Step 6: Commit**

```bash
git add app/presenters/dashboard_presenter.rb app/presenters/dashboard/expenses_presenter.rb spec/system/dashboard/index/expenses_tab_spec.rb
git commit -m "dashboard: sum per-category budget curves and expose prorated in breakdown entries"
```

---

## Task 6: Dashboard expenses tab view — wording + cache key

**Files:**
- Modify: `app/views/dashboard/_expenses_tab.html.erb`

- [ ] **Step 1: Bump cache key**

Edit line 2 of `app/views/dashboard/_expenses_tab.html.erb`. Change:

```erb
<% cache [current_user, selected_date, current_period, show_total, :expenses_v7] do %>
```

to:

```erb
<% cache [current_user, selected_date, current_period, show_total, :expenses_v8] do %>
```

- [ ] **Step 2: Replace breakdown wording block**

Locate the block at lines 75-79 of the same file:

```erb
<% if cat[:budget_percentage] %>
  <p class="text-xs font-medium <%= cat[:over_budget] ? "text-terracotta" : "text-gray-500" %>">
    <%= cat[:over_budget] ? "+#{number_to_currency(cat[:budget_diff])} over" : "#{number_to_currency(cat[:budget_diff])} left" %>
  </p>
<% end %>
```

Replace with:

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

- [ ] **Step 3: Run dashboard spec, verify all prorated scenario assertions pass**

Run: `bundle exec rspec spec/system/dashboard/index/expenses_tab_spec.rb`
Expected: full spec file passes, including "+$50.00 over pace".

- [ ] **Step 4: Commit**

```bash
git add app/views/dashboard/_expenses_tab.html.erb
git commit -m "dashboard view: over-pace wording for prorated budget rows"
```

---

## Task 7: Category show — collapse chart branch + add prorated row

**Files:**
- Modify: `app/views/categories/_partials/show/_summary_card.html.erb`
- Modify: `app/views/categories/_partials/show/_budget_card.html.erb`
- Modify: `spec/system/categories/show/summary_card_spec.rb`

- [ ] **Step 1: Write failing summary_card spec assertions for prorated ramp + pace bar**

Append a new `describe` group to `spec/system/categories/show/summary_card_spec.rb` (use the `system-test-writer` skill's conventions — the pattern used by other describe blocks in this file).

Add (inside the top-level describe, before the final `end`):

```ruby
  describe "prorated budget summary", :aggregate_failures do
    let(:april15) { Date.new(2026, 4, 15) }
    let!(:groceries) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:groceries_item) { create(:item, category: groceries, name: "Weekly Shopping") }

    before do
      create(:budget, category: groceries, amount: 300, prorated: true)
      create(:entry, item: groceries_item, amount: 200, date: Date.new(2026, 4, 10))
      travel_to april15
      visit category_path(groceries)
    end

    after { travel_back }

    it "shows pace-based percentage and exceeded status" do
      # Day 15 of 30. Pace = $150. Spent = $200. Percentage = 133%. Status = exceeded.
      expect(page).to have_content("133% used")
      expect(page).to have_content("Budget exceeded")
    end

    it "shows $ spent / $ full-cap in the header" do
      expect(page).to have_content("$200.00")
      expect(page).to have_content("$300.00")
    end
  end
```

(If the existing spec doesn't already define `user`/`sign_in`, follow the pattern in `spec/system/categories/show/summary_card_spec.rb` — reuse its outer `let!(:user)` and `before { sign_in }` blocks.)

- [ ] **Step 2: Run spec, verify failure**

Run: `bundle exec rspec spec/system/categories/show/summary_card_spec.rb`
Expected: new examples fail (percentage shows 67% from the current cap-based calculation, or "Well under budget" status).

Note: the calculator change from Task 4 already made `budget_percentage` pace-based — if you're seeing 133%, this test may pass without the view change. Still run it to confirm state.

- [ ] **Step 3: Delete yearly subtext block from summary_card**

Edit `app/views/categories/_partials/show/_summary_card.html.erb`. Locate lines 48-52:

```erb
<% if calc.yearly_budget? %>
  <p class="text-xs text-gray-400 mb-2">
    <%= number_to_currency(calc.monthly_budget_rate) %>/mo from <%= number_to_currency(category.budget.amount) %>/yr
  </p>
<% end %>
```

Delete this block entirely. (The method `yearly_budget?` still exists — it'll be removed in Task 9. For now we just stop calling it.)

- [ ] **Step 4: Collapse chart-data branch**

In the same file, locate the block around lines 80-98 (the `<% if current_period == :ytd ... else ... end %>` block building `chart_data`). Replace the entire ERB scriptlet with:

```erb
<%
  spending_data = if current_period == :ytd
                    calculate_running_total(category.entries.group_by_month(:date, range: calc.date_range).sum(:amount))
                  else
                    calculate_running_total(category.entries.group_by_day(:date, range: calc.date_range).sum(:amount))
                  end
  chart_data = [{ name: "Spending", data: spending_data }]
  chart_data << { name: "Budget", data: calc.budget_curve } if calc.budget_curve.any?
%>
<%= line_chart chart_data, curve: false, points: false, colors: ["#3b82f6", "#ef4444"], prefix: "$ " %>
```

(The existing file already has this `line_chart` call inside the if/else branches. After this change, one call at the end does the job.)

- [ ] **Step 5: Run summary_card spec, verify passing**

Run: `bundle exec rspec spec/system/categories/show/summary_card_spec.rb`
Expected: all examples pass.

- [ ] **Step 6: Swap Period row for Prorated row in _budget_card.html.erb**

Edit `app/views/categories/_partials/show/_budget_card.html.erb`. Replace the Period row (lines 12-15):

```erb
<div class="py-3 flex justify-between">
  <dt class="text-sm font-medium text-gray-500">Period</dt>
  <dd class="text-sm text-gray-900"><%= category.budget.period.capitalize %></dd>
</div>
```

with:

```erb
<div class="py-3 flex justify-between">
  <dt class="text-sm font-medium text-gray-500">Prorated</dt>
  <dd class="text-sm text-gray-900">
    <%= category.budget.prorated? ? "Yes — tracks daily pace" : "No — flat monthly cap" %>
  </dd>
</div>
```

- [ ] **Step 7: Run the category budget_spec.rb to verify no regression**

Run: `bundle exec rspec spec/system/categories/show/budget_spec.rb`
Expected: passes (existing coverage — we add prorated-specific assertions in Task 8).

- [ ] **Step 8: Commit**

```bash
git add app/views/categories/_partials/show/_summary_card.html.erb app/views/categories/_partials/show/_budget_card.html.erb spec/system/categories/show/summary_card_spec.rb
git commit -m "category show: use budget_curve for chart and surface prorated flag"
```

---

## Task 8: Budget form — prorated checkbox + controller param + persistence spec

**Files:**
- Modify: `app/views/budgets/_form.html.erb`
- Modify: `app/controllers/budgets_controller.rb`
- Modify: `spec/system/categories/show/budget_spec.rb`

- [ ] **Step 1: Write failing persistence spec**

Append to `spec/system/categories/show/budget_spec.rb` (inside the top-level describe, before the final `end`). If the file structure uses page-based helpers, follow that pattern — use the `system-test-writer` skill to match conventions.

```ruby
  describe "prorated flag persistence", :aggregate_failures do
    let!(:user) { create(:user) }
    let!(:groceries) { create(:category, :expense, user: user, name: "Groceries") }

    before { sign_in user, scope: :user }

    it "creates a prorated budget when the checkbox is checked" do
      visit new_budget_path(category_id: groceries.id)
      fill_in "Amount", with: "300.00"
      check "Prorate daily"
      click_button "Create Budget"

      expect(page).to have_current_path(category_path(groceries))
      expect(groceries.reload.budget.prorated).to eq(true)
    end

    it "creates a non-prorated budget when the checkbox is left unchecked" do
      visit new_budget_path(category_id: groceries.id)
      fill_in "Amount", with: "300.00"
      click_button "Create Budget"

      expect(groceries.reload.budget.prorated).to eq(false)
    end
  end
```

- [ ] **Step 2: Run spec, verify failure**

Run: `bundle exec rspec spec/system/categories/show/budget_spec.rb`
Expected: fails — "Prorate daily" field not found.

- [ ] **Step 3: Add `:prorated` to permitted params**

Edit `app/controllers/budgets_controller.rb`. Change:

```ruby
  def budget_params
    params.expect(budget: [:amount, :period, :category_id])
  end
```

to:

```ruby
  def budget_params
    params.expect(budget: [:amount, :period, :category_id, :prorated])
  end
```

(We keep `:period` for now — Task 9 removes it along with the enum.)

- [ ] **Step 4: Add prorated checkbox to the form**

Edit `app/views/budgets/_form.html.erb`. After the Budget Amount block (ending near line 51) and before the Budget Period block (starting near line 53), insert:

```erb
<%# Prorated toggle %>
<div>
  <%= f.input :prorated,
      as: :boolean,
      label: "Prorate daily",
      wrapper_html: { class: "flex items-start gap-3" },
      hint: "Spread the budget evenly across the month so you can see if you're on pace day-to-day. Turn off for expenses that happen in one-time chunks (like rent or subscriptions)." %>
</div>
```

- [ ] **Step 5: Run the spec, verify passing**

Run: `bundle exec rspec spec/system/categories/show/budget_spec.rb`
Expected: all examples pass.

- [ ] **Step 6: Commit**

```bash
git add app/views/budgets/_form.html.erb app/controllers/budgets_controller.rb spec/system/categories/show/budget_spec.rb
git commit -m "budgets: add prorated checkbox to form"
```

---

## Task 9: Remove `Budget#period` — migration + full cleanup

This is the largest task. Every change in this task must be committed **together** so CI stays green. Run migrations and affected specs locally first, then commit.

**Files:**
- Create: `db/migrate/<timestamp>_remove_period_from_budgets.rb`
- Modify: `app/models/budget.rb`
- Modify: `app/controllers/budgets_controller.rb`
- Modify: `app/services/category_calculator.rb`
- Modify: `app/views/budgets/_form.html.erb`
- Modify: `spec/factories/budgets.rb`
- Modify: `spec/models/budget_spec.rb`
- Modify: `spec/system/budgets/form_spec.rb`

- [ ] **Step 1: Generate the migration**

Run:
```bash
bin/rails generate migration RemovePeriodFromBudgets
```

- [ ] **Step 2: Edit migration body**

Replace the generated migration with:

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

- [ ] **Step 3: Remove enum + validation from Budget model**

Edit `app/models/budget.rb`. Replace the contents with:

```ruby
# frozen_string_literal: true

class Budget < ApplicationRecord
  belongs_to :category, touch: true

  validates :amount, presence: true
  validate :category_must_be_expense
  validate :category_must_not_have_pool

  delegate :user, to: :category

  private

  def category_must_be_expense
    errors.add(:category, "must be an expense category") unless category&.expense?
  end

  def category_must_not_have_pool
    errors.add(:category, "cannot have a budget when linked to a savings pool") if category&.savings_pool_id?
  end
end
```

- [ ] **Step 4: Remove `:period` from permitted params**

Edit `app/controllers/budgets_controller.rb`. Change `budget_params` to:

```ruby
  def budget_params
    params.expect(budget: [:amount, :category_id, :prorated])
  end
```

- [ ] **Step 5: Simplify `monthly_budget_rate` and delete `yearly_budget?`**

Edit `app/services/category_calculator.rb`. Replace `monthly_budget_rate`:

```ruby
  def monthly_budget_rate
    return nil unless category.expense?
    category.budget&.amount
  end
```

Delete the `yearly_budget?` method entirely (the 3-line method that returned `category.budget&.year?`).

- [ ] **Step 6: Remove period select from form**

Edit `app/views/budgets/_form.html.erb`. Delete the Budget Period block (approximately lines 53-63 in the current file — the `<%# Budget Period %>` comment plus its `<div>...f.input :period...</div>` block).

- [ ] **Step 7: Update factory**

Edit `spec/factories/budgets.rb`. Replace the file with:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :budget do
    amount { Faker::Number.decimal(l_digits: 3, r_digits: 2) }
    association :category, factory: [:category, :expense]

    trait :prorated do
      prorated { true }
    end
  end
end
```

- [ ] **Step 8: Update model spec**

Edit `spec/models/budget_spec.rb`. Replace with:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budget, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:category) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:amount) }

    describe "category type validation" do
      let(:income_category) { create(:category, :income) }

      it "requires category to be an expense category", :aggregate_failures do
        budget = build(:budget, category: income_category)
        expect(budget).not_to be_valid
        expect(budget.errors[:category]).to include("must be an expense category")
      end
    end

    describe "pool mutual exclusivity" do
      let(:user) { create(:user) }
      let(:pool) { create(:savings_pool, user: user) }
      let(:expense_category) { create(:category, :expense, user: user, savings_pool: pool) }

      it "rejects budget on a category linked to a savings pool", :aggregate_failures do
        budget = build(:budget, category: expense_category)
        expect(budget).not_to be_valid
        expect(budget.errors[:category]).to include("cannot have a budget when linked to a savings pool")
      end
    end
  end

  describe "prorated flag" do
    it "defaults to false" do
      expect(build(:budget).prorated).to eq(false)
    end

    it "accepts true when explicitly set" do
      expect(build(:budget, :prorated).prorated).to eq(true)
    end
  end
end
```

- [ ] **Step 9: Update form system spec — remove yearly test, adjust edit test**

Edit `spec/system/budgets/form_spec.rb`. Locate the "pre-fills all budget fields with existing data" test and the "updates budget and redirects to category page" test (lines 145-161). Replace them with versions that don't reference the Period select:

```ruby
    it "pre-fills all budget fields with existing data" do
      expect(page).to have_field("Amount", with: "500.0")
    end

    it "updates budget and redirects to category page" do
      fill_in "Amount", with: "750.00"
      click_button "Update Budget"

      expect(page).to have_current_path(category_path(expense_category))
      expect(page).to have_content("Budget was successfully updated")

      budget.reload
      expect(budget.amount).to eq(750.00)
    end
```

Also scan the rest of the file for any `have_select("Period", ...)`, `select ... from: "Period"`, or references to `period` on Budget instances — remove those assertions.

- [ ] **Step 10: Run migration**

Run: `bin/rails db:migrate`
Expected: migration succeeds, `db/schema.rb` no longer has `period` on budgets.

- [ ] **Step 11: Run affected specs**

Run each one by one:

```bash
bundle exec rspec spec/models/budget_spec.rb
bundle exec rspec spec/services/category_calculator_spec.rb
bundle exec rspec spec/system/budgets/form_spec.rb
bundle exec rspec spec/system/dashboard/index/expenses_tab_spec.rb
bundle exec rspec spec/system/categories/show/summary_card_spec.rb
bundle exec rspec spec/system/categories/show/budget_spec.rb
```

Expected: all pass.

- [ ] **Step 12: Commit everything**

```bash
git add db/migrate/*_remove_period_from_budgets.rb db/schema.rb \
        app/models/budget.rb app/controllers/budgets_controller.rb \
        app/services/category_calculator.rb app/views/budgets/_form.html.erb \
        spec/factories/budgets.rb spec/models/budget_spec.rb \
        spec/system/budgets/form_spec.rb
git commit -m "budgets: remove period enum; all budgets are monthly"
```

---

## Task 10: Full verification

**Files:** none (verification only — may produce small follow-up commits)

- [ ] **Step 1: Rebuild Tailwind**

Run: `bin/rails tailwindcss:build`
Expected: clean build.

- [ ] **Step 2: Run full CI**

Run: `bin/ci`
Expected: style, security, tests, seeds all pass.

- [ ] **Step 3: Manual visual check**

Start the server (`bin/dev`), log in as `demo@example.com` / `password123`, and verify in a browser (desktop viewport 1440px):
1. Dashboard → Expenses tab, monthly view — chart shows a blended ramp line if any prorated budgets exist; rows with prorated budgets show "over pace" / "under pace"; Monthly Budget stat matches the sum of caps.
2. Dashboard → Expenses tab, YTD view — behavior unchanged; no ramp.
3. Category show page for a prorated category — chart has ramp line; % and status reflect pace.
4. Category show page for a flat category — unchanged behavior.
5. `/budgets/new?category_id=X` — form shows Amount + "Prorate daily" checkbox; no Period select.
6. Browser console has no JavaScript errors.

Capture a screenshot of the dashboard Expenses tab with a prorated category for the PR description.

- [ ] **Step 4: Run code review agent**

Invoke the `rails-code-reviewer` agent to review uncommitted + recent commits on this branch.

- [ ] **Step 5: Address any critical review feedback**

If the reviewer flags issues, fix them and commit a follow-up (`git commit -m "review: <what>"`). If no issues, nothing to commit.

- [ ] **Step 6: Clean up screenshots**

Run: `rm -f *.png`

- [ ] **Step 7: Final sanity check**

Run: `git status` — expected clean tree. Run `git log --oneline -12` — expected ordered commits matching the task list.

---

## Self-review notes

**Spec coverage** (checked against `docs/superpowers/specs/2026-04-17-prorated-budgets-design.md`):

- Migration for `prorated` → Task 1
- Migration removing `period` with data migration → Task 9 Step 2
- `Budget` model changes (enum removal) → Task 9 Step 3
- `BudgetsController#budget_params` → Task 8 Step 3, Task 9 Step 4
- `CategoryCalculator` — `@date` storage → Task 3 Step 3
- `CategoryCalculator#budget_curve` + helpers → Task 3 Step 4
- `CategoryCalculator#budget_pace` + `pace_day` → Task 4 Step 3
- `CategoryCalculator#budget_percentage` swap → Task 4 Step 4
- `monthly_budget_rate` simplification → Task 9 Step 5
- `yearly_budget?` deletion → Task 9 Step 5
- `DashboardPresenter#enrich_with_budget` → Task 5 Step 3
- `Dashboard::ExpensesPresenter#budget_line_data` + `sum_curves` → Task 5 Step 4
- Budget stat card (unchanged behavior) → verified in Task 5 spec + Task 10 visual check
- `_form.html.erb` prorated checkbox → Task 8 Step 4
- `_form.html.erb` period removal → Task 9 Step 6
- `_budget_card.html.erb` row swap → Task 7 Step 6
- `_summary_card.html.erb` yearly block deletion → Task 7 Step 3
- `_summary_card.html.erb` chart collapse → Task 7 Step 4
- `_expenses_tab.html.erb` wording + cache key → Task 6
- Factory changes → Task 2 (add trait), Task 9 Step 7 (remove period)
- Model spec changes → Task 9 Step 8
- Calculator spec → Tasks 3 & 4
- Dashboard system spec → Task 5 Step 1
- Summary card system spec → Task 7 Step 1
- Budget system spec (persistence) → Task 8 Step 1
- Form system spec (yearly removal) → Task 9 Step 9

All spec requirements covered.

**Placeholder scan:** No TBDs, TODOs, or "handle appropriately" phrases. Every code step shows exact code.

**Type consistency:** `budget_curve` returns `Hash<Date, Numeric>` in every reference. `budget_pace(today:)` accepts a kwarg in every test and in the method definition. `effective_budget` signature unchanged. `entry[:prorated]`, `entry[:budget]`, `entry[:budget_percentage]`, `entry[:over_budget]`, `entry[:budget_diff]` keys match between presenter (Task 5) and view (Task 6).
