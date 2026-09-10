# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Show - Summary Card Period Labels", type: :system do
  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

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

  # Scoped to `[data-summary-card]`, and the scope is load-bearing: the holdings card in the
  # right-hand column speaks the same vocabulary, so an unscoped negative asserts nothing.
  describe "what the sentence says the spending counts against", :aggregate_failures do
    it "names the category's own rules when they claim its money" do
      food = create(:category, :expense, user: user, name: "Food")
      create(:rule, :rate, category: food, amount: 400)

      visit category_path(food)

      within("[data-summary-card]") do
        expect(page).to have_content("Spending here counts against what this category's rules claim")
        expect(page).to have_no_content("comes straight out of what's free to spend")
      end
    end

    it "names free money when nothing claims it" do
      visit category_path(create(:category, :expense, user: user, name: "Health"))

      within("[data-summary-card]") do
        expect(page).to have_content("Nothing claims this category's spending — it comes straight out of what's free to spend")
        expect(page).to have_no_content("counts against what this category's rules claim")
      end
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

  # The environment configures a null store, so every other example would pass against a key that
  # never busts anything. This one turns a real store on, which is the only way it means anything.
  describe "the category's rules inside the fragment cache" do
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

    # `Rule belongs_to :category, touch: true` moves `updated_at`, which is the whole of what puts
    # the category in the key — so the cached left column and the uncached holdings card next door
    # cannot come to different verdicts about the same category on the same load.
    it "is fresh once a rule claims the category, and agrees with the holdings card", :aggregate_failures do
      visit category_path(spending)
      within("[data-summary-card]") { expect(page).to have_content("comes straight out of what's free to spend") }

      create(:rule, :rate, category: spending, amount: 400)
      visit category_path(spending)

      within("[data-summary-card]") do
        expect(page).to have_content("counts against what this category's rules claim")
        expect(page).to have_no_content("comes straight out of what's free to spend")
      end
      expect(find("[data-holdings-card]")["data-holdings-state"]).to eq("ruled")
    end
  end
end
