# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Edit - Form", type: :system do
  let!(:user) { create(:user) }
  let!(:category) { create(:category, name: "Original Name", category_type: "expense", color: "#C9C78B", user: user) }

  before { sign_in user, scope: :user }

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

    # TWO TILES, NOT THREE (plan 3, task 5) — `Category.category_types` drives the loop.
    it "shows category type options", :aggregate_failures do
      expect(page).to have_content("Expense")
      expect(page).to have_content("Income")
      expect(page).to have_no_content("Savings")
    end

    it "shows color selection options" do
      expect(page).to have_content("Selected:")
      # Check that color grid is present
      expect(page).to have_css("[data-app--category--form-target='colorOption']", count: 16)
    end

    it "shows navigation elements" do
      expect(page).to have_link("Categories", href: categories_path)
      expect(page).to have_link(category.name, href: category_path(category))
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
      find("label", text: "Income").click
      fill_in "Color", with: "#00FF00"
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
      expect(page).to have_current_path(categories_path(type: "income"))

      category.reload
      expect(category.name).to eq("Completely Updated")
      expect(category.category_type).to eq("income")
      expect(category.color).to eq("#00FF00")
    end
  end

  # ── WHAT THIS CATEGORY HOLDS (two-ledger spec §3, §4, Task 7). The three columns that replaced
  # the pool picker, and the two of them that move something.
  describe "the holding fields", :aggregate_failures do
    let(:goal_attributes) do
      { name: "Vacation", target_amount: 2_400, priority: 3, funded_since: Date.new(2026, 2, 6) }
    end

    it "pre-fills the target, the priority and the funding start" do
      visit edit_category_path(create(:category, :expense, user: user, **goal_attributes))

      expect(page).to have_field("Target", with: "2400.0")
      expect(page).to have_field("Funding priority", with: "3")
      expect(page).to have_field("Holding since", with: "2026-02-06")
    end

    it "turns an ordinary category into a goal" do
      visit edit_category_path(category)
      fill_in "Target", with: "2400"
      fill_in "Holding since", with: Date.new(2026, 2, 6)
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
      expect(category.reload).to be_savings
    end
  end

  # ** EDITING `funded_since` MOVES A CATEGORY IN AND OUT OF THE FILL ORDER (Task 7's ruling). **
  #
  # `Category.in_fill_order` is `expenses.where.not(funded_since: nil)`, and `AllocationCalculator`
  # walks exactly that scope — so clearing the date on a category that CARRIES A RULE does not
  # merely change a balance's start line: the rule stops being reachable by any distribution, and
  # the Budget page has a band that says so. This is the pair the form's hint promises, asserted on
  # the screen that shows the consequence rather than on the record alone.
  describe "clearing and setting the funding start on a ruled category", :aggregate_failures do
    let!(:groceries) do
      create(:category, :expense, :funded, user: user, name: "Groceries", priority: 0)
    end

    before { create(:budget, :per_period_rate, category: groceries, amount: 400) }

    it "drops the category out of the fill order and into the band that says why" do
      visit edit_category_path(groceries)
      fill_in "Holding since", with: ""
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
      expect(groceries.reload.funded_since).to be_nil

      visit budget_page_path
      expect(page).to have_no_css("[data-category-group='Groceries']")
      within("[data-not-filling-rule='Groceries']") do
        expect(page).to have_content("Groceries isn't holding money yet")
      end
    end

    it "puts it back in the fill order when the date is set again" do
      groceries.update!(funded_since: nil)

      visit edit_category_path(groceries)
      fill_in "Holding since", with: Date.new(2026, 2, 6)
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
      expect(groceries.reload.funded_since).to eq(Date.new(2026, 2, 6))

      visit budget_page_path
      expect(page).to have_css("[data-category-group='Groceries']")
      expect(page).to have_no_css("[data-not-filling-rule='Groceries']")
    end
  end

  # ** CLEARING THE FUNDING START IS REFUSED WHILE THE CATEGORY HOLDS MONEY (final fix wave, I-1). **
  # The form is where the stranding was reachable: clear the date on a category carrying allocations
  # and the money stays exactly where it is while every reader stops looking at it — out of
  # `Category.in_fill_order`, out of every holder population, and out of the reallocation picker, so
  # there is no screen left that can move it back out. `Category#money_may_not_be_stranded` refuses
  # it, and this is that refusal arriving at the screen the user is on.
  #
  # THE BLOCK ABOVE IS THE OTHER DIRECTION AND STAYS UNCHANGED: Groceries there holds nothing, and it
  # clears freely. The guard is about money, not about rules.
  describe "clearing the funding start on a category holding money", :aggregate_failures do
    let!(:groceries) do
      create(:category, :expense, :funded, user: user, name: "Groceries", priority: 0)
    end

    before { create(:allocation, to_category: groceries, amount: 400, date: Date.current) }

    it "refuses, says the figure, and writes nothing" do
      visit edit_category_path(groceries)
      fill_in "Holding since", with: ""
      click_button "Update Category"

      expect(page).to have_content("can't be cleared while this category still holds $400.00")
      expect(page).to have_no_content("Category was successfully updated")
      expect(groceries.reload.funded_since).not_to be_nil
    end

    # THE DOOR THE MESSAGE NAMES, WALKED. Moving the $400 back to available is what the reallocation
    # screen writes, and the clear must then go through — a refusal a user cannot resolve would be a
    # lock rather than a guard.
    it "goes through once the money has been moved back to available" do
      create(:allocation, from_category: groceries, to_category: nil, amount: 400, date: Date.current)

      visit edit_category_path(groceries)
      fill_in "Holding since", with: ""
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
      expect(groceries.reload.funded_since).to be_nil
    end

    # THE HINT SAYS IT BEFORE THE CLICK. A constraint a user only meets as a 422 is a constraint the
    # form is hiding.
    it "warns in the field's own hint that the money has to move first" do
      visit edit_category_path(groceries)

      expect(page).to have_content("which you can only do once it holds nothing, so move any money out first")
    end
  end

  describe "navigation", :aggregate_failures do
    before { visit edit_category_path(category) }

    it "navigates to category details when clicking the category breadcrumb" do
      within("nav[aria-label='Breadcrumb']") { click_link category.name }
      expect(page).to have_current_path(category_path(category))
    end

    it "returns to categories index when clicking the Categories breadcrumb" do
      within("nav[aria-label='Breadcrumb']") { click_link "Categories" }
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
  end
end
