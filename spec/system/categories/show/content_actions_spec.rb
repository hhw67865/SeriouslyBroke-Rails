# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Show - Content & Actions", type: :system do
  let!(:user) { create(:user) }

  before { sign_in user, scope: :user }

  describe "expense category", :aggregate_failures do
    let!(:category) { create(:category, category_type: "expense", user: user, name: "Food") }

    # The cap this planted (`create(:budget, category: …)`) is deleted with the shape, and the
    # summary card's "Monthly Budget" arm went with it: the card says what the category spent and
    # what that spending counts against (computed-claims Task 4 — its own rules' claims, or nothing
    # at all, in which case it comes straight out of what's free to spend).
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

  # A SAVINGS GOAL IS A CATEGORY (two-ledger spec §3, Task 7). This described a category POINTING
  # AT a savings pool — the shape the pool layer made possible — and the pool is gone: a goal is a
  # category with a target and a funding start, and its own page is the only page about it. The
  # claim worth keeping is the noun one: the app calls it a Goal and never a "Savings Pool".
  describe "a category saving toward a goal", :aggregate_failures do
    let!(:category) do
      create(:category, :expense, :funded, user: user, name: "Emergency Fund", target_amount: 2_000)
    end

    before { visit category_path(category) }

    it "shows key sections and the goal's one noun" do
      expect(page).to have_content("Emergency Fund")
      expect(page).to have_content("Expense category details and management")
      expect(page).to have_content("Summary")
      expect(page).to have_content("Goal")
      expect(page).to have_no_content("Savings Pool")
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
end
