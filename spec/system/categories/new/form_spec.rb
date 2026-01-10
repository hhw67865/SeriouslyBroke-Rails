# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories New - Form", type: :system do
  let!(:user) { create(:user) }

  before { sign_in user, scope: :user }

  describe "form display", :aggregate_failures do
    before { visit new_category_path }

    it "shows all form elements and page content" do
      expect(page).to have_content("Create New Category")
      expect(page).to have_content("Set up a new category to organize your finances")
      expect(page).to have_field("Name")
      expect(page).to have_content("Basic Information")
      expect(page).to have_content("Appearance")
      expect(page).to have_button("Create Category")
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
      expect(page).to have_link("Back to Categories")
      expect(page).to have_link("Cancel")
    end
  end

  describe "type prepopulation", :aggregate_failures do
    it "prepopulates expense type when accessed with type=expense" do
      visit new_category_path(type: "expense")

      expect(page).to have_checked_field("category_category_type_expense")
      expect(page).not_to have_checked_field("category_category_type_income")
      expect(page).not_to have_checked_field("category_category_type_savings")
    end

    it "prepopulates income type when accessed with type=income" do
      visit new_category_path(type: "income")

      expect(page).to have_checked_field("category_category_type_income")
      expect(page).not_to have_checked_field("category_category_type_expense")
      expect(page).not_to have_checked_field("category_category_type_savings")
    end

    it "prepopulates savings type when accessed with type=savings" do
      visit new_category_path(type: "savings")

      expect(page).to have_checked_field("category_category_type_savings")
      expect(page).not_to have_checked_field("category_category_type_expense")
      expect(page).not_to have_checked_field("category_category_type_income")
    end

    it "shows no type selected when no type parameter provided" do
      visit new_category_path

      expect(page).not_to have_checked_field("category_category_type_expense")
      expect(page).not_to have_checked_field("category_category_type_income")
      expect(page).not_to have_checked_field("category_category_type_savings")
    end
  end

  describe "form validation", :aggregate_failures do
    before { visit new_category_path }

    it "shows error for missing name" do
      find("label", text: "Expense").click
      click_button "Create Category"

      expect(page).to have_content("can't be blank")
      expect(page).to have_current_path(new_category_path)
    end

    it "shows error for missing category type" do
      fill_in "Name", with: "Test Category"
      click_button "Create Category"

      expect(page).to have_content("can't be blank")
      expect(page).to have_current_path(new_category_path)
    end

    it "shows error for duplicate name" do
      create(:category, name: "Groceries", user: user)

      fill_in "Name", with: "Groceries"
      find("label", text: "Expense").click
      click_button "Create Category"

      expect(page).to have_content("has already been taken")
      expect(page).to have_current_path(new_category_path)
    end

    it "allows duplicate names for different users" do
      other_user = create(:user)
      create(:category, name: "Groceries", user: other_user)

      fill_in "Name", with: "Groceries"
      find("label", text: "Expense").click
      click_button "Create Category"

      expect(page).to have_content("Category was successfully created")
    end
  end

  describe "successful submission", :aggregate_failures do
    before { visit new_category_path }

    it "creates expense category and redirects to expense index" do
      fill_in "Name", with: "New Expense Category"
      find("label", text: "Expense").click
      click_button "Create Category"

      expect(page).to have_content("Category was successfully created")
      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content("New Expense Category")
    end

    it "creates income category and redirects to income index" do
      fill_in "Name", with: "New Income Category"
      find("label", text: "Income").click
      click_button "Create Category"

      expect(page).to have_content("Category was successfully created")
      expect(page).to have_current_path(categories_path(type: "income"))
      expect(page).to have_content("New Income Category")
    end

    it "creates savings category and redirects to savings index" do
      fill_in "Name", with: "New Savings Category"
      find("label", text: "Savings").click
      click_button "Create Category"

      expect(page).to have_content("Category was successfully created")
      expect(page).to have_current_path(categories_path(type: "savings"))
      expect(page).to have_content("New Savings Category")
    end

    it "creates category with custom color" do
      fill_in "Name", with: "Colorful Category"
      find("label", text: "Expense").click
      fill_in "Color", with: "#FF5733"
      click_button "Create Category"

      expect(page).to have_content("Category was successfully created")
      created_category = Category.find_by(name: "Colorful Category")
      expect(created_category.color).to eq("#FF5733")
    end
  end

  describe "navigation", :aggregate_failures do
    before { visit new_category_path }

    it "returns to categories index when clicking Back to Categories" do
      click_link "Back to Categories"
      expect(page).to have_current_path(categories_path)
    end

    it "returns to categories index when clicking Cancel" do
      click_link "Cancel"
      expect(page).to have_current_path(categories_path)
    end
  end

  describe "type-specific navigation from prepopulated form", :aggregate_failures do
    it "navigates back to expense categories when prepopulated with expense" do
      visit new_category_path(type: "expense")
      click_link "Back to Categories"
      expect(page).to have_current_path(categories_path)
    end

    it "creates expense category and maintains type context" do
      visit new_category_path(type: "expense")

      fill_in "Name", with: "Prepopulated Expense"
      click_button "Create Category"

      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content("Expense Categories")
    end
  end
end
