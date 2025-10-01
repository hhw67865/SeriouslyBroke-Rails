# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entries Index - Filtering", type: :system do
  let!(:user) { create(:user) }
  let!(:expense_category) { create(:category, :expense, user: user, name: "Food") }
  let!(:income_category) { create(:category, :income, user: user, name: "Salary") }
  let!(:savings_category) { create(:category, :savings, user: user, name: "Emergency Fund") }

  let!(:expense_item) { create(:item, category: expense_category, name: "Groceries") }
  let!(:income_item) { create(:item, category: income_category, name: "Monthly Pay") }
  let!(:savings_item) { create(:item, category: savings_category, name: "Emergency Savings") }

  before do
    sign_in user
    create(:entry, item: expense_item, amount: 150, description: "Weekly shopping")
    create(:entry, item: income_item, amount: 3000, description: "Salary payment")
    create(:entry, item: savings_item, amount: 500, description: "Emergency fund deposit")
  end

  describe "type tab filtering", :aggregate_failures do
    it "shows all entries by default" do
      visit entries_path

      expect(page).to have_content("All")
      expect(page).to have_content("Groceries")
      expect(page).to have_content("Monthly Pay")
      expect(page).to have_content("Emergency Savings")
    end

    it "filters to expense entries only" do
      visit entries_path(type: "expenses")

      expect(page).to have_content("Expenses")
      expect(page).to have_content("Groceries")
      expect(page).to have_content("Food")
      expect(page).not_to have_content("Monthly Pay")
      expect(page).not_to have_content("Emergency Savings")
    end

    it "filters to income entries only" do
      visit entries_path(type: "income")

      expect(page).to have_content("Income")
      expect(page).to have_content("Monthly Pay")
      expect(page).to have_content("Salary")
      expect(page).not_to have_content("Groceries")
      expect(page).not_to have_content("Emergency Savings")
    end

    it "filters to savings entries only" do
      visit entries_path(type: "savings")

      expect(page).to have_content("Savings")
      expect(page).to have_content("Emergency Savings")
      expect(page).to have_content("Emergency Fund")
      expect(page).not_to have_content("Groceries")
      expect(page).not_to have_content("Monthly Pay")
    end
  end

  describe "tab navigation", :aggregate_failures do
    before { visit entries_path }

    it "switches to expenses tab" do
      click_link "Expenses"
      expect(page).to have_current_path(entries_path(type: "expenses"))
      expect(page).to have_css("a.border-brand.text-brand", text: "Expenses")
    end

    it "switches to income tab" do
      click_link "Income"
      expect(page).to have_current_path(entries_path(type: "income"))
      expect(page).to have_css("a.border-brand.text-brand", text: "Income")
    end

    it "switches to savings tab" do
      click_link "Savings"
      expect(page).to have_current_path(entries_path(type: "savings"))
      expect(page).to have_css("a.border-brand.text-brand", text: "Savings")
    end

    it "switches back to all tab" do
      click_link "Expenses"
      click_link "All"
      expect(page).to have_current_path(entries_path)
      expect(page).to have_css("a.border-brand.text-brand", text: "All")
    end
  end

  describe "empty states for filtered types", :aggregate_failures do
    before do
      # Clear all entries and create only expense entries
      Entry.destroy_all
      create(:entry, item: expense_item, amount: 100)
    end

    it "shows empty state for income when none exist" do
      visit entries_path(type: "income")

      expect(page).to have_content("No entries found")
    end

    it "shows empty state for savings when none exist" do
      visit entries_path(type: "savings")

      expect(page).to have_content("No entries found")
    end
  end

  describe "type filtering with pagination", :aggregate_failures do
    before do
      # Create many entries of different types
      create_list(:entry, 15, item: expense_item)
      create_list(:entry, 25, item: income_item) # More than per_page limit
    end

    it "paginates within filtered type" do
      visit entries_path(type: "income")

      expect(page).to have_content("Showing 1 to 20 of 26 entries") # 25 + 1 from before block
      expect(page).to have_link("Next")

      click_link "Next"
      expect(page).to have_content("Showing 21 to 26 of 26 entries")
      expect(page).to have_current_path(entries_path(type: "income", page: 2))
    end
  end
end
