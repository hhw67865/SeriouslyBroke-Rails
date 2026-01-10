# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Index - Header", type: :system do
  let!(:user) { create(:user) }

  before do
    create_list(:category, 2, :income, user: user)
    create_list(:category, 2, :expense, user: user)
    create_list(:category, 1, :savings, user: user)
    sign_in user, scope: :user
  end

  describe "type-specific headers", :aggregate_failures do
    it "shows correct content for income categories" do
      visit categories_path(type: "income")

      expect(page).to have_content("Income Categories")
      expect(page).to have_content("Track your income sources and monthly earnings")
      expect(page).to have_link("New Income Category")
    end

    it "shows correct content for expense categories" do
      visit categories_path(type: "expense")

      expect(page).to have_content("Expense Categories")
      expect(page).to have_content("Manage your expense categories and track your spending")
      expect(page).to have_link("New Expense Category")
    end

    it "shows correct content for savings categories" do
      visit categories_path(type: "savings")

      expect(page).to have_content("Savings Categories")
      expect(page).to have_content("Organize your savings pools and track progress")
      expect(page).to have_link("New Saving Category")
    end
  end

  describe "create button navigation" do
    it "navigates to new category page with correct type", :aggregate_failures do
      visit categories_path(type: "income")
      click_link "New Income Category"

      expect(page).to have_current_path(new_category_path(type: "income"))
    end
  end

  describe "search form elements" do
    before { visit categories_path(type: "income") }

    it "shows search form with correct defaults", :aggregate_failures do
      expect(page).to have_select("field", selected: "Name")
      expect(page).to have_field("q")
      # Search form submits on Enter, no search button exists
      expect(page).to have_css("input[name='q']")
    end
  end
end
