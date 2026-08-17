# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Show - Content & Actions", type: :system do
  let!(:user) { create(:user) }

  before { sign_in user, scope: :user }

  describe "expense category", :aggregate_failures do
    let!(:category) { create(:category, category_type: "expense", user: user, name: "Food") }

    # The cap this planted (`create(:budget, category: …)`) is deleted with the shape, and the
    # summary card's "Monthly Budget" arm went with it: an expense category names a pool now, so
    # the card says what it spent and which pool it came out of.
    before { visit category_path(category) }

    it "shows key sections and expense summary" do
      expect(page).to have_content("Food")
      expect(page).to have_content("Expense category details and management")
      expect(page).to have_content("Summary")
      expect(page).to have_content("Items This Month")
      expect(page).to have_content("Details")
      expect(page).to have_content("Recent Activity")
      expect(page).to have_content("Spent this month")
      expect(page).to have_no_content("Monthly Budget")
    end

    it "navigates with Edit button" do
      click_link "Edit"
      expect(page).to have_current_path(edit_category_path(category))
    end

    it "deletes category completely from database", :aggregate_failures do
      expect(Category.exists?(category.id)).to be(true)

      accept_confirm { click_button "Delete" }

      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content("Category was successfully deleted")
      expect(page).not_to have_content(category.name)
      expect(Category.exists?(category.id)).to be(false)
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

    it "deletes category completely from database", :aggregate_failures do
      expect(Category.exists?(category.id)).to be(true)

      accept_confirm { click_button "Delete" }

      expect(page).to have_current_path(categories_path(type: "income"))
      expect(page).to have_content("Category was successfully deleted")
      expect(page).not_to have_content(category.name)
      expect(Category.exists?(category.id)).to be(false)
    end
  end

  describe "savings category", :aggregate_failures do
    let!(:pool) { create(:pool, user: user, name: "Main Pool") }
    let!(:category) { create(:category, category_type: "savings", user: user, name: "Emergency Fund", pool: pool) }

    before { visit category_path(category) }

    it "shows key sections and savings summary" do
      expect(page).to have_content("Emergency Fund")
      expect(page).to have_content("Savings category details and management")
      expect(page).to have_content("Summary")
      expect(page).to have_content("Monthly Contribution")
      # CHANGED WITH THE ONE NAMER (2d whole-plan review, fix 2): a savings pool is a "Goal" in
      # every sentence the app writes about one, this page's summary box included.
      expect(page).to have_content("Goal")
      expect(page).to have_no_content("Savings Pool")
      expect(page).to have_content("Main Pool")
    end

    it "navigates with Edit button" do
      click_link "Edit"
      expect(page).to have_current_path(edit_category_path(category))
    end

    it "deletes category completely from database", :aggregate_failures do
      expect(Category.exists?(category.id)).to be(true)

      accept_confirm { click_button "Delete" }

      expect(page).to have_current_path(categories_path(type: "savings"))
      expect(page).to have_content("Category was successfully deleted")
      expect(page).not_to have_content(category.name)
      expect(Category.exists?(category.id)).to be(false)
    end
  end
end
