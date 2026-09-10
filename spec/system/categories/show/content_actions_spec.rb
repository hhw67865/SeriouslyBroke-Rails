# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Show - Content & Actions", type: :system do
  let!(:user) { create(:user) }

  before { sign_in user, scope: :user }

  describe "expense category", :aggregate_failures do
    let!(:category) { create(:category, category_type: "expense", user: user, name: "Food") }

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

      click_button "Delete"

      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content("Category was successfully deleted")
      expect(page).to have_no_content(category.name)
      expect(Category.exists?(category.id)).to be(false)
    end
  end

  # A fund is a category with a rule saving toward a day, so the fixture plants the rule rather
  # than a figure on the record.
  describe "a category saving toward a day", :aggregate_failures do
    let!(:category) do
      create(:category, :expense, user: user, name: "Emergency Fund").tap do |fund|
        create(:rule, :choice, :by_date, category: fund, amount: 2_000)
      end
    end

    before { visit category_path(category) }

    it "shows key sections and the fund's one noun" do
      expect(page).to have_content("Emergency Fund")
      expect(page).to have_content("Expense category details and management")
      expect(page).to have_content("Summary")
      within("[data-holdings-card]") do
        expect(page).to have_css("h2", exact_text: "Target")
        expect(page).to have_no_content("Envelope")
        expect(page).to have_no_content("Goal")
      end
    end

    it "navigates with Edit button" do
      click_link "Edit"
      expect(page).to have_current_path(edit_category_path(category))
    end

    it "deletes category completely from database", :aggregate_failures do
      expect(Category.exists?(category.id)).to be(true)

      click_button "Delete"

      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content("Category was successfully deleted")
      expect(page).to have_no_content(category.name)
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

      click_button "Delete"

      expect(page).to have_current_path(categories_path(type: "income"))
      expect(page).to have_content("Category was successfully deleted")
      expect(page).to have_no_content(category.name)
      expect(Category.exists?(category.id)).to be(false)
    end
  end
end
