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

  # THE LEFT COLUMN'S OWN SENTENCE ABOUT WHERE THE SPENDING COMES FROM (Task 7). It named the POOL
  # — "Spending here comes out of the envelope Groceries", linked to the pool page — and both
  # halves are gone with the layer: a category holds its own money (two-ledger spec §3). It asks
  # `Category#holder?` now, which is the SAME predicate the holdings card in the right-hand column
  # branches on, so the two cards on one page cannot say different things about one category.
  describe "what the sentence says the spending comes out of", :aggregate_failures do
    it "names the category's own holdings when it holds money" do
      visit category_path(create(:category, :expense, :funded, user: user, name: "Food"))

      expect(page).to have_content("Spending here comes out of what this category holds")
      expect(page).to have_no_content("comes out of what's available")
    end

    it "names available when it holds nothing" do
      visit category_path(create(:category, :expense, user: user, name: "Health"))

      expect(page).to have_content("Spending here comes out of what's available")
      expect(page).to have_no_content("what this category holds")
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

  # THE "savings category labels" DESCRIBE IS DELETED WITH THE ARM (plan 3, task 5). It pinned
  # "Monthly Contribution" / "YTD Contribution" — `CategoriesHelper#period_amount_label(:savings)`,
  # deleted with the type — over the card's savings arm, which is gone with the goal box and the
  # running-total chart inside it. The expense and income label pairs above make the same claim
  # over the two types that survive.

  # THE PRORATED SUMMARY IS DELETED (plan 3, task 3). Three examples planted a $300 prorated cap
  # and read the daily ramp off the card — "67% used", "Budget exceeded" against a $150 pace, and
  # "Expected by today: $150.00". The cap and the `prorated` ramp are both gone, so the fixture is
  # unbuildable and the sentences are unrenderable; they are deleted with the behaviour.

  # THE LEFT COLUMN'S FRAGMENT CACHE, AND THE KEY THAT BUSTS IT (2d task 6, revised in plan 3 task
  # 5 and again in Task 7).
  #
  # `@category.pool` IS OUT OF THE KEY. It was there for one rendered byte — the pool's noun and
  # name in the sentence above — and that sentence names no pool now, so keying on a column nothing
  # under the cache reads bought nothing and would have outlived the association. What the sentence
  # DOES read is `Category#holder?`, and the category is in the key, so an ordinary write busts it.
  #
  # THE ENVIRONMENT MAKES THIS INVISIBLE BY DEFAULT — `config.cache_store = :null_store` in test —
  # so every other example in this suite would pass against a key that never busts anything. These
  # two turn a real store on, which is the only way either half means anything.
  describe "the funding start inside the fragment cache" do
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

    let!(:spending) { create(:category, category_type: "expense", user: user, name: "Rainy Day") }

    # THE BUST ITSELF: the category starts holding money, and the sentence has moved on the next
    # load. `update!` moves `updated_at`, which is the whole of what puts the category in the key.
    it "moves when the category starts holding money", :aggregate_failures do
      visit category_path(spending)
      expect(page).to have_content("comes out of what's available")

      spending.update!(funded_since: Date.current - 1.month)
      visit category_path(spending)

      expect(page).to have_content("comes out of what this category holds")
      expect(page).to have_no_content("comes out of what's available")
    end

    # AND THE CACHE IS GENUINELY ON, which the example above cannot show on its own — it would read
    # exactly the same against a store that never stored anything, and the null store is what this
    # environment configures. `update_column` writes the date with no callbacks, so `updated_at`
    # does not move and the key does not either: the LEFT column keeps serving the old sentence
    # while the holdings card in the uncached right column already says the category holds money.
    # One load, both halves.
    it "still serves a cached left column when nothing in the key moved", :aggregate_failures do
      visit category_path(spending)
      expect(page).to have_content("comes out of what's available")

      # SKIPPING THE CALLBACKS IS THE POINT, not a shortcut: `update!` would move `updated_at`,
      # which is exactly what this example needs NOT to happen — a key that moved would prove
      # nothing about whether anything was ever stored.
      spending.update_column(:funded_since, Date.current - 1.month) # rubocop:disable Rails/SkipsModelValidations
      visit category_path(spending)

      expect(page).to have_content("comes out of what's available")
      expect(find("[data-holdings-card]")["data-holdings-state"]).to eq("holding")
    end
  end
end
