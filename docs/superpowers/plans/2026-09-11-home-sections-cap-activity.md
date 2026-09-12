# Home Sections, Lane Names, Fund Cap and Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split Home's "This period" into Budget and Savings sections with totals, name item-less rules plainly, give a fund rule an optional cap, and add an Activity page listing every entry, transfer and adjustment with Edit and Remove.

**Architecture:** Two view/helper changes (sections, lane words), one small model+calculator change (the cap: a nullable column, two fund arms in the walk, form and copy), and one new read-only page (`ActivityPresenter` interleaving three tables, with the existing destroy actions learning a `return: "activity"` arm and a new `transfers#destroy`).

**Tech Stack:** Rails 8.1, Hotwire, Tailwind, simple_form, kaminari, RSpec + Capybara.

**Spec:** `docs/superpowers/specs/2026-09-11-home-sections-cap-activity-design.md`. The "what": `docs/decisions.md` §4 and §10.

## Global Constraints

- Home "This period": a heading row with counts and the kinds legend, then `<section data-budget-section>` headed "Budget · $X claimed" (category blocks, unbudgeted rows, the empty-state sentence), then `<section data-savings-section>` headed "Savings · $Y owed" (savings blocks), rendered only when a targeted account exists.
- Lane names: item name when the rule names an item; "Everything else in <Category>" when the category has other rules; "All of <Category>" when it is the only rule. "Whole category" appears on no screen; `ClaimLine::WHOLE_CATEGORY` stays only as the `data-rule-row`/`data-rule` hook value.
- Cap: `rules.cap` money nullable with check `cap IS NULL OR (keeps_unspent AND cap > 0::money)`; fund `planned = capped ? min(amount, max(cap − built_up, 0)) : amount`; fund `accrued = capped ? min(built_up + planned + Σadj, cap) : …`; `target = cap` for a capped fund; `Rule#ask` unchanged. Copy: "built up $X of $Y", "full at $Y", preview "It builds up to $Y, then stops asking until some of it is spent.", form field "Stop at" with hint "optional — once the pile reaches this, the rule stops asking until you spend from it".
- Activity: route `/activity`, nav "Look back": Activity then Reports; rows newest first by `[date desc, created_at desc]`, 50 per page via `Kaminari.paginate_array`; words per the spec §5; every Remove returns to Activity.
- Tests as the repo's rules: logic in presenter/model/service specs, system specs for rendering once and each interaction, Rack::Test unless `:js` is needed, no `sleep`; `bundle exec rubocop -A` before every commit, no new disables; the whole suite before the last commit.
- Commit messages `type/area: sentence` ending with the session's attribution lines.
- Fixed-date fixtures; biweekly grid anchored 2026-02-06 (Sep 9 sits in Sep 4 – Sep 17).

---

## File Structure

**Created**: `db/migrate/*_add_cap_to_rules.rb`, `app/presenters/activity_presenter.rb`, `app/controllers/activity_controller.rb`, `app/views/activity/show.html.erb`, `app/views/activity/_row.html.erb`, `spec/presenters/activity_presenter_spec.rb`, `spec/requests/activity_spec.rb`, `spec/system/activity/show_spec.rb`, `spec/system/home/sections_spec.rb`.

**Modified**: `app/views/home/_this_period.html.erb`, `app/helpers/home_helper.rb`, `app/views/budget_page/_category_open.html.erb`, `app/models/rule.rb`, `app/services/rule_form.rb`, `app/services/claim_calculator.rb`, `app/presenters/claim_line.rb` (only if `bar?` needs it), `app/helpers/budget_page_helper.rb`, `app/views/rules/_form.html.erb`, `app/controllers/transfers_controller.rb`, `app/controllers/adjustments_controller.rb`, `app/controllers/entries_controller.rb` (only if `previous_url` needs widening), `app/views/shared/_sidebar.html.erb`, `config/routes.rb`, `spec/factories/rules.rb`, and the specs named per task.

---

### Task 1: Home sections and lane names

**Files:**
- Modify: `app/views/home/_this_period.html.erb`, `app/helpers/home_helper.rb`, `app/views/budget_page/_category_open.html.erb`, `spec/system/home/this_period_spec.rb`, `spec/system/budget_page/rules_spec.rb:83,145`, `spec/system/navbar_spec.rb` (no change; listed to say so)
- Create: `spec/system/home/sections_spec.rb`

**Interfaces:**
- Produces: `HomeHelper#lane_words(line, rows)`.

- [ ] **Step 1: Failing specs**

`spec/system/home/sections_spec.rb` (reuse `this_period_spec`'s scaffolding: `user` biweekly, `today` Sep 9, checking account, `sign_in`, `read_home`):
```ruby
  it "splits this period into Budget and Savings, each with its total", :aggregate_failures do
    groceries = create(:category, user: user, name: "Groceries")
    create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1))
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))

    read_home

    within("[data-budget-section]") do
      expect(page).to have_css("[data-section-total]", text: "$400.00 claimed")
      expect(page).to have_css("[data-category-block='Groceries']")
    end
    within("[data-savings-section]") do
      expect(page).to have_css("[data-section-total]", text: "$200.00 owed")
      expect(page).to have_css("[data-savings-block='Emergency']")
    end
  end

  it "shows no Savings section without a targeted account" do
    create(:rule, :rate, amount: 400, category: create(:category, user: user, name: "Groceries"), starts_on: Date.new(2026, 1, 1))
    read_home
    expect(page).to have_no_css("[data-savings-section]")
  end

  it "names an item-less rule by what it covers", :aggregate_failures do
    groceries = create(:category, user: user, name: "Groceries")
    create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1))
    pets = create(:category, user: user, name: "Pets")
    create(:rule, :rate, amount: 60, category: pets, starts_on: Date.new(2026, 1, 1))
    create(:rule, :rate, amount: 40, category: pets, item: create(:item, category: pets, name: "Vet"), starts_on: Date.new(2026, 1, 1))

    read_home

    expect(find("[data-category-block='Groceries']")).to have_content("All of Groceries")
    expect(find("[data-category-block='Pets']")).to have_content("Everything else in Pets")
    expect(page).to have_no_content("Whole category")
  end
```
In `spec/system/budget_page/rules_spec.rb`, lines 83 and 145 (`have_content("Whole category")`) become `have_content("All of Groceries")`.

- [ ] **Step 2: Run to see them fail**

Run: `bundle exec rspec spec/system/home/sections_spec.rb spec/system/budget_page/rules_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Helper and views**

`app/helpers/home_helper.rb`:
```ruby
  # What a row calls the lane a rule covers. An item names itself; an item-less rule covers the
  # category's other items, so it is "everything else" beside item rules and "all of" it alone.
  def lane_words(line, rows)
    return line.rule.item.name if line.rule.item.present?

    rows.size > 1 ? "Everything else in #{line.category.name}" : "All of #{line.category.name}"
  end
```
`app/views/home/_this_period.html.erb`: the row name `<p class="text-sm font-medium text-gray-900 truncate"><%= row.name %></p>` becomes `<%= lane_words(row, block.rows) %>` (the `data-rule-row="<%= row.name %>"` hook stays). Wrap the category-block grid, the unbudgeted rows and the empty-state paragraph in:
```erb
  <section data-budget-section>
    <div class="flex items-baseline justify-between gap-3 pb-2">
      <h4 class="text-xs font-semibold uppercase tracking-wide text-gray-500">Budget</h4>
      <span class="text-sm text-gray-700 tabular-nums" data-section-total><%= number_to_currency(presenter.budget_claim) %> claimed</span>
    </div>
    …existing grid, unbudgeted rows, empty state…
  </section>

  <% if presenter.savings_blocks.any? %>
    <section class="mt-6" data-savings-section>
      <div class="flex items-baseline justify-between gap-3 pb-2">
        <h4 class="text-xs font-semibold uppercase tracking-wide text-gray-500">Savings</h4>
        <span class="text-sm text-gray-700 tabular-nums" data-section-total><%= number_to_currency(presenter.savings_claim) %> owed</span>
      </div>
      <div class="grid grid-cols-1 gap-3 lg:grid-cols-2 lg:items-start">
        <% presenter.savings_blocks.each do |row| %>
          <%= render "home/savings_block", row: row, presenter: presenter %>
        <% end %>
      </div>
    </section>
  <% end %>
```
(remove the savings-blocks loop from inside the category grid). `app/views/budget_page/_category_open.html.erb`: the row's `<%= line.name %>` becomes `<%= lane_words(line, row.lines) %>`.

- [ ] **Step 4: Run and commit**

Run: `bundle exec rspec spec/system/home spec/system/budget_page`
Expected: PASS.
```bash
bundle exec rubocop -A
git add -A app spec
git commit -m "feat/home: this period is a Budget section and a Savings section, and a lane says what it covers"
```

---

### Task 2: The fund cap

**Files:**
- Create: `db/migrate/*_add_cap_to_rules.rb` (via `bin/rails generate migration AddCapToRules`)
- Modify: `app/models/rule.rb`, `app/services/rule_form.rb`, `app/services/claim_calculator.rb`, `app/helpers/home_helper.rb`, `app/helpers/budget_page_helper.rb`, `app/views/rules/_form.html.erb`, `spec/factories/rules.rb`, `spec/models/rule_spec.rb`, `spec/services/rule_form_spec.rb`, `spec/services/claim_calculator_spec.rb`, `spec/system/rules/form_spec.rb`, `spec/system/budget_page/rules_spec.rb`, `spec/system/home/this_period_spec.rb`

**Interfaces:**
- Produces: `Rule#cap`, `#capped?`; `RuleForm#cap`; `ClaimCalculator` fund arms per the constraints; `HomeHelper#figure_words`/`#when_words` capped words; `BudgetPageHelper#steady_words` "full at"; `#rule_preview_holding_sentence` capped sentence.

- [ ] **Step 1: Migration**

`bin/rails generate migration AddCapToRules`, body:
```ruby
class AddCapToRules < ActiveRecord::Migration[8.1]
  def change
    add_column :rules, :cap, :money, scale: 2
    add_check_constraint :rules, "cap IS NULL OR (keeps_unspent AND cap > 0::money)", name: "rules_cap_only_on_a_fund"
  end
end
```
`bin/rails db:migrate && RAILS_ENV=test bin/rails db:migrate && bundle exec rake parallel:prepare`.

- [ ] **Step 2: Failing calculator spec**

In `spec/services/claim_calculator_spec.rb`'s "a fund rule" describe add (the fund there is `:keeps_unspent`, $60 a period; adapt the amount if it differs):
```ruby
    it "stops adding at its cap, asks nothing while full, and rebuilds after spending", :aggregate_failures do
      capped = create(:rule, :keeps_unspent, amount: 100, cap: 250, category: groceries, item: bread, starts_on: Date.new(2026, 7, 24))
      # periods: Jul 24, Aug 7, Aug 21, Sep 4 → 100, 200, 250 (capped), 250
      full = described_class.new(capped, today: today)
      expect(full.claim).to eq(250)
      expect(full.planned_this_period).to eq(0)
      expect(full.target).to eq(250)

      spend(180, on: Date.new(2026, 9, 6))
      drawn = described_class.new(capped, today: today)
      expect(drawn.claim).to eq(70)
      expect(described_class.new(capped, today: Date.new(2026, 9, 20)).planned_this_period).to eq(100)
      expect(described_class.new(capped, today: Date.new(2026, 9, 20)).claim).to eq(170)
    end

    it "lets an adjustment top a capped fund up only to its cap" do
      capped = create(:rule, :keeps_unspent, amount: 100, cap: 250, category: groceries, item: bread, starts_on: Date.new(2026, 8, 21))
      create(:adjustment, source: capped, amount: 500, date: Date.new(2026, 9, 5))

      expect(described_class.new(capped, today: today).claim).to eq(250)
    end
```

- [ ] **Step 3: Model, form, calculator**

`app/models/rule.rb`: `validates :cap, numericality: { greater_than: 0 }, allow_nil: true`; `validate :cap_needs_a_fund` adding "only a rule that keeps what it doesn't spend can have a cap" on `:cap` when `cap.present? && !keeps_unspent?`; `def capped? = cap.present?`.

`app/services/rule_form.rb`: `:cap` in `FIELDS`, `attr_accessor :cap`, `from` includes `cap: rule.cap`, `schedule_columns`'s per-period hash gains `cap: (keeps? ? cap.presence : nil)`, the by-date hash gains `cap: nil`, `RULE_ERROR_FIELDS` gains `cap: :cap`.

`app/services/claim_calculator.rb`:
```ruby
  def target
    return @target if defined?(@target)

    @target = if dated? then rule.amount.to_d
              elsif fund? then rule.cap&.to_d
              else 0.to_d
              end
  end
  …
  def accrued_in(state, period)
    accrued = state.built_up + state.planned + adjustments_within(period)
    return capped_fund? ? [accrued, target].min : accrued if fund?

    [accrued, target].min
  end

  def planned_for(period, state, due)
    return fund_planned(state) if fund?
    …unchanged…
  end

  def fund_planned(state)
    return rate_per_period unless capped_fund?

    [rate_per_period, [target - state.built_up, 0.to_d].max].min
  end

  def capped_fund? = fund? && rule.capped?
```
`ClaimLine#bar?`/`#denominator` already use `target` for non-rate rules, so a capped fund draws its bar with no change; confirm `fund_short?` still requires `dated?`.

`spec/factories/rules.rb`: a `:capped` trait (`keeps_unspent { true }`, `anchor_date { nil }`, `cap { 1_000 }`).

- [ ] **Step 4: Words**

`app/helpers/home_helper.rb`: `figure_words` → `return "built up #{number_to_currency(line.filled)}#{" of #{number_to_currency(line.target)}" if line.target}" if line.fund?`; `fund_when_clause` → `return "full at #{number_to_currency(line.target)}" if line.target && line.per_period.zero?` before the existing lines.
`app/helpers/budget_page_helper.rb`: `steady_words(line)` (or wherever Task 3 of the previous plan put it; it may live in `HomeHelper`) gains, before the equality arm: `return "full at #{number_to_currency(line.target)}" if line.fund? && line.target && line.per_period.zero?`. `rule_preview_holding_sentence`: `return "It builds up to #{number_to_currency(preview.rule.cap)}, then stops asking until some of it is spent." if preview.fund? && preview.rule.capped?` before the existing fund line.

`app/views/rules/_form.html.erb`, inside the keeps block after `f.input :keeps`:
```erb
          <%= f.input :cap,
              as: :decimal,
              label: "Stop at",
              required: false,
              hint: "optional — once the pile reaches this, the rule stops asking until you spend from it",
              input_html: { step: 0.01, min: 0.01, disabled: rule_form.schedule == "by_date" } %>
```
If the Stimulus controller `app/javascript/controllers/app/budget/rule_form_controller.js` toggles `disabled` on `keepsField`'s inputs by querying them, the new input is covered; if it targets one input, extend the query to `input` elements within the field.

- [ ] **Step 5: Specs**

`spec/models/rule_spec.rb`: a cap on a rate rule is refused; a cap on a fund is fine; zero is refused. `spec/services/rule_form_spec.rb`: `cap` round-trips through `from` and writes only with keeps. `spec/system/rules/form_spec.rb`: the field renders with its label and hint; saving a fund with "Stop at" 2000 shows the preview sentence and the Budget row "built up $0.00 of $2,000.00". `spec/system/budget_page/rules_spec.rb`: a full capped fund's row reads "full at $250.00" in both the figure cell's steady line and the When cell. `spec/system/home/this_period_spec.rb`: the fund example gains a capped variant asserting "built up $250.00 of $250.00" and "full at $250.00".

- [ ] **Step 6: Run and commit**

Run: `bundle exec rspec spec/models/rule_spec.rb spec/services/rule_form_spec.rb spec/services/claim_calculator_spec.rb spec/presenters spec/system/rules spec/system/budget_page spec/system/home`
Expected: PASS.
```bash
bundle exec rubocop -A
git add -A app spec db
git commit -m "feat/rules: a fund can stop at a cap, and asks nothing while it sits there"
```

---

### Task 3: Activity

**Files:**
- Create: `app/presenters/activity_presenter.rb`, `app/controllers/activity_controller.rb`, `app/views/activity/show.html.erb`, `app/views/activity/_row.html.erb`, `spec/presenters/activity_presenter_spec.rb`, `spec/requests/activity_spec.rb`, `spec/system/activity/show_spec.rb`
- Modify: `config/routes.rb`, `app/views/shared/_sidebar.html.erb`, `spec/system/navbar_spec.rb`, `app/controllers/transfers_controller.rb`, `app/controllers/adjustments_controller.rb`, `spec/requests/transfers_spec.rb`, `spec/requests/adjustments_spec.rb`

**Interfaces:**
- Produces: `ActivityPresenter.new(user:, page:)#rows` (kaminari-paginated `Row`s), `ActivityPresenter::Row`; `transfers#destroy`; `adjustments#back_to` "activity" arm; routes `activity_path`, `transfer_path` (delete).

- [ ] **Step 1: Failing presenter spec**

`spec/presenters/activity_presenter_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityPresenter do
  let(:user) { create(:user, :biweekly) }
  let!(:checking) { create(:account, user: user, name: "Checking", opening_balance: 1_000) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let(:bread) { create(:item, category: groceries, name: "Bread") }

  it "interleaves entries, transfers and adjustments newest first with their words", :aggregate_failures do
    emergency = create(:account, user: user, name: "Emergency")
    rule = create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1))
    create(:entry, item: bread, amount: 30, date: Date.new(2026, 9, 6))
    create(:transfer, from_account: checking, to_account: emergency, amount: 200, date: Date.new(2026, 9, 7))
    create(:adjustment, source: rule, amount: -50, date: Date.new(2026, 9, 8))
    create(:entry, item: create(:item, :income, user: user, name: "Paycheck"), amount: 2_000, date: Date.new(2026, 9, 8))

    rows = described_class.new(user: user, page: nil).rows
    expect(rows.map { |r| [r.kind, r.date] }).to eq([[:entry, Date.new(2026, 9, 8)], [:adjustment, Date.new(2026, 9, 8)], [:transfer, Date.new(2026, 9, 7)], [:entry, Date.new(2026, 9, 6)]])
    expect(rows.map(&:words)).to eq(["Paycheck · #{Item.find_by!(name: "Paycheck").category.name}", "Groceries · reduced", "Checking → Emergency", "Bread · Groceries"])
    expect(rows.map(&:amount)).to eq([2_000, -50, 200, -30])
    expect(rows.first.edit_path).to be_present
    expect(rows[2].remove_path).to include("/transfers/")
  end

  it "pages fifty at a time" do
    60.times { |n| create(:entry, item: bread, amount: 1, date: Date.new(2026, 9, 1) - n) }
    expect(described_class.new(user: user, page: 2).rows.size).to eq(10)
  end
end
```
(Newest first on the same date orders by `created_at desc`; the income entry is created after the adjustment, so it leads.)

- [ ] **Step 2: Presenter, controller, routes, nav**

`app/presenters/activity_presenter.rb`:
```ruby
# frozen_string_literal: true

# Everything that happened, newest first: entries, transfers and adjustments as one list of rows,
# each saying what it was, what it moved, and where to edit or undo it.
class ActivityPresenter
  PER_PAGE = 50
  Row = Data.define(:kind, :date, :created_at, :words, :amount, :edit_path, :remove_path, :remove_confirm) do
    def entry? = kind == :entry
    def transfer? = kind == :transfer
    def adjustment? = kind == :adjustment
  end

  include Rails.application.routes.url_helpers

  attr_reader :user, :page

  def initialize(user:, page:)
    @user = user
    @page = page
  end

  def rows
    @rows ||= Kaminari.paginate_array(all_rows.sort_by { |row| [row.date, row.created_at] }.reverse).page(page).per(PER_PAGE)
  end

  private

  def all_rows = entry_rows + transfer_rows + adjustment_rows

  def entry_rows
    user.entries.includes(item: :category).map do |entry|
      Row.new(kind: :entry, date: entry.date, created_at: entry.created_at,
              words: "#{entry.item.name} · #{entry.category.name}",
              amount: entry.category.income? ? entry.amount.to_d : -entry.amount.to_d,
              edit_path: edit_entry_path(entry, previous_url: activity_path),
              remove_path: entry_path(entry, previous_url: activity_path),
              remove_confirm: "Remove this entry? Your balances will change.")
    end
  end

  def transfer_rows
    ids = user.accounts.select(:id)
    Transfer.where(from_account_id: ids).or(Transfer.where(to_account_id: ids)).includes(:from_account, :to_account).map do |transfer|
      Row.new(kind: :transfer, date: transfer.date, created_at: transfer.created_at,
              words: "#{transfer.from_account.name} → #{transfer.to_account.name}",
              amount: transfer.amount.to_d,
              edit_path: nil,
              remove_path: transfer_path(transfer, return: "activity"),
              remove_confirm: "Remove this transfer? The money goes back where it came from.")
    end
  end

  def adjustment_rows
    Adjustment.where(source: user.rules).or(Adjustment.where(source: user.accounts)).includes(:source).map do |change|
      Row.new(kind: :adjustment, date: change.date, created_at: change.created_at,
              words: "#{adjustment_name(change)} · #{adjustment_verb(change)}",
              amount: change.amount.to_d,
              edit_path: nil,
              remove_path: adjustment_path(change, return: "activity"),
              remove_confirm: "Remove this adjustment?")
    end
  end

  def adjustment_name(change) = change.rule? ? (change.source.item&.name || change.source.category.name) : change.source.name

  def adjustment_verb(change)
    return change.amount.negative? ? "reduced" : "topped up" if change.account? || change.source.cadence == :per_period

    change.amount.negative? ? "took back" : "set aside"
  end
end
```
(A skip is a negative adjustment of the period's accrual and reads "reduced"; that is acceptable here.) If `Adjustment.where(source: user.rules)` does not compile for a polymorphic `or`, use `Adjustment.on_rules(user.rules.select(:id)).or(Adjustment.on_accounts(user.accounts.select(:id)))`.

`app/controllers/activity_controller.rb`:
```ruby
# frozen_string_literal: true

class ActivityController < ApplicationController
  def show
    @presenter = ActivityPresenter.new(user: current_user, page: params[:page])
  end
end
```
`config/routes.rb`: `get "activity" => "activity#show", as: :activity`; `resources :transfers, only: [:create, :destroy]`.
`app/views/shared/_sidebar.html.erb` "Look back": `{ name: "Activity", path: activity_path, icon: "clock" }` before Reports; `spec/system/navbar_spec.rb`'s `sidebar_links` gains `"Activity" => activity_path` between Savings and Reports (keep the order assertion true).

`app/controllers/transfers_controller.rb`:
```ruby
  def destroy
    transfer = Transfer.where(from_account_id: current_user.accounts.select(:id)).find(params[:id])
    transfer.destroy
    redirect_to(params[:return] == "activity" ? activity_path : savings_path, notice: "Removed the transfer of #{helpers.number_to_currency(transfer.amount)} from #{transfer.from_account.name} to #{transfer.to_account.name}.")
  end
```
`app/controllers/adjustments_controller.rb#back_to`: `return activity_path if params[:return] == "activity"` as the first line. `EntriesController#destroy` already honours `previous_url` for its redirect (check `set_previous_url`/the redirect target; if destroy redirects to a fixed path, make it `redirect_to(params[:previous_url].presence || entries_path, …)` — only for a same-origin path; use `url_from(params[:previous_url]) || entries_path`).

- [ ] **Step 3: Views**

`app/views/activity/show.html.erb`:
```erb
<% content_for :title, "Activity" %>

<%= page_header(title: "Activity", subtitle: "Everything that happened, newest first.") %>

<div class="bg-white rounded shadow-sm border border-gray-200" data-activity>
  <% if @presenter.rows.any? %>
    <div class="md:hidden divide-y divide-gray-200">
      <%= render partial: "activity/row", collection: @presenter.rows, as: :row, locals: { card: true } %>
    </div>
    <div class="hidden md:block overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <thead class="bg-gray-50">
          <tr>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">What</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Date</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Detail</th>
            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Amount</th>
            <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          <%= render partial: "activity/row", collection: @presenter.rows, as: :row, locals: { card: false } %>
        </tbody>
      </table>
    </div>
    <div class="px-6 py-3 border-t border-gray-200"><%= paginate @presenter.rows %></div>
  <% else %>
    <p class="px-6 py-8 text-sm text-gray-500" data-activity-empty>Nothing has happened yet. Log an entry and it shows up here.</p>
  <% end %>
</div>
```
`app/views/activity/_row.html.erb`: a `<tr data-activity-row="<%= row.kind %>">` (or a card `<div>` when `card`) with a kind badge (`Entry` / `Transfer` / `Adjustment`, the savings badge colour for a transfer), the date `%b %-d`, `row.words`, the signed amount (red when negative), and actions: `link_to "Edit", row.edit_path` when present, and `button_to "Remove", row.remove_path, method: :delete, form: { data: { turbo_confirm: row.remove_confirm } }`. Follow the entries table's classes so the two pages match.

- [ ] **Step 4: Request and system specs**

`spec/requests/activity_spec.rb`: signed-in user gets 200 and the empty-state sentence with nothing logged. `spec/requests/transfers_spec.rb`: `delete transfer_path(transfer, return: "activity")` removes it and redirects to `activity_path`; a foreign transfer 404s. `spec/requests/adjustments_spec.rb`: `delete adjustment_path(change, return: "activity")` redirects to `activity_path`.

`spec/system/activity/show_spec.rb`: one entry, one transfer and one adjustment render as three rows newest first with their words and amounts; `click_button "Remove"` on the transfer row (Rack::Test, no confirm) removes it and returns to Activity with the notice; the same for the adjustment; the entry's Edit link points at its edit form.

- [ ] **Step 5: Run and commit**

Run: `bundle exec rspec spec/presenters/activity_presenter_spec.rb spec/requests spec/system/activity spec/system/navbar_spec.rb spec/system/savings spec/system/home`
Expected: PASS.
```bash
bundle exec rubocop -A
git add -A app spec config
git commit -m "feat/activity: everything that happened, newest first, with a way to undo it"
```

---

### Task 4: Docs, the whole suite, the visual check

- [ ] `docs/coding-standards.md`: add `ActivityPresenter` to the presenter list and one sentence that a fund may cap; `docs/decisions.md` is already the target — read §4 and §10 against the pages and report any untrue sentence.
- [ ] `bundle exec rubocop` and `bundle exec parallel_rspec spec`, both clean.
- [ ] Visual check with the demo user on port 3001: `/` (two sections with totals; lane names), `/budget` open a category (lane name; a capped fund row if you add one via the form), `/rules/new?category_id=…` (Stop at field, preview sentence with a cap typed), `/activity`. Console clean. `rm -f *.png`.
- [ ] Commit: `docs/layout: activity and the fund cap in the standards`.

---

## Self-Review

**Spec coverage.** §2 → Task 1; §3 → Task 1; §4 → Task 2; §5 → Task 3; §6 tests → each task; §7 commits → four. **Placeholders**: none; the Stimulus `keepsField` note and the `previous_url` note give the check to make and the exact fallback. **Type consistency**: `lane_words(line, rows)` is called with `block.rows` on Home and `row.lines` on Budget, both arrays of `ClaimLine`; `Rule#capped?` is what the calculator and helpers call; `ActivityPresenter::Row` fields are what `_row.html.erb` reads; `params[:return] == "activity"` is the arm both destroy actions check.
