# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories New - Form", type: :system do
  let!(:user) { create(:user) }

  # EVERY CATEGORY NAMES A POOL (plan 3 decision 3), so this form now needs one to offer — and a
  # brand-new user has none, which is a state this file has to hold BOTH sides of.
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before do
    user.update!(default_account: checking)
    sign_in user, scope: :user
  end

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

    # TWO TILES, NOT THREE (plan 3, task 5). The form loops `Category.category_types`, so the
    # savings tile disappeared with the enum value and the grid closes at two.
    it "shows category type options", :aggregate_failures do
      expect(page).to have_content("Expense")
      expect(page).to have_content("Income")
      expect(page).to have_no_content("Savings")
      expect(page).to have_no_field("category_category_type_savings", visible: :all)
    end

    it "shows color selection options" do
      expect(page).to have_content("Selected:")
      # Check that color grid is present
      expect(page).to have_css("[data-app--category--form-target='colorOption']", count: 16)
    end

    it "shows navigation elements" do
      expect(page).to have_link("Categories", href: categories_path)
      expect(page).to have_link("Cancel")
    end

    # DECISION 3'S CONTROL. The pool is required, so the form must ask — and it must OPEN on the
    # default account rather than on a blank, because a blank is the one answer the model refuses
    # and a new category's honest default is "this comes out of my buffer".
    it "asks where the money lives and opens on the default account", :aggregate_failures do
      expect(page).to have_select("Where this money lives", selected: "Checking")
      # No blank option: the choice is required, and a prompt that submits an empty string would
      # offer the one answer the model refuses.
      expect(page).to have_css("select[name='category[pool_id]'] option", count: 1)
    end

    # The pools are grouped by what they ARE, in the nouns the rest of the app prints.
    it "groups the pools by their noun", :aggregate_failures do
      envelope = create(:pool, :budget_pool, user: user, account: checking, name: "Groceries")
      create(:pool, :savings_pool, user: user, account: checking, name: "Vacation")

      visit new_category_path

      expect(page).to have_css("optgroup[label='Buffer'] option", text: "Checking")
      expect(page).to have_css("optgroup[label='Envelope'] option", text: envelope.name)
      expect(page).to have_css("optgroup[label='Goal'] option", text: "Vacation")
    end
  end

  # THE STATE DECISION 3 MAKES REACHABLE FOR THE FIRST TIME: a user with no pools at all. An empty
  # picker would submit blank and meet "Pool must exist" with nothing the user could do about it,
  # so the form says what is missing and names the route to it.
  describe "a user with no pools", :aggregate_failures do
    before do
      user.update!(default_account: nil)
      checking.destroy!
      visit new_category_path
    end

    it "says so and points at the pool form rather than offering an empty picker" do
      expect(page).to have_no_select("Where this money lives")
      expect(page).to have_css("[data-no-pools]", text: "you have no accounts yet")
      expect(page).to have_link("Make an account first", href: new_pool_path)
    end
  end

  describe "type prepopulation", :aggregate_failures do
    it "prepopulates expense type when accessed with type=expense" do
      visit new_category_path(type: "expense")

      expect(page).to have_checked_field("category_category_type_expense")
      expect(page).not_to have_checked_field("category_category_type_income")
    end

    it "prepopulates income type when accessed with type=income" do
      visit new_category_path(type: "income")

      expect(page).to have_checked_field("category_category_type_income")
      expect(page).not_to have_checked_field("category_category_type_expense")
    end

    # `?type=savings` NAMES A TYPE THE ENUM NO LONGER HAS (plan 3, task 5), and this action USED TO
    # ASSIGN THE PARAMETER STRAIGHT THROUGH — `category_type = "savings"` raises ArgumentError, so a
    # stale bookmark took the whole page down with a 500. Measured at the browser before it was
    # fixed. The controller checks the parameter now and an unknown type selects nothing, which is
    # what the form does with no `type` at all.
    it "opens with nothing selected when accessed with the retired type=savings", :aggregate_failures do
      visit new_category_path(type: "savings")

      expect(page).to have_content("Create New Category")
      expect(page).not_to have_checked_field("category_category_type_expense")
      expect(page).not_to have_checked_field("category_category_type_income")
    end

    it "shows no type selected when no type parameter provided" do
      visit new_category_path

      expect(page).not_to have_checked_field("category_category_type_expense")
      expect(page).not_to have_checked_field("category_category_type_income")
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

    it "keeps the pool the picker was opened on" do
      fill_in "Name", with: "Buffer Spending"
      find("label", text: "Expense").click
      click_button "Create Category"

      expect(page).to have_content("Category was successfully created")
      expect(Category.find_by(name: "Buffer Spending").pool).to eq(checking)
    end

    it "writes the pool the user picked instead" do
      envelope = create(:pool, :budget_pool, user: user, account: checking, name: "Groceries")
      visit new_category_path

      fill_in "Name", with: "Weekly Shop"
      find("label", text: "Expense").click
      select envelope.name, from: "Where this money lives"
      click_button "Create Category"

      expect(page).to have_content("Category was successfully created")
      expect(Category.find_by(name: "Weekly Shop").pool).to eq(envelope)
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

    it "returns to categories index when clicking the Categories breadcrumb" do
      within("nav[aria-label='Breadcrumb']") { click_link "Categories" }
      expect(page).to have_current_path(categories_path)
    end

    it "returns to categories index when clicking Cancel" do
      click_link "Cancel"
      expect(page).to have_current_path(categories_path)
    end
  end

  describe "type-specific navigation from prepopulated form", :aggregate_failures do
    it "navigates back to categories when prepopulated with expense" do
      visit new_category_path(type: "expense")
      within("nav[aria-label='Breadcrumb']") { click_link "Categories" }
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
