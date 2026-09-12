# Accounts and Rules, Screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put every screen of the accounts-and-rules design on top of the core plan's backend by transplanting the reference branch's views, JavaScript and helpers, rewriting the presenters and controllers against the new models, and restoring the system and request specs.

**Architecture:** Views, Stimulus controllers, CSS and helpers are copied from the reference commit `4ee68de` and adapted with a fixed rename table. Presenters and controllers are rewritten here in full, because the concepts they read (opening entries, income routing, funding dates, typed income, suggestions) do not exist any more. System specs are transplanted page by page, trimmed to flows and JavaScript, and run under Rack::Test unless tagged `:js`.

**Tech Stack:** Rails 8.1.1, Turbo, Stimulus (importmap), Tailwind 4, simple_form, Capybara.

**Spec:** `docs/superpowers/specs/2026-09-09-accounts-and-rules-design.md`

**Prerequisite:** `docs/superpowers/plans/2026-09-09-accounts-and-rules-core.md` complete: models, ledgers, forms and the migrations are on the branch and green.

## Global Constraints

- Same branch, worktree, commit trailer and style rules as the core plan.
- **Reading the reference:** `git show 4ee68de:<path>` prints a reference file; `git show 4ee68de:<path> > <path>` copies it. Never `git checkout 4ee68de -- <path>` (it stages the old file wholesale, comments included).
- **The rename table.** Apply to every transplanted file, then grep to prove none of the left column survives:

| reference | here |
|---|---|
| `Pool`, `pool`, `pools`, `pool_type_account`, `.accounts` on pools | `Account`, `account`, `accounts` |
| `Budget` (model), `budget` (a record), `budgets`, `Budget.for_user` | `Rule`, `rule`, `rules`, `Rule.for_user` |
| `budget_path`, `budgets_path`, `new_budget_path`, `edit_budget_path`, `preview_budgets_path` | `rule_path`, `rules_path`, `new_rule_path`, `edit_rule_path`, `preview_rules_path` |
| `bank_account_path`, `bank_accounts_path`, `edit_bank_account_path`, `bank_account_opening_path` | `account_path`, `accounts_path`, `edit_account_path`, (gone) |
| `AccountMovement`, `from_pool`, `to_pool`, `from_pool_id`, `to_pool_id` | `Transfer`, `from_account`, `to_account`, `from_account_id`, `to_account_id` |
| `default_account`, `default_account_id` | `main_account`, `main_account_id` |
| `funded_since`, `holder?`, `start_holding`, `.in_fill_order` (holders) | `starts_on` on the rule, `ruled?`, gone, `.in_fill_order` (ruled) |
| `Category.rule_order` | `Rule.sort_key` |
| `category.today`, `budget.today`, `user.local_day(x)`, `period_datetimes_containing` | `user.today`, `rule.today`, `x` (already a day), `period_containing` |
| `CategoryLedger::ENTRY_CATEGORY_ID` and friends | `Entry.in_lane_of`, `Entry.on_unruled_items`, `Entry.since` |
| `typical_income` (user column) | `AccountLedger#typical_income` |
| `CategoryCalculator`, `category.calculator` | `CategoryStats`, `category.stats` |
| `destination_account_id`, `route_income_to!`, `routed_account` | `account_id`, `entry.account`, `entry.landing_account` |
| `opening_account_id`, `opening?`, `opening_entry`, `AccountOpening`, `awaiting_opening?`, `opened` trait | gone: an account always has a balance |
| `SuggestionEngine`, `suggestion*`, `_chip`, `chips`, `hidden_suggestions`, `suggestion_pointer`, `spent_recently` | gone |
| `budget_rule_name`, `budget_rule_basis`, `pool_rule_label` | `rule_name`, `rule_basis`, `rule_label` |
| `bank_account` (form object name), `@bank_account`, `@new_bank_account` | `account`, `@account`, `@new_account` |
| `Budget.steady_need` | `Rule.steady_need` |

- **Proof grep**, run at the end of every task and expected empty:

```bash
grep -rnE '\b(Pool|pool_type|Budget\b|budget_path|budgets_path|bank_account|AccountMovement|from_pool|to_pool|default_account|funded_since|holder\?|start_holding|CategoryLedger|CategoryCalculator|typical_income|destination_account|route_income|opening_account|AccountOpening|awaiting_opening|Suggestion|suggestion|spent_recently|budget_rule_|pool_rule_label|local_day|period_datetimes)' app config db/seeds.rb spec
```

- **Gate:** after every task the core gate stays green, plus the system and request specs the task adds. `bundle exec rspec spec` green at the end.
- Screens are not redesigned. A view is adapted only where it named something that no longer exists.

---

## File Structure

| file | responsibility |
|---|---|
| `app/views/layouts/**`, `app/views/shared/**`, `app/assets/**`, `app/javascript/controllers/shared/**` | chrome and assets, copied whole |
| `app/presenters/home_presenter.rb`, `app/controllers/home_controller.rb`, `app/controllers/accounts_controller.rb`, `app/views/home/**`, `app/views/accounts/edit.html.erb`, `app/helpers/home_helper.rb` | Home and accounts |
| `app/controllers/entries_controller.rb`, `app/presenters/entry_impact_presenter.rb`, `app/views/entries/**`, `app/javascript/controllers/app/entry/**` | Entries |
| `app/controllers/categories_controller.rb`, `app/presenters/category_budget_presenter.rb`, `app/views/categories/**` | Categories |
| `app/controllers/rules_controller.rb`, `app/controllers/budget_page_controller.rb`, `app/controllers/adjustments_controller.rb`, `app/controllers/sacrifices_controller.rb`, `app/presenters/{budget_page_presenter,claim_rows,claim_line,rule_preview,sacrifice_presenter}.rb`, `app/views/{budget_page,rules,sacrifices}/**`, `app/javascript/controllers/app/{budget,budget_page,sacrifice}/**`, `app/helpers/{budget_page_helper,rule_actions_helper,sacrifices_helper}.rb` | Budget page, rules, adjustments, sacrifice |
| `app/services/category_stats.rb`, `app/presenters/dashboard*`, `app/presenters/*_calendar_presenter.rb`, `app/views/{dashboard,calendar}/**` | Reports and calendar |
| `db/seeds.rb`, `CLAUDE.md`, `spec/testing_guidelines.md`, `docs/coding-standards.md` | seeds and documentation |
| `app/controllers/concerns/home_state.rb`, `app/controllers/concerns/budget_page_state.rb` | the re-render state a second controller needs, without inheritance |

---

## Task 1: Chrome, assets and shared helpers (part of spec commit 6)

**Files:**
- Copy from `4ee68de`: `app/assets/stylesheets/custom.css`, `app/assets/stylesheets/animations.css`, `app/assets/tailwind/application.css`, `app/views/layouts/application.html.erb`, every file under `app/views/shared/`, every file under `app/javascript/controllers/shared/` and `app/javascript/controllers/public/`, `app/javascript/controllers/index.js`, `app/javascript/application.js`, `app/helpers/application_helper.rb`, `app/helpers/category_type_helper.rb`, `app/helpers/entries_helper.rb`, `app/helpers/search_helper.rb`, `app/helpers/digits_helper.rb`, `app/helpers/rule_actions_helper.rb`, `config/locales/en.yml`
- Modify: `app/views/shared/_sidebar.html.erb`, `config/routes.rb`

**Interfaces:**
- Produces: the sidebar links `root_path`, `budget_page_path`, `entries_path`, `categories_path`, `calendar_path`, `reports_path`, `settings_path`; `DigitsHelper.digits(amount)`; `RuleActionsHelper#rule_action_classes`. Routes for every screen in this plan.

- [ ] **Step 1: Copy the files**

```bash
for f in app/assets/stylesheets/custom.css app/assets/stylesheets/animations.css app/assets/tailwind/application.css \
         app/views/layouts/application.html.erb app/javascript/controllers/index.js app/javascript/application.js \
         app/helpers/application_helper.rb app/helpers/category_type_helper.rb app/helpers/entries_helper.rb \
         app/helpers/search_helper.rb app/helpers/digits_helper.rb app/helpers/rule_actions_helper.rb config/locales/en.yml; do
  git show 4ee68de:$f > $f
done
for d in app/views/shared app/javascript/controllers/shared app/javascript/controllers/public; do
  for f in $(git ls-tree -r --name-only 4ee68de $d); do mkdir -p $(dirname $f); git show 4ee68de:$f > $f; done
done
```

Then delete the comment block under `en:` in `config/locales/en.yml` that starts `# ── THE POOL RESTRICT BLOCK`, leaving `en:` with `hello: "Hello world"`.

- [ ] **Step 2: Routes for the whole plan**

Replace `config/routes.rb` with:

```ruby
# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :users, controllers: { registrations: "users/registrations" }

  authenticated :user do
    root "home#index", as: :authenticated_root
  end

  get "reports", to: "dashboard#index", as: :reports

  resources :accounts, only: [:create, :edit, :update, :destroy]

  resources :entries, except: [:show] do
    collection do
      get :impact
    end
  end

  resources :items, only: [:edit, :update, :destroy]

  resources :categories do
    resources :items, only: [:index, :new, :create], controller: "categories/items" do
      collection do
        get :merge
        post :merge, action: :perform_merge
        post :move
      end
    end
    member do
      patch :toggle_tracked
    end
    collection do
      patch :update_tracked
    end
  end

  resources :rules, only: [:new, :create, :edit, :update, :destroy] do
    collection do
      match :preview, via: [:post, :patch]
    end
  end

  get "budget" => "budget_page#show", as: :budget_page
  patch "budget/user" => "budget_page#update", as: :budget_page_user
  patch "budget/reorder" => "budget_page#reorder", as: :budget_page_reorder
  resources :adjustments, only: [:create, :destroy]
  get "sacrifice" => "sacrifices#show"

  resource :settings, only: [:show] do
    patch :toggle_theme
    patch :toggle_ming_mode
  end

  get "calendar", to: "calendar#index", as: :calendar
  get "calendar/week", to: "calendar#week", as: :calendar_week

  root "pages#home"
  get "up" => "rails/health#show", as: :rails_health_check
end
```

- [ ] **Step 3: The sidebar's settings link and the helper renames**

In `app/views/shared/_user_profile.html.erb` the link is already `settings_path` (Task 2 of the core plan renamed it; the copied reference file says `account_path`). Re-run the core plan's sed on the copied shared views:

```bash
sed -i '' -e 's/toggle_theme_account_path/toggle_theme_settings_path/g' -e 's/toggle_ming_mode_account_path/toggle_ming_mode_settings_path/g' -e 's/\baccount_path\b/settings_path/g' app/views/shared/*.erb
```

In `app/helpers/entries_helper.rb`, `search_helper.rb` and `category_type_helper.rb` the copies already have no `savings` entries. Strip every comment paragraph longer than two lines from the copied helpers and Stimulus controllers; keep one-line comments that explain a choice.

- [ ] **Step 4: Rebuild CSS and boot**

```bash
bin/rails tailwindcss:build
bin/rails runner 'puts Rails.application.routes.url_helpers.budget_page_path'
```

Expected: `/budget`.

- [ ] **Step 5: Commit**

```bash
bundle exec rubocop -A app/helpers config/routes.rb
git add -A
git commit -m "screens: chrome, assets, shared helpers and the routes"
```

---

## Task 2: Home and accounts (spec commit 6)

**Files:**
- Create: `app/presenters/home_presenter.rb`, `app/controllers/home_controller.rb`, `app/controllers/concerns/home_state.rb`, `app/controllers/accounts_controller.rb`, `app/helpers/home_helper.rb`, `app/views/accounts/edit.html.erb`
- Copy from `4ee68de` then adapt: `app/views/home/index.html.erb`, `_money.html.erb`, `_accounts_line.html.erb`, `_account.html.erb`, `_your_accounts.html.erb`, `_this_period.html.erb`, `_runway.html.erb`, `_shortfall.html.erb`, `_trouble.html.erb`; `app/views/bank_accounts/edit.html.erb` to `app/views/accounts/edit.html.erb`
- Do not copy: `app/views/home/_opening_row.html.erb`
- Specs: `spec/presenters/home_presenter_spec.rb`, `spec/requests/accounts_spec.rb`, `spec/system/home/*.rb`

**Interfaces:**
- Consumes: `ClaimLedger`, `AccountLedger`, `ClaimRows` (Task 5 of this plan; copy `app/presenters/claim_rows.rb` and `claim_line.rb` from the reference now, apply the rename table, and let Task 5 own their spec).
- Produces: `HomePresenter` public API below; `HomeState#assign_home_state`; `AccountsController` create/edit/update/destroy; the account form posts `account[name]` and `account[balance]`.

- [ ] **Step 1: Copy ClaimRows and ClaimLine, renamed**

```bash
git show 4ee68de:app/presenters/claim_rows.rb > app/presenters/claim_rows.rb
git show 4ee68de:app/presenters/claim_line.rb > app/presenters/claim_line.rb
```

Apply the rename table by hand. The only semantic edits: in `ClaimRows#categories` use `user.categories.in_fill_order.to_a`; replace `Category.rule_order(...)` with `Rule.sort_key(...)`; `ranked_categories` stays. Strip the long comments.

- [ ] **Step 2: Presenter spec**

`spec/presenters/home_presenter_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe HomePresenter do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let!(:main) { create(:account, user: user, opening_balance: 1_000) }
  let(:presenter) { described_class.new(user: user, today: today) }

  def rule_on(name, **attributes)
    category = create(:category, user: user, name: name)
    create(:rule, category: category, starts_on: Date.new(2026, 1, 1), **attributes)
  end

  it "reads the pot, free to spend and the claimed share", :aggregate_failures do
    rule_on("Groceries", amount: 400)
    create(:account, user: user, opening_balance: 250)

    expect(presenter.in_checking).to eq(1_000)
    expect(presenter.free_to_spend).to eq(600)
    expect(presenter.claimed_percent).to eq(40)
    expect(presenter.other_accounts_total).to eq(250)
    expect(presenter).to be_money_parked_elsewhere
    expect(presenter).to be_anything_claimed
    expect(presenter).not_to be_short
    expect(presenter.troubles).to be_empty
  end

  it "reports a shortfall and who gives way, choices first", :aggregate_failures do
    rule_on("Rent", :bill, amount: 900)
    rule_on("Fun", :choice, amount: 300)

    expect(presenter).to be_short
    expect(presenter.shortfall).to eq(200)
    expect(presenter.uncovered_claims.map { |u| [u.category.name, u.amount] }).to eq([["Fun", 200]])
    expect(presenter.troubles.map(&:kind)).to eq([:shortfall])
    expect(presenter.per_day_pace).to eq((200.to_d / 9).round(2))
  end

  it "flags an overdrawn other account and a structural gap", :aggregate_failures do
    other = create(:account, user: user)
    create(:transfer, from_account: other, to_account: main, amount: 10, date: today)
    rule_on("Rent", :bill, amount: 5_000)
    create(:entry, :income, user: user, amount: 100, date: Date.new(2026, 8, 25))

    kinds = presenter.troubles.map(&:kind)
    expect(kinds).to include(:overdraft, :structural)
    expect(presenter.overdrawn_other_accounts).to eq([other])
  end

  it "measures the period and the runway", :aggregate_failures do
    rule_on("Dentist", :bill, amount: 300, anchor_date: Date.new(2026, 9, 12), starts_on: Date.new(2026, 8, 1))

    expect(presenter.period_progress).to have_attributes(day: 6, days: 14, days_left: 8)
    expect(presenter.runway.ticks.map(&:label)).to eq(["Dentist"])
    expect(presenter.runway.ticks.first.day_index).to eq(9)
  end

  it "lists spending in categories no rule claims" do
    create(:entry, :expense, user: user, amount: 42, date: Date.new(2026, 9, 6))

    expect(presenter.unbudgeted_rows.map(&:spent)).to eq([42])
  end
end
```

- [ ] **Step 3: Run it to see it fail**

Run: `bundle exec rspec spec/presenters/home_presenter_spec.rb`
Expected: `uninitialized constant HomePresenter`.

- [ ] **Step 4: The presenter**

```ruby
# frozen_string_literal: true

# Everything the home page shows: accounts and balances, free to spend, this period's progress,
# the trouble strip, the give-way list and the runway. Reads through one ClaimLedger.
class HomePresenter
  UnbudgetedRow = Data.define(:category, :spent)
  Trouble = Data.define(:kind, :subject)
  Uncovered = Data.define(:line, :amount) do
    delegate :category, :claim, to: :line
    def whole? = amount >= claim
  end
  Progress = Data.define(:first, :last, :day, :days) do
    def days_left = days - day
    def percent = percent_at(day)
    def percent_at(day_index) = ((day_index.to_f / days) * 100).round.clamp(0, 100)
  end
  RunwayTick = Data.define(:line, :day_index, :percent, :label, :amount, :state, :gap) do
    def ready? = state == :ready
    def short? = state == :short
  end
  Runway = Data.define(:progress, :ticks, :due_total, :short) do
    delegate :first, :last, :day, :days, :days_left, :percent, to: :progress
    def any_due? = ticks.any?
  end
  Pace = Data.define(:amount, :fine) do
    def fine? = fine
  end

  attr_reader :user, :today

  def initialize(user:, today: user.today)
    @user = user
    @today = today
  end

  def accounts = @accounts ||= user.accounts.order(:name).to_a
  delegate :balance_of, to: :account_ledger
  def main?(account) = account.main?
  def onboarding? = accounts.empty?
  def other_accounts = accounts.reject { |account| main?(account) }
  def other_accounts_total = other_accounts.sum(0.to_d) { |account| balance_of(account) }
  def overdrawn_other_accounts = other_accounts.select { |account| balance_of(account).negative? }
  def overdraft_for(account) = -balance_of(account)

  def in_checking = claim_ledger.pot
  def free_to_spend = claim_ledger.free
  delegate :total_claims, to: :claim_ledger
  def money_parked_elsewhere? = other_accounts_total.positive?
  def anything_claimed? = total_claims.positive?

  def claimed_percent
    return nil unless in_checking.positive?

    ((total_claims / in_checking) * 100).round.clamp(0, 100)
  end

  def categories = @categories ||= user.categories.in_fill_order.includes(:rules).to_a
  delegate :ranked_categories, :blocks, :period_range, :give_way_order, to: :claim_rows

  def period_progress
    range = period_range
    return nil if range.nil?

    Progress.new(first: range.first, last: range.last, day: (today - range.first).to_i + 1, days: range.count)
  end

  def runway
    return @runway if defined?(@runway)

    @runway = build_runway
  end

  def pace_line
    progress = period_progress
    return nil if progress.nil?
    return Pace.new(amount: per_day_pace, fine: false) if short?

    Pace.new(amount: (free_to_spend / [progress.days_left, 1].max).round(2), fine: true)
  end

  def short? = free_to_spend.negative?
  def shortfall = -free_to_spend

  def per_day_pace
    progress = period_progress
    return nil if progress.nil? || !short?

    (shortfall / [progress.days_left, 1].max).round(2)
  end

  # Which claims give way to cover the shortfall, in give-way order.
  def uncovered_claims
    @uncovered_claims ||= begin
      remaining = short? ? shortfall : 0.to_d
      give_way_order.each_with_object([]) do |line, list|
        break list unless remaining.positive?
        next unless line.claim.positive?

        taken = [line.claim, remaining].min
        list << Uncovered.new(line: line, amount: taken)
        remaining -= taken
      end
    end
  end

  def uncovered_remainder
    return 0.to_d if uncovered_claims.empty?

    shortfall - uncovered_claims.sum(0.to_d, &:amount)
  end

  def troubles
    @troubles ||= [
      *overdrawn_other_accounts.map { |account| Trouble.new(kind: :overdraft, subject: account) },
      *(short? ? [Trouble.new(kind: :shortfall, subject: nil)] : []),
      *trouble_lines.map { |line| Trouble.new(kind: line.over? ? :over : :overdue, subject: line) },
      *(structurally_underwater? ? [Trouble.new(kind: :structural, subject: nil)] : [])
    ]
  end

  def trouble? = troubles.any?

  # Rules ask for more per period than typical income brings in.
  def structurally_underwater?
    return @structurally_underwater if defined?(@structurally_underwater)

    income = typical_income
    @structurally_underwater = user.period_cadence.present? && income.present? && rules_need > income
  end

  def typical_income = @typical_income ||= account_ledger.typical_income
  def rules_need = @rules_need ||= Rule.steady_need(user, today: today, ledger: claim_ledger)

  # Spending this period in expense categories no rule claims.
  def unbudgeted_rows
    @unbudgeted_rows ||= begin
      claimed = user.categories.with_a_rule.select(:id)
      Entry.expenses.where(categories: { user_id: user.id }).where.not(categories: { id: claimed })
        .where(date: user.period_containing(today)).group("categories.id").sum(:amount)
        .filter_map do |category_id, spent|
          UnbudgetedRow.new(category: Category.find(category_id), spent: spent.to_d) if spent.positive?
        end.sort_by { |row| row.category.name }
    end
  end

  private

  def build_runway
    progress = period_progress
    return nil if progress.nil?

    ticks = runway_ticks(progress)
    Runway.new(progress: progress, ticks: ticks, due_total: ticks.sum(0.to_d, &:amount), short: ticks.select(&:short?))
  end

  def runway_ticks(progress)
    give_way_order
      .select { |line| line.dated? && line.due_this_period && !line.paid? }
      .sort_by { |line| [line.next_due_on, line.name] }
      .map { |line| runway_tick(line, progress) }
  end

  def runway_tick(line, progress)
    day_index = (line.next_due_on - progress.first).to_i + 1
    RunwayTick.new(line: line, day_index: day_index, percent: progress.percent_at(day_index),
                   label: line.rule.item&.name || line.category.name, amount: line.target,
                   state: line.fund_short? ? :short : :ready, gap: line.fund_gap)
  end

  def trouble_lines = @trouble_lines ||= blocks.flat_map(&:rows).select(&:trouble?)
  def claim_ledger = @claim_ledger ||= ClaimLedger.new(user, today: today)
  def claim_rows = @claim_rows ||= ClaimRows.new(ledger: claim_ledger, today: today, categories: categories)
  def account_ledger = claim_ledger.account_ledger
end
```

- [ ] **Step 5: Controllers, concern and helper**

`app/controllers/concerns/home_state.rb`:

```ruby
# frozen_string_literal: true

# The state the home page renders with, for the controllers that re-render it after a refusal.
module HomeState
  extend ActiveSupport::Concern

  private

  def assign_home_state(new_account: nil, new_account_balance: nil)
    @presenter = HomePresenter.new(user: current_user, today: current_user.today)
    @new_account = new_account || current_user.accounts.new
    @new_account_balance = new_account_balance
  end
end
```

`app/controllers/home_controller.rb`:

```ruby
# frozen_string_literal: true

class HomeController < ApplicationController
  include HomeState

  def index
    assign_home_state
  end
end
```

`app/controllers/accounts_controller.rb`:

```ruby
# frozen_string_literal: true

class AccountsController < ApplicationController
  include HomeState

  before_action :set_account, only: [:edit, :update, :destroy]

  def create
    account = Account.open(current_user, name: account_params[:name], balance: account_params[:balance].presence || 0)
    return redirect_to root_path, notice: "#{account.name} added." if account.persisted?

    assign_home_state(new_account: account, new_account_balance: account_params[:balance])
    render "home/index", status: :unprocessable_content
  end

  def edit; end

  def update
    if @account.update(name: account_params[:name]) && correct_balance
      redirect_to root_path, notice: "#{@account.name} updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    pot_before = AccountLedger.new(current_user).pot
    if @account.destroy
      redirect_to root_path, notice: deletion_notice(pot_before)
    else
      redirect_to root_path, alert: @account.errors[:base].to_sentence
    end
  end

  private

  def set_account = @account = current_user.accounts.find(params[:id])

  def correct_balance
    typed = account_params[:balance]
    typed.blank? || @account.correct_balance(typed)
  end

  def deletion_notice(pot_before)
    returned = (AccountLedger.new(current_user).pot - pot_before).round(2)
    return "#{@account.name} deleted." unless returned.positive?

    "#{@account.name} deleted — #{helpers.number_to_currency(returned)} is back in checking."
  end

  def account_params = params.expect(account: [:name, :balance])
end
```

`app/helpers/home_helper.rb`: copy from the reference, apply the rename table, then delete the `:monthly` arm of `cadence_words` (a per-period rule reads "a period", a rolling one "every N months", a one-off through `one_off_words`), and rename `pool_rule_label` to `rule_label`.

- [ ] **Step 6: Views**

```bash
for f in index _money _accounts_line _account _your_accounts _this_period _runway _shortfall _trouble; do
  git show 4ee68de:app/views/home/$f.html.erb > app/views/home/$f.html.erb
done
mkdir -p app/views/accounts && git show 4ee68de:app/views/bank_accounts/edit.html.erb > app/views/accounts/edit.html.erb
```

Adapt, with the rename table and these specific edits:

- `_your_accounts.html.erb`: delete the `presenter.onboarding_accounts.each` block that rendered `opening_row`. The add form is `simple_form_for @new_account, as: :account, url: accounts_path` with `f.input :name` and `f.input :balance` (value `@new_account_balance`), submit "Add an account".
- `_account.html.erb`: delete the `<details data-edit-balance>` block and its `render "opening_row"`. The Rename link goes to `edit_account_path(account)`; Delete is `button_to account_path(account), method: :delete`. The header keeps `presenter.balance_of(account)`. Every `awaiting_opening?` branch collapses to the finished-account branch.
- `accounts/edit.html.erb`: `simple_form_for @account, url: account_path(@account)` with `f.input :name` and a second input `f.input :balance, label: "Balance today", input_html: { value: number_with_precision(@account.balance, precision: 2) }`, hint "Correcting the balance moves the opening balance; nothing else changes."
- `_money.html.erb`, `_accounts_line.html.erb`, `_trouble.html.erb`, `_shortfall.html.erb`, `_this_period.html.erb`, `_runway.html.erb`, `index.html.erb`: rename table only. Remove any `<%# ... %>` block longer than two lines.

- [ ] **Step 7: Request spec**

`spec/requests/accounts_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Accounts" do
  let(:user) { create(:user) }

  before { sign_in user }

  it "opens an account with its balance and makes the first one main", :aggregate_failures do
    post accounts_path, params: { account: { name: "Checking", balance: "250.00" } }

    expect(response).to redirect_to(root_path)
    account = user.reload.main_account
    expect(account.name).to eq("Checking")
    expect(account.balance).to eq(250)
  end

  it "re-renders home with the refusal", :aggregate_failures do
    create(:account, user: user, name: "Checking")

    post accounts_path, params: { account: { name: "checking", balance: "" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("has already been taken")
  end

  it "renames and corrects a balance", :aggregate_failures do
    account = create(:account, user: user, name: "Old", opening_balance: 10)

    patch account_path(account), params: { account: { name: "New", balance: "99.5" } }

    expect(response).to redirect_to(root_path)
    expect(account.reload).to have_attributes(name: "New", opening_balance: 99.5)
  end

  it "deletes a non-main account and refuses main", :aggregate_failures do
    main = create(:account, user: user)
    other = create(:account, user: user)

    delete account_path(other)
    expect(Account.exists?(other.id)).to be(false)

    delete account_path(main)
    expect(Account.exists?(main.id)).to be(true)
    expect(flash[:alert]).to include("main account")
  end

  it "never touches another user's account" do
    other = create(:account)

    expect { delete account_path(other) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
```

- [ ] **Step 8: System specs**

Copy `spec/system/home/*.rb` from the reference, then rewrite:

- Delete `openings_spec.rb` and `new_account_spec.rb`; fold "add an account with a balance" into `accounts_spec.rb` as one `:js`-free example that fills `Name` and `Balance` and expects the account card with its balance.
- Every helper named `deposit`, `spend`, `envelope`, `holder`, `rate`, `goal` becomes a three-line helper on the new factories, e.g.:

```ruby
def deposit(amount, on: today) = create(:entry, :income, user: user, amount: amount, date: on)
def envelope(name, rate:) = create(:rule, :rate, amount: rate, category: create(:category, user: user, name: name), starts_on: Date.new(2026, 1, 1))
def spend(category, amount, on: today) = create(:entry, item: create(:item, category: category), amount: amount, date: on)
```

- Keep one example per figure the page shows (free to spend, claimed, elsewhere, period progress, each trouble kind, the runway, the pace line) and every interaction (add, rename, delete an account). Drop examples that re-prove presenter arithmetic already in `home_presenter_spec.rb`.
- `money_spec.rb`'s 375px example stays and is tagged `:js`; it keeps the `setDeviceMetricsOverride` idiom.
- No `sleep`. Every `click_*` is followed by a waiting assertion.

Run: `bundle exec rspec spec/presenters/home_presenter_spec.rb spec/requests/accounts_spec.rb spec/system/home`
Expected: green.

- [ ] **Step 9: Proof grep and commit**

Run the proof grep from Global Constraints on `app/presenters/home_presenter.rb app/controllers app/views/home app/views/accounts app/helpers/home_helper.rb spec/system/home spec/requests/accounts_spec.rb`. Expected: empty.

```bash
bundle exec rubocop -A app spec
git add -A
git commit -m "screens: home and accounts"
```

---

## Task 3: Entries and items (part of spec commit 7)

**Files:**
- Create: `app/controllers/entries_controller.rb`, `app/presenters/entry_impact_presenter.rb`
- Copy then adapt: `app/views/entries/**` except `_opening_form.html.erb`; `app/views/items/**`; `app/javascript/controllers/app/entry/form_controller.js`, `impact_controller.js`; `app/javascript/controllers/app/item/**`; `app/controllers/items_controller.rb` stays as `main`
- Do not copy: `app/javascript/controllers/app/entry/routing_controller.js` (the account select is a plain `<select>` shown for income categories by `form_controller.js`)
- Specs: `spec/presenters/entry_impact_presenter_spec.rb`, `spec/requests/entries_spec.rb`, `spec/system/entries/**`, `spec/system/items/**`

**Interfaces:**
- Consumes: `EntryForm`, `ClaimLedger`, `Entry.landing_account`.
- Produces: `EntriesController` index/new/create/edit/update/destroy/impact; the form posts `entry[amount]`, `entry[date]`, `entry[description]`, `entry[item_id]`, `entry[account_id]`, `entry[item_attributes][name]` and `category_id`.

- [ ] **Step 1: Presenter spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntryImpactPresenter do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }

  before { create(:account, user: user) }

  def impact(category:, amount: nil, entry: nil) = described_class.new(user: user, category: category, amount: amount, entry: entry, today: today)

  it "does not render for income, or for a category with no rule", :aggregate_failures do
    expect(impact(category: create(:category, :income, user: user))).not_to be_render
    expect(impact(category: groceries)).to be_render
    expect(impact(category: groceries)).to be_unbudgeted
    expect(impact(category: groceries)).not_to be_figures
  end

  it "shows the balance before and after for a rate rule", :aggregate_failures do
    create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1))
    create(:entry, item: create(:item, category: groceries), amount: 100, date: Date.new(2026, 9, 5))

    figures = impact(category: groceries, amount: "50")
    expect(figures.balance).to eq(300)
    expect(figures.balance_after).to eq(250)
    expect(figures.denominator).to eq(400)
    expect(figures.bar_percent).to eq(63)
    expect(figures).not_to be_overdrawn
    expect(impact(category: groceries, amount: "350")).to be_overdrawn
  end

  it "gives an edited entry its own amount back before subtracting the new one" do
    create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1))
    entry = create(:entry, item: create(:item, category: groceries), amount: 100, date: Date.new(2026, 9, 5))

    expect(impact(category: groceries, amount: "120", entry: entry).balance).to eq(400)
  end

  it "names a dated target and uses it as the bar's denominator", :aggregate_failures do
    create(:rule, :bill, amount: 600, anchor_date: Date.new(2026, 10, 15), category: groceries, starts_on: Date.new(2026, 8, 1))

    figures = impact(category: groceries, amount: "10")
    expect(figures).to be_fund
    expect(figures.fund_target).to eq(600)
    expect(figures.noun).to eq("bill")
    expect(figures.balance).to eq(400)
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/presenters/entry_impact_presenter_spec.rb`
Expected: `uninitialized constant EntryImpactPresenter`.

- [ ] **Step 3: The presenter**

```ruby
# frozen_string_literal: true

# The card under the entry form: what the category's rules hold now and after this amount.
class EntryImpactPresenter
  TYPED_AMOUNT = /\A\d*\.?\d+\z/

  attr_reader :user, :category, :entry, :today

  def initialize(user:, category:, amount: nil, entry: nil, today: user.today)
    @user = user
    @category = category
    @raw_amount = amount
    @entry = entry
    @today = today
  end

  def render? = category.present? && !category.income?
  def unbudgeted? = category.nil? || calculators.empty?
  def fund? = calculators.any?(&:dated?)

  def fund_target
    return nil unless calculators.one? && calculators.first.dated?

    calculators.first.target
  end

  def noun
    return "envelope" unless fund?

    dated_rules.any?(&:bill?) ? "bill" : "target"
  end

  def dated_rules = calculators.select(&:dated?).map(&:rule)

  # The claim as it stands, with an edited entry's own amount given back first.
  def balance
    @balance ||= begin
      given_back = own_contribution
      given_back.zero? ? claim : (pre_clamp_claim + given_back).clamp(0.to_d, most_it_could_claim)
    end
  end

  def amount
    @amount ||= case @raw_amount
                when nil then 0.to_d
                when Numeric, BigDecimal then [@raw_amount.to_d, 0.to_d].max
                else @raw_amount.to_s.strip.match?(TYPED_AMOUNT) ? @raw_amount.to_s.to_d : 0.to_d
                end
  end

  def balance_after = @balance_after ||= (balance - amount).to_d
  def figures? = render? && !unbudgeted?
  def overdrawn? = figures? && balance_after.negative?
  def denominator = @denominator ||= fund_target || steady_claim
  def bar? = figures? && denominator.positive?

  def bar_fraction
    return 0.to_d unless denominator.positive?

    (balance_after / denominator).clamp(0.to_d, 1.to_d)
  end

  def bar_percent = (bar_fraction * 100).round

  def period_ends_on
    return nil if user.period_cadence.blank? || user.period_anchor_date.blank?

    user.period_containing(today).last
  end

  def balance_param = DigitsHelper.digits(balance)
  def denominator_param = DigitsHelper.digits(denominator)

  private

  def steady_claim = calculators.sum(0.to_d, &:standing_ask)
  def claim = @claim ||= calculators.sum(0.to_d, &:claim).to_d

  def calculators
    @calculators ||= category.nil? ? [] : category.rules.includes(:item).map { |rule| rule.claim_calculator(today: today) }
  end

  def pre_clamp_claim
    calculators.sum(0.to_d) { |calculator| calculator.rate? ? calculator.raw_rate : calculator.built_up }
  end

  def most_it_could_claim = calculators.sum(0.to_d) { |calculator| ceiling_for(calculator) }

  def ceiling_for(calculator)
    return [calculator.accrued_this_period, 0.to_d].max if calculator.rate?
    return calculator.built_up + calculator.planned_this_period if calculator.fund?

    calculator.target
  end

  def own_contribution
    counted = counted_entry
    return 0.to_d unless counted && counted.item.category_id == category.id && counted_by_the_claim?(counted)

    counted.amount.to_d
  end

  def counted_by_the_claim?(counted)
    calculators.any? { |calculator| calculator.counts_spending_on?(counted.date) } &&
      calculators.none? { |calculator| !calculator.rate? && calculator.over? }
  end

  def counted_entry
    return nil unless entry&.persisted?

    entry.changed? ? user.entries.find_by(id: entry.id) : entry
  end
end
```

- [ ] **Step 4: The controller**

```ruby
# frozen_string_literal: true

class EntriesController < ApplicationController
  include Searchable

  before_action :set_entry, only: [:edit, :update, :destroy]
  before_action :load_options, only: [:new, :edit, :create, :update]
  before_action :set_previous_url, only: [:new, :create, :edit, :update]

  helper_method :entry_impact

  def index
    @entries = build_entries_query
    @current_type = params[:type] || "all"
    @current_sort = params[:sort]
    @current_direction = params[:direction] == "desc" ? "desc" : "asc"
    @search_state = current_search_state(params)
  end

  def new
    @entry = Entry.new(item: current_user.items.find_by(id: params[:item_id]))
  end

  def edit; end

  def create
    @entry = Entry.new
    write(:new, "Entry was successfully created.")
  end

  def update
    write(:edit, "Entry was successfully updated.")
  end

  def destroy
    @entry.destroy
    redirect_to entries_path, notice: "Entry was successfully deleted."
  end

  def impact
    render partial: "entries/impact", locals: { impact: EntryImpactPresenter.new(
      user: current_user, category: current_user.categories.find_by(id: params[:category_id]),
      amount: params[:amount], entry: current_user.entries.find_by(id: params[:entry_id])
    ) }
  end

  private

  def write(template, notice)
    form = EntryForm.new(current_user, @entry, entry_params, category_id: params[:category_id])
    if form.save
      redirect_to previous_path, notice: notice
    else
      render template, status: :unprocessable_content
    end
  end

  def entry_impact(entry)
    @entry_impact ||= {}
    @entry_impact[entry] ||= EntryImpactPresenter.new(
      user: current_user, category: entry.item&.category, amount: entry.amount, entry: entry.persisted? ? entry : nil
    )
  end

  def build_entries_query
    entries = current_user.entries.includes(item: :category)
    entries = apply_type_filter(entries)
    entries = apply_search(entries, { q: params[:q], field: params[:field] })
    apply_sorting(entries).page(params[:page])
  end

  def apply_type_filter(entries)
    case params[:type]
    when "expenses" then entries.expenses
    when "income" then entries.incomes
    else entries
    end
  end

  def apply_sorting(entries)
    direction = params[:direction] == "desc" ? "desc" : "asc"
    case params[:sort]
    when "date" then entries.order(date: direction)
    when "amount" then entries.order(amount: direction)
    else entries.order(date: :desc)
    end
  end

  def set_entry = @entry = current_user.entries.find(params[:id])

  def load_options
    @categories = current_user.categories.order(:category_type, :name)
    @accounts = current_user.accounts.order(:name)
  end

  def entry_params
    params.expect(entry: [:amount, :date, :description, :item_id, :account_id, { item_attributes: [:name] }])
  end

  def set_previous_url
    @previous_url = params[:previous_url]
    return unless @previous_url.blank? && request.referer.present? && URI(request.referer).path != new_entry_path

    @previous_url = request.referer
  end

  def previous_path
    return calendar_week_path(date: @entry.date) if @previous_url.present? && @previous_url.include?("calendar")

    @previous_url || entries_path
  end
end
```

- [ ] **Step 5: Views and JavaScript**

```bash
for f in $(git ls-tree -r --name-only 4ee68de app/views/entries app/views/items app/javascript/controllers/app/entry app/javascript/controllers/app/item); do
  git show 4ee68de:$f > $f
done
rm app/views/entries/_opening_form.html.erb app/javascript/controllers/app/entry/routing_controller.js
```

Adapt:

- `entries/_form.html.erb`: the `data-controller` loses `app--entry--routing`. The "Lands in" block becomes `f.select :account_id, options_from_collection_for_select(@accounts, :id, :name, entry.account_id || current_user.main_account_id), {}, { id: "entry_account_id", class: "form-select" }`, wrapped in a `div data-app--entry--form-target="account"` that `form_controller.js` shows only while the chosen category is income (add an `account` target and a `toggleAccount()` call inside the existing category-change handler, using `incomeIds` passed as a `data-app--entry--form-income-ids-value`). The edit page renders `_form` for every entry (`edit.html.erb` loses the `opening?` branch).
- `entries/_impact.html.erb`, `_entry.html.erb`, `_table.html.erb`, `_entry_card.html.erb`: rename table; delete the `opening` refusal copy.
- `items/**`: rename table only.

- [ ] **Step 6: Request and system specs**

`spec/requests/entries_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entries" do
  let(:user) { create(:user) }
  let!(:main) { create(:account, user: user) }
  let(:savings) { create(:account, user: user) }
  let(:salary) { create(:category, :income, user: user, name: "Salary") }
  let(:groceries) { create(:category, user: user, name: "Groceries") }

  before { sign_in user }

  it "creates a new item by name in the category and lands income in the chosen account", :aggregate_failures do
    post entries_path, params: { category_id: salary.id, entry: { amount: "1000 + 200", date: "2026-09-05", item_id: "", item_attributes: { name: "Pay" }, account_id: savings.id } }

    expect(response).to redirect_to(entries_path)
    entry = user.entries.sole
    expect(entry).to have_attributes(amount: 1200, account: savings)
    expect(entry.item.name).to eq("Pay")
  end

  it "keeps spending in main whatever account is posted" do
    bread = create(:item, category: groceries, name: "Bread")

    post entries_path, params: { entry: { amount: "5", date: "2026-09-05", item_id: bread.id, account_id: savings.id } }

    expect(user.entries.sole.account).to be_nil
  end

  it "re-renders the form on a refusal" do
    post entries_path, params: { entry: { amount: "abc", date: "2026-09-05", item_id: create(:item, category: groceries).id } }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "renders the impact card for an expense category" do
    create(:rule, :rate, amount: 400, category: groceries)

    get impact_entries_path, params: { category_id: groceries.id, amount: "50" }

    expect(response.body).to include("$350.00")
  end
end
```

System specs: copy `spec/system/entries/**` and `spec/system/items/**` from the reference. Delete `entries/new/routing_spec.rb`; add to `entries/form_spec.rb` one `:js` example "shows the account select only for an income category and lands the entry there". Replace the five `sleep` calls in `entries/form_spec.rb` and `navbar_spec.rb` with waiting assertions (`expect(page).to have_css(...)`). Tag every example that uses the calculator pad or TomSelect `:js`. Everything else runs under Rack::Test.

Run: `bundle exec rspec spec/presenters/entry_impact_presenter_spec.rb spec/requests/entries_spec.rb spec/system/entries spec/system/items`
Expected: green.

- [ ] **Step 7: Proof grep and commit**

```bash
bundle exec rubocop -A app spec
git add -A
git commit -m "screens: entries and items"
```

---

## Task 4: Categories (spec commit 7)

**Files:**
- Create: `app/controllers/categories_controller.rb`, `app/presenters/category_budget_presenter.rb`
- Copy then adapt: `app/views/categories/**` except `_partials/show/_suggestion_pointer.html.erb`; `app/javascript/controllers/app/category/**`; `app/helpers/categories_helper.rb` (the reference's, which dropped the budget-status helpers)
- Keep from `main`: `app/controllers/categories/items_controller.rb`
- Specs: `spec/presenters/category_budget_presenter_spec.rb`, `spec/requests/categories_spec.rb`, `spec/system/categories/**`

**Interfaces:**
- Consumes: `ClaimLedger`, `ClaimRows#lines_for(category)`.
- Produces: `CategoryBudgetPresenter.new(category:, claims:, rows:, today:)` with `#ruled?`, `#claim`, `#lines`, `#rules`, `#needs_attention?`, `#fund?`, `#fund_line`, `#fund_rule`, `#fund_is_the_only_rule?`, `#fund_figure`, `#target`, `#progress_percentage`, `#bar?`; the category form posts `category[name]`, `category[category_type]`, `category[color]`, `category[priority]`, `category[regular]`.

- [ ] **Step 1: Presenter spec**

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategoryBudgetPresenter do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let(:ledger) { ClaimLedger.new(user, today: today) }
  let(:presenter) { described_class.new(category: groceries, claims: ledger, rows: ClaimRows.new(ledger: ledger, today: today), today: today) }

  before { create(:account, user: user) }

  it "is unruled with no rules", :aggregate_failures do
    expect(presenter).not_to be_ruled
    expect(presenter.claim).to eq(0)
    expect(presenter.lines).to be_empty
    expect(presenter).not_to be_fund
  end

  it "sums its rules' claims and finds a goal among them", :aggregate_failures do
    create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1))
    goal = create(:rule, :choice, amount: 600, anchor_date: Date.new(2026, 10, 15), item: create(:item, category: groceries), category: groceries, starts_on: Date.new(2026, 8, 1))

    expect(presenter).to be_ruled
    expect(presenter.claim).to eq(800)
    expect(presenter).to be_fund
    expect(presenter.fund_rule).to eq(goal)
    expect(presenter).not_to be_fund_is_the_only_rule
    expect(presenter.target).to be_nil
  end

  it "shows a progress bar when the goal is the category's only rule", :aggregate_failures do
    create(:rule, :choice, amount: 600, anchor_date: Date.new(2026, 10, 15), category: groceries, starts_on: Date.new(2026, 8, 1))

    expect(presenter).to be_fund_is_the_only_rule
    expect(presenter.target).to eq(600)
    expect(presenter.fund_figure).to eq(400)
    expect(presenter.progress_percentage).to eq(67)
    expect(presenter).to be_bar
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `bundle exec rspec spec/presenters/category_budget_presenter_spec.rb`
Expected: `uninitialized constant CategoryBudgetPresenter`.

- [ ] **Step 3: Presenter and controller**

`app/presenters/category_budget_presenter.rb`:

```ruby
# frozen_string_literal: true

# The holdings card on a category's page and the claim figure on its index card.
class CategoryBudgetPresenter
  attr_reader :category, :today

  def initialize(category:, claims:, rows:, today: category.user.today)
    @category = category
    @claims = claims
    @claim_rows = rows
    @today = today
  end

  def ruled? = lines.any?
  def lines = @claim_rows.lines_for(category)
  def rules = lines.map(&:rule)
  def claim = lines.sum(0.to_d, &:claim)
  def needs_attention? = lines.any?(&:trouble?)
  def fund? = fund_line.present?

  # A goal: a dated rule that is not a bill.
  def fund_line
    return @fund_line if defined?(@fund_line)

    @fund_line = lines.detect { |line| line.dated? && !line.rule.bill? }
  end

  def fund_rule = fund_line&.rule
  def fund_is_the_only_rule? = rules.one? && fund?
  def fund_figure = fund_line&.built_up

  def target
    return nil unless fund_is_the_only_rule?

    fund_line.target
  end

  def progress_percentage
    return 0 unless bar?

    (fund_figure / target * 100).round.clamp(0, 100)
  end

  def bar? = target&.positive? || false
end
```

`app/controllers/categories_controller.rb`:

```ruby
# frozen_string_literal: true

class CategoriesController < ApplicationController
  include Searchable
  include PeriodContext

  before_action :set_category, only: [:show, :edit, :update, :destroy, :toggle_tracked]
  before_action :set_categories, only: [:index]

  helper_method :claim_ledger, :claim_rows

  def index; end

  def show
    @holdings_card = CategoryBudgetPresenter.new(category: @category, claims: claim_ledger, rows: claim_rows) if @category.expense?
  end

  def new
    @category = current_user.categories.new(category_type: known_type(params[:type]) || :expense, color: Category::DEFAULT_COLOR)
  end

  def edit; end

  def create
    @category = current_user.categories.new(category_params)
    if @category.save
      redirect_to categories_path(type: @category.category_type), notice: "Category was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @category.update(category_params)
      redirect_to categories_path(type: @category.category_type), notice: "Category was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    category_type = @category.category_type
    @category.destroy
    redirect_to categories_path(type: category_type), notice: "Category was successfully deleted."
  end

  def toggle_tracked
    if @category.update(tracked: !@category.tracked?)
      redirect_back_or_to(reports_path)
    else
      redirect_back_or_to(reports_path, alert: "Could not update category.")
    end
  end

  def update_tracked
    params[:categories]&.each do |id, attrs|
      current_user.categories.find_by(id: id)&.update(tracked: attrs[:tracked] == "1")
    end
    redirect_back_or_to(reports_path)
  end

  private

  def set_category
    @category = current_user.categories.find(params[:id])
    @recent_entries = @category.entries.includes(:item).order(date: :desc).limit(5)
  end

  def category_params = params.expect(category: [:name, :category_type, :color, :priority, :regular])

  def known_type(type) = Category.category_types.key?(type) ? type : nil

  def set_categories
    @type = known_type(params[:type]) || "expense"
    @search_state = current_search_state(params)
    categories = current_user.categories.with_type(@type)
    categories = apply_search(categories, { q: params[:q], field: params[:field] })
    @categories = categories.order(name: :asc).to_a
  end

  def claim_rows = @claim_rows ||= ClaimRows.new(ledger: claim_ledger, today: current_user.today)
  def claim_ledger = @claim_ledger ||= ClaimLedger.new(current_user, today: current_user.today)
end
```

- [ ] **Step 4: Views**

```bash
for f in $(git ls-tree -r --name-only 4ee68de app/views/categories app/javascript/controllers/app/category); do git show 4ee68de:$f > $f; done
rm app/views/categories/_partials/show/_suggestion_pointer.html.erb
git show 4ee68de:app/helpers/categories_helper.rb > app/helpers/categories_helper.rb
```

Adapt:

- `_form.html.erb`: delete the `f.input :funded_since` block and its comment. Keep `f.input :priority` (label "Gives way", hint "Lower numbers give way first when money is short."). Add, inside the income-only section the form already toggles by type (the `data-controller="app--category--form"` element), `f.input :regular, as: :boolean, label: "Counts as typical income", hint: "Untick for bonuses and gifts."`.
- `_partials/show/_holdings_card.html.erb`: delete the `render "categories/_partials/show/suggestion_pointer"` line; `presenter.holding?` becomes `presenter.ruled?`; delete every `funded_since` line (the card no longer shows a funding date). Give the root element `data-holdings-card`.
- `_partials/show/_summary_card.html.erb` and `_partials/_category_card.html.erb`: `category.holder?` becomes `category.ruled?`; `claim_rows` and `claim_ledger` stay.
- `show.html.erb`, `index.html.erb`, `new/edit`: rename table only.

- [ ] **Step 5: Specs**

`spec/requests/categories_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories" do
  let(:user) { create(:user) }

  before { sign_in user }

  it "writes priority and the regular flag", :aggregate_failures do
    post categories_path, params: { category: { name: "Gifts", category_type: "income", regular: "0", priority: "3" } }

    expect(response).to redirect_to(categories_path(type: "income"))
    expect(user.categories.sole).to have_attributes(regular: false, priority: 3)
  end

  it "shows the holdings card only on an expense category", :aggregate_failures do
    create(:account, user: user)
    expense = create(:category, user: user)
    income = create(:category, :income, user: user)

    get category_path(expense)
    expect(response.body).to include("data-holdings-card")
    get category_path(income)
    expect(response.body).not_to include("data-holdings-card")
  end
end
```

System specs: copy `spec/system/categories/**` from the reference. `show/holdings_spec.rb` keeps one example per state (unruled, ruled, a goal with a bar) and drops the suggestion-pointer examples. `new/form_spec.rb` and `edit/form_spec.rb` gain one example each for the regular checkbox appearing only for income (`:js`, since the form toggles by script) and for priority saving. Delete every example about `funded_since`.

Run: `bundle exec rspec spec/presenters/category_budget_presenter_spec.rb spec/requests/categories_spec.rb spec/system/categories`
Expected: green.

- [ ] **Step 6: Proof grep and commit**

```bash
bundle exec rubocop -A app spec
git add -A
git commit -m "screens: categories"
```

### Squash checkpoint (spec commit 7)

After Task 4, fold Tasks 3 and 4 into one commit:

```bash
git reset --soft HEAD~2
git commit -m "screens: entries, items and categories"
```

---

## Task 5: Budget page, rules, adjustments and sacrifice (spec commit 8)

**Files:**
- Create: `app/presenters/budget_page_presenter.rb`, `app/presenters/rule_preview.rb`, `app/presenters/sacrifice_presenter.rb`, `app/controllers/budget_page_controller.rb`, `app/controllers/concerns/budget_page_state.rb`, `app/controllers/rules_controller.rb`, `app/controllers/adjustments_controller.rb`, `app/controllers/sacrifices_controller.rb`, `app/helpers/budget_page_helper.rb`, `app/helpers/sacrifices_helper.rb`
- Copy then adapt: `app/views/budget_page/**` except the five `_suggestion*.html.erb`; `app/views/budgets/**` to `app/views/rules/**` except `_chip.html.erb`; `app/views/sacrifices/show.html.erb`; `app/javascript/controllers/app/budget/rule_form_controller.js`, `app/javascript/controllers/app/budget_page/**`, `app/javascript/controllers/app/sacrifice/dial_controller.js`
- Specs: `spec/presenters/budget_page_presenter_spec.rb`, `spec/presenters/sacrifice_presenter_spec.rb`, `spec/requests/rules_spec.rb`, `spec/requests/budget_page_spec.rb`, `spec/requests/adjustments_spec.rb`, `spec/system/budget_page/**`, `spec/system/rules/form_spec.rb`, `spec/system/sacrifices/show_spec.rb`, `spec/helpers/budget_page_helper_spec.rb`

**Interfaces:**
- Consumes: `RuleForm`, `AdjustmentForm`, `CadenceChange`, `ClaimLedger`, `ClaimRows`, `AccountLedger#typical_income`, `Category.apply_fill_order`.
- Produces: `BudgetPagePresenter` (`#tiles`, `#category_rows`, `#reorderable_rows`, `#open?`, `#declaring?`, `#type_overview`, `#no_categories?`, `#rules_need`, `#typical_income`, `#leftover`, `#underwater?`, `#declared?`, `#history?`), `RulePreview`, `SacrificePresenter`; helpers `rule_name(rule)`, `rule_basis(rule)`, `rule_basis_phrase(rule)`, `rule_type_heading`, `reordered_category_ids`, `reorder_edge?`, `rule_amount_hint`, `category_toggle_path`, `category_toggle_label`, `rule_preview_*`, `interval_label`.

- [ ] **Step 1: Presenter specs**

`spec/presenters/budget_page_presenter_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe BudgetPagePresenter do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:presenter) { described_class.new(user: user, today: today) }
  let(:salary) { create(:category, :income, user: user, name: "Salary") }

  before { create(:account, user: user, opening_balance: 1_000) }

  def earn(amount, on:) = create(:entry, item: create(:item, category: salary), amount: amount, date: on)

  def rule_on(name, priority: 0, **attributes)
    create(:rule, category: create(:category, user: user, name: name, priority: priority), starts_on: Date.new(2026, 1, 1), **attributes)
  end

  it "lists ruled categories by priority then the unruled ones by name", :aggregate_failures do
    rule_on("Rent", priority: 1, amount: 900)
    rule_on("Fun", priority: 0, amount: 100)
    create(:category, user: user, name: "Aardvark")

    expect(presenter.category_rows.map(&:name)).to eq(["Fun", "Rent", "Aardvark"])
    expect(presenter.reorderable_rows.map(&:name)).to eq(["Fun", "Rent"])
    expect(presenter.category_rows.first).to be_ruled
    expect(presenter.category_rows.last).not_to be_ruled
    expect(presenter).not_to be_no_categories
  end

  it "compares what the rules need with typical income", :aggregate_failures do
    rule_on("Rent", :bill, amount: 900)
    earn(2_000, on: Date.new(2026, 8, 7))
    earn(2_000, on: Date.new(2026, 8, 25))

    expect(presenter.rules_need).to eq(900)
    expect(presenter.typical_income).to eq(2_000)
    expect(presenter.leftover).to eq(1_100)
    expect(presenter).to be_declared
    expect(presenter).to be_history
    expect(presenter.tiles).to have_attributes(need: 900, income: 2_000, fits: true, declared: true)
    expect(presenter.type_overview).to eq([[:bill, 900]])
  end

  it "has no history and no verdict until a period completes", :aggregate_failures do
    rule_on("Rent", :bill, amount: 900)

    expect(presenter.typical_income).to be_nil
    expect(presenter).not_to be_history
    expect(presenter).not_to be_underwater
    expect(presenter.tiles.fits).to be(false)
  end

  it "is underwater when the rules need more than comes in" do
    rule_on("Rent", :bill, amount: 3_000)
    earn(2_000, on: Date.new(2026, 8, 25))

    expect(presenter).to be_underwater
  end

  it "opens the category it is told to" do
    rent = rule_on("Rent", amount: 900).category

    expect(described_class.new(user: user, today: today, open_category_id: rent.id).open?(rent)).to be(true)
  end
end
```

`spec/presenters/sacrifice_presenter_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe SacrificePresenter do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:presenter) { described_class.new(user: user, today: today) }
  let(:salary) { create(:category, :income, user: user, name: "Salary") }

  before do
    create(:account, user: user)
    create(:entry, item: create(:item, category: salary), amount: 1_000, date: Date.new(2026, 8, 25))
  end

  def rule_on(name, **attributes)
    create(:rule, **{ category: create(:category, user: user, name: name), starts_on: Date.new(2026, 1, 1) }.merge(attributes))
  end

  it "measures the gap and splits rules into cuttable and fixed", :aggregate_failures do
    rule_on("Rent", :bill, amount: 900, anchor_date: Date.new(2026, 9, 12), starts_on: Date.new(2026, 9, 4))
    rule_on("Fun", :choice, amount: 300)
    rule_on("Insurance", :bill, amount: 600, anchor_date: Date.new(2026, 10, 1), interval_months: 6)

    expect(presenter).to be_declared
    expect(presenter).to be_underwater
    expect(presenter.gap).to eq(246.15)
    expect(presenter.cuttable_rows.map { |row| row.rule.category.name }).to eq(["Rent", "Fun"])
    expect(presenter.fixed_rows.map { |row| row.rule.category.name }).to eq(["Insurance"])
    expect(presenter).not_to be_unwinnable
    expect(presenter.rows_total).to eq(1_246.15)
  end

  it "is not underwater without a cadence or history" do
    expect(described_class.new(user: create(:user), today: today)).not_to be_underwater
  end
end
```

The figures: Rent is a one-off of $900 due Sep 12 starting Sep 4, so its standing ask is $900 over one period; Fun asks $300; Insurance asks 600 × 12 / (26 × 6) = $46.15; the rules need $1,246.15 against $1,000 of typical income, a gap of $246.15 that the two cuttable rules ($1,200) can close.

- [ ] **Step 2: Run them to see them fail**

Run: `bundle exec rspec spec/presenters/budget_page_presenter_spec.rb spec/presenters/sacrifice_presenter_spec.rb`
Expected: uninitialized constants.

- [ ] **Step 3: Presenters**

`app/presenters/budget_page_presenter.rb`:

```ruby
# frozen_string_literal: true

# The Budget page: the tiles, every expense category with its rules, and the declaration form.
class BudgetPagePresenter
  CategoryRow = Data.define(:category, :lines, :type_dots, :claimed, :open) do
    delegate :name, :priority, to: :category
    def open? = open
    def rule_count = lines.size
    def ruled? = lines.any?
    def needs_attention? = lines.any?(&:trouble?)
    def reorderable? = ruled?
  end
  Segment = Data.define(:type, :amount, :percent)
  Tiles = Data.define(:need, :segments, :income, :cadence, :leftover, :declared, :fits) do
    def declared? = declared
    def fits? = fits
  end

  TYPE_OVERVIEW_ORDER = [:bill, :usage, :choice].freeze

  attr_reader :user, :today, :declaration

  def initialize(user:, today: user.today, declaration: nil, open_category_id: nil, declaring: false)
    @user = user
    @today = today
    @declaration = declaration || user
    @open_category_id = open_category_id.presence&.to_s
    @declaring = declaring
  end

  def tiles
    @tiles ||= Tiles.new(need: rules_need, segments: segments, income: typical_income, cadence: user.period_cadence,
                         leftover: leftover, declared: declared?, fits: fits?)
  end

  def category_rows = @category_rows ||= ruled_rows + unruled_rows
  def reorderable_rows = @reorderable_rows ||= category_rows.select(&:reorderable?)
  def open?(category) = @open_category_id.present? && @open_category_id == category.id.to_s
  def declaring? = @declaring || declaration.errors.any?
  def no_categories? = category_rows.empty?

  def type_overview
    @type_overview ||= begin
      asks = claim_ledger.rules.group_by { |rule| rule.rule_type.to_sym }
      TYPE_OVERVIEW_ORDER.filter_map do |type|
        group = asks[type]
        [type, group.sum(0.to_d) { |rule| claim_ledger.calculator_for(rule).standing_ask }] if group
      end
    end
  end

  def rules_need = @rules_need ||= Rule.steady_need(user, today: today, ledger: claim_ledger)
  def typical_income = @typical_income ||= claim_ledger.account_ledger.typical_income
  def leftover = typical_income && (typical_income - rules_need)
  def declared? = user.period_cadence.present?
  def history? = typical_income.present?
  def underwater? = declared? && history? && rules_need > typical_income

  private

  def ruled_rows
    claim_rows.blocks
      .sort_by { |block| [block.category.priority, block.category.name] }
      .map { |block| row_for(block.category, lines: block.rows, claimed: block.claimed) }
  end

  def unruled_rows
    ruled = claim_rows.blocks.to_set { |block| block.category.id }
    expense_categories.reject { |category| ruled.include?(category.id) }
      .map { |category| row_for(category, lines: [], claimed: 0.to_d) }
  end

  def row_for(category, lines:, claimed:)
    CategoryRow.new(category: category, lines: lines, type_dots: lines.map(&:stripe_type), claimed: claimed, open: open?(category))
  end

  def expense_categories = @expense_categories ||= user.categories.expenses.order(:name).to_a

  def claim_rows
    @claim_rows ||= ClaimRows.new(ledger: claim_ledger, today: today, categories: user.categories.in_fill_order.to_a,
                                  adjustments: adjustments_this_period)
  end

  def segments
    total = type_overview.sum { |(_type, amount)| amount }
    return [] unless total.positive?

    type_overview.map { |(type, amount)| Segment.new(type: type, amount: amount, percent: ((amount / total) * 100).round.clamp(0, 100)) }
  end

  def fits? = declared? && history? && !underwater?
  def claim_ledger = @claim_ledger ||= ClaimLedger.new(user, today: today)

  def adjustments_this_period
    @adjustments_this_period ||= Adjustment.where(rule_id: claim_ledger.rules.map(&:id))
      .dated_within(user.period_containing(today)).order(:date, :created_at).group_by(&:rule_id)
  end
end
```

`app/presenters/rule_preview.rb`: copy from the reference, apply the rename table, and delete `converted_from_monthly?`, `monthly_amount` and their delegations. `rule` is `rule_form.rule`.

`app/presenters/sacrifice_presenter.rb`:

```ruby
# frozen_string_literal: true

# What would have to give when the rules need more per period than typical income brings in.
class SacrificePresenter
  Row = Data.define(:rule, :claim, :reason) do
    def cuttable? = reason.nil?
    def claim_param = DigitsHelper.digits(claim)
  end

  attr_reader :user, :today

  def initialize(user:, today: user.today)
    @user = user
    @today = today
  end

  def rules_need = @rules_need ||= Rule.steady_need(user, today: today, ledger: ledger)
  def typical_income = @typical_income ||= ledger.account_ledger.typical_income
  def gap = @gap ||= rules_need - typical_income.to_d
  def gap_param = DigitsHelper.digits(gap)
  def declared? = user.period_cadence.present? && typical_income.present?
  def underwater? = declared? && gap.positive?
  def cuttable_rows = rows.select(&:cuttable?)
  def fixed_rows = rows.reject(&:cuttable?)
  def cuttable_total = @cuttable_total ||= cuttable_rows.sum(0.to_d, &:claim)
  def unwinnable? = cuttable_total < gap
  def unclosable = gap - cuttable_total
  def rows_total = rows.sum(0.to_d, &:claim)

  private

  # A rolling bill is fixed; an allowance or a one-off can be cut.
  def rows
    @rows ||= ledger.rules
      .map { |rule| Row.new(rule: rule, claim: rule.steady_ask(today: today), reason: reason_for(rule)) }
      .sort_by { |row| [-row.claim, row.rule.category.name, row.rule.id] }
  end

  def reason_for(rule) = rule.cadence == :every_n ? :fixed : nil
  def ledger = @ledger ||= ClaimLedger.new(user, today: today)
end
```

- [ ] **Step 4: Controllers, concern and helpers**

`app/controllers/concerns/budget_page_state.rb`:

```ruby
# frozen_string_literal: true

# The Budget page's presenter, for the controllers that render it after a write.
module BudgetPageState
  extend ActiveSupport::Concern

  private

  def build_budget_page(user: current_user, declaration: nil)
    BudgetPagePresenter.new(user: user, today: user.today, declaration: declaration,
                            open_category_id: params[:open], declaring: params[:declare].present?)
  end

  def refuse_on_budget_page(message)
    flash.now[:alert] = message
    @presenter = build_budget_page
    render "budget_page/show", status: :unprocessable_content
  end
end
```

`app/controllers/budget_page_controller.rb`:

```ruby
# frozen_string_literal: true

class BudgetPageController < ApplicationController
  include BudgetPageState

  def show
    @presenter = build_budget_page
  end

  def update
    change = CadenceChange.new(user: current_user, declaration: declaration_params)
    return offer_scaling(change) if change.offered? && scale_choice.nil?

    if change.apply(scale: scale_choice)
      redirect_to budget_page_path, notice: saved_notice(change)
    else
      @presenter = build_budget_page(user: User.find(current_user.id), declaration: current_user)
      render :show, status: :unprocessable_content
    end
  end

  def reorder
    ordered = Category.apply_fill_order(user: current_user, category_ids: params.permit(category_ids: [])[:category_ids])
    return redirect_to(budget_page_path, notice: "Your money fills them in that order now.") if ordered

    refuse_on_budget_page("That order didn't match your categories — nothing was changed. Reload and try again.")
  end

  private

  def offer_scaling(change)
    @cadence_change = change
    @presenter = build_budget_page
    render :show, status: :unprocessable_content
  end

  def scale_choice
    return nil if params[:scale].blank?

    params[:scale] == "1"
  end

  def saved_notice(change)
    return "Your period is saved — every figure below is re-derived." unless change.scaled?

    "Your period is saved and your per-period amounts were scaled to it — every figure below is re-derived."
  end

  def declaration_params = params.expect(user: [:period_cadence, :period_anchor_date])
end
```

`app/controllers/rules_controller.rb`:

```ruby
# frozen_string_literal: true

class RulesController < ApplicationController
  before_action :set_rule, only: [:edit, :update, :destroy]
  before_action :set_previewed_rule, only: [:preview]

  NEW_NEEDS_A_CATEGORY = "Open a category on the Budget page to write a rule for it."

  def new
    @rule_form = RuleForm.new(current_user, prefill)
    return redirect_to budget_page_path, alert: NEW_NEEDS_A_CATEGORY if @rule_form.rule.category.blank?

    prepare_page
  end

  def edit
    @rule_form = RuleForm.new(current_user, RuleForm.from(@rule), rule: @rule)
    prepare_page
  end

  def create
    @rule_form = RuleForm.new(current_user, rule_params)
    write(:new, "Rule was successfully created.")
  end

  def update
    @rule_form = RuleForm.new(current_user, RuleForm.from(@rule).merge(update_params), rule: @rule)
    write(:edit, "Rule was successfully updated.")
  end

  def preview
    words = @rule ? RuleForm.from(@rule).merge(payload.except(:category_id)) : payload
    @rule_form = RuleForm.new(current_user, words, rule: @rule)
    @preview = RulePreview.new(@rule_form, user: current_user)
    return render partial: "rules/preview", locals: { preview: @preview } if turbo_frame_request?

    prepare_page
    render @rule ? :edit : :new
  end

  def destroy
    @rule.destroy
    redirect_to budget_page_path, notice: "Rule was successfully deleted."
  end

  private

  def write(template, notice)
    if @rule_form.save
      redirect_to budget_page_path(open: @rule_form.rule.category_id), notice: notice
    else
      prepare_page
      render template, status: :unprocessable_content
    end
  end

  def set_rule = @rule = Rule.for_user(current_user).find(params[:id])

  def set_previewed_rule
    @rule = Rule.for_user(current_user).find(params[:id]) if params[:id].present?
  end

  def prepare_page
    @category = @rule_form.rule.category
    @preview ||= RulePreview.new(@rule_form, user: current_user)
  end

  def prefill
    scoped({ category_id: params[:category_id].presence }.compact.merge(payload))
  end

  def payload = params[:rule].blank? ? {} : params.expect(rule: RuleForm::FIELDS).to_h.symbolize_keys
  def rule_params = scoped(params.expect(rule: RuleForm::FIELDS).to_h.symbolize_keys)
  def update_params = scoped(params.expect(rule: RuleForm::FIELDS - [:category_id]).to_h.symbolize_keys)

  # Ids are looked up through current_user so a foreign id 404s instead of writing.
  def scoped(words)
    words[:category_id] = current_user.categories.find(words[:category_id]).id if words[:category_id].present?
    words[:item_id] = current_user.items.find(words[:item_id]).id if words[:item_id].present?
    words
  end
end
```

`app/controllers/adjustments_controller.rb`:

```ruby
# frozen_string_literal: true

class AdjustmentsController < ApplicationController
  include BudgetPageState

  def create
    rule = scoped_rule
    form = AdjustmentForm.new(rule: rule, params: params, name: helpers.rule_name(rule), today: current_user.today)
    if form.save
      redirect_to back_to(rule), notice: confirmation(form)
    else
      refuse_on_budget_page(form.error_sentence)
    end
  end

  def destroy
    adjustment = Adjustment.where(rule_id: Rule.for_user(current_user).select(:id)).find(params[:id])
    rule = adjustment.rule
    adjustment.destroy
    redirect_to back_to(rule), notice: removal(adjustment, rule)
  end

  private

  def back_to(rule) = budget_page_path(open: rule.category_id)
  def scoped_rule = Rule.for_user(current_user).find(params[:rule_id])

  def confirmation(form)
    money = helpers.number_to_currency(form.adjustment.amount.abs)
    name = form.name
    negative = form.adjustment.amount.negative?
    return "Skipped this period for #{name} — #{money} less set aside." if form.skip?

    if form.allowance?
      negative ? "Reduced #{name} by #{money} this period." : "Topped up #{name} by #{money} this period."
    else
      negative ? "Took back #{money} from #{name}." : "Set aside #{money} for #{name}."
    end
  end

  def removal(adjustment, rule)
    money = helpers.number_to_currency(adjustment.amount.abs)
    name = helpers.rule_name(rule)
    negative = adjustment.amount.negative?
    if rule.claim_calculator(today: current_user.today).allowance?
      negative ? "Removed the #{money} reduction on #{name}." : "Removed the #{money} top-up on #{name}."
    else
      negative ? "Removed the #{money} taken back from #{name}." : "Removed the #{money} set aside for #{name}."
    end
  end
end
```

`app/controllers/sacrifices_controller.rb`:

```ruby
# frozen_string_literal: true

class SacrificesController < ApplicationController
  def show
    @presenter = SacrificePresenter.new(user: current_user, today: current_user.today)
    return if @presenter.underwater?

    redirect_to budget_page_path, notice: refusal_for(@presenter)
  end

  private

  def refusal_for(presenter)
    return "Set your period on the Budget page and log a period of income, and we can say what would have to give." unless presenter.declared?

    "Your rules already fit what you bring in, so there's nothing here to cut."
  end
end
```

`app/helpers/budget_page_helper.rb`: copy from the reference, apply the rename table, then delete `budget_monthly_conversion_note`, `suggestion_key`, `suggestion_accept_path`, `suggestion_proposes_a_rule?`, `suggestion_accept_label`, `spent_recently_words` and `rule_preview_units`; rename `suggestion_interval_label` to `interval_label`; `rule_basis` reads `rule.cadence` with arms `:per_period`, `:one_off`, `:every_n` only. `app/helpers/sacrifices_helper.rb`: copy and rename (`row.rule`).

- [ ] **Step 5: Views and JavaScript**

```bash
for f in $(git ls-tree -r --name-only 4ee68de app/views/budget_page app/views/sacrifices app/javascript/controllers/app/budget app/javascript/controllers/app/budget_page app/javascript/controllers/app/sacrifice); do git show 4ee68de:$f > $f; done
rm app/views/budget_page/_suggestion*.html.erb
mkdir -p app/views/rules
for f in _form _preview edit new; do git show 4ee68de:app/views/budgets/$f.html.erb > app/views/rules/$f.html.erb; done
```

Adapt:

- `budget_page/_category_row.html.erb` and `_category_open.html.erb`: delete the suggestion badge, the suggestions block, the hidden-suggestions block and the `spent_recently` line. A row shows its name, rule count, type dots, claimed figure and the toggle.
- `budget_page/_declaration_form.html.erb`: delete the `typical_income` input; the submit reads "Save period". Above the form, when `presenter.history?` is false, one sentence: "Typical income is measured from your regular income categories once a full period has passed."
- `budget_page/_tiles.html.erb`: the income tile shows `tiles.income` or "not enough history yet".
- `budget_page/show.html.erb`, `_adjust.html.erb`, `_cadence_confirm.html.erb`, `_reorder_controls.html.erb`, `_empty.html.erb`: rename table.
- `rules/_form.html.erb`: `simple_form_for rule_form, as: :rule, url: (rule_form.persisted? ? rule_path(rule_form.rule) : rules_path)`; delete the chips block (`chips.each`) and the monthly-conversion note; add `f.input :starts_on, as: :date, label: "Counts from"` under the amount with hint "Spending before this day is not counted."; the preview frame posts to `preview_rules_path`.
- `rules/_preview.html.erb`, `new.html.erb`, `edit.html.erb`: rename table; delete `@suggested_amount` and `@current_amount` references.
- `sacrifices/show.html.erb`: rename table; `row.rule`.
- `rule_form_controller.js`: rename the preview URL data value if it is hard-coded; nothing else changes. `category_list_controller.js` and `reorder_controller.js`: delete the suggestion-badge handling; keep open/close and reorder.

- [ ] **Step 6: Request specs**

`spec/requests/rules_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rules" do
  let(:user) { create(:user, :biweekly) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }

  before do
    create(:account, user: user)
    sign_in user
  end

  it "writes a rule and opens its category on the Budget page", :aggregate_failures do
    post rules_path, params: { rule: { category_id: groceries.id, rule_type: "usage", amount: "400", schedule: "per_period", starts_on: "2026-09-01" } }

    expect(response).to redirect_to(budget_page_path(open: groceries.id))
    expect(groceries.rules.sole).to have_attributes(amount: 400, starts_on: Date.new(2026, 9, 1))
  end

  it "re-renders with the refusal" do
    post rules_path, params: { rule: { category_id: groceries.id, rule_type: "usage", amount: "0", schedule: "per_period" } }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "previews inside a turbo frame" do
    post preview_rules_path, params: { rule: { category_id: groceries.id, rule_type: "bill", amount: "600", schedule: "by_date", anchor_date: "2026-10-15" } },
                             headers: { "Turbo-Frame" => "rule-preview" }

    expect(response.body).to include("$600.00")
  end

  it "sends new without a category back to the Budget page" do
    get new_rule_path

    expect(response).to redirect_to(budget_page_path)
  end

  it "never edits another user's rule" do
    expect { get edit_rule_path(create(:rule)) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
```

`spec/requests/budget_page_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Budget page" do
  let(:user) { create(:user, :biweekly) }

  before do
    create(:account, user: user)
    sign_in user
  end

  it "saves a period declaration", :aggregate_failures do
    patch budget_page_user_path, params: { user: { period_cadence: "weekly", period_anchor_date: "2026-09-04" } }

    expect(response).to redirect_to(budget_page_path)
    expect(user.reload).to be_period_weekly
  end

  it "offers scaling when the cadence changes and per-period rules exist" do
    create(:rule, :rate, category: create(:category, user: user))

    patch budget_page_user_path, params: { user: { period_cadence: "monthly", period_anchor_date: "2026-09-04" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("scale")
  end

  it "reorders the ruled categories", :aggregate_failures do
    a = create(:category, user: user, name: "A", priority: 0)
    b = create(:category, user: user, name: "B", priority: 1)
    [a, b].each { |category| create(:rule, category: category) }

    patch budget_page_reorder_path, params: { category_ids: [b.id, a.id] }

    expect(response).to redirect_to(budget_page_path)
    expect(b.reload.priority).to eq(0)
  end
end
```

`spec/requests/adjustments_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Adjustments" do
  let(:user) { create(:user, :biweekly) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let!(:rule) { create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1)) }

  before do
    create(:account, user: user)
    sign_in user
  end

  it "tops up and takes back", :aggregate_failures do
    post adjustments_path, params: { rule_id: rule.id, amount: "50" }
    expect(response).to redirect_to(budget_page_path(open: groceries.id))
    expect(rule.adjustments.sole.amount).to eq(50)

    delete adjustment_path(rule.adjustments.sole)
    expect(rule.adjustments).to be_empty
  end

  it "refuses a date outside the period with the reason" do
    post adjustments_path, params: { rule_id: rule.id, amount: "50", date: (user.period_containing(user.today).first - 1).to_s }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("pick a date between")
  end
end
```

- [ ] **Step 7: System specs**

Copy `spec/system/budget_page/**` (delete `suggestions_spec.rb`), `spec/system/budgets/form_spec.rb` to `spec/system/rules/form_spec.rb`, and `spec/system/sacrifices/show_spec.rb`. Rewrite helpers on the new factories as in Task 2. Keep: `list_spec` (rows and order), `open_spec` (open and close, `:js`), `reorder_spec` (`:js`), `rules_spec` (each shape reads its line), `adjustments_spec` (each button, the refusal), `tiles_spec` (need, income or "not enough history", fits and underwater), `rules/form_spec` (the two schedules, keeps, repeats, the live preview `:js`, errors, `starts_on`), `sacrifices/show_spec` (cuttable and fixed rows, the dial `:js`). Delete every example about suggestions, chips, typed income and monthly conversion.

`spec/helpers/budget_page_helper_spec.rb`: copy from the reference and delete the suggestion and conversion examples.

Run: `bundle exec rspec spec/presenters spec/requests spec/helpers spec/system/budget_page spec/system/rules spec/system/sacrifices`
Expected: green.

- [ ] **Step 8: Proof grep and commit**

```bash
bundle exec rubocop -A app spec
git add -A
git commit -m "screens: budget page, rules, adjustments and sacrifice"
```

---

## Task 6: Calendar and reports (spec commit 9)

**Files:**
- Create: `app/services/category_stats.rb` (from `app/services/category_calculator.rb`), `spec/services/category_stats_spec.rb` (from `spec/services/category_calculator_spec.rb`)
- Copy then adapt: `app/controllers/calendar_controller.rb`, `app/controllers/dashboard_controller.rb`, `app/controllers/concerns/date_context.rb`, `app/presenters/monthly_calendar_presenter.rb`, `app/presenters/weekly_calendar_presenter.rb`, `app/presenters/dashboard_presenter.rb`, `app/presenters/dashboard/*.rb`, `app/views/dashboard/**`, `app/views/calendar/**`, `app/helpers/calendar_helper.rb`
- Modify: `app/models/category.rb` (`calculator` becomes `stats`)
- Specs: `spec/presenters/dashboard/overview_presenter_spec.rb`, `spec/system/dashboard/**`, `spec/system/calendar/**`, `spec/system/timezone/localization_spec.rb`, `spec/system/navbar_spec.rb`, `spec/system/authentication_spec.rb`, `spec/system/capybaras_spec.rb`

**Interfaces:**
- Produces: `CategoryStats.new(category, date, period:)` with the same API as `main`'s `CategoryCalculator`; `Category#stats`; the reports page splits expenses into "unruled" (was buffer) and "ruled" (was envelope) by `Category.with_a_rule`; the savings strip lists `Rule.saving_toward_a_date` rules.

- [ ] **Step 1: Rename the stats service**

```bash
git mv app/services/category_calculator.rb app/services/category_stats.rb
git mv spec/services/category_calculator_spec.rb spec/services/category_stats_spec.rb
sed -i '' -e 's/CategoryCalculator/CategoryStats/g' app/services/category_stats.rb spec/services/category_stats_spec.rb
sed -i '' -e 's/def calculator(date = user.today, period: :monthly)/def stats(date = user.today, period: :monthly)/' -e 's/CategoryCalculator.new/CategoryStats.new/' app/models/category.rb
```

In `spec/services/category_stats_spec.rb`, `date:` values are timestamps on `main`; make them dates. Run: `bundle exec rspec spec/services/category_stats_spec.rb`. Expected: green.

- [ ] **Step 2: Copy and adapt the calendar and dashboard**

```bash
for f in $(git ls-tree -r --name-only 4ee68de app/views/dashboard app/views/calendar app/presenters/dashboard); do git show 4ee68de:$f > $f; done
for f in app/controllers/calendar_controller.rb app/controllers/dashboard_controller.rb app/controllers/concerns/date_context.rb \
         app/presenters/monthly_calendar_presenter.rb app/presenters/weekly_calendar_presenter.rb app/presenters/dashboard_presenter.rb app/helpers/calendar_helper.rb; do
  git show 4ee68de:$f > $f
done
```

Adapt `app/presenters/dashboard_presenter.rb`:

- `tracked_buffer_funded_categories` becomes `tracked_unruled_categories = tracked_expense_categories.reject(&:ruled?)`; `tracked_enveloped_categories` becomes `tracked_ruled_categories = tracked_expense_categories.select(&:ruled?)`; `buffer_funded_expenses` becomes `unruled_expenses = @user.entries.expenses.where.not(categories: { id: Category.with_a_rule.select(:id) })`; `enveloped_expenses` becomes `ruled_expenses = @user.entries.expenses.where(categories: { id: Category.with_a_rule.select(:id) })`; `spendable` and `earned` become `expenses` and `incomes`; `category.calculator` becomes `category.stats`; `includes(items: :entries)` gains `:rules` where `ruled?` is asked.
- `dashboard/expenses_presenter.rb`: the six `*_buffer_*` and `*_envelope_*` readers keep their names on the view side but read the renamed scopes; delegate names in `DashboardPresenter` unchanged.
- `dashboard/overview_presenter.rb`: `savings_categories` becomes `@user.categories.expenses.where(id: Rule.saving_toward_a_date.select(:category_id)).includes(:rules).order(:name)`; `savings_line` picks `category.rules.select(&:saving_toward_a_date?).sole`.
- Calendar presenters: entries' `date` is a date; every `.to_date`, `beginning_of_day` and `end_of_day` on an entry date goes; ranges are date ranges.
- Views: rename table. `_savings_strip.html.erb` reads `line.rule`.

- [ ] **Step 3: Specs**

Copy `spec/presenters/dashboard/overview_presenter_spec.rb` and `spec/system/dashboard/**`, `spec/system/calendar/**`, `spec/system/timezone/localization_spec.rb`, `spec/system/navbar_spec.rb`, `spec/system/authentication_spec.rb`, `spec/system/capybaras_spec.rb` from the reference. Rename helpers; entries take dates. Replace `navbar_spec.rb`'s `sleep 0.5` with a waiting assertion. Tag the chart examples `:js` (Chartkick draws by script); everything else runs under Rack::Test.

Run: `bundle exec rspec spec/services/category_stats_spec.rb spec/presenters/dashboard spec/system/dashboard spec/system/calendar spec/system/timezone spec/system/navbar_spec.rb spec/system/authentication_spec.rb spec/system/capybaras_spec.rb`
Expected: green.

- [ ] **Step 4: Proof grep and commit**

```bash
bundle exec rubocop -A app spec
git add -A
git commit -m "screens: calendar and reports"
```

---

## Task 7: Seeds, documentation and CI (spec commit 10)

**Files:**
- Modify: `db/seeds.rb`, `CLAUDE.md`, `spec/testing_guidelines.md`, `docs/coding-standards.md`, `README.md`
- Create: `spec/seeds_spec.rb`

- [ ] **Step 1: Seeds**

```ruby
# frozen_string_literal: true

# A demo household on a fortnightly grid: four accounts, income landing in two of them, every
# rule shape, a transfer, and adjustments. Log in as demo@example.com / password123.
demo_timezone = "America/New_York"
Time.zone = demo_timezone

[Adjustment, Rule, Transfer, Entry, Item, Category, Account, User].each(&:delete_all)

user = User.create!(email: "demo@example.com", password: "password123", name: "Demo User", timezone: demo_timezone)
today = Time.find_zone!(user.timezone).today
user.update!(period_cadence: :biweekly, period_anchor_date: today)
periods_ago = ->(n) { today - (n * 14) }
demo_start = periods_ago[13]

checking = Account.open(user, name: "Checking", balance: 1_800)
ally = Account.open(user, name: "Ally Savings", balance: 4_200)
side_gig = Account.open(user, name: "Side Gig Checking", balance: 350)
Account.open(user, name: "Health Savings", balance: 900)

category = ->(name, type, color, **attributes) { user.categories.create!(name: name, category_type: type, color: color, **attributes) }
item = ->(cat, name) { cat.items.create!(name: name) }
rule = ->(cat, **attributes) { Rule.create!(category: cat, starts_on: demo_start, rule_type: :usage, **attributes) }
log = ->(it, amount, on, description = nil, account: nil) { it.entries.create!(amount: amount, date: on, description: description, account: account) }

salary = category["Salary", :income, "#66BB6A"]
freelance = category["Freelance", :income, "#26C6DA"]
gifts = category["Gifts", :income, "#EC407A", regular: false]
paycheck = item[salary, "Paycheck"]
contract = item[freelance, "Contract work"]
birthday = item[gifts, "Birthday"]

rent = category["Rent", :expense, "#E57373", priority: 1]
utilities = category["Utilities", :expense, "#FFD54F", priority: 2]
dentist = category["Dentist", :expense, "#F48FB1", priority: 3]
car_insurance = category["Car Insurance", :expense, "#9575CD", priority: 4]
dining = category["Dining Out", :expense, "#81C784", priority: 5]
groceries = category["Groceries", :expense, "#8BC34A", priority: 6]
pet_care = category["Pet Care", :expense, "#A1887F", priority: 7]
vacation = category["Vacation to Europe", :expense, "#FF8A65", priority: 8]
coffee = category["Coffee", :expense, "#795548"]

rent_item = item[rent, "Monthly Rent"]
electric = item[utilities, "Electric Bill"]
internet = item[utilities, "Internet"]
restaurants = item[dining, "Restaurants"]
supermarket = item[groceries, "Supermarket"]
pet_food = item[pet_care, "Pet Food"]
vet = item[pet_care, "Vet"]
flights = item[vacation, "Flights & Hotels"]
cafe = item[coffee, "Cafe"]

rule[rent, item: rent_item, amount: 1_500, interval_months: 1, anchor_date: today + 10, rule_type: :bill]
rule[utilities, item: electric, amount: 120, interval_months: 1, anchor_date: today - 10]
rule[dentist, amount: 300, anchor_date: today + 3, rule_type: :bill]
rule[car_insurance, amount: 1_200, interval_months: 6, anchor_date: today + 1.month, rule_type: :bill]
rule[dining, amount: 100, rule_type: :choice]
rule[groceries, amount: 400]
rule[pet_care, amount: 60, keeps_unspent: true]
rule[pet_care, item: vet, amount: 180, anchor_date: today + 20, rule_type: :bill]
rule[vacation, amount: 5_000, anchor_date: demo_start + (14 * 78) - 1, rule_type: :choice]

(0..13).each do |n|
  payday = periods_ago[13 - n]
  log[paycheck, 2_050, payday, "Fortnightly pay"]
  log[contract, 400, payday + 3, "Invoice", account: side_gig] if n.even?
  log[supermarket, 180, payday + 2]
  log[supermarket, 165, payday + 9]
  log[restaurants, 45, payday + 5]
  log[cafe, 12, payday + 1]
  log[pet_food, 38, payday + 4]
  log[electric, 118, payday + 1] if n.odd?
  log[internet, 60, payday + 1] if n.odd?
  log[rent_item, 1_500, payday + 1] if n.odd?
end
log[birthday, 200, today - 30, "From Mom"]
log[flights, 620, today - 40, "Deposit on flights"]

Transfer.create!(from_account: checking, to_account: ally, amount: 300, date: today - 7)
Adjustment.create!(rule: Rule.find_by!(category: vacation, item_id: nil), amount: 250, date: today - 3)
Adjustment.create!(rule: Rule.find_by!(category: dining, item_id: nil), amount: -20, date: today - 1)

Rails.logger.debug { "Seeded #{user.email}: #{Account.count} accounts, #{Category.count} categories, #{Entry.count} entries, #{Rule.count} rules" }
```

`spec/seeds_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "db/seeds.rb" do
  it "plants a demo household the app can read", :aggregate_failures do
    load Rails.root.join("db/seeds.rb")

    user = User.find_by!(email: "demo@example.com")
    ledger = ClaimLedger.new(user)
    expect(user.accounts.count).to eq(4)
    expect(user.main_account.name).to eq("Checking")
    expect(user.rules.count).to eq(9)
    expect(ledger.total_claims).to be > 0
    expect(ledger.account_ledger.typical_income).to be > 2_000
    expect(HomePresenter.new(user: user).troubles.map(&:kind)).not_to include(:structural)
  end
end
```

Run: `bundle exec rspec spec/seeds_spec.rb` then `bin/rails db:seed:replant`. Expected: green, then the log line.

- [ ] **Step 2: CLAUDE.md**

Replace the "Testing Workflow" section (from `## Testing Workflow` to the line before `## Summary: Implementation Checklist`) with:

```markdown
## Testing Workflow

Use the `system-test-writer` skill to write system tests. Logic (figures, states, validations,
formulas) is proven in model, service and presenter specs. A system spec proves a page renders
its figures once, and every real interaction.

### Drivers

System specs run under Rack::Test. Tag an example `:js` only when it needs JavaScript (the
calculator pad, TomSelect, the rule preview, drag reorder, charts, a 375px layout). `:js`
examples share one headless Chrome per process; the browser is never restarted between examples.

### Running Tests

Run a directory, or the whole suite in parallel:

```bash
bundle exec rspec spec/models                     # one directory
bundle exec rspec spec/system/home/money_spec.rb  # one file
bundle exec parallel_rspec spec                    # everything, across cores
```

The test databases are `seriously_broke_test`, `seriously_broke_test2`, … (`TEST_ENV_NUMBER`);
`bundle exec rake parallel:create parallel:prepare` makes them.

### Rules

- No `sleep`. Wait with a Capybara assertion (`have_content`, `have_css`, `have_current_path`).
- After a `click_*`, assert on the page before asserting on the database.
- Fixtures pass `today:` and explicit dates; nothing reads the wall clock inside `travel_to`.
- A narrow-viewport example uses `Emulation.setDeviceMetricsOverride` (see `spec/system/home/money_spec.rb`).
```

In the "Summary: Implementation Checklist", item 8 becomes: `**Run tests** - Run the directory you touched with `bundle exec rspec spec/<dir>`, then `bundle exec parallel_rspec spec` before committing`. In the "Commands" block replace the three rspec lines with the three above.

- [ ] **Step 3: Testing guidelines, coding standards, README**

`spec/testing_guidelines.md`: add a "Drivers and speed" section at the top with the same three rules as CLAUDE.md, and change every `create(:savings_pool ...)` or `budget` example to the new factories. `docs/coding-standards.md`: in the Presenter and Calculator sections, name `AccountLedger`, `ClaimCalculator`, `ClaimLedger` and the form objects as the examples, and delete mentions of savings pools. `README.md`: the setup section mentions `config/database.yml.example` and `parallel:create parallel:prepare`.

- [ ] **Step 4: Commit**

```bash
bundle exec rubocop -A db/seeds.rb spec/seeds_spec.rb
git add -A
git commit -m "seeds, docs and CI for the accounts-and-rules design"
```

---

## Task 8: The whole suite, timed, and the eyes-on check

- [ ] **Step 1: Run everything, in parallel, and record the time**

```bash
pgrep -f "[r]spec" && echo "another rspec is running; wait" || true
time bundle exec parallel_rspec spec
```

Expected: 0 failures. Record the wall time in the commit message of Step 3. If it is over five minutes, `bundle exec rspec spec/system --profile 20` names the slowest examples; each is either missing a `:js` tag it does not need, or re-proving a figure a presenter spec already holds.

- [ ] **Step 2: Look at every page**

```bash
bin/rails db:seed:replant && bin/rails tailwindcss:build && bin/rails server -p 3001
```

Log in as `demo@example.com` / `password123` with the `agent-browser` skill and take a 1440px screenshot of Home, Budget, a category page, the rule form, an entry form with an income category chosen, Sacrifice (it redirects unless underwater; that is fine), Calendar, Reports and Settings. Check the console for errors. Anything that renders a raw exception or an empty figure is a bug in this plan's adaptation, not in the design; fix it in the task that owns the page and re-run that task's specs. Then `rm -f *.png`.

- [ ] **Step 3: Final commit and hand-off**

```bash
git add -A
git commit -m "verified: full suite green in <time>; every page checked in the browser"
git log --oneline main..HEAD
```

Expected: the squash-checkpoint commits plus Task 8's. The branch is ready for a pull request to `main`; the reference branch `feature/envelope-budgeting` can be deleted once it merges.

---

## Self-review

- Spec §5 components: every presenter and controller has a task (Home 2, Entries 3, Categories 4, Budget/Rules/Adjustments/Sacrifice 5, Calendar/Reports 6). `CategoryStats` Task 6. The two concerns replace the reference's controller inheritance.
- Spec §6 screens: each page's view directory is copied and adapted in its task; suggestions are absent by construction (the partials are never copied and the proof grep refuses the word).
- Spec §8: Task 7 rewrites `CLAUDE.md`; Task 8 measures the suite.
- Spec §9: commits 6 to 10 map to Tasks 1+2, 3+4, 5, 6, 7.
- Names used across tasks: `HomeState#assign_home_state` (Task 2), `BudgetPageState#build_budget_page` and `#refuse_on_budget_page` (Task 5), `rule_name` helper (Task 5, used by the adjustments controller), `Category#ruled?` and `Category.with_a_rule` (core plan Task 6), `AccountLedger#typical_income` (core plan Task 10). All consistent.
