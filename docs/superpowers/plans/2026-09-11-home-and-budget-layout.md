# Home, Budget and the Nav Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Regroup the nav, make Home the full picture (tiles, Coming up, this period with Adjust and a kinds legend), keep Budget as the setup page showing what each rule takes this period, and put the kind definitions on the rule form.

**Architecture:** No model or calculator changes. `HomePresenter` gains tiles, an upcoming list (replacing the runway), savings blocks read through `SavingsPresenter`, and this period's adjustments; the adjust panel moves from Budget to Home and the adjustments controller redirects to Home for rules. `BudgetPagePresenter` gains `budget_now`, `leftover_now` and a per-category `takes_now` from figures the calculators already produce, and drops claimed and adjustments. One helper constant holds the kind definitions.

**Tech Stack:** Rails 8.1, Hotwire, Tailwind, RSpec + Capybara.

**Spec:** `docs/superpowers/specs/2026-09-11-home-and-budget-layout-design.md`. The "what": `docs/decisions.md` §4 and §10. Mockups: https://claude.ai/code/artifact/8df83bbb-e085-4609-ba34-a5bae0b6de9f

## Global Constraints

- Nav groups and order: **Today** (Home, Entries, Calendar), **Plan** (Budget, Savings), **Look back** (Reports), **Set up** (Categories, Settings). Icons unchanged.
- Home: header is the day and "Day N of M in this period · next payday <date>"; four tiles in this order: Free to spend (tinted, subline "after everything claimed is set aside"), In checking (subline "spent $X this period"), Claimed (subline "Budget $X · Savings $Y"), In savings (subline "N accounts · owed $Z"); then the trouble strip only when there is trouble; then Coming up (dated rules due within 30 days, states ready / short / building); then This period with the kinds legend "gives way first →  Choice · Usage · Savings · Bill" in its header, category blocks, then one block per savings account with a target, and Adjust on every rule row and savings block.
- **No per-day pace figure anywhere.** `Pace`, `pace_line`, `per_day_pace`, `pace_words` and the shortfall's pace line are deleted.
- Budget keeps its sections, reorder, rules table, spending frames and the per-category "New rule" door. Three changes only: the "Now" column becomes "Takes this period" (`line.per_period`) with the steady figure beneath ("$Y a period once caught up", or "same every period"); no claimed figure on the page; no Adjust and no adjustments list on the page.
- Budget tiles: "Where it goes" shows `budget_now + savings` labelled "this period", the steady bar and split as now, and "Z a period once every bill is caught up" when Z differs; "That leaves" keeps the steady verdict and adds "This period leaves W" when it differs. `fits`/`underwater?` use the steady figures.
- Rule form: only step 3's three help strings change, to the definitions in `BudgetPageHelper::KIND_DEFINITIONS`.
- Kind definitions, verbatim: bill — "A must. A set amount on a date, once or every so many months. Rent, insurance, a loan payment. Gives way last."; usage — "Something you have to spend on, but how much depends on how you use it. Utilities, groceries, fuel. Gives way after choice."; choice — "Something you choose to get. Not a necessity; you could go without. Eating out, hobbies, clothes. Gives way first."
- An adjustment on a rule redirects to Home (`root_path`, anchored `#block-<category id>`); on an account it redirects to `savings_path`, or to Home when the form carried `return=home`. Refusals re-render the page they came from with the flash.
- Tests: logic in presenter specs; a system spec proves a page renders its figures once and every real interaction; Rack::Test unless `:js` is needed; no `sleep`. Run the touched directory, then `bundle exec parallel_rspec spec` before the last commit; `bundle exec rubocop -A` before every commit, no new disables; `bin/rails tailwindcss:build` when a new utility class appears.
- Commit messages `type/area: sentence`, ending with the attribution lines the session gives you.
- Fixed-date fixtures; biweekly grid anchored 2026-02-06 (Sep 9 sits in Sep 4 – Sep 17).

---

## File Structure

**Created**
- `app/views/home/_tiles.html.erb` (replaces `_money`), `app/views/home/_upcoming.html.erb` (replaces `_runway`), `app/views/home/_adjust.html.erb` (moved from `budget_page/_adjust`), `app/views/home/_savings_block.html.erb`
- `spec/system/home/tiles_spec.rb` (replaces `money_spec`), `spec/system/home/upcoming_spec.rb` (replaces `runway_spec`), `spec/system/home/adjustments_spec.rb` (moved from `budget_page/adjustments_spec`)

**Modified**
- `app/views/shared/_sidebar.html.erb`, `spec/system/navbar_spec.rb`
- `app/presenters/home_presenter.rb`, `app/presenters/savings_presenter.rb`, `app/helpers/home_helper.rb`, `app/views/home/index.html.erb`, `app/views/home/_this_period.html.erb`, `app/views/home/_shortfall.html.erb`, `app/controllers/concerns/home_state.rb`, `app/controllers/adjustments_controller.rb`, `app/views/savings/_adjust.html.erb`
- `app/presenters/budget_page_presenter.rb`, `app/views/budget_page/_tiles.html.erb`, `_category_row.html.erb`, `_category_open.html.erb`
- `app/helpers/budget_page_helper.rb`, `app/views/rules/_form.html.erb`
- specs: `home_presenter_spec`, `budget_page_presenter_spec`, `system/home/{this_period,trouble}_spec`, `system/budget_page/{tiles,open,list,rules}_spec`, `requests/adjustments_spec`, `system/rules/form_spec`
- `docs/coding-standards.md`

**Deleted**
- `app/views/home/_money.html.erb`, `_runway.html.erb`, `_manage_accounts.html.erb`, `app/views/budget_page/_adjust.html.erb`
- `spec/system/home/money_spec.rb`, `runway_spec.rb`, `spec/system/budget_page/adjustments_spec.rb`

---

### Task 1: The nav in four groups

**Files:**
- Modify: `app/views/shared/_sidebar.html.erb:220-246`, `spec/system/navbar_spec.rb`

- [ ] **Step 1: Failing spec**

In `spec/system/navbar_spec.rb`, replace the first example with:
```ruby
    it "links to every section of the app, in four groups", :aggregate_failures do
      within_sidebar do
        expect(page).to have_link("Home", href: root_path)
        expect(page).to have_link("Entries", href: entries_path)
        expect(page).to have_link("Calendar", href: calendar_path)
        expect(page).to have_link("Budget", href: budget_page_path)
        expect(page).to have_link("Savings", href: savings_path)
        expect(page).to have_link("Reports", href: reports_path)
        expect(page).to have_link("Categories", href: categories_path)
        expect(page).to have_link("Settings", href: settings_path)
        expect(all("nav h3, nav [data-nav-title]").map(&:text)).to eq(["Today", "Plan", "Look back", "Set up"])
        expect(all("nav a").map(&:text).map(&:strip).reject(&:empty?)).to eq(%w[Home Entries Calendar Budget Savings Reports Categories Settings])
      end
    end
```
Open `app/views/shared/_nav_section.html.erb` and note the element that prints the title; if it is not an `h3`, add `data-nav-title` to it so the selector above holds (say which in your report).

- [ ] **Step 2: Run to see it fail**

Run: `bundle exec rspec spec/system/navbar_spec.rb`
Expected: FAIL on the titles.

- [ ] **Step 3: Regroup the sidebar**

Replace the three `render "shared/nav_section"` calls with four:
```erb
            <%= render "shared/nav_section",
                title: "Today",
                links: [
                  { name: "Home", path: root_path, icon: "home" },
                  { name: "Entries", path: entries_path, icon: "document-text" },
                  { name: "Calendar", path: calendar_path, icon: "calendar" }
                ]
            %>

            <%= render "shared/nav_section",
                title: "Plan",
                links: [
                  { name: "Budget", path: budget_page_path, icon: "adjustments-horizontal" },
                  { name: "Savings", path: savings_path, icon: "banknotes" }
                ]
            %>

            <%= render "shared/nav_section",
                title: "Look back",
                links: [
                  { name: "Reports", path: reports_path, icon: "chart-bar" }
                ]
            %>

            <%= render "shared/nav_section",
                title: "Set up",
                links: [
                  { name: "Categories", path: categories_path, icon: "tag" },
                  { name: "Settings", path: settings_path, icon: "cog-6-tooth" }
                ]
            %>
```
If Settings already has a link elsewhere in the sidebar (the user-profile block), keep it there too; the spec counts `nav a` only. If the `cog-6-tooth` heroicon is missing in this version, use `cog`.

- [ ] **Step 4: Run and commit**

Run: `bundle exec rspec spec/system/navbar_spec.rb`
Expected: PASS.
```bash
bundle exec rubocop -A
git add -A app/views/shared spec/system/navbar_spec.rb
git commit -m "feat/nav: four groups — today, plan, look back, set up"
```

---

### Task 2: Home is the full picture

**Files:**
- Create: `app/views/home/_tiles.html.erb`, `_upcoming.html.erb`, `_adjust.html.erb`, `_savings_block.html.erb`, `spec/system/home/tiles_spec.rb`, `upcoming_spec.rb`, `adjustments_spec.rb`
- Modify: `app/presenters/home_presenter.rb`, `app/presenters/savings_presenter.rb`, `app/helpers/home_helper.rb`, `app/views/home/index.html.erb`, `_this_period.html.erb`, `_shortfall.html.erb`, `app/controllers/concerns/home_state.rb`, `app/controllers/adjustments_controller.rb`, `app/views/savings/_adjust.html.erb`, `spec/presenters/home_presenter_spec.rb`, `spec/system/home/this_period_spec.rb`, `spec/system/home/trouble_spec.rb`, `spec/requests/adjustments_spec.rb`
- Delete: `app/views/home/_money.html.erb`, `_runway.html.erb`, `_manage_accounts.html.erb`, `spec/system/home/money_spec.rb`, `runway_spec.rb`

**Interfaces:**
- Consumes: `ClaimLedger#claimed/#budget_claim/#savings_claim/#free/#pot`, `ClaimLine` (`dated?`, `paid?`, `short?`, `fund_short?`, `next_due_on`, `target`, `built_up`, `per_period`, `adjustments`, `name`), `SavingsLine`, `ClaimRows#blocks`, `Adjustment.on_rules(ids).dated_within(range)`.
- Produces: `HomePresenter#day_words`, `#period_words`, `#tiles` (`HomePresenter::Tiles`), `#upcoming` (`[HomePresenter::Upcoming]`), `#savings_blocks` (`[SavingsLine]`), `#kinds_legend`; `SavingsPresenter.new(user:, today:, ledger: nil)`; `HomeState#refuse_on_home(message)`; adjustments controller redirects per the constraints.

- [ ] **Step 1: Failing presenter spec**

In `spec/presenters/home_presenter_spec.rb`, replace the "measures the period and the runway" example with these three and delete any example that references `runway`, `pace_line` or `per_day_pace`:
```ruby
  it "reads the four tiles off the ledger", :aggregate_failures do
    create(:account, user: user, name: "Checking", opening_balance: 1_000) unless user.main_account
    rule_on("Groceries", :rate, amount: 400)
    emergency = create(:account, user: user, name: "Emergency", opening_balance: 500)
    create(:savings_target, account: emergency, amount: 200, starts_on: user.period_containing(today).first)
    create(:entry, item: create(:item, category: user.categories.find_by!(name: "Groceries")), amount: 30, date: today)

    tiles = described_class.new(user: user, today: today).tiles
    expect(tiles).to have_attributes(checking: 970, spent_this_period: 30, claimed: 570, budget_claim: 370, savings_claim: 200, free: 400, savings_total: 500, savings_owed: 200, savings_count: 1)
  end

  it "lists dated rules due within 30 days with their state, soonest first", :aggregate_failures do
    create(:account, user: user, name: "Checking", opening_balance: 5_000) unless user.main_account
    rule_on("Dentist", :bill, amount: 300, anchor_date: Date.new(2026, 9, 12), starts_on: Date.new(2026, 8, 1))
    rule_on("Vet", :bill, amount: 180, anchor_date: Date.new(2026, 10, 1), starts_on: Date.new(2026, 9, 4))
    rule_on("Insurance", :bill, amount: 1_200, anchor_date: Date.new(2026, 12, 1), starts_on: Date.new(2026, 9, 4))
    presenter = described_class.new(user: user, today: today)

    expect(presenter.upcoming.map { |u| [u.line.name, u.due_on, u.state] })
      .to eq([["Dentist", Date.new(2026, 9, 12), :ready], ["Vet", Date.new(2026, 10, 1), :building]])
    expect(presenter.upcoming.first.set_aside).to eq(300)
    expect(presenter.day_words).to eq("Wednesday, September 9")
    expect(presenter.period_words).to eq("Day 6 of 14 in this period · next payday Sep 18")
  end

  it "carries one savings block per targeted account and the legend in give-way order", :aggregate_failures do
    create(:account, user: user, name: "Checking") unless user.main_account
    emergency = create(:account, user: user, name: "Emergency")
    create(:account, user: user, name: "Joint")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
    presenter = described_class.new(user: user, today: today)

    expect(presenter.savings_blocks.map(&:name)).to eq(["Emergency"])
    expect(presenter.savings_blocks.first.claim).to eq(200)
    expect(presenter.kinds_legend).to eq([[:choice, "Choice"], [:usage, "Usage"], [:savings, "Savings"], [:bill, "Bill"]])
  end
```
(The Dentist figure: $300 by Sep 12 started Aug 1 with nothing spent is fully built by Sep 9 on the biweekly grid, so `:ready`; adjust the `set_aside` expectation to the calculator's `built_up` if it differs, and say so. The "short" state is covered in the system spec.)

- [ ] **Step 2: Run to see it fail**

Run: `bundle exec rspec spec/presenters/home_presenter_spec.rb`
Expected: FAIL on `tiles`.

- [ ] **Step 3: The presenter**

`app/presenters/savings_presenter.rb`: let Home hand in its ledger so the rows are built from one read:
```ruby
  def initialize(user:, today: user.today, ledger: nil)
    @user = user
    @today = today
    @ledger = ledger
  end
```
(`ledger` stays the private memoised method; `@ledger ||=` now respects the handed one.)

`app/presenters/home_presenter.rb`: delete `Pace`, `pace_line`, `per_day_pace`, `Runway`, `RunwayTick`, `runway`, `build_runway`, `runway_ticks`, `runway_tick`; add:
```ruby
  Tiles = Data.define(:free, :checking, :spent_this_period, :claimed, :budget_claim, :savings_claim,
                      :savings_total, :savings_owed, :savings_count)
  # One dated rule due soon. `state` is :ready (the money is there), :short (due this period and
  # not there) or :building (still accruing toward a later day).
  Upcoming = Data.define(:line, :state) do
    delegate :name, to: :line
    def due_on = line.next_due_on
    def amount = line.target
    def set_aside = line.built_up
    def ready? = state == :ready
    def short? = state == :short
    def building? = state == :building
  end

  UPCOMING_DAYS = 30

  def day_words = today.strftime("%A, %B %-d")

  def period_words
    progress = period_progress
    return "No period set yet" if progress.nil?

    "Day #{progress.day} of #{progress.days} in this period · next payday #{(progress.last + 1).strftime("%b %-d")}"
  end

  def tiles
    @tiles ||= Tiles.new(
      free: free_to_spend, checking: in_checking, spent_this_period: spent_this_period,
      claimed: claimed, budget_claim: budget_claim, savings_claim: savings_claim,
      savings_total: other_accounts_total, savings_owed: savings_claim, savings_count: other_accounts.size
    )
  end

  def spent_this_period
    @spent_this_period ||= Entry.expenses.where(categories: { user_id: user.id })
      .where(date: user.period_containing(today)).sum(:amount).to_d
  end

  # Dated rules due from today through UPCOMING_DAYS, soonest first, each with where its money stands.
  def upcoming
    @upcoming ||= blocks.flat_map(&:rows)
      .select { |line| line.dated? && !line.paid? && line.next_due_on&.between?(today, today + UPCOMING_DAYS) }
      .sort_by { |line| [line.next_due_on, line.name] }
      .map { |line| Upcoming.new(line: line, state: upcoming_state(line)) }
  end

  # Savings accounts with a target, as the Savings page reads them, off this page's own ledger.
  def savings_blocks
    @savings_blocks ||= SavingsPresenter.new(user: user, today: today, ledger: claim_ledger).rows.select(&:targeted?)
  end

  def kinds_legend = ClaimLedger::KIND_RANK.keys.map { |kind| [kind, kind.to_s.capitalize] }

  private

  def upcoming_state(line)
    return :short if line.short?
    return :building if line.fund_short?

    :ready
  end

  # This period's adjustments, so each rule row can list them under its Adjust panel.
  def adjustments_this_period
    @adjustments_this_period ||= Adjustment.on_rules(claim_ledger.rules.map(&:id))
      .dated_within(user.period_containing(today)).order(:date, :created_at).group_by(&:source_id)
  end
```
and change `claim_rows` to `ClaimRows.new(ledger: claim_ledger, today: today, categories: categories, adjustments: adjustments_this_period)`. Keep `period_progress`, `short?`, `shortfall`, `uncovered_claims`, `troubles`, `unbudgeted_rows`, `blocks`, `give_way_order`.

`app/helpers/home_helper.rb`: delete `runway_tick_words` and `pace_words`; add
```ruby
  # What an upcoming row says beside its amount.
  def upcoming_words(row)
    return "Ready — it's all there" if row.ready?
    return "#{number_to_currency(row.line.fund_gap)} short" if row.short?

    "#{number_to_currency(row.set_aside)} set aside · +#{number_to_currency(row.line.per_period)} a period"
  end
```

- [ ] **Step 4: Run the presenter spec**

Run: `bundle exec rspec spec/presenters/home_presenter_spec.rb`
Expected: PASS.

- [ ] **Step 5: The views**

`git rm app/views/home/_money.html.erb app/views/home/_runway.html.erb app/views/home/_manage_accounts.html.erb`; `git mv app/views/budget_page/_adjust.html.erb app/views/home/_adjust.html.erb`.

`app/views/home/index.html.erb`:
```erb
<% content_for :title, "Home" %>

<%= page_header(title: @presenter.day_words, subtitle: @presenter.period_words) %>

<%# The full picture: the four tiles, trouble only when there is some, what is coming up, and this
    period rule by rule. An adjustment is the one thing written here; everything else links out. %>
<div class="space-y-4 lg:space-y-6">
  <%= render "home/tiles", presenter: @presenter %>

  <% if @presenter.trouble? %>
    <%= render "home/trouble", presenter: @presenter %>
  <% end %>

  <%= render "home/upcoming", presenter: @presenter %>

  <%= render "home/this_period", presenter: @presenter %>
</div>
```

`app/views/home/_tiles.html.erb`:
```erb
<%# THE FOUR TILES. Local: `presenter`. Free first and tinted; the others are what it is made of. %>
<% tiles = presenter.tiles %>
<div class="grid grid-cols-2 gap-3 lg:grid-cols-4 lg:gap-4" data-tiles>
  <div class="col-span-2 bg-brand-light border border-brand rounded p-4 lg:col-span-1 lg:p-5" data-tile="free">
    <p class="text-xs font-medium uppercase tracking-wide text-gray-600">Free to spend</p>
    <p class="mt-1 text-3xl font-semibold tabular-nums <%= tiles.free.negative? ? "text-status-danger" : "text-gray-900" %>" data-free>
      <%= number_to_currency(tiles.free) %>
    </p>
    <p class="mt-1 text-xs text-gray-600">after everything claimed is set aside</p>
  </div>
  <div class="bg-white border border-gray-200 rounded p-4 lg:p-5" data-tile="checking">
    <p class="text-xs font-medium uppercase tracking-wide text-gray-500">In checking</p>
    <p class="mt-1 text-xl font-semibold tabular-nums <%= tiles.checking.negative? ? "text-status-danger" : "text-gray-900" %>" data-in-checking>
      <%= number_to_currency(tiles.checking) %>
    </p>
    <p class="mt-1 text-xs text-gray-500" data-spent-this-period>spent <%= number_to_currency(tiles.spent_this_period) %> this period</p>
  </div>
  <div class="bg-white border border-gray-200 rounded p-4 lg:p-5" data-tile="claimed">
    <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Claimed</p>
    <p class="mt-1 text-xl font-semibold tabular-nums text-gray-900" data-claimed><%= number_to_currency(tiles.claimed) %></p>
    <p class="mt-1 text-xs text-gray-500" data-claimed-split>
      Budget <span class="tabular-nums text-gray-900" data-budget-claim><%= number_to_currency(tiles.budget_claim) %></span>
      <span class="text-gray-400" aria-hidden="true">·</span>
      Savings <span class="tabular-nums text-gray-900" data-savings-claim><%= number_to_currency(tiles.savings_claim) %></span>
    </p>
  </div>
  <div class="bg-white border border-gray-200 rounded p-4 lg:p-5" data-tile="savings">
    <p class="text-xs font-medium uppercase tracking-wide text-gray-500">In savings</p>
    <p class="mt-1 text-xl font-semibold tabular-nums text-gray-900" data-savings-total><%= number_to_currency(tiles.savings_total) %></p>
    <p class="mt-1 text-xs text-gray-500">
      <%= pluralize(tiles.savings_count, "account") %> · owed <span class="tabular-nums" data-savings-owed><%= number_to_currency(tiles.savings_owed) %></span>
      · <%= link_to "Savings", savings_path, class: "text-brand-dark hover:text-brand underline" %>
    </p>
  </div>
</div>
```

`app/views/home/_upcoming.html.erb`:
```erb
<%# COMING UP — every dated rule due in the next 30 days, with where its money stands. Local:
    `presenter`. Absent when nothing is due, rather than an empty card. %>
<% if presenter.upcoming.any? %>
  <section class="bg-white border border-gray-200 rounded" data-upcoming aria-labelledby="upcoming-heading">
    <div class="flex items-baseline justify-between gap-3 px-4 py-3 border-b border-gray-200 lg:px-5">
      <h3 id="upcoming-heading" class="text-sm font-semibold text-gray-900">Coming up</h3>
      <p class="text-xs text-gray-500">the next <%= HomePresenter::UPCOMING_DAYS %> days</p>
    </div>
    <ul class="divide-y divide-gray-100">
      <% presenter.upcoming.each do |row| %>
        <li class="grid grid-cols-[56px_1fr_auto] items-center gap-3 px-4 py-3 sm:grid-cols-[56px_1.4fr_1fr_1fr] lg:px-5"
            data-upcoming-row="<%= row.name %>" data-upcoming-state="<%= row.state %>">
          <div class="rounded border border-gray-200 py-1 text-center">
            <div class="text-[10px] uppercase text-gray-500"><%= row.due_on.strftime("%b") %></div>
            <div class="text-lg font-semibold leading-tight text-gray-900"><%= row.due_on.day %></div>
          </div>
          <div class="min-w-0">
            <p class="text-sm font-medium text-gray-900 truncate"><%= row.name %></p>
            <p class="text-xs <%= type_text_class(row.line) %>"><%= shape_words(row.line) %></p>
          </div>
          <p class="text-sm tabular-nums text-gray-900 sm:text-left"><%= number_to_currency(row.amount) %></p>
          <p class="col-span-3 text-xs sm:col-span-1 sm:text-sm <%= row.short? ? "text-status-danger font-medium" : row.ready? ? "text-status-success font-medium" : "text-gray-600" %>"
             data-upcoming-words>
            <%= upcoming_words(row) %>
          </p>
        </li>
      <% end %>
    </ul>
  </section>
<% end %>
```

`app/views/home/_this_period.html.erb`: three edits.
1. The heading row gains the legend after the counts:
```erb
    <p class="basis-full flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-gray-500 sm:basis-auto" data-kinds-legend>
      <span>gives way first →</span>
      <% presenter.kinds_legend.each do |kind, label| %>
        <span class="inline-flex items-center gap-1.5"><span class="h-2 w-2 rounded-sm <%= type_fill(kind) %>" aria-hidden="true"></span><%= label %></span>
      <% end %>
    </p>
```
2. Each category block's `<div … data-category-block>` gains `id="block-<%= block.category.id %>"`, and after each row's `</details>` (inside the `block.rows.each`) add:
```erb
          <div class="px-4 pb-3">
            <%= render "home/adjust", line: line %>
            <% if line.adjustments.any? %>
              <ul class="mt-2 space-y-1" data-rule-changes>
                <% line.adjustments.each do |change| %>
                  <li class="flex items-baseline gap-2 text-xs text-gray-600" data-change="<%= change.id %>">
                    <span class="text-gray-500"><%= change.date.strftime("%b %-d") %></span>
                    <span class="<%= change.amount.negative? ? "text-status-danger" : "text-gray-900" %>" data-change-amount><%= number_to_currency(change.amount) %></span>
                    <%= button_to "Remove", adjustment_path(change), method: :delete, class: "text-brand-dark hover:text-brand underline" %>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>
```
3. After the category blocks loop and before the unbudgeted rows, one block per savings account:
```erb
    <% presenter.savings_blocks.each do |row| %>
      <%= render "home/savings_block", row: row, presenter: presenter %>
    <% end %>
```

`app/views/home/_adjust.html.erb` (the moved file): remove `open: line.category.id` from both `adjustments_path(...)` calls (plain `adjustments_path`); everything else stays, including the `data-adjust` hook and the "Adjust what's owed now" summary.

`app/views/home/_savings_block.html.erb`:
```erb
<%# ONE SAVINGS ACCOUNT WITH A TARGET, in the shape of a category block. Locals: `row`
    (SavingsLine), `presenter`. The bar is what has arrived this period against what is owed. %>
<div class="bg-white border border-gray-200 rounded overflow-hidden" data-savings-block="<%= row.name %>" id="savings-<%= row.account.id %>">
  <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1 px-4 py-2 border-b border-gray-200 bg-gray-50" data-block-header>
    <div class="flex items-baseline gap-2">
      <h4 class="text-sm font-semibold text-gray-900"><%= row.name %></h4>
      <span class="text-xs text-gray-500">savings</span>
    </div>
    <span class="text-sm text-gray-700 tabular-nums" data-block-owed><%= number_to_currency(row.claim) %> owed</span>
  </div>
  <div class="flex gap-3 px-4 py-3">
    <span class="w-1 shrink-0 rounded bg-savings" aria-hidden="true"></span>
    <div class="min-w-0 flex-1">
      <div class="flex flex-wrap items-baseline justify-between gap-x-3">
        <p class="text-sm font-medium text-gray-900 truncate"><%= row.target_words %></p>
        <p class="text-sm tabular-nums text-gray-700" data-savings-figure><%= number_to_currency(row.accrued) %> owed this period</p>
      </div>
      <p class="mt-0.5 text-xs text-savings">savings · <%= row.mode_words %></p>
      <p class="mt-1 flex flex-wrap items-baseline gap-x-2 text-xs text-gray-500">
        <% if row.transferable? %>
          <%= button_to "Transfer #{number_to_currency(row.claim)}", transfers_path,
                        params: { transfer: { from_account_id: presenter.user.main_account_id, to_account_id: row.account.id, amount: row.claim, date: presenter.today }, return: "home" },
                        class: "text-brand-dark hover:text-brand underline", form: { class: "inline" }, data: { transfer_owed: row.name } %>
        <% else %>
          <span class="text-status-success font-medium">On pace</span>
        <% end %>
      </p>
    </div>
  </div>
  <div class="px-4 pb-3">
    <%= render "savings/adjust", row: row, return_to: "home" %>
  </div>
</div>
```
`app/views/savings/_adjust.html.erb`: accept `return_to: nil` (`<% return_to = local_assigns[:return_to] %>`) and add `<%= hidden_field_tag :return, return_to if return_to %>` inside both forms. `TransfersController#create`: `redirect_to(params[:return] == "home" ? root_path : savings_path, notice: …)`.

`app/views/home/_shortfall.html.erb`: delete the `<% if pace = presenter.pace_line %> … <% end %>` block.

- [ ] **Step 6: The controllers**

`app/controllers/concerns/home_state.rb`:
```ruby
  def refuse_on_home(message)
    flash.now[:alert] = message
    assign_home_state
    render "home/index", status: :unprocessable_content
  end
```
`app/controllers/adjustments_controller.rb`: replace `include BudgetPageState` with `include HomeState`, and:
```ruby
  def back_to(source)
    return root_path(anchor: "block-#{source.category_id}") if source.is_a?(Rule)

    params[:return] == "home" ? root_path(anchor: "savings-#{source.id}") : savings_path
  end

  def refuse(source, message)
    source.is_a?(Rule) || params[:return] == "home" ? refuse_on_home(message) : refuse_on_savings_page(message)
  end
```
`spec/requests/adjustments_spec.rb:17`: `expect(response).to redirect_to(root_path(anchor: "block-#{groceries.id}"))`. Add one example: an account adjustment posted with `return: "home"` redirects to `root_path(anchor: "savings-#{emergency.id}")`.

- [ ] **Step 7: System specs**

`git rm spec/system/home/money_spec.rb spec/system/home/runway_spec.rb`; `git mv spec/system/budget_page/adjustments_spec.rb spec/system/home/adjustments_spec.rb`.

`spec/system/home/tiles_spec.rb` (carry the money spec's `user`/`today`/`before`/`read_home` scaffolding; replace its examples):
```ruby
  it "shows the four tiles with their sublines", :aggregate_failures do
    rule_for("Groceries", rate: 400)
    emergency = create(:account, user: user, name: "Emergency", opening_balance: 500)
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
    create(:entry, item: create(:item, category: create(:category, user: user, name: "Fuel")), amount: 25, date: today)

    read_home

    expect(page).to have_css("h1", text: "Wednesday, September 9")
    expect(page).to have_content("Day 6 of 14 in this period · next payday Sep 18")
    expect(page).to have_css("[data-tile='free'] [data-free]", text: "$375.00")
    expect(page).to have_css("[data-tile='free']", text: "after everything claimed is set aside")
    expect(page).to have_css("[data-in-checking]", text: "$975.00")
    expect(page).to have_css("[data-spent-this-period]", text: "spent $25.00 this period")
    expect(page).to have_css("[data-claimed]", text: "$600.00")
    expect(page).to have_css("[data-claimed-split]", text: "Budget $400.00 · Savings $200.00")
    expect(page).to have_css("[data-savings-total]", text: "$500.00")
    expect(page).to have_css("[data-tile='savings']", text: "1 account · owed $200.00")
    expect(page).to have_no_content("a day")
  end
```
(Checking opens at 1,000 in that scaffold; fix the figures if its balance differs.)

`spec/system/home/upcoming_spec.rb` (same scaffolding; `today` Sep 9):
```ruby
  it "lists what is due within 30 days, soonest first, with its state", :aggregate_failures do
    dated("Dentist", 300, Date.new(2026, 9, 12), starts_on: Date.new(2026, 8, 1))
    dated("Vet", 180, Date.new(2026, 10, 1), starts_on: Date.new(2026, 9, 4))
    dated("Insurance", 1_200, Date.new(2026, 12, 1), starts_on: Date.new(2026, 9, 4))
    dated("Rent", 900, Date.new(2026, 9, 12), starts_on: Date.new(2026, 9, 4))

    read_home

    within("[data-upcoming]") do
      expect(all("[data-upcoming-row]").map { |row| row["data-upcoming-row"] }).to eq(%w[Dentist Rent Vet])
      expect(page).to have_css("[data-upcoming-row='Dentist'][data-upcoming-state='ready']", text: "Ready — it's all there")
      expect(page).to have_css("[data-upcoming-row='Rent'][data-upcoming-state='short']", text: "short")
      expect(page).to have_css("[data-upcoming-row='Vet'][data-upcoming-state='building']", text: "set aside")
      expect(page).to have_no_css("[data-upcoming-row='Insurance']")
    end
  end

  it "renders nothing when nothing is due" do
    rule_for("Groceries", rate: 400)
    read_home
    expect(page).to have_no_css("[data-upcoming]")
  end
```
with `def dated(name, amount, due, starts_on:)` creating a `:bill` rule on a fresh category with `anchor_date: due`. (Rent: $900 due Sep 12, started Sep 4 with one period to fund and $5,000 in checking is built but `fund_short?` depends on built_up < target after one period's planning; if the calculator has it `:ready`, make Rent start today and lower checking, and say so.)

`spec/system/home/adjustments_spec.rb` (the moved file): `visit budget_page_path(open: groceries.id)` → `visit root_path`; `claimed` → `find("[data-category-block='Groceries'] [data-block-claimed]")`; expected claimed texts drop "claimed"? They read "$450.00 claimed" already on Home's block header, so keep the strings; describe name "Home adjustments"; every `data-adjust='Groceries'` hook stays. Add one `:js` example: a savings block's "Skip this period" from Home redirects back to Home with the notice.

`spec/system/home/this_period_spec.rb`: add
```ruby
  it "carries the kinds legend and a savings block", :aggregate_failures do
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
    read_home

    expect(page).to have_css("[data-kinds-legend]", text: "gives way first → Choice Usage Savings Bill")
    within("[data-savings-block='Emergency']") do
      expect(page).to have_css("[data-block-owed]", text: "$200.00 owed")
      expect(page).to have_css("[data-savings-figure]", text: "$200.00 owed this period")
      expect(page).to have_button("Transfer $200.00")
      expect(page).to have_css("[data-adjust='Emergency']")
    end
  end
```
`spec/system/home/trouble_spec.rb`: delete any assertion on `data-shortfall-pace` or "a day".

- [ ] **Step 8: Run, rebuild, commit**

```bash
bin/rails tailwindcss:build
bundle exec rspec spec/presenters/home_presenter_spec.rb spec/system/home spec/requests/adjustments_spec.rb spec/system/savings spec/system/budget_page
```
Expected: PASS (`spec/system/budget_page` still passes because `_category_open` still renders the adjust partial from its new path only after Task 3; if the moved partial breaks Budget now, temporarily point `_category_open`'s render at `"home/adjust"` and note it; Task 3 removes it).
```bash
bundle exec rubocop -A
git add -A app spec
git commit -m "feat/home: the full picture — four tiles, coming up, this period with adjust and the kinds legend"
```

---

### Task 3: Budget shows what each rule takes this period

**Files:**
- Modify: `app/presenters/budget_page_presenter.rb`, `app/views/budget_page/_tiles.html.erb`, `_category_row.html.erb`, `_category_open.html.erb`, `spec/presenters/budget_page_presenter_spec.rb`, `spec/system/budget_page/{tiles,open,list,rules}_spec.rb`

**Interfaces:**
- Produces: `BudgetPagePresenter#budget_now`, `#leftover_now`, `Tiles#budget_now`, `#leftover_now`, `#where_now`, `CategoryRow#takes_now`.

- [ ] **Step 1: Failing presenter spec**

Add to `spec/presenters/budget_page_presenter_spec.rb`:
```ruby
  it "says what the rules take this period as of today, beside the steady figure", :aggregate_failures do
    rule_on("Groceries", amount: 400)
    fresh = create(:category, user: user, name: "Insurance")
    create(:rule, :bill, category: fresh, amount: 1_200, anchor_date: Date.new(2027, 2, 11), interval_months: 12, starts_on: today)
    presenter = described_class.new(user: user, today: today)

    expect(presenter.budget).to eq(400 + 46.15)
    expect(presenter.budget_now).to eq(400 + 109.09)
    expect(presenter.tiles.where_now).to eq(presenter.budget_now + presenter.savings)
    expect(presenter.category_rows.find { |row| row.name == "Insurance" }.takes_now).to eq(109.09)
  end
```
(109.09 is $1,200 over the 11 biweekly periods from Sep 4 to Feb 11; take the calculator's `planned_this_period` if it rounds differently and say so.)

- [ ] **Step 2: Presenter**

```ruby
  CategoryRow = Data.define(:category, :lines, :type_dots, :takes_now, :open) do  # claimed → takes_now
  Tiles = Data.define(:budget, :budget_now, :savings, :segments, :income, :cadence, :leftover, :leftover_now, :declared, :fits) do
    def declared? = declared
    def fits? = fits
    def where = budget + savings
    def where_now = budget_now + savings
    def catching_up? = budget_now != budget
  end

  def budget_now = @budget_now ||= claim_ledger.rules.sum(0.to_d) { |rule| claim_ledger.calculator_for(rule).planned_this_period }
  def leftover_now = typical_income && (typical_income - savings - budget_now)
```
`tiles` passes `budget_now:` and `leftover_now:`. `row_for` computes `takes_now: lines.sum(0.to_d, &:per_period)`; `ruled_rows` no longer passes `claimed:`. Delete `adjustments_this_period` and the `adjustments:` argument to `ClaimRows.new`.

- [ ] **Step 3: Views**

`_tiles.html.erb` "Where it goes": figure `number_to_currency(presenter.tiles.where_now)` with the unit word "this period"; keep the bar and `data-tile-split`; add after the split:
```erb
    <% if presenter.tiles.catching_up? %>
      <p class="mt-1 text-xs text-gray-500" data-tile-steady><%= number_to_currency(presenter.tiles.where) %> a period once every bill is caught up</p>
    <% end %>
```
"That leaves": keep the steady figure and verdict; add `<p class="mt-1 text-xs text-gray-500" data-tile-leftover-now>This period leaves <%= number_to_currency(presenter.tiles.leftover_now) %></p>` when `catching_up?` and history.

`_category_row.html.erb`: the claimed span becomes
```erb
        <span class="text-sm tabular-nums <%= row.needs_attention? ? "text-status-danger font-medium" : "text-gray-700" %>" data-category-takes>
          takes <%= number_to_currency(row.takes_now) %> this period
        </span>
```
`_category_open.html.erb`: header "Now" → "Takes this period"; the figure `<p data-rule-figure>` becomes
```erb
                  <div class="sm:w-40 sm:text-right" data-rule-figure>
                    <p class="text-sm tabular-nums font-medium text-gray-900"><%= number_to_currency(line.per_period) %></p>
                    <p class="text-xs text-gray-500" data-rule-steady><%= line.per_period == line.rule.ask ? "same every period" : "#{number_to_currency(line.rule.ask)} a period once caught up" %></p>
                  </div>
```
the When cell prints `[when_words(line), figure_words(line)].compact.join(" · ")`; delete the `render "budget_page/adjust"` line and the `line.adjustments` list.

- [ ] **Step 4: Specs**

`spec/system/budget_page/tiles_spec.rb`: the where tile's figure assertions read `where_now` (same as before when nothing is catching up) with "this period"; add one example with a fresh 12-month bill asserting `[data-tile-steady]` and `[data-tile-leftover-now]`. `list_spec`/`open_spec`/`rules_spec`: `data-category-claim` → `data-category-takes` with "takes $X this period"; the "Now" header → "Takes this period"; `[data-rule-figure]` assertions read the per-period figure and `[data-rule-steady]`; delete any assertion on `data-adjust` or `data-rule-changes` on the Budget page.

- [ ] **Step 5: Run and commit**

Run: `bundle exec rspec spec/presenters/budget_page_presenter_spec.rb spec/system/budget_page spec/system/home`
Expected: PASS.
```bash
bundle exec rubocop -A
git add -A app spec
git commit -m "feat/budget: the rules table says what each rule takes this period, and adjust lives on Home"
```

---

### Task 4: The kinds, in one place

**Files:**
- Modify: `app/helpers/budget_page_helper.rb`, `app/views/rules/_form.html.erb`, `spec/system/rules/form_spec.rb`

- [ ] **Step 1: Failing spec**

Add to `spec/system/rules/form_spec.rb`, in the new-rule context:
```ruby
  it "explains the three kinds where one is picked", :aggregate_failures do
    visit new_rule_path(category_id: groceries.id)

    expect(page).to have_content("A must. A set amount on a date, once or every so many months. Rent, insurance, a loan payment. Gives way last.")
    expect(page).to have_content("Something you have to spend on, but how much depends on how you use it. Utilities, groceries, fuel. Gives way after choice.")
    expect(page).to have_content("Something you choose to get. Not a necessity; you could go without. Eating out, hobbies, clothes. Gives way first.")
  end
```

- [ ] **Step 2: Implement**

`app/helpers/budget_page_helper.rb`:
```ruby
  # The three kinds, in the user's words, read by the rule form. `fetch`, so a fourth type fails loudly.
  KIND_DEFINITIONS = {
    "bill" => "A must. A set amount on a date, once or every so many months. Rent, insurance, a loan payment. Gives way last.",
    "usage" => "Something you have to spend on, but how much depends on how you use it. Utilities, groceries, fuel. Gives way after choice.",
    "choice" => "Something you choose to get. Not a necessity; you could go without. Eating out, hobbies, clothes. Gives way first."
  }.freeze

  def kind_definition(type) = KIND_DEFINITIONS.fetch(type.to_s)
```
`app/views/rules/_form.html.erb` step 3: delete the `type_help` hash; the help span reads `<%= kind_definition(type) %>`. Nothing else on the form changes.

- [ ] **Step 3: Run and commit**

Run: `bundle exec rspec spec/system/rules`
Expected: PASS.
```bash
bundle exec rubocop -A
git add -A app spec
git commit -m "feat/rules: the three kinds explained where one is picked"
```

---

### Task 5: Docs, the whole suite, the visual check

- [ ] **Step 1: Docs**

`docs/coding-standards.md`: where presenters are listed, name `HomePresenter#tiles`, `#upcoming`, `#savings_blocks`; say Budget shows `planned_this_period` beside `ask`; say adjustments are written from Home and Savings only. `docs/decisions.md` needs no change; read §10 once more against the pages and fix any sentence the code contradicts.

- [ ] **Step 2: The suite**

```bash
bundle exec rubocop
bundle exec parallel_rspec spec
```
Both clean.

- [ ] **Step 3: Visual check**

`PORT=3001 bin/dev`, `demo@example.com` / `password123`, Claude in Chrome: `/`, `/budget` with a category open, `/rules/new?category_id=<one>`, and `/savings`. Check the console. Compare each against decisions §10. `rm -f *.png` afterwards.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs/layout: coding-standards names the home and budget figures"
```

---

## Self-Review

**Spec coverage.** §2 nav → Task 1. §3 Home (tiles, upcoming, savings blocks, legend, adjust moved, controller redirects, deletions, no pace) → Task 2. §4 Budget (budget_now, leftover_now, takes_now, column, no claimed, no adjust) → Task 3. §5 rule form wording → Task 4. §6 tests → each task. §7 commits → five here. §8 out of scope → nothing touches Savings, Sacrifice, Entries, Calendar, Reports, Categories, Settings beyond the nav and the `return` hidden field on the savings adjust partial.

**Placeholders.** None. Two figures are stated as "take the calculator's value and say so" because they depend on period arithmetic the implementer can read in one run.

**Type consistency.** `HomePresenter::Tiles` fields (Task 2) match `_tiles.html.erb`; `Upcoming#ready?/short?/building?` match `upcoming_words` and the view's classes; `SavingsPresenter.new(ledger:)` is used only by `savings_blocks`; `HomeState#refuse_on_home` is what `AdjustmentsController#refuse` calls; `BudgetPagePresenter::Tiles#where_now/#catching_up?` (Task 3) are what `_tiles.html.erb` reads; `CategoryRow#takes_now` is what `_category_row` prints; `kind_definition` (Task 4) is what the form calls.
