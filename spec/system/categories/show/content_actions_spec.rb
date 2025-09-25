# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Show - Content & Actions", type: :system do
  let!(:user) { create(:user) }

  before { sign_in user }

  describe "expense category", :aggregate_failures do
    before do
      create(:category, category_type: "expense", user: user, name: "Food")
      create(:budget, category: category, amount: 1000)
      visit category_path(category)
    end

    it "shows key sections and expense summary" do
      expect(page).to have_content("Food")
      expect(page).to have_content("Expense category details and management")
      expect(page).to have_content("Summary")
      expect(page).to have_content("Items This Month")
      expect(page).to have_content("Details")
      expect(page).to have_content("Recent Activity")
      expect(page).to have_content("Monthly Budget")
    end

    it "navigates with Edit button" do
      click_link "Edit"
      expect(page).to have_current_path(edit_category_path(category))
    end

    it "deletes with Delete button and redirects to index with type" do
      accept_confirm { click_button "Delete" }
      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content("Category was successfully deleted")
    end
  end

  describe "income category", :aggregate_failures do
    let!(:category) { create(:category, category_type: "income", user: user, name: "Salary") }

    before { visit category_path(category) }

    it "shows key sections and income summary" do
      expect(page).to have_content("Salary")
      expect(page).to have_content("Income category details and management")
      expect(page).to have_content("Summary")
      expect(page).to have_content("Monthly Income")
    end

    it "navigates with Edit button" do
      click_link "Edit"
      expect(page).to have_current_path(edit_category_path(category))
    end

    it "deletes with Delete button and redirects to index with type" do
      accept_confirm { click_button "Delete" }
      expect(page).to have_current_path(categories_path(type: "income"))
      expect(page).to have_content("Category was successfully deleted")
    end
  end

  describe "savings category", :aggregate_failures do
    let!(:pool) { create(:savings_pool, user: user, name: "Main Pool") }
    let!(:category) { create(:category, category_type: "savings", user: user, name: "Emergency Fund", savings_pool: pool) }

    before { visit category_path(category) }

    it "shows key sections and savings summary" do
      expect(page).to have_content("Emergency Fund")
      expect(page).to have_content("Savings category details and management")
      expect(page).to have_content("Summary")
      expect(page).to have_content("Monthly Contribution")
      expect(page).to have_content("Savings Pool")
      expect(page).to have_content("Main Pool")
    end

    it "navigates with Edit button" do
      click_link "Edit"
      expect(page).to have_current_path(edit_category_path(category))
    end

    it "deletes with Delete button and redirects to index with type" do
      accept_confirm { click_button "Delete" }
      expect(page).to have_current_path(categories_path(type: "savings"))
      expect(page).to have_content("Category was successfully deleted")
    end
  end
end
