# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Index - Expenses Tab", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  describe "empty state", :aggregate_failures do
    before { visit root_path(tab: "expenses") }

    it "shows empty message when no expense data" do
      expect(page).to have_content("No budgeted expense data")
      expect(page).to have_content("No budgeted expenses")
      expect(page).to have_content("No pool-covered expenses")
    end
  end

  describe "budgeted vs pool-covered split", :aggregate_failures do
    let!(:pool) { create(:savings_pool, user: user, name: "Car Fund", target_amount: 5000, start_date: 1.year.ago) }

    # Budgeted expense category
    let!(:groceries) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:groceries_item) { create(:item, category: groceries, name: "Weekly Shopping") }

    # Pool-covered expense category
    let!(:car_repair) { create(:category, :expense, user: user, name: "Car Repair", savings_pool: pool) }
    let!(:car_repair_item) { create(:item, category: car_repair, name: "Mechanic") }

    before do
      create(:budget, category: groceries, amount: 500)
      create(:entry, item: groceries_item, amount: 150.00, date: base_date + 5.days)
      create(:entry, item: car_repair_item, amount: 200.00, date: base_date + 10.days)
      visit root_path(tab: "expenses")
    end

    it "shows Monthly Budget section with only budgetable categories" do
      within monthly_budget_section do
        expect(page).to have_link("Groceries")
        expect(page).to have_content("$150.00")
        expect(page).not_to have_link("Car Repair")
      end
    end

    it "shows Pool-Covered section with only pool-linked categories" do
      within pool_covered_section do
        expect(page).to have_link("Car Repair")
        expect(page).to have_content("$200.00")
        expect(page).not_to have_link("Groceries")
      end
    end

    it "shows budget total only for budgetable categories" do
      expect(page).to have_content("Monthly Budget")
      expect(page).to have_content("$500.00")
    end

    it "excludes pool-covered spending from budgeted totals" do
      within_stat_card("Tracked Budgeted") { expect(page).to have_content("$150.00") }
      within_stat_card("Total Budgeted") { expect(page).to have_content("$150.00") }
    end
  end

  describe "show/hide total toggle", :aggregate_failures do
    let!(:expense_category) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:expense_item) { create(:item, category: expense_category, name: "Weekly Shopping") }

    before do
      create(:budget, category: expense_category, amount: 500)
      create(:entry, item: expense_item, amount: 150.00, date: base_date + 5.days)
      visit root_path(tab: "expenses")
    end

    it "shows 'Show Total' button by default" do
      expect(page).to have_link("Show Total")
      expect(page).not_to have_link("Hide Total")
    end

    it "toggles to 'Hide Total' when clicked" do
      click_link "Show Total"

      expect(page).to have_link("Hide Total")
      expect(page).not_to have_link("Show Total")
    end
  end

  describe "untracked categories in breakdown", :aggregate_failures do
    let!(:groceries) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:groceries_item) { create(:item, category: groceries, name: "Weekly Shopping") }
    let!(:dining) { create(:category, :expense, user: user, name: "Dining", tracked: false) }
    let!(:dining_item) { create(:item, category: dining, name: "Restaurants") }

    before do
      create(:entry, item: groceries_item, amount: 300.00, date: base_date + 1.day)
      create(:entry, item: dining_item, amount: 150.00, date: base_date + 2.days)
      visit root_path(tab: "expenses")
    end

    it "shows tracked and total budgeted stats with category links" do
      within_stat_card("Tracked Budgeted") { expect(page).to have_content("$300.00") }
      within_stat_card("Total Budgeted") { expect(page).to have_content("$450.00") }
      expect(page).to have_css("p.uppercase", text: /untracked/i)
      expect(page).to have_link("Groceries", href: category_path(groceries))
      expect(page).to have_link("Dining", href: category_path(dining))
    end
  end

  describe "budget details in budgeted section", :aggregate_failures do
    let!(:groceries) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:groceries_item) { create(:item, category: groceries, name: "Weekly Shopping") }
    let!(:utilities) { create(:category, :expense, user: user, name: "Utilities") }
    let!(:utilities_item) { create(:item, category: utilities, name: "Electric") }
    let!(:dining) { create(:category, :expense, user: user, name: "Dining") }
    let!(:dining_item) { create(:item, category: dining, name: "Restaurant") }

    before do
      create(:budget, category: groceries, amount: 500)
      create(:budget, category: utilities, amount: 200)
      create(:budget, category: dining, amount: 300)

      # Groceries: $650 spent on $500 budget → +$150 over
      create(:entry, item: groceries_item, amount: 650, date: base_date + 1.day)
      # Utilities: $80 spent on $200 budget → $120 left
      create(:entry, item: utilities_item, amount: 80, date: base_date + 2.days)
      # Dining: $400 spent on $300 budget → +$100 over
      create(:entry, item: dining_item, amount: 400, date: base_date + 3.days)

      visit root_path(tab: "expenses")
    end

    it "shows budget amount next to spent amount" do
      within monthly_budget_section do
        expect(page).to have_content("$650.00 / $500.00")
        expect(page).to have_content("$80.00 / $200.00")
        expect(page).to have_content("$400.00 / $300.00")
      end
    end

    it "shows over/remaining amounts" do
      within monthly_budget_section do
        expect(page).to have_content("+$150.00 over")
        expect(page).to have_content("+$100.00 over")
        expect(page).to have_content("$120.00 left")
      end
    end

    it "orders categories by most over budget first" do
      within monthly_budget_section do
        names = all("a[href^='/categories']").map(&:text)
        expect(names).to eq(["Groceries", "Dining", "Utilities"])
      end
    end

    it "shows budget totals" do
      within monthly_budget_section do
        expect(page).to have_content("$1,130.00 / $1,000.00")
      end
    end
  end

  describe "YTD view", :aggregate_failures do
    let!(:expense_category) { create(:category, :expense, user: user, name: "Utilities") }
    let!(:expense_item) { create(:item, category: expense_category, name: "Electric") }

    before do
      create(:budget, category: expense_category, amount: 200)
      create(:entry, item: expense_item, amount: 100.00, date: base_date)
      create(:entry, item: expense_item, amount: 120.00, date: base_date - 1.month)
      visit root_path(tab: "expenses", period: "ytd")
    end

    it "shows YTD Budgeted Spending heading" do
      expect(page).to have_content("YTD Budgeted Spending")
    end

    it "shows YTD Tracked Budgeted label in summary stats" do
      expect(page).to have_content("YTD Tracked Budgeted")
    end

    it "shows YTD Budget label" do
      expect(page).to have_content("YTD Budget")
    end
  end

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

    it "shows prorated row with over-pace text and expected pace amount" do
      # Groceries pace on day 15 = 300 * 15 / 30 = 150. Spent $200. Over pace by $50.
      within(".space-y-3") do
        expect(page).to have_content("Groceries")
        expect(page).to have_content("$200.00")
        expect(page).to have_content("$300.00")
        expect(page).to have_content("+$50.00 over pace")
        expect(page).to have_content("expected today: $150.00")
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

  private

  def monthly_budget_section
    find("h2", text: "Monthly Budget").ancestor("section")
  end

  def pool_covered_section
    find("h2", text: "Pool-Covered Spending").ancestor("section")
  end

  def within_stat_card(label, &)
    card = find("p", text: label).ancestor("div.bg-gray-50")
    within(card, &)
  end
end
