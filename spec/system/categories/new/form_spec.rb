# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories New - Form", type: :system do
  let!(:user) { create(:user) }

  # THE POOL PICKER IS GONE (two-ledger spec §5, Task 7). This file used to need an account to
  # offer it — and used to hold both sides of "a user with no pools at all", the state a required
  # `pool_id` made reachable. A category holds its own money now, so there is nothing to point at
  # and no such state: what the form asks instead is what the category HOLDS.
  before { sign_in user, scope: :user }

  describe "form display", :aggregate_failures do
    before { visit new_category_path }

    it "shows all form elements and page content" do
      expect(page).to have_content("Create New Category")
      expect(page).to have_content("Set up a new category to organize your finances")
      expect(page).to have_field("Name")
      expect(page).to have_content("Basic Information")
      expect(page).to have_content("Holding money")
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

    # THE THREE COLUMNS THAT REPLACED THE PICKER (two-ledger spec §3, §4), all three blank on a
    # new category: a category that holds nothing is the honest default, and its spending drains
    # available until it gets a rule or an allocation.
    it "asks what the category holds, and opens on nothing", :aggregate_failures do
      expect(page).to have_field("Target", with: "")
      expect(page).to have_field("Holding since", with: "")
      # `categories.priority` is NOT NULL DEFAULT 0, so the box opens on the front of the queue
      # rather than on a blank — the column has no "unset" to render.
      expect(page).to have_field("Funding priority", with: "0")
      expect(page).to have_no_select("Where this money lives")
    end

    # ** THE TWO HINTS THAT DESCRIBE A CONSEQUENCE, not a field. ** A target switches off
    # use-it-or-lose-it (`HoldingCalculator#compute_period_closed` refuses to sweep a
    # target-bearing category at all), and editing the funding start RE-READS spending that is
    # already recorded. Both are things a user meets a period later if the form does not say them.
    it "says a target stops the sweep and a start date moves history", :aggregate_failures do
      expect(page).to have_content("never swept back to available")
      expect(page).to have_content("changing this date moves history")
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

    it "creates a category that holds nothing when the three boxes are left alone", :aggregate_failures do
      fill_in "Name", with: "Buffer Spending"
      find("label", text: "Expense").click
      click_button "Create Category"

      expect(page).to have_content("Category was successfully created")
      category = Category.find_by(name: "Buffer Spending")
      expect(category).not_to be_holder
      expect([category.target_amount, category.funded_since]).to eq([nil, nil])
    end

    it "writes the target, the priority and the funding start", :aggregate_failures do
      submit_goal

      expect(page).to have_content("Category was successfully created")
      category = Category.find_by(name: "Vacation")
      expect([category.target_amount, category.priority]).to eq([2_400, 3])
      expect(category.funded_since).to eq(Date.new(2026, 2, 6))
      expect(category).to be_savings
    end

    def submit_goal
      fill_in "Name", with: "Vacation"
      find("label", text: "Expense").click
      fill_in "Target", with: "2400"
      fill_in "Funding priority", with: "3"
      # A `Date`, NOT a formatted string: Capybara sends a String into a date input as KEYSTROKES,
      # which reads back as the year 60206. See spec/system/budget_page/suggestions_spec.rb.
      fill_in "Holding since", with: Date.new(2026, 2, 6)
      click_button "Create Category"
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
