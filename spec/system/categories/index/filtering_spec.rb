# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Index - Filtering", type: :system do
  let!(:user) { create(:user) }
  let!(:income_categories) { create_list(:category, 2, :income, user: user) }
  let!(:expense_categories) { create_list(:category, 2, :expense, user: user) }

  before { sign_in user, scope: :user }

  describe "type filtering", :aggregate_failures do
    it "shows only income categories when income type selected" do
      visit categories_path(type: "income")
      expect(page).to have_content("Income Categories")
      income_categories.each { |cat| expect(page).to have_content(cat.name) }
      expense_categories.each { |cat| expect(page).not_to have_content(cat.name) }
    end

    it "shows only expense categories when expense type selected" do
      visit categories_path(type: "expense")
      expect(page).to have_content("Expense Categories")
      expense_categories.each { |cat| expect(page).to have_content(cat.name) }
      income_categories.each { |cat| expect(page).not_to have_content(cat.name) }
    end

    it "defaults to expense categories when no type specified" do
      visit categories_path
      expect(page).to have_content("Expense Categories")
    end
  end

  describe "type switching", :aggregate_failures do
    before { visit categories_path(type: "income") }

    # TWO TABS, NOT THREE (plan 3, task 5).
    it "shows navigation links to other category types", :aggregate_failures do
      expect(page).to have_link("Expense").or have_link("Expense Categories")
      expect(page).to have_no_link("Savings")
    end

    it "switches to expense categories when expense link clicked" do
      begin
        click_link "Expense"
      rescue StandardError
        click_link "Expense Categories"
      end
      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content("Expense Categories")
    end
  end

  describe "search with type filtering" do
    before do
      # Create searchable categories for different types
      create(:category, name: "Freelance Income", category_type: "income", user: user)
      create(:category, name: "Freelance Tools", category_type: "expense", user: user)

      visit categories_path(type: "income")
    end

    it "searches within selected category type only", :aggregate_failures do
      fill_in "q", with: "Freelance"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("Freelance Income")
      expect(page).not_to have_content("Freelance Tools") # Different type
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
