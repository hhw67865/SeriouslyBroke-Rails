# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Calendar Week - Summary", type: :system do
  let!(:user) { create(:user) }
  let!(:expense_category) { create(:category, :expense, user: user, name: "Food") }
  let!(:income_category) { create(:category, :income, user: user, name: "Salary") }
  let!(:savings_category) { create(:category, :savings, user: user, name: "Emergency") }
  let(:test_date) { Date.current }

  before { sign_in user, scope: :user }

  describe "weekly summary section", :aggregate_failures do
    before { visit calendar_week_path(date: test_date.strftime("%Y-%m-%d")) }

    it "shows weekly summary heading" do
      expect(page).to have_content("Weekly Summary")
    end

    it "shows all three summary cards" do
      expect(page).to have_content("Expenses")
      expect(page).to have_content("Income")
      expect(page).to have_content("Savings")
    end
  end

  describe "summary totals with entries", :aggregate_failures do
    before do
      expense_item = create(:item, category: expense_category, name: "Groceries")
      income_item = create(:item, category: income_category, name: "Paycheck")
      savings_item = create(:item, category: savings_category, name: "Deposit")

      # Create entries for different days in the same week
      week_start = test_date - test_date.wday
      create(:entry, item: expense_item, amount: 100.00, date: week_start)
      create(:entry, item: expense_item, amount: 50.00, date: week_start + 2)
      create(:entry, item: income_item, amount: 3000.00, date: week_start + 1)
      create(:entry, item: savings_item, amount: 500.00, date: week_start + 3)

      visit calendar_week_path(date: test_date.strftime("%Y-%m-%d"))
    end

    it "shows correct expense total" do
      within(".grid") do
        expect(page).to have_content("-$150.00")
      end
    end

    it "shows correct income total" do
      within(".grid") do
        expect(page).to have_content("+$3,000.00")
      end
    end

    it "shows correct savings total" do
      within(".grid") do
        expect(page).to have_content("+$500.00")
      end
    end
  end

  describe "category breakdown", :aggregate_failures do
    before do
      food_category = create(:category, :expense, user: user, name: "Dining")
      transport_category = create(:category, :expense, user: user, name: "Transport")

      food_item = create(:item, category: food_category, name: "Restaurant")
      transport_item = create(:item, category: transport_category, name: "Gas")

      week_start = test_date - test_date.wday
      create(:entry, item: food_item, amount: 45.00, date: week_start)
      create(:entry, item: transport_item, amount: 60.00, date: week_start + 1)

      visit calendar_week_path(date: test_date.strftime("%Y-%m-%d"))
    end

    it "shows category names in breakdown" do
      expect(page).to have_content("Dining")
      expect(page).to have_content("Transport")
    end

    it "shows category amounts in breakdown" do
      expect(page).to have_content("$45.00")
      expect(page).to have_content("$60.00")
    end
  end

  describe "empty summary state", :aggregate_failures do
    before { visit calendar_week_path(date: test_date.strftime("%Y-%m-%d")) }

    it "shows no entries message when category has no data" do
      expect(page).to have_content("No entries")
    end

    it "shows zero totals" do
      expect(page).to have_content("-$0.00")
      expect(page).to have_content("+$0.00")
    end
  end
end
