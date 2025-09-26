# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Edit - Form", type: :system do
  let!(:user) { create(:user) }
  let!(:category) { create(:category, name: "Original Name", category_type: "expense", color: "#C9C78B", user: user) }

  before { sign_in user }

  describe "form display", :aggregate_failures do
    before { visit edit_category_path(category) }

    it "shows all form elements and page content" do
      expect(page).to have_content("Edit Original Name")
      expect(page).to have_content("Update your category details")
      expect(page).to have_field("Name")
      expect(page).to have_content("Basic Information")
      expect(page).to have_content("Appearance")
      expect(page).to have_button("Update Category")
    end

    it "shows category type options" do
      expect(page).to have_content("Expense")
      expect(page).to have_content("Income")
      expect(page).to have_content("Savings")
    end

    it "shows color selection options" do
      expect(page).to have_content("Selected:")
      # Check that color grid is present
      expect(page).to have_css("[data-app--category--form-target='colorOption']", count: 16)
    end

    it "shows navigation elements" do
      expect(page).to have_link("View Details")
      expect(page).to have_link("Back to Categories")
      expect(page).to have_link("Cancel")
    end
  end

  describe "form pre-population", :aggregate_failures do
    it "pre-fills form with existing category data" do
      visit edit_category_path(category)

      expect(page).to have_field("Name", with: "Original Name")
      expect(page).to have_checked_field("category_category_type_expense")
      expect(page).to have_field("Color", with: "#C9C78B")
    end

    it "pre-fills income category correctly" do
      income_category = create(:category, :income, name: "Salary Income", user: user)
      visit edit_category_path(income_category)

      expect(page).to have_field("Name", with: "Salary Income")
      expect(page).to have_checked_field("category_category_type_income")
    end

    it "pre-fills savings category correctly" do
      savings_pool = create(:savings_pool, user: user)
      savings_category = create(:category, :savings, name: "Emergency Fund", user: user, savings_pool: savings_pool)
      visit edit_category_path(savings_category)

      expect(page).to have_field("Name", with: "Emergency Fund")
      expect(page).to have_checked_field("category_category_type_savings")
    end
  end

  describe "form validation", :aggregate_failures do
    before { visit edit_category_path(category) }

    it "shows error for empty name" do
      fill_in "Name", with: ""
      click_button "Update Category"

      expect(page).to have_content("can't be blank")
      expect(page).to have_current_path(edit_category_path(category))
    end

    it "shows error for duplicate name" do
      create(:category, name: "Duplicate Name", user: user)

      fill_in "Name", with: "Duplicate Name"
      click_button "Update Category"

      expect(page).to have_content("has already been taken")
      expect(page).to have_current_path(edit_category_path(category))
    end

    it "allows same name if unchanged" do
      fill_in "Name", with: "Original Name"
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
      expect(page).to have_current_path(categories_path(type: "expense"))
    end

    it "allows duplicate names for different users" do
      other_user = create(:user)
      create(:category, name: "Shared Name", user: other_user)

      fill_in "Name", with: "Shared Name"
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
    end
  end

  describe "successful updates", :aggregate_failures do
    before { visit edit_category_path(category) }

    it "updates name and redirects to correct index" do
      fill_in "Name", with: "Updated Name"
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content("Updated Name")
    end

    it "updates category type and redirects to new type index" do
      find("label", text: "Income").click
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
      expect(page).to have_current_path(categories_path(type: "income"))
      expect(page).to have_content("Original Name")
    end

    it "updates color" do
      fill_in "Color", with: "#FF5733"
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
      category.reload
      expect(category.color).to eq("#FF5733")
    end

    it "updates multiple fields simultaneously" do
      fill_in "Name", with: "Completely Updated"
      find("label", text: "Savings").click
      fill_in "Color", with: "#00FF00"
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
      expect(page).to have_current_path(categories_path(type: "savings"))

      category.reload
      expect(category.name).to eq("Completely Updated")
      expect(category.category_type).to eq("savings")
      expect(category.color).to eq("#00FF00")
    end
  end

  describe "navigation", :aggregate_failures do
    before { visit edit_category_path(category) }

    it "navigates to category details when clicking View Details" do
      click_link "View Details"
      expect(page).to have_current_path(category_path(category))
    end

    it "returns to categories index when clicking Back to Categories" do
      click_link "Back to Categories"
      expect(page).to have_current_path(categories_path)
    end

    it "returns to category details when clicking Cancel" do
      click_link "Cancel"
      expect(page).to have_current_path(category_path(category))
    end
  end

  describe "type-specific redirect behavior", :aggregate_failures do
    it "redirects to expense index when updating expense category" do
      expense_category = create(:category, category_type: "expense", user: user)
      visit edit_category_path(expense_category)

      fill_in "Name", with: "Updated Expense"
      click_button "Update Category"

      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content("Expense Categories")
    end

    it "redirects to income index when updating income category" do
      income_category = create(:category, :income, user: user)
      visit edit_category_path(income_category)

      fill_in "Name", with: "Updated Income"
      click_button "Update Category"

      expect(page).to have_current_path(categories_path(type: "income"))
      expect(page).to have_content("Income Categories")
    end

    it "redirects to savings index when updating savings category" do
      savings_pool = create(:savings_pool, user: user)
      savings_category = create(:category, :savings, user: user, savings_pool: savings_pool)
      visit edit_category_path(savings_category)

      fill_in "Name", with: "Updated Savings"
      click_button "Update Category"

      expect(page).to have_current_path(categories_path(type: "savings"))
      expect(page).to have_content("Savings Categories")
    end
  end
end
