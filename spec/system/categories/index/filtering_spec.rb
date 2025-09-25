# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Index - Filtering", type: :system do
  let!(:user) { create(:user) }
  let!(:income_categories) { create_list(:category, 2, :income, user: user) }
  let!(:expense_categories) { create_list(:category, 2, :expense, user: user) }
  let!(:savings_categories) { create_list(:category, 1, :savings, user: user) }

  before { sign_in user }

  describe "type filtering", :aggregate_failures do
    it "shows correct categories for each type" do
      # Test income type
      visit categories_path(type: "income")
      expect(page).to have_content("Income Categories")
      income_categories.each { |cat| expect(page).to have_content(cat.name) }
      (expense_categories + savings_categories).each { |cat| expect(page).not_to have_content(cat.name) }

      # Test expense type  
      visit categories_path(type: "expense")
      expect(page).to have_content("Expense Categories")
      expense_categories.each { |cat| expect(page).to have_content(cat.name) }
      (income_categories + savings_categories).each { |cat| expect(page).not_to have_content(cat.name) }

      # Test savings type
      visit categories_path(type: "savings")
      expect(page).to have_content("Savings Categories")
      savings_categories.each { |cat| expect(page).to have_content(cat.name) }
      (income_categories + expense_categories).each { |cat| expect(page).not_to have_content(cat.name) }

      # Test default (expense)
      visit categories_path
      expect(page).to have_content("Expense Categories")
    end
  end

  describe "type switching", :aggregate_failures do
    before { visit categories_path(type: "income") }

    it "switches between category types" do
      expect(page).to have_link("Expense").or have_link("Expense Categories")
      expect(page).to have_link("Savings").or have_link("Savings Categories")
      
      # Test switching to expense
      click_link "Expense" rescue click_link "Expense Categories"
      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content("Expense Categories")
      
      # Test switching to savings
      click_link "Savings" rescue click_link "Savings Categories"
      expect(page).to have_current_path(categories_path(type: "savings"))
      expect(page).to have_content("Savings Categories")
    end
  end

  describe "search with type filtering" do
    let!(:searchable_income) { create(:category, name: "Freelance Income", category_type: "income", user: user) }
    let!(:searchable_expense) { create(:category, name: "Freelance Tools", category_type: "expense", user: user) }
    let!(:searchable_savings) { create(:category, name: "Freelance Savings", category_type: "savings", user: user) }

    before { visit categories_path(type: "income") }

    it "searches within selected category type only", :aggregate_failures do
      fill_in "q", with: "Freelance"
      find("input[name='q']").send_keys(:return)
      
      expect(page).to have_content("Freelance Income")
      expect(page).not_to have_content("Freelance Tools") # Different type
      expect(page).not_to have_content("Freelance Savings") # Different type
    end

    it "handles search clearing and empty results", :aggregate_failures do
      # Test search with no results
      fill_in "q", with: "NonexistentCategory"
      find("input[name='q']").send_keys(:return)
      expect(page).to have_content("No Income Categories")

      # Test clearing search with clear button
      fill_in "q", with: "Test"
      find("input[name='q']").send_keys(:return)
      expect(page).to have_link("Clear")
      click_link "Clear"
      income_categories.each { |cat| expect(page).to have_content(cat.name) }
    end

    it "preserves type during search operations", :aggregate_failures do
      fill_in "q", with: "Test"
      find("input[name='q']").send_keys(:return)
      
      expect(page).to have_current_path(categories_path(type: "income", field: "name", q: "Test"))
      expect(page).to have_content("Income Categories")
      
      # Clear search and verify type preserved
      fill_in "q", with: ""
      find("input[name='q']").send_keys(:return)
      expect(page).to have_current_path(categories_path(type: "income", field: "name", q: ""))
    end
  end
end
