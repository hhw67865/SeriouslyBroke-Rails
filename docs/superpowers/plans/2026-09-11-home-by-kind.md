# Home by Kind Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Home's body as decided: the sum card (in checking − claimed = guilt-free money) with savings beside it, Coming up capped at four with a Calendar footer, and "What's claimed" as four kind columns (Bills, Savings, Usage, Choice) that become a segmented control on a phone.

**Architecture:** `HomePresenter` gains three readers off the ClaimLedger it already holds — `columns` (four `KindColumn`s), `claimed_shares` (the bar's four segments) and a re-sorted, capped `upcoming` with a footer summary — and loses `kinds_legend`. The views are rewritten around them: `_sum`, `_upcoming`, `_claimed` with `_rule_card` and `_savings_card`; `_tiles`, `_this_period` and `_savings_block` go. A small Stimulus controller shows one column at a time below `lg`. Every figure stays derived at read time; nothing new is queried.

**Tech Stack:** Rails 8 views (ERB), Tailwind 4 (rebuild CSS after new classes), Stimulus via importmap, RSpec system specs under Rack::Test with `:js` for the phone control.

**Spec:** `docs/decisions.md` §1 (guilt-free money) and §10 Home. Mockups: https://claude.ai/code/artifact/ad5e6778-ea57-4b95-82bd-de625b6d729c (Combined page).

## Global Constraints

- Present-tense vocabulary from `docs/decisions.md`: "guilt-free money" on screen, "claimed", "owed" for savings, "Adjust", "Transfer". Never "Whole category", never "free to spend".
- Kind order on screen is the order they hold on: **bill, savings, usage, choice** (`HomePresenter::KIND_ORDER`). Within a kind, rows keep `ClaimRows#give_way_order`.
- Coming up: at most `HomePresenter::UPCOMING_ROWS = 4` rows, short first then soonest; the footer always renders and links to `calendar_path`.
- Colours only from `custom.css` tokens and `HomeHelper::STRIPE_FILLS`; squared corners (`rounded`, never `rounded-lg`).
- Rack::Test by default; `:js` only for the segmented control and the 375px layout. No `sleep`.
- Run `bin/rails tailwindcss:build` after adding utility classes; `bundle exec rubocop -A` before each commit.

---

## File structure

| File | Responsibility |
| --- | --- |
| `app/presenters/home_presenter.rb` | Adds `KIND_ORDER`, `KIND_NAMES`, `KindColumn`, `ClaimedShare`, `columns`, `claimed_shares`, `rule_count`, `UPCOMING_ROWS`, `upcoming_shown`, `upcoming_hidden`, `upcoming_footer_words`. Removes `kinds_legend`. |
| `app/helpers/home_helper.rb` | `bar_fill` paints a normal bar in the kind's colour; new `card_context_words(line, rows)`; `kind_name(kind)`. |
| `app/views/home/index.html.erb` | Order: sum, trouble, upcoming, claimed. |
| `app/views/home/_sum.html.erb` (new) | The equation card and the savings aside. Replaces `_tiles.html.erb`. |
| `app/views/home/_upcoming.html.erb` | Capped rows plus the footer. |
| `app/views/home/_claimed.html.erb` (new) | Header, segmented control, four columns, unbudgeted rows, empty state. Replaces `_this_period.html.erb`. |
| `app/views/home/_rule_card.html.erb` (new) | One rule's card. |
| `app/views/home/_savings_card.html.erb` (new) | One targeted savings account's card. Replaces `_savings_block.html.erb`. |
| `app/javascript/controllers/app/home/kinds_controller.js` (new) | Segmented control below `lg`. |
| `spec/presenters/home_presenter_spec.rb` | Columns, shares, capped upcoming, footer words. |
| `spec/system/home/sum_spec.rb` (renamed from `tiles_spec.rb`) | What the sum card and savings aside say. |
| `spec/system/home/upcoming_spec.rb` | Order, cap, footer. |
| `spec/system/home/columns_spec.rb` (renamed from `sections_spec.rb`) | Four columns, headers, totals, empties, phone control. |
| `spec/system/home/cards_spec.rb` (renamed from `this_period_spec.rb`) | One card per shape, context words, bar colour, unbudgeted, empty state. |
| `spec/system/home/adjustments_spec.rb`, `navigation_spec.rb`, `trouble_spec.rb`, `spec/requests/adjustments_spec.rb`, `spec/requests/transfers_spec.rb`, `spec/system/sacrifices/show_spec.rb` | Selector renames only. |

Selector hooks (the contract between views and specs):

| Old | New |
| --- | --- |
| `[data-tiles]` | `[data-sum]` |
| `[data-tile='free'] [data-free]` | `[data-guilt-free]` |
| `[data-tile='savings']` | `[data-savings-aside]` |
| `[data-claimed-split]` | `[data-claimed-bar] [data-claimed-kind='bill']` … |
| `[data-this-period]` / `[data-budget-section]` / `[data-savings-section]` | `[data-claimed-section]` / `[data-kind-column='bill']` … `[data-kind-column='savings']` |
| `[data-category-block='Groceries']` | gone; cards are `[data-rule-row='All of Groceries']` inside a column |
| `[data-block-claimed]` | `[data-column-total]` on the column |
| `[data-savings-block='Emergency']` | `[data-savings-card='Emergency']` |
| `[data-block-owed]` | `[data-savings-owed]` on the card |
| `[data-rule-shape]` | `[data-rule-context]` (schedule, with the category when the name doesn't say it) |
| `[data-kinds-legend]` | gone |
| summary "Adjust what's owed now" | summary "Adjust" |

Unchanged: `[data-in-checking]`, `[data-spent-this-period]`, `[data-claimed]`, `[data-savings-total]`, `[data-savings-owed]`, `[data-upcoming]`, `[data-upcoming-row]`, `[data-upcoming-state]`, `[data-upcoming-words]`, `[data-rule-row]`, `[data-rule-figure]`, `[data-rule-when]`, `[data-rule-bar]`, `[data-rule-bar-state]`, `[data-adjust=…]`, `[data-rule-changes]`, `[data-change]`, `[data-unbudgeted-row]`, `[data-savings-figure]`, `[data-transfer-owed]`, everything under `[data-trouble]`.

---

### Task 1: Presenter — kind columns and claimed shares

**Files:**
- Modify: `app/presenters/home_presenter.rb`
- Test: `spec/presenters/home_presenter_spec.rb`

**Interfaces:**
- Produces: `HomePresenter::KIND_ORDER` (`[:bill, :savings, :usage, :choice]`), `HomePresenter::KIND_NAMES` (`{ bill: "Bills", savings: "Savings", usage: "Usage", choice: "Choice" }`), `HomePresenter::KindColumn` (`kind`, `rows`, `total`; `#name`, `#savings?`, `#count`, `#count_words`, `#empty?`), `HomePresenter::ClaimedShare` (`kind`, `amount`, `percent`), `#columns` (four `KindColumn`s in `KIND_ORDER`), `#claimed_shares` (four `ClaimedShare`s in `KIND_ORDER`), `#rule_count`. Removes `#kinds_legend`.
- Consumes: `ClaimRows#give_way_order` (ClaimLines, `#stripe_type`, `#claim`), `#savings_blocks` (SavingsLines, `#claim`), `#claimed`.

- [ ] **Step 1: Write the failing tests**

Replace the example `"carries one savings block per targeted account and the legend in give-way order"` in `spec/presenters/home_presenter_spec.rb` with these three:

```ruby
  it "reads four kind columns in the order they hold on, each with its rows and total", :aggregate_failures do
    create(:account, user: user, name: "Checking") unless user.main_account
    rule_on("Rent", :bill, amount: 900)
    rule_on("Fun", :choice, amount: 300)
    rule_on("Groceries", :usage, amount: 400)
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
    presenter = described_class.new(user: user, today: today)

    columns = presenter.columns
    expect(columns.map(&:kind)).to eq([:bill, :savings, :usage, :choice])
    expect(columns.map(&:name)).to eq(["Bills", "Savings", "Usage", "Choice"])
    expect(columns.map(&:total)).to eq([900, 200, 400, 300])
    expect(columns.map(&:count_words)).to eq(["1 rule", "1 account", "1 rule", "1 rule"])
    expect(columns.first.rows.map { |row| row.category.name }).to eq(["Rent"])
    expect(columns.second.rows.map(&:name)).to eq(["Emergency"])
    expect(columns.second).to be_savings
    expect(presenter.rule_count).to eq(3)
  end

  it "keeps an empty kind as an empty column and never a missing one", :aggregate_failures do
    rule_on("Rent", :bill, amount: 900)

    columns = presenter.columns
    expect(columns.size).to eq(4)
    expect(columns.map(&:empty?)).to eq([false, true, true, true])
    expect(columns.second.count_words).to eq("0 accounts")
  end

  it "splits claimed into four shares that sum to claimed, as rounded percents", :aggregate_failures do
    create(:account, user: user, name: "Checking") unless user.main_account
    rule_on("Rent", :bill, amount: 600)
    rule_on("Fun", :choice, amount: 200)
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
    presenter = described_class.new(user: user, today: today)

    shares = presenter.claimed_shares
    expect(shares.map(&:kind)).to eq([:bill, :savings, :usage, :choice])
    expect(shares.map(&:amount)).to eq([600, 200, 0, 200])
    expect(shares.map(&:percent)).to eq([60, 20, 0, 20])
    expect(shares.sum(0.to_d, &:amount)).to eq(presenter.claimed)
  end

  it "gives every share a zero percent when nothing is claimed" do
    expect(presenter.claimed_shares.map(&:percent)).to eq([0, 0, 0, 0])
  end
```

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/presenters/home_presenter_spec.rb`
Expected: 4 failures, `undefined method 'columns'` / `'claimed_shares'` / `'rule_count'`.

- [ ] **Step 3: Implement in the presenter**

In `app/presenters/home_presenter.rb`, after the `Upcoming` definition add:

```ruby
  # The order the kinds hold on in — a bill gives way last — which is the order Home lists them.
  KIND_ORDER = %i[bill savings usage choice].freeze
  KIND_NAMES = { bill: "Bills", savings: "Savings", usage: "Usage", choice: "Choice" }.freeze

  # One kind's column: ClaimLines for a rule kind, SavingsLines for savings, in give-way order.
  KindColumn = Data.define(:kind, :rows, :total) do
    def name = HomePresenter::KIND_NAMES.fetch(kind)
    def savings? = kind == :savings
    def count = rows.size
    def count_words = "#{count} #{(savings? ? "account" : "rule").pluralize(count)}"
    def empty? = rows.empty?
  end

  # One segment of the claimed bar. Percent is of claimed, so the four sum to about 100.
  ClaimedShare = Data.define(:kind, :amount, :percent)
```

Replace `def kinds_legend = ...` with:

```ruby
  # Four columns, always four: an empty kind renders as an empty column so the page keeps its shape.
  def columns
    @columns ||= KIND_ORDER.map do |kind|
      rows = kind == :savings ? savings_blocks : give_way_order.select { |line| line.stripe_type == kind }
      KindColumn.new(kind: kind, rows: rows, total: rows.sum(0.to_d, &:claim))
    end
  end

  def claimed_shares
    @claimed_shares ||= columns.map do |column|
      ClaimedShare.new(kind: column.kind, amount: column.total, percent: share_percent(column.total))
    end
  end

  def rule_count = blocks.sum(&:rule_count)
```

And in the private section:

```ruby
  def share_percent(amount)
    return 0 unless claimed.positive?

    ((amount / claimed) * 100).round.clamp(0, 100)
  end
```

- [ ] **Step 4: Run the presenter spec**

Run: `bundle exec rspec spec/presenters/home_presenter_spec.rb`
Expected: all pass (the `Tiles` and other examples untouched).

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A app/presenters/home_presenter.rb spec/presenters/home_presenter_spec.rb
git add app/presenters/home_presenter.rb spec/presenters/home_presenter_spec.rb docs/decisions.md
git commit -m "feat/home: four kind columns and the claimed bar's shares, off the ledger

docs/decisions: Home is the sum card, Coming up capped at four, and what's claimed by kind"
```

---

### Task 2: Presenter — Coming up sorted short-first, capped at four, with footer words

**Files:**
- Modify: `app/presenters/home_presenter.rb`
- Test: `spec/presenters/home_presenter_spec.rb`

**Interfaces:**
- Produces: `HomePresenter::UPCOMING_ROWS = 4`, `#upcoming` (now short first, then due date, then name), `#upcoming_shown` (first four), `#upcoming_hidden` (the rest), `#upcoming_footer_words` (String).
- Consumes: `Upcoming#short?`, `#ready?`, `#building?`, `#due_on`, `#name`; `UPCOMING_DAYS`.

- [ ] **Step 1: Write the failing tests**

Replace the example `"lists dated rules due within 30 days with their state, soonest first"` with:

```ruby
  it "lists dated rules due within 30 days, anything short first and then soonest", :aggregate_failures do
    create(:account, user: user, name: "Checking", opening_balance: 5_000) unless user.main_account
    rule_on("Dentist", :bill, amount: 300, anchor_date: Date.new(2026, 9, 12), starts_on: Date.new(2026, 8, 1))
    rule_on("Vet", :bill, amount: 180, anchor_date: Date.new(2026, 10, 1), starts_on: Date.new(2026, 9, 4))
    rule_on("Insurance", :bill, amount: 1_200, anchor_date: Date.new(2026, 12, 1), starts_on: Date.new(2026, 9, 4))
    rent = rule_on("Rent", :bill, amount: 900, anchor_date: Date.new(2026, 9, 12), starts_on: Date.new(2026, 9, 4))
    create(:entry, item: create(:item, category: rent.category), amount: 200, date: Date.new(2026, 9, 6))
    presenter = described_class.new(user: user, today: today)

    expect(presenter.upcoming.map { |u| [u.name, u.due_on, u.state] })
      .to eq([["Rent", Date.new(2026, 9, 12), :short], ["Dentist", Date.new(2026, 9, 12), :ready], ["Vet", Date.new(2026, 10, 1), :building]])
    expect(presenter.upcoming_shown.size).to eq(3)
    expect(presenter.upcoming_hidden).to be_empty
    expect(presenter.upcoming_footer_words).to eq("3 due in the next 30 days")
    expect(presenter.day_words).to eq("Wednesday, September 9")
    expect(presenter.period_words).to eq("Day 6 of 14 in this period · next payday Sep 18")
  end

  it "shows four and counts the rest by state", :aggregate_failures do
    create(:account, user: user, name: "Checking", opening_balance: 50_000) unless user.main_account
    %w[Water Internet Phone Gym Trash Gas].each_with_index do |name, index|
      rule_on(name, :bill, amount: 100, anchor_date: Date.new(2026, 9, 12 + index), starts_on: Date.new(2026, 8, 1))
    end
    rule_on("Tuition", :bill, amount: 2_000, anchor_date: Date.new(2026, 10, 5), starts_on: Date.new(2026, 9, 4))
    presenter = described_class.new(user: user, today: today)

    expect(presenter.upcoming_shown.map(&:name)).to eq(%w[Water Internet Phone Gym])
    expect(presenter.upcoming_hidden.map(&:name)).to eq(%w[Trash Gas Tuition])
    expect(presenter.upcoming_footer_words).to eq("3 more by Oct 9 · 2 ready · 1 still building")
  end
```

- [ ] **Step 2: Run to see them fail**

Run: `bundle exec rspec spec/presenters/home_presenter_spec.rb`
Expected: 2 failures — the first on order (Dentist before Rent), the second on `undefined method 'upcoming_shown'`.

- [ ] **Step 3: Implement**

In `app/presenters/home_presenter.rb`, change the constant line and `#upcoming`, and add the three readers:

```ruby
  UPCOMING_DAYS = 30
  UPCOMING_ROWS = 4
```

```ruby
  # Dated rules due from today through UPCOMING_DAYS: anything short first, then soonest, each with
  # where its money stands.
  def upcoming
    @upcoming ||= upcoming_lines
      .map { |line| Upcoming.new(line: line, state: upcoming_state(line)) }
      .sort_by { |row| [row.short? ? 0 : 1, row.due_on, row.name] }
  end

  def upcoming_shown = upcoming.first(UPCOMING_ROWS)
  def upcoming_hidden = upcoming.drop(UPCOMING_ROWS)

  # "3 due in the next 30 days", or past the cap "3 more by Oct 9 · 2 ready · 1 still building".
  def upcoming_footer_words
    return "#{upcoming.size} due in the next #{UPCOMING_DAYS} days" if upcoming_hidden.empty?

    [
      "#{upcoming_hidden.size} more by #{(today + UPCOMING_DAYS).strftime("%b %-d")}",
      *hidden_state_counts.map { |words, count| "#{count} #{words}" }
    ].join(" · ")
  end
```

Private:

```ruby
  # Only the states that are there, in the order ready, still building, short.
  def hidden_state_counts
    { "ready" => upcoming_hidden.count(&:ready?), "still building" => upcoming_hidden.count(&:building?), "short" => upcoming_hidden.count(&:short?) }
      .select { |_, count| count.positive? }
  end
```

- [ ] **Step 4: Run the presenter spec**

Run: `bundle exec rspec spec/presenters/home_presenter_spec.rb`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A app/presenters/home_presenter.rb spec/presenters/home_presenter_spec.rb
git add app/presenters/home_presenter.rb spec/presenters/home_presenter_spec.rb
git commit -m "feat/home: coming up puts anything short first, shows four, and counts the rest"
```

---

### Task 3: Helper — bars in the kind's colour, card context words

**Files:**
- Modify: `app/helpers/home_helper.rb`
- Test: `spec/helpers/home_helper_spec.rb` (create if absent; check `ls spec/helpers` first)

**Interfaces:**
- Produces: `bar_fill(line)` returns the kind's fill class for a `:normal` bar (`bg-brand-dark` for bill, `bg-dusty-teal` usage, `bg-terracotta` choice) and the status class otherwise; `card_context_words(line, rows)` — `"Pet Care · once, Oct 1"` for an item rule, `"a period"` for an item-less one; `kind_name(kind)` → `HomePresenter::KIND_NAMES`.
- Consumes: `ClaimLine#bar_state`, `#stripe_type`, `#rule.item`, `#category.name`; existing `shape_schedule_words(line)`.

- [ ] **Step 1: Write the failing test**

Create `spec/helpers/home_helper_spec.rb` (if one exists, add these examples to it):

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe HomeHelper do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }

  before { create(:account, user: user, name: "Checking", opening_balance: 5_000) }

  def line_for(rule) = ClaimRows.new(ledger: ClaimLedger.new(user, today: today)).lines_for(rule.category).first

  it "paints a normal bar in the kind's colour and a full one in the status colour", :aggregate_failures do
    usage = create(:rule, :rate, :usage, amount: 400, starts_on: Date.new(2026, 1, 1), category: create(:category, user: user, name: "Groceries"))
    bill = create(:rule, :bill, amount: 300, anchor_date: Date.new(2026, 9, 12), starts_on: Date.new(2026, 8, 1), category: create(:category, user: user, name: "Dentist"))

    expect(helper.bar_fill(line_for(usage))).to eq("bg-dusty-teal")
    expect(helper.bar_fill(line_for(bill))).to eq("bg-status-success")
  end

  it "says a card's context: the category only when the lane's name does not", :aggregate_failures do
    pets = create(:category, user: user, name: "Pet Care")
    vet = create(:rule, :bill, amount: 180, anchor_date: Date.new(2026, 10, 1), starts_on: Date.new(2026, 9, 4), category: pets, item: create(:item, category: pets, name: "Vet"))
    rest = create(:rule, :rate, amount: 60, starts_on: Date.new(2026, 1, 1), category: pets)
    rows = ClaimRows.new(ledger: ClaimLedger.new(user, today: today)).lines_for(pets)

    expect(helper.card_context_words(rows.find { |row| row.rule == vet }, rows)).to eq("Pet Care · once, Oct 1")
    expect(helper.card_context_words(rows.find { |row| row.rule == rest }, rows)).to eq("a period")
    expect(helper.kind_name(:bill)).to eq("Bills")
  end
end
```

- [ ] **Step 2: Run to see it fail**

Run: `bundle exec rspec spec/helpers/home_helper_spec.rb`
Expected: fails on `bar_fill` returning `"bg-brand"` and `undefined method 'card_context_words'`.

- [ ] **Step 3: Implement**

In `app/helpers/home_helper.rb`, replace `BAR_FILLS`/`bar_fill` with:

```ruby
  # What the bar says in colour. A normal bar wears its kind, so a column reads as one thing; the
  # three states that are news keep their status colours. The state is ClaimLine#bar_state.
  STATE_FILLS = { full: "bg-status-success", over: "bg-status-danger", short: "bg-status-danger" }.freeze

  def bar_fill(line) = STATE_FILLS.fetch(line.bar_state) { type_fill(line.stripe_type) }
```

Add:

```ruby
  def kind_name(kind) = HomePresenter::KIND_NAMES.fetch(kind.to_sym)

  # A card's second line. The kind is the column and the lane is the first line, so what is left is
  # the schedule — and the category, only when the lane is an item that doesn't name it.
  def card_context_words(line, rows)
    [(line.category.name if line.rule.item.present?), shape_schedule_words(line)].compact.join(" · ")
  end
```

(`rows` is accepted for symmetry with `lane_words(line, rows)` and so a caller can pass the column's rows without thinking; it is unused. If rubocop flags it, name it `_rows`.)

- [ ] **Step 4: Run helper and presenter specs**

Run: `bundle exec rspec spec/helpers/home_helper_spec.rb spec/presenters/home_presenter_spec.rb`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A app/helpers/home_helper.rb spec/helpers/home_helper_spec.rb
git add app/helpers/home_helper.rb spec/helpers/home_helper_spec.rb
git commit -m "feat/home: a normal bar wears its kind, and a card says its category only when its name doesn't"
```

---

### Task 4: The sum card and the savings aside

**Files:**
- Create: `app/views/home/_sum.html.erb`
- Delete: `app/views/home/_tiles.html.erb`
- Modify: `app/views/home/index.html.erb`
- Rename + rewrite: `spec/system/home/tiles_spec.rb` → `spec/system/home/sum_spec.rb`
- Modify (selector only): `spec/system/home/navigation_spec.rb:20`, `spec/system/home/trouble_spec.rb:51`, `spec/requests/adjustments_spec.rb:29,66`, `spec/requests/transfers_spec.rb:40`, `spec/system/sacrifices/show_spec.rb:281,292`

**Interfaces:**
- Consumes: `presenter.tiles` (`checking`, `spent_this_period`, `claimed`, `free`, `savings_total`, `savings_owed`, `savings_count`), `presenter.claimed_shares`, `kind_name`, `type_fill`, `savings_path`.
- Produces hooks: `[data-sum]`, `[data-in-checking]`, `[data-spent-this-period]`, `[data-claimed]`, `[data-claimed-bar]`, `[data-claimed-kind='bill'][data-claimed-percent='60']`, `[data-guilt-free]`, `[data-savings-aside]`, `[data-savings-total]`, `[data-savings-owed]`.

- [ ] **Step 1: Write the failing system spec**

`git mv spec/system/home/tiles_spec.rb spec/system/home/sum_spec.rb`, then replace its contents:

```ruby
# frozen_string_literal: true

require "rails_helper"

# THE SUM — Home's first answer, as one card: in checking, minus claimed with its bar split by
# kind, equals guilt-free money. In savings stands beside the card and outside it. The arithmetic
# is `spec/presenters/home_presenter_spec.rb`'s; what is measured here is what the card says.
RSpec.describe "Home sum", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }

  before do
    create(:account, user: user, name: "Checking", opening_balance: 1_000)
    sign_in user, scope: :user
  end

  def rule_for(name, rate:, **attributes)
    create(:rule, :rate, amount: rate, starts_on: Date.new(2026, 1, 1), category: create(:category, user: user, name: name), **attributes)
  end

  def read_home = travel_to(today) { visit root_path }

  def seed!
    rule_for("Groceries", rate: 400)
    rule_for("Rent", rate: 200, rule_type: :bill)
    emergency = create(:account, user: user, name: "Emergency", opening_balance: 500)
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
    create(:entry, item: create(:item, category: create(:category, user: user, name: "Fuel")), amount: 25, date: today)
  end

  it "reads checking minus claimed equals guilt-free money, with the bar split by kind", :aggregate_failures do
    seed!

    read_home

    expect(page).to have_css("h1", text: "Wednesday, September 9")
    expect(page).to have_content("Day 6 of 14 in this period · next payday Sep 18")
    within("[data-sum]") do
      expect(page).to have_css("[data-in-checking]", text: "$975.00")
      expect(page).to have_css("[data-spent-this-period]", text: "spent $25.00 this period")
      expect(page).to have_css("[data-claimed]", text: "$800.00")
      expect(page).to have_css("[data-claimed-bar] [data-claimed-kind='bill'][data-claimed-percent='25']")
      expect(page).to have_css("[data-claimed-bar] [data-claimed-kind='savings'][data-claimed-percent='25']")
      expect(page).to have_css("[data-claimed-bar] [data-claimed-kind='usage'][data-claimed-percent='50']")
      expect(page).to have_css("[data-claimed-bar] [data-claimed-kind='choice'][data-claimed-percent='0']")
      expect(page).to have_content("Bills $200.00")
      expect(page).to have_content("Usage $400.00")
      expect(page).to have_css("[data-guilt-free]", text: "$175.00")
      expect(page).to have_content("Guilt-free money")
      expect(page).to have_content("what's left in checking once everything claimed is set aside")
      expect(page).to have_no_content("Free to spend")
    end
  end

  it "keeps savings beside the sum, outside it, with what is owed and a door to Savings", :aggregate_failures do
    seed!

    read_home

    within("[data-savings-aside]") do
      expect(page).to have_css("[data-savings-total]", text: "$500.00")
      expect(page).to have_content("1 account · owed")
      expect(page).to have_css("[data-savings-owed]", text: "$200.00")
      expect(page).to have_link("Savings", href: savings_path)
    end
    expect(page).to have_no_css("[data-sum] [data-savings-aside]")
  end

  it "reddens guilt-free money below zero" do
    rule_for("Rent", rate: 1_500, rule_type: :bill)
    read_home
    expect(page).to have_css("[data-guilt-free].text-status-danger", text: "-$500.00")
  end

  # A user with no cadence has no period, so `spent this period` would state one as fact — the
  # header already says there is none.
  it "has no spent-this-period line for a user who has declared no cadence", :aggregate_failures do
    undeclared = create(:user)
    create(:account, user: undeclared, name: "Checking", opening_balance: 1_000)
    sign_in undeclared, scope: :user

    visit root_path

    expect(page).to have_content("No period set yet")
    expect(page).to have_no_css("[data-spent-this-period]")
  end
end
```

Then the selector-only edits:
- `spec/system/home/navigation_spec.rb:20`: `expect(page).to have_css("[data-sum] [data-guilt-free]")`
- `spec/system/home/trouble_spec.rb:51`: `expect(page).to have_css("[data-guilt-free]", text: "$600.00")`
- `spec/requests/adjustments_spec.rb:29,66`, `spec/requests/transfers_spec.rb:40`: `include("data-sum")`
- `spec/system/sacrifices/show_spec.rb:281,292`: `have_css("[data-sum]")`

- [ ] **Step 2: Run to see it fail**

Run: `bundle exec rspec spec/system/home/sum_spec.rb`
Expected: fails, no `[data-sum]`.

- [ ] **Step 3: Write the partial**

`app/views/home/_sum.html.erb`:

```erb
<%# THE SUM, as one card: in checking − claimed = guilt-free money. Local: `presenter`. In savings
    stands beside the card and outside it — it is not in the sum, and the card's edge says so. %>
<% tiles = presenter.tiles %>
<div class="grid grid-cols-1 gap-4 lg:grid-cols-[minmax(0,1fr)_220px] lg:gap-8 lg:items-stretch">
  <div class="bg-white border border-gray-200 rounded overflow-hidden grid grid-cols-1 lg:grid-cols-[200px_28px_minmax(0,1fr)_28px_270px] lg:items-stretch" data-sum>
    <div class="p-4 lg:p-5">
      <p class="text-xs font-medium uppercase tracking-wide text-gray-500">In checking</p>
      <p class="mt-1 text-xl font-semibold tabular-nums <%= tiles.checking.negative? ? "text-status-danger" : "text-gray-900" %>" data-in-checking>
        <%= number_to_currency(tiles.checking) %>
      </p>
      <% unless tiles.spent_this_period.nil? %>
        <p class="mt-1 text-xs text-gray-500" data-spent-this-period>spent <%= number_to_currency(tiles.spent_this_period) %> this period</p>
      <% end %>
    </div>

    <%# On a phone the operator sits on a divider between the stacked cells; on desktop it stands
        between the columns. `aria-hidden`, because the labels already say what the sum is. %>
    <div class="flex items-center gap-3 px-4 lg:px-0 lg:justify-center" aria-hidden="true">
      <span class="h-px flex-1 bg-gray-200 lg:hidden"></span>
      <span class="text-2xl leading-none text-gray-400">−</span>
      <span class="h-px flex-1 bg-gray-200 lg:hidden"></span>
    </div>

    <div class="px-4 pb-4 pt-3 lg:p-5 flex flex-col justify-center gap-2">
      <div class="flex items-baseline gap-2.5">
        <p class="text-xs font-medium uppercase tracking-wide text-gray-500">Claimed</p>
        <span class="text-xl font-semibold tabular-nums text-gray-900" data-claimed><%= number_to_currency(tiles.claimed) %></span>
      </div>
      <div class="flex h-2 gap-0.5 rounded-sm overflow-hidden" data-claimed-bar role="img" aria-label="Claimed, split by kind">
        <% presenter.claimed_shares.each do |share| %>
          <div class="h-2 <%= type_fill(share.kind) %>" style="width: <%= share.percent %>%;"
               data-claimed-kind="<%= share.kind %>" data-claimed-percent="<%= share.percent %>"></div>
        <% end %>
      </div>
      <div class="grid grid-cols-2 gap-x-3 gap-y-0.5">
        <% presenter.claimed_shares.each do |share| %>
          <p class="flex items-center gap-1.5 text-xs">
            <span class="h-2 w-2 rounded-sm <%= type_fill(share.kind) %>" aria-hidden="true"></span>
            <span class="font-semibold <%= TYPE_TEXT.fetch(share.kind) %>"><%= kind_name(share.kind) %></span>
            <span class="tabular-nums text-gray-900"><%= number_to_currency(share.amount) %></span>
          </p>
        <% end %>
      </div>
    </div>

    <div class="flex items-center gap-3 px-4 lg:px-0 lg:justify-center" aria-hidden="true">
      <span class="h-px flex-1 bg-gray-200 lg:hidden"></span>
      <span class="text-2xl leading-none text-gray-400">=</span>
      <span class="h-px flex-1 bg-gray-200 lg:hidden"></span>
    </div>

    <div class="p-4 lg:p-5 bg-brand-light border-t border-brand lg:border-t-0 lg:border-l flex flex-col justify-center">
      <p class="text-xs font-medium uppercase tracking-wide text-gray-600">Guilt-free money</p>
      <p class="mt-1 text-3xl font-semibold tabular-nums <%= tiles.free.negative? ? "text-status-danger" : "text-gray-900" %>" data-guilt-free>
        <%= number_to_currency(tiles.free) %>
      </p>
      <p class="mt-1 text-xs text-gray-600">what's left in checking once everything claimed is set aside</p>
    </div>
  </div>

  <div class="border border-dashed border-gray-300 rounded p-4 lg:p-5 flex flex-col justify-center" data-savings-aside>
    <p class="text-xs font-medium uppercase tracking-wide text-gray-500">In savings</p>
    <p class="mt-1 text-xl font-semibold tabular-nums text-gray-900" data-savings-total><%= number_to_currency(tiles.savings_total) %></p>
    <p class="mt-1 text-xs text-gray-500">
      <%= pluralize(tiles.savings_count, "account") %> · owed <span class="tabular-nums" data-savings-owed><%= number_to_currency(tiles.savings_owed) %></span>
      · <%= link_to "Savings", savings_path, class: "text-brand-dark hover:text-brand underline" %>
    </p>
  </div>
</div>
```

Note `TYPE_TEXT` is a `HomeHelper` constant; in ERB write `HomeHelper::TYPE_TEXT.fetch(share.kind)` or add `def type_text(kind) = TYPE_TEXT.fetch(kind.to_sym)` to the helper and call that. Add the helper method (preferred).

`app/views/home/index.html.erb` — replace `render "home/tiles"` with `render "home/sum", presenter: @presenter`. Delete `app/views/home/_tiles.html.erb` (`git rm`).

- [ ] **Step 4: Rebuild CSS and run**

Run: `bin/rails tailwindcss:build && bundle exec rspec spec/system/home/sum_spec.rb spec/system/home/navigation_spec.rb spec/system/home/trouble_spec.rb spec/requests/adjustments_spec.rb spec/requests/transfers_spec.rb spec/system/sacrifices/show_spec.rb`
Expected: pass. (`this_period_spec`, `sections_spec`, `upcoming_spec` still pass because their partials are untouched.)

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A
git add -A app/views/home app/helpers/home_helper.rb spec app/assets/builds
git commit -m "feat/home: the sum is one card — in checking, minus claimed by kind, equals guilt-free money — and savings stands beside it"
```

(Check whether `app/assets/builds` is gitignored before adding it; if it is, leave it out.)

---

### Task 5: Coming up — four rows and the footer

**Files:**
- Modify: `app/views/home/_upcoming.html.erb`
- Modify: `spec/system/home/upcoming_spec.rb`

**Interfaces:**
- Consumes: `presenter.upcoming_shown`, `#upcoming_footer_words`, `presenter.upcoming.any?`, `calendar_path`.
- Produces hooks: `[data-upcoming-footer]`, `[data-upcoming-rows]`; rows unchanged.

- [ ] **Step 1: Write the failing spec**

In `spec/system/home/upcoming_spec.rb`, change the first example's expectations and add one:

```ruby
  it "lists what is due within 30 days, anything short first, then soonest, with a door to Calendar", :aggregate_failures do
    seed_upcoming!

    read_home

    within("[data-upcoming]") do
      expect(all("[data-upcoming-row]").pluck("data-upcoming-row")).to eq(["Rent", "Dentist", "Vet"])
      expect(page).to have_css("[data-upcoming-row='Dentist'][data-upcoming-state='ready']", text: "Ready — it's all there")
      expect(page).to have_css("[data-upcoming-row='Rent'][data-upcoming-state='short']", text: "short")
      expect(page).to have_css("[data-upcoming-row='Vet'][data-upcoming-state='building']", text: "set aside")
      expect(page).to have_no_css("[data-upcoming-row='Insurance']")
      expect(page).to have_css("[data-upcoming-footer]", text: "3 due in the next 30 days")
      expect(page).to have_link("See them all on Calendar", href: calendar_path)
    end
  end

  # Past four, the rest are a count by state rather than rows; the door to Calendar stays.
  it "shows four rows and counts the rest", :aggregate_failures do
    %w[Water Internet Phone Gym Trash Gas].each_with_index do |name, index|
      dated(name, 100, Date.new(2026, 9, 12 + index), starts_on: Date.new(2026, 8, 1))
    end

    read_home

    within("[data-upcoming]") do
      expect(all("[data-upcoming-row]").pluck("data-upcoming-row")).to eq(%w[Water Internet Phone Gym])
      expect(page).to have_css("[data-upcoming-footer]", text: "2 more by Oct 9 · 2 ready")
      expect(page).to have_link("See them all on Calendar", href: calendar_path)
    end
  end
```

- [ ] **Step 2: Run to see it fail**

Run: `bundle exec rspec spec/system/home/upcoming_spec.rb`
Expected: 2 failures (order; no footer).

- [ ] **Step 3: Rewrite the partial**

`app/views/home/_upcoming.html.erb`:

```erb
<%# COMING UP — dated rules due in the next 30 days: anything short first, then the soonest, at most
    UPCOMING_ROWS of them. The footer always counts and always opens Calendar; past the cap it counts
    the rest by state. Local: `presenter`. Absent when nothing is due, rather than an empty card. %>
<% if presenter.upcoming.any? %>
  <section class="bg-white border border-gray-200 rounded overflow-hidden" data-upcoming aria-labelledby="upcoming-heading">
    <div class="flex items-baseline justify-between gap-3 px-4 py-3 lg:px-5">
      <h3 id="upcoming-heading" class="text-sm font-semibold text-gray-900">Coming up</h3>
      <p class="text-xs text-gray-500">the next <%= HomePresenter::UPCOMING_DAYS %> days</p>
    </div>
    <ul class="divide-y divide-gray-100 border-t border-gray-100" data-upcoming-rows>
      <% presenter.upcoming_shown.each do |row| %>
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
    <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1 px-4 py-2.5 border-t border-gray-200 bg-gray-50 text-sm text-gray-600 lg:px-5" data-upcoming-footer>
      <span><%= presenter.upcoming_footer_words %></span>
      <%= link_to "See them all on Calendar", calendar_path, class: "text-brand-dark hover:text-brand underline" %>
    </div>
  </section>
<% end %>
```

- [ ] **Step 4: Run**

Run: `bin/rails tailwindcss:build && bundle exec rspec spec/system/home/upcoming_spec.rb`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A
git add -A app/views/home/_upcoming.html.erb spec/system/home/upcoming_spec.rb
git commit -m "feat/home: coming up shows four, short first, and always opens Calendar"
```

---

### Task 6: What's claimed — four columns of cards

**Files:**
- Create: `app/views/home/_claimed.html.erb`, `app/views/home/_rule_card.html.erb`, `app/views/home/_savings_card.html.erb`
- Delete: `app/views/home/_this_period.html.erb`, `app/views/home/_savings_block.html.erb`
- Modify: `app/views/home/index.html.erb`, `app/views/home/_adjust.html.erb` (summary text)
- Rename + rewrite: `spec/system/home/sections_spec.rb` → `spec/system/home/columns_spec.rb`; `spec/system/home/this_period_spec.rb` → `spec/system/home/cards_spec.rb`
- Modify (selectors): `spec/system/home/adjustments_spec.rb`

**Interfaces:**
- Consumes: `presenter.columns` (`KindColumn#kind/#name/#rows/#total/#savings?/#count_words/#empty?`), `presenter.rule_count`, `presenter.savings_blocks.size`, `presenter.unbudgeted_rows`, helpers `lane_words`, `card_context_words`, `figure_words`, `when_words`, `bar_fill`, `type_fill`, `type_text(kind)`, `rule_action_classes`, `spending_rule_path`, `transfers_path`, `adjustment_path`, and `render "home/adjust"`, `render "savings/adjust"`.
- Produces hooks per the table at the top. The segmented control markup is laid down here (static, hidden at `lg`) and wired in Task 7.

- [ ] **Step 1: Write the failing specs**

`git mv spec/system/home/sections_spec.rb spec/system/home/columns_spec.rb` and replace its contents:

```ruby
# frozen_string_literal: true

require "rails_helper"

# "WHAT'S CLAIMED" — four columns in the order they hold on: Bills, Savings, Usage, Choice. Each
# is headed by its kind, its count and its total, and holds one card per rule or targeted account.
# The grid is biweekly anchored 2026-02-06, so the period containing Sep 9 is Sep 4 – Sep 17.
RSpec.describe "Home columns", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }

  before do
    create(:account, user: user, name: "Checking", opening_balance: 5_000)
    sign_in user, scope: :user
  end

  def read_home = travel_to(today) { visit root_path }

  def rule_for(name, rate:, **attributes) = create(:rule, :rate, amount: rate, starts_on: Date.new(2026, 1, 1), category: create(:category, user: user, name: name), **attributes)

  def savings_for(name, amount:) = create(:savings_target, account: create(:account, user: user, name: name), amount: amount, starts_on: Date.new(2026, 9, 4))

  def column(kind) = find("[data-kind-column='#{kind}']")

  it "lays the four kinds out in the order they hold on, each with its count and total", :aggregate_failures do
    rule_for("Rent", rate: 900, rule_type: :bill)
    rule_for("Groceries", rate: 400)
    rule_for("Fun", rate: 300, rule_type: :choice)
    savings_for("Emergency", amount: 200)

    read_home

    within("[data-claimed-section]") do
      expect(page).to have_content("What's claimed · 3 rules · 1 savings account")
      expect(all("[data-kind-column]").pluck("data-kind-column")).to eq(%w[bill savings usage choice])
    end
    expect(column("bill")).to have_content("Bills 1 rule")
    expect(column("bill")).to have_css("[data-column-total]", text: "$900.00")
    expect(column("bill")).to have_css("[data-rule-row='All of Rent']")
    expect(column("savings")).to have_content("Savings 1 account")
    expect(column("savings")).to have_css("[data-column-total]", text: "$200.00")
    expect(column("savings")).to have_css("[data-savings-card='Emergency']")
    expect(column("usage")).to have_css("[data-rule-row='All of Groceries']")
    expect(column("choice")).to have_css("[data-rule-row='All of Fun']")
    expect(page).to have_no_css("[data-kinds-legend]")
  end

  # An empty kind keeps its column, so the page keeps its shape and the absence is readable.
  it "keeps an empty kind as a column that says so", :aggregate_failures do
    rule_for("Groceries", rate: 400)

    read_home

    expect(column("bill")).to have_content("Bills 0 rules")
    expect(column("bill")).to have_content("Nothing yet")
    expect(column("savings")).to have_content("Savings 0 accounts")
    expect(column("savings")).to have_content("Nothing yet")
  end

  # Within a kind the cards keep give-way order, the only sort on the screen.
  it "orders the cards inside a column by give-way order" do
    rule_for("Rent", rate: 900, rule_type: :bill)
    rule_for("Loan", rate: 100, rule_type: :bill)

    read_home

    expect(column("bill").all("[data-rule-row]").pluck("data-rule-row")).to eq(["All of Loan", "All of Rent"])
  end

  it "names an item-less rule by what it covers", :aggregate_failures do
    groceries = create(:category, user: user, name: "Groceries")
    create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1))
    pets = create(:category, user: user, name: "Pets")
    create(:rule, :rate, amount: 60, category: pets, starts_on: Date.new(2026, 1, 1))
    create(:rule, :rate, amount: 40, category: pets, item: create(:item, category: pets, name: "Vet"), starts_on: Date.new(2026, 1, 1))

    read_home

    expect(column("usage")).to have_css("[data-rule-row='All of Groceries']")
    expect(column("usage")).to have_css("[data-rule-row='Everything else in Pets']")
    expect(column("usage")).to have_css("[data-rule-row='Vet'] [data-rule-context]", text: "Pets · a period")
    expect(page).to have_no_content("Whole category")
    expect(page).to have_no_css("[aria-label*='Whole category']")
  end
end
```

(The "Loan before Rent" ordering assumes both categories have equal priority, so the within-category key — amount — decides; check `Rule.sort_key` and adjust the expectation if it sorts differently. The point is that the column order is `give_way_order` filtered, not name order.)

`git mv spec/system/home/this_period_spec.rb spec/system/home/cards_spec.rb` and rewrite it — same fixtures and helpers as today's file, but `block(name)` becomes `card(name)`:

```ruby
  def card(lane) = find("[data-rule-row='#{lane}']")
```

and each example changes as follows:

- rate rule: `within(card("All of Groceries"))`; `[data-rule-context]` text `"a period"` (was `[data-rule-shape]` "usage · a period"); the `[data-block-claimed]` line becomes `expect(find("[data-kind-column='usage'] [data-column-total]")).to have_content("$100.00")`; add `expect(page).to have_css("[data-rule-bar].bg-dusty-teal, [data-rule-fill].bg-dusty-teal", visible: :all)` — the fill carries the kind colour.
- dated rule: `within(card("All of Dentist"))`; context `"once, Sep 12"`.
- fund: `within(card("All of Books"))`; context `"a period, keeps"`.
- capped fund: `within(card("All of Pantry"))`.
- overspent: the card reddens the figure — `expect(card("All of Groceries")).to have_css("[data-rule-figure].text-status-danger")`; and the card wears a danger border: `expect(card("All of Groceries")).to have_css("[data-rule-card].border-status-danger")` — wait, `card()` finds the row; make the hook `data-rule-card` sit on the same element as `data-rule-row` (see partial below) and assert `expect(page).to have_css("[data-rule-row='All of Groceries'].border-status-danger")`.
- give-way order example becomes: `expect(all("[data-kind-column]").pluck("data-kind-column")).to eq(%w[bill savings usage choice])` and `expect(page).to have_css("[data-claimed-section]", text: "$1,200.00")` is dropped (the total lives in the sum card now, tested in sum_spec). Delete this example — columns_spec covers order.
- unbudgeted row and empty-state examples: unchanged text.
- `:js` entries example: `within(card("All of Groceries")) { find("[data-rule-figure]").click }`.
- the legend + savings block example becomes:

```ruby
  it "carries a savings card with what is owed, a transfer and an adjust", :aggregate_failures do
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
    read_home

    within("[data-savings-card='Emergency']") do
      expect(page).to have_content("$200.00 a period · keeps extra")
      expect(page).to have_css("[data-savings-owed]", text: "$200.00 owed")
      expect(page).to have_css("[data-savings-figure]", text: "$200.00 owed this period")
      expect(page).to have_button("Transfer $200.00")
      expect(page).to have_css("[data-adjust='Emergency']")
    end
  end
```

(Confirm `mode_words` for a fresh account — `keeps_extra?` default — and adjust the expected string to what the factory produces.)

- frame src example: `within(card("All of Groceries"))`.

`spec/system/home/adjustments_spec.rb`: line 54 `def claimed = find("[data-kind-column='usage'] [data-column-total]")`; lines 141 and 171 `[data-savings-card='Emergency']`. Check every `claimed` assertion still reads a "$X" figure (the column total prints `$450.00` without the word "claimed" — update expected strings accordingly, e.g. `have_content("$450.00")`).

- [ ] **Step 2: Run to see them fail**

Run: `bundle exec rspec spec/system/home/columns_spec.rb spec/system/home/cards_spec.rb`
Expected: fail, no `[data-kind-column]`.

- [ ] **Step 3: Write the partials**

`app/views/home/_claimed.html.erb`:

```erb
<%# "WHAT'S CLAIMED" — four columns in the order they hold on, one card per rule or targeted
    account. Local: `presenter`. The kind is the column, so a card never repeats it. Below `lg` the
    columns become a segmented control, one kind at a time (controllers/app/home/kinds). %>
<section data-claimed-section data-controller="app--home--kinds">
  <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1 pb-3">
    <h3 class="text-sm font-semibold text-gray-900">
      What's claimed <span class="font-normal text-gray-500">· <%= pluralize(presenter.rule_count, "rule") %> · <%= pluralize(presenter.savings_blocks.size, "savings account") %></span>
    </h3>
    <p class="hidden text-xs text-gray-500 lg:block">Adjust changes what's owed now; the rule itself lives on the Budget page</p>
  </div>

  <%# The phone's control: one tab per kind, each carrying its total. Hidden from `lg` up, where
      every column shows. `aria-selected` and the columns' `hidden` are the controller's to move. %>
  <div class="grid grid-cols-4 gap-0.5 rounded bg-gray-200 p-0.5 mb-3 lg:hidden" role="tablist" data-kinds-tabs>
    <% presenter.columns.each_with_index do |column, index| %>
      <button type="button" role="tab" aria-selected="<%= index.zero? %>" aria-controls="kind-<%= column.kind %>"
              class="flex h-11 flex-col items-center justify-center gap-0.5 rounded-sm text-xs font-semibold text-gray-600 aria-selected:bg-white aria-selected:text-gray-900 aria-selected:shadow-sm"
              data-kinds-target="tab" data-action="app--home--kinds#pick" data-kind="<%= column.kind %>">
        <span class="flex items-center gap-1.5"><span class="h-2 w-2 rounded-sm <%= type_fill(column.kind) %>" aria-hidden="true"></span><%= column.name %></span>
        <span class="text-[11px] font-normal text-gray-500 tabular-nums"><%= number_to_currency(column.total) %></span>
      </button>
    <% end %>
  </div>

  <div class="grid grid-cols-1 gap-4 lg:grid-cols-4 lg:items-start">
    <% presenter.columns.each_with_index do |column, index| %>
      <div id="kind-<%= column.kind %>" role="tabpanel" class="<%= "hidden" unless index.zero? %> lg:block rounded bg-gray-100 p-3 space-y-2.5"
           data-kind-column="<%= column.kind %>" data-kinds-target="column">
        <div class="flex items-baseline justify-between gap-2 px-0.5 pb-0.5">
          <p class="flex items-center gap-2 text-sm">
            <span class="h-2.5 w-2.5 rounded-sm <%= type_fill(column.kind) %>" aria-hidden="true"></span>
            <span class="font-semibold <%= type_text(column.kind) %>"><%= column.name %></span>
            <span class="text-xs text-gray-500"><%= column.count_words %></span>
          </p>
          <span class="text-sm tabular-nums text-gray-700" data-column-total><%= number_to_currency(column.total) %></span>
        </div>

        <% if column.empty? %>
          <p class="px-0.5 py-2 text-xs text-gray-500">Nothing yet</p>
        <% elsif column.savings? %>
          <% column.rows.each do |row| %>
            <%= render "home/savings_card", row: row, presenter: presenter %>
          <% end %>
        <% else %>
          <% column.rows.each do |row| %>
            <%= render "home/rule_card", row: row, rows: column.rows %>
          <% end %>
        <% end %>
      </div>
    <% end %>
  </div>

  <%# A category no rule claims, with spending this period: the fact, no bar, no pressure. %>
  <% if presenter.unbudgeted_rows.any? %>
    <div class="mt-4 space-y-2">
      <h4 class="text-xs font-semibold uppercase tracking-wide text-gray-500">Spent with no rule</h4>
      <% presenter.unbudgeted_rows.each do |row| %>
        <div class="bg-white border border-gray-200 rounded px-4 py-3 flex items-baseline justify-between gap-3"
             data-unbudgeted-row="<%= row.category.name %>">
          <span class="text-sm font-medium text-gray-900"><%= row.category.name %></span>
          <span class="text-sm text-gray-700 tabular-nums">spent <%= number_to_currency(row.spent) %></span>
        </div>
      <% end %>
    </div>
  <% end %>

  <%# Said plainly rather than left as four empty columns: a blank panel on a money screen reads as
      something that failed to load. %>
  <% if presenter.columns.all?(&:empty?) && presenter.unbudgeted_rows.empty? %>
    <p class="mt-4 bg-white border border-gray-200 rounded px-4 py-3 text-sm text-gray-500">
      Nothing is budgeted yet, and nothing has been spent this period.
      <%= link_to "Give a category a rule on the Budget page", budget_page_path, class: "text-status-info hover:underline" %>
    </p>
  <% end %>
</section>
```

Decide whether the four empty columns should render at all when everything is empty: they should not — wrap the tablist and the columns grid in `<% unless presenter.columns.all?(&:empty?) %> … <% end %>` so the empty-state sentence stands alone. Keep the empty-per-kind column when at least one kind has rows.

`app/views/home/_rule_card.html.erb`:

```erb
<%# ONE RULE'S CARD. Locals: `row` (ClaimLine), `rows` (the column's rows, for lane words). Named by
    the LANE, not the category: a column may carry two rules of one category. %>
<div class="bg-white border rounded px-3.5 py-3 space-y-1.5 <%= row.over? || row.short? || row.overdue? ? "border-status-danger" : "border-gray-200" %>"
     data-rule-row="<%= lane_words(row, rows) %>" id="rule-card-<%= row.rule.id %>">
  <details data-rule-spending>
    <summary class="list-none cursor-pointer space-y-1.5">
      <div class="flex items-baseline justify-between gap-2">
        <p class="min-w-0 truncate text-sm font-medium text-gray-900"><%= lane_words(row, rows) %></p>
        <p class="text-sm tabular-nums <%= row.over? ? "text-status-danger font-medium" : "text-gray-700" %>" data-rule-figure>
          <%= figure_words(row) %> <span class="text-gray-400" aria-hidden="true">&#9662;</span>
        </p>
      </div>
      <p class="text-xs text-gray-500" data-rule-context><%= card_context_words(row, rows) %></p>
      <% if row.bar? %>
        <div class="h-1 bg-gray-200 rounded-full overflow-hidden"
             role="progressbar" aria-valuenow="<%= row.percent %>" aria-valuemin="0" aria-valuemax="100"
             aria-label="<%= row.category.name %> · <%= lane_words(row, rows) %>"
             data-rule-bar="<%= row.percent %>" data-rule-bar-state="<%= row.bar_state %>">
          <div class="h-1 rounded-full <%= bar_fill(row) %>" style="width: <%= row.percent %>%;" data-rule-fill></div>
        </div>
      <% end %>
      <% if when_clause = when_words(row) %>
        <p class="text-xs <%= row.trouble? || row.short? ? "text-status-danger font-medium" : "text-gray-500" %>" data-rule-when><%= when_clause %></p>
      <% end %>
    </summary>
    <%= turbo_frame_tag dom_id(row.rule, :spending), src: spending_rule_path(row.rule), loading: :lazy, class: "block mt-2" do %>
      <p class="text-xs text-gray-500">Loading…</p>
    <% end %>
  </details>

  <%= render "home/adjust", line: row %>
  <% if row.adjustments.any? %>
    <ul class="mt-1 space-y-1" data-rule-changes>
      <% row.adjustments.each do |change| %>
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

(Old `id="block-<category id>"` anchors: grep for `block-` in app and specs — `HomeState`/adjustments may redirect to `#block-…`; if so, switch that anchor to `rule-card-<rule id>` for rules and keep `savings-<account id>` for accounts.)

`app/views/home/_savings_card.html.erb`:

```erb
<%# ONE SAVINGS ACCOUNT WITH A TARGET, as a card in the Savings column. Locals: `row`
    (SavingsLine), `presenter`. %>
<div class="bg-white border border-gray-200 rounded px-3.5 py-3 space-y-1.5" data-savings-card="<%= row.name %>" id="savings-<%= row.account.id %>">
  <p class="text-sm font-medium text-gray-900"><%= row.name %></p>
  <p class="text-xs text-gray-500"><%= row.target_words %> · <%= row.mode_words %></p>
  <p class="text-xs text-gray-500" data-savings-figure><%= number_to_currency(row.accrued) %> owed this period</p>
  <div class="flex flex-wrap items-center justify-between gap-2">
    <p class="text-sm tabular-nums" data-savings-owed><span class="text-gray-900"><%= number_to_currency(row.claim) %></span> <span class="text-gray-500">owed</span></p>
    <% if row.transferable? %>
      <%= button_to(
            "Transfer #{number_to_currency(row.claim)}",
            transfers_path,
            params: {
              transfer: {
                from_account_id: presenter.user.main_account_id,
                to_account_id: row.account.id,
                amount: row.claim,
                date: presenter.today
              },
              return: "home"
            },
            class: "btn btn-primary h-7 px-2.5 text-xs",
            form: { class: "inline" },
            data: { transfer_owed: row.name }
          ) %>
    <% else %>
      <span class="text-xs font-medium text-status-success">On pace</span>
    <% end %>
  </div>
  <details data-adjust="<%= row.name %>">
    <summary class="<%= rule_action_classes("cursor-pointer text-xs sm:text-left") %>">Adjust</summary>
    <%= render "savings/adjust", row: row, return_to: "home" %>
  </details>
</div>
```

`app/views/home/_adjust.html.erb`: change the summary text `Adjust what's owed now` → `Adjust`, and its class to `rule_action_classes("cursor-pointer text-xs sm:text-left")`; leave the panel alone.

`app/views/home/index.html.erb`:

```erb
<% content_for :title, "Home" %>

<%= page_header(title: @presenter.day_words, subtitle: @presenter.period_words) %>

<%# The full picture: the sum, trouble only when there is some, what is coming up, and what's
    claimed by kind. An adjustment is the one thing written here; everything else links out. %>
<div class="space-y-4 lg:space-y-6">
  <%= render "home/sum", presenter: @presenter %>

  <% if @presenter.trouble? %>
    <%= render "home/trouble", presenter: @presenter %>
  <% end %>

  <%= render "home/upcoming", presenter: @presenter %>

  <%= render "home/claimed", presenter: @presenter %>
</div>
```

`git rm app/views/home/_this_period.html.erb app/views/home/_savings_block.html.erb`. Grep `app spec` for `savings_block`, `this_period`, `data-category-block`, `block-` and clean up every reference (the request specs and `HomeState` anchors included).

- [ ] **Step 4: Rebuild CSS and run the Home suite**

Run: `bin/rails tailwindcss:build && bundle exec rspec spec/system/home spec/presenters/home_presenter_spec.rb spec/requests/adjustments_spec.rb spec/requests/transfers_spec.rb`
Expected: pass. Fix any expectation whose figure moved (column totals print without "claimed").

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A
git add -A app/views/home spec
git commit -m "feat/home: what's claimed is four columns of cards, in the order they hold on"
```

---

### Task 7: The phone's segmented control

**Files:**
- Create: `app/javascript/controllers/app/home/kinds_controller.js`
- Test: `spec/system/home/columns_spec.rb` (one `:js` example)

**Interfaces:**
- Consumes the markup from Task 6: `data-controller="app--home--kinds"`, `data-kinds-target="tab"` buttons with `data-kind`, `data-kinds-target="column"` panels with `data-kind-column`, `data-action="app--home--kinds#pick"`.
- Behaviour: `pick` sets `aria-selected` on the tabs and toggles `hidden` on the columns so only the picked kind shows below `lg`; from `lg` up the CSS `lg:block` shows every column regardless.

- [ ] **Step 1: Write the failing `:js` spec**

Add to `spec/system/home/columns_spec.rb` (look at `spec/system/home/money_spec.rb`'s narrow-viewport example for the exact `Emulation.setDeviceMetricsOverride` incantation and copy it):

```ruby
  # At phone width the columns become tabs, and only the picked kind shows.
  it "shows one kind at a time on a phone", :aggregate_failures, :js do
    rule_for("Rent", rate: 900, rule_type: :bill)
    rule_for("Groceries", rate: 400)

    travel_to(today) do
      visit root_path
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 812, deviceScaleFactor: 1, mobile: true)

      expect(page).to have_css("[data-kind-column='bill']", visible: :visible)
      expect(page).to have_css("[data-kind-column='usage']", visible: :hidden)

      find("[data-kinds-tabs] [data-kind='usage']").click

      expect(page).to have_css("[data-kind-column='usage']", visible: :visible)
      expect(page).to have_css("[data-kind-column='bill']", visible: :hidden)
      expect(page).to have_css("[data-kinds-tabs] [data-kind='usage'][aria-selected='true']")
    ensure
      page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    end
  end
```

- [ ] **Step 2: Run to see it fail**

Run: `bundle exec rspec spec/system/home/columns_spec.rb -e "one kind at a time"`
Expected: fails after the click — usage column still hidden.

- [ ] **Step 3: Write the controller**

`app/javascript/controllers/app/home/kinds_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// The phone's "What's claimed": one kind at a time. Tabs carry `data-kind`; columns carry
// `data-kind-column`. From `lg` up the columns' `lg:block` shows all four whatever `hidden` says,
// so this only ever matters on a narrow screen.
export default class extends Controller {
  static targets = ["tab", "column"]

  pick(event) {
    const kind = event.currentTarget.dataset.kind
    this.tabTargets.forEach((tab) => tab.setAttribute("aria-selected", tab.dataset.kind === kind))
    this.columnTargets.forEach((column) => column.classList.toggle("hidden", column.dataset.kindColumn !== kind))
  }
}
```

Check how existing controllers under `app/javascript/controllers/app/**` are identified (`app--budget--…`) so `data-controller="app--home--kinds"` resolves; adjust the path if the loader expects a different nesting.

- [ ] **Step 4: Run**

Run: `bundle exec rspec spec/system/home/columns_spec.rb`
Expected: pass, including the `:js` example.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A
git add app/javascript/controllers/app/home/kinds_controller.js spec/system/home/columns_spec.rb
git commit -m "feat/home: on a phone, what's claimed shows one kind at a time"
```

---

### Task 8: Review, visual check, full suite

**Files:** none new.

- [ ] **Step 1: rails-code-reviewer** — dispatch the `rails-code-reviewer` agent on the uncommitted/branch changes; address anything critical.
- [ ] **Step 2: Quick Visual Check** — with `bin/dev` running, open `http://localhost:3000/` as `demo@example.com` / `password123` in Claude in Chrome at 1440 wide and at 375 wide; compare against the canvas; confirm the console is clean; then `rm -f *.png`.
- [ ] **Step 3: Full suite** — `bundle exec rubocop -A && bundle exec parallel_rspec spec`. Expected: green.
- [ ] **Step 4: Docs** — `docs/decisions.md` is already updated (Task 1's commit). Re-read §10 Home against what was built and fix any sentence that no longer matches, in present tense.
- [ ] **Step 5: Commit** anything the review or docs pass changed:

```bash
git add -A
git commit -m "docs/home: decisions match the built page"
```
