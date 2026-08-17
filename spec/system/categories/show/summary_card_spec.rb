# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Show - Summary Card Period Labels", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  # THE PERIOD LABELS AN EXPENSE CATEGORY GETS. `Monthly Budget` / `YTD Budget` belonged to the
  # cap arm, which is deleted (plan 3, task 3) — an expense category names a pool now, so it takes
  # the pooled arm and the period word rides on `Spent`.
  describe "expense category labels", :aggregate_failures do
    let!(:category) { create(:category, category_type: "expense", user: user, name: "Food") }
    let!(:item) { create(:item, category: category, name: "Groceries") }

    before { create(:entry, item: item, amount: 100, date: base_date + 5.days) }

    it "shows Monthly labels in default view" do
      visit category_path(category)

      expect(page).to have_content("Spent this month")
      expect(page).to have_content("Monthly Spending Trend")
      expect(page).to have_content("Items This Month")
      expect(page).to have_no_content("Monthly Budget")
    end

    it "shows YTD labels in YTD view" do
      visit category_path(category, period: "ytd")

      expect(page).to have_content("Spent this year")
      expect(page).to have_content("YTD Spending Trend")
      expect(page).to have_content("Items This Year")
      expect(page).to have_no_content("YTD Budget")
    end
  end

  # THE LEFT COLUMN'S OWN NOUN (2d whole-plan review, fix 2, found in the visual check). This
  # sentence read "Funded by savings pool <name>" for every pool-covered expense category — false
  # twice over about an ENVELOPE (not a savings pool, and it is not funding anything: the money
  # comes out of it), and false once about a goal an expense category SPENDS from. The card sits on
  # the same page as the budget block and the pool card, which had both been moved onto
  # `Pool#noun`; this one was still saying the third thing.
  describe "what the pool-covered sentence calls the pool", :aggregate_failures do
    let(:checking) { create(:pool, :account, user: user, name: "Checking") }

    it "names an envelope an envelope" do
      envelope = create(:pool, :budget_pool, user: user, account: checking, name: "Groceries")

      visit category_path(create(:category, :expense, user: user, name: "Food", pool: envelope))

      expect(page).to have_content("Spending here comes out of the envelope Groceries")
      expect(page).to have_no_content("Funded by savings pool")
    end

    # The other direction on the same sentence, and the one the demo actually holds
    # (Health → Emergency Fund).
    it "names a savings pool a goal" do
      goal = create(:pool, user: user, name: "Emergency Fund", target_amount: 2_000)

      visit category_path(create(:category, :expense, user: user, name: "Health", pool: goal))

      expect(page).to have_content("Spending here comes out of the goal Emergency Fund")
      expect(page).to have_no_content("comes out of the envelope")
    end
  end

  describe "income category labels", :aggregate_failures do
    let!(:category) { create(:category, category_type: "income", user: user, name: "Salary") }
    let!(:item) { create(:item, category: category, name: "Paycheck") }

    before { create(:entry, item: item, amount: 1000, date: base_date + 3.days) }

    it "shows Monthly labels in default view" do
      visit category_path(category)

      expect(page).to have_content("Monthly Income")
      expect(page).to have_content("Items This Month")
    end

    it "shows YTD labels in YTD view" do
      visit category_path(category, period: "ytd")

      expect(page).to have_content("YTD Income")
      expect(page).to have_content("Items This Year")
    end
  end

  describe "savings category labels", :aggregate_failures do
    let!(:pool) { create(:pool, user: user) }
    let!(:category) { create(:category, category_type: "savings", user: user, pool: pool, name: "Emergency") }
    let!(:item) { create(:item, category: category, name: "Transfer") }

    before { create(:entry, item: item, amount: 200, date: base_date + 7.days) }

    it "shows Monthly labels in default view" do
      visit category_path(category)

      expect(page).to have_content("Monthly Contribution")
      expect(page).to have_content("Items This Month")
    end

    it "shows YTD labels in YTD view" do
      visit category_path(category, period: "ytd")

      expect(page).to have_content("YTD Contribution")
      expect(page).to have_content("Items This Year")
    end
  end

  # THE PRORATED SUMMARY IS DELETED (plan 3, task 3). Three examples planted a $300 prorated cap
  # and read the daily ramp off the card — "67% used", "Budget exceeded" against a $150 pace, and
  # "Expected by today: $150.00". The cap and the `prorated` ramp are both gone, so the fixture is
  # unbuildable and the sentences are unrenderable; they are deleted with the behaviour.

  # THE POOL BALANCE THE LEFT COLUMN STILL PRINTS, AND THE KEY THAT NOW BUSTS IT (2d task 6).
  #
  # Task 5 narrowed this fragment cache to the left column because an envelope's balance is not
  # derived from THIS category's entries — a `PoolMovement` moves it and touches nothing here — and
  # moved the two readers it found outside. It missed one: `_summary_card`'s savings arm prints
  # `pool.calculator.{current_balance,progress_percentage}` from inside the gray box in the middle
  # of the partial, where taking the reader out would mean taking the box out of the card it is
  # drawn in. So the POOL is in the key instead, which works because the bust chain exists on that
  # side: `PoolMovement belongs_to :from_pool/:to_pool, touch: true`.
  #
  # THE ENVIRONMENT MAKES THIS INVISIBLE BY DEFAULT — `config.cache_store = :null_store` in test —
  # so every other example in this suite would pass against a key that never busts anything. These
  # two turn a real store on, which is the only way either half means anything.
  describe "the pool figure inside the fragment cache" do
    around do |example|
      cache = Rails.cache
      controller_cache = ActionController::Base.cache_store
      caching = ActionController::Base.perform_caching

      Rails.cache = ActionController::Base.cache_store = ActiveSupport::Cache::MemoryStore.new
      ActionController::Base.perform_caching = true
      example.run
    ensure
      Rails.cache = cache
      ActionController::Base.cache_store = controller_cache
      ActionController::Base.perform_caching = caching
    end

    let(:checking) { create(:pool, :account, user: user, name: "Checking") }
    let(:goal) { create(:pool, user: user, name: "Emergency Fund", target_amount: 2_000) }
    let!(:savings) { create(:category, category_type: "savings", user: user, name: "Rainy Day", pool: goal) }

    def fund(amount) = create(:pool_movement, from_pool: checking, to_pool: goal, amount: amount, date: Date.current)

    # THE STALENESS FIX ITSELF: a movement, and the figure has moved on the next load. Before the
    # pool joined the key this second load served the first load's fragment — `$500.00 / $2,000.00`
    # under a live "View details" link pointing at a pool screen reading $800.
    it "moves when a movement funds the pool", :aggregate_failures do
      fund(500)
      visit category_path(savings)
      expect(page).to have_content("$500.00 / $2,000.00")

      fund(300)
      visit category_path(savings)

      expect(page).to have_content("$800.00 / $2,000.00")
    end

    # AND THE CACHE IS GENUINELY ON, which the example above cannot show on its own — it would read
    # exactly the same against a store that never stored anything, and the null store is what this
    # environment configures. `update_column` writes the name with no callbacks, so no `touch`
    # reaches the pool and the key does not move: the LEFT column keeps serving the stale name while
    # the pool card in the uncached right column already shows the new one. One load, both halves.
    it "still serves a cached left column when nothing in the key moved", :aggregate_failures do
      fund(500)
      visit category_path(savings)
      expect(page).to have_content("Emergency Fund")

      # SKIPPING THE CALLBACKS IS THE POINT, not a shortcut: `update!` would move `updated_at`,
      # which is exactly what this example needs NOT to happen — a key that moved would prove
      # nothing about whether anything was ever stored.
      goal.update_column(:name, "Renamed Fund") # rubocop:disable Rails/SkipsModelValidations
      visit category_path(savings)

      expect(page).to have_content("Emergency Fund")
      expect(page).to have_content("Renamed Fund")
    end
  end
end
