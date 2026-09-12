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

    # Two tiles, not three — `Category.category_types` drives the loop.
    it "shows category type options", :aggregate_failures do
      within("main") do
        expect(page).to have_content("Expense")
        expect(page).to have_content("Income")
        expect(page).to have_no_content("Savings")
      end
    end

    it "shows color selection options" do
      expect(page).to have_content("Selected:")
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
      expect(page).to have_button("Update Category")
    end

    it "shows error for duplicate name" do
      create(:category, name: "Duplicate Name", user: user)

      fill_in "Name", with: "Duplicate Name"
      click_button "Update Category"

      expect(page).to have_content("has already been taken")
      expect(page).to have_field("Name", with: "Duplicate Name")
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
      expect(category.reload.color).to eq("#FF5733")
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

  # What the form still writes about claiming: the give-way order, and nothing else. How much a
  # category is saving toward is a fact about a RULE.
  describe "the claiming fields", :aggregate_failures do
    it "pre-fills the give-way order and offers no target or start date" do
      visit edit_category_path(create(:category, :expense, user: user, name: "Vacation", priority: 3))

      expect(page).to have_field("Gives way", with: "3")
      expect(page).to have_no_field("Claiming since")
      expect(page).to have_no_field("Target")
    end

    it "writes the give-way order" do
      visit edit_category_path(category)
      fill_in "Gives way", with: "5"
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
      expect(category.reload.priority).to eq(5)
    end

    # The question this is really about — can this form damage a goal by saving something else? —
    # is asked of the record that holds the goal.
    it "leaves the goal's own figure alone" do
      vacation = create(:category, :expense, user: user, name: "Vacation")
      goal = create(:rule, :choice, :by_date, category: vacation, amount: 2_400, due: Date.new(2027, 6, 1))

      visit edit_category_path(vacation)
      fill_in "Name", with: "Vacation Fund"
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
      expect(goal.reload.slice(:amount, :anchor_date))
        .to eq("amount" => 2_400, "anchor_date" => Date.new(2027, 6, 1))
      expect(vacation.reload.name).to eq("Vacation Fund")
    end
  end

  # The server writes the `hidden` attribute for the wrong type, so the non-JS path is right on its
  # own and these need no browser.
  describe "the sections only one type can answer", :aggregate_failures do
    it "asks an expense category for its give-way order and nothing about income" do
      visit edit_category_path(category)

      expect(page).to have_field("Gives way")
      expect(page).to have_no_field("Counts as typical income")
    end

    it "asks an income category about typical income and nothing about giving way" do
      visit edit_category_path(create(:category, :income, user: user, name: "Salary"))

      expect(page).to have_field("Counts as typical income")
      expect(page).to have_no_field("Gives way")
    end

    it "unticks typical income for a bonus category" do
      bonus = create(:category, :income, user: user, name: "Bonus")
      visit edit_category_path(bonus)

      uncheck "Counts as typical income"
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
      expect(bonus.reload.regular).to be(false)
    end
  end

  # `:js`: the Stimulus controller swaps the two sections as the tiles change, which the first
  # paint cannot show.
  describe "the type-only sections under script", :js do
    it "swaps the two sections when the type changes", :aggregate_failures do
      visit edit_category_path(create(:category, :income, user: user, name: "Salary"))

      expect(page).to have_field("Counts as typical income")
      expect(page).to have_no_field("Gives way")

      find("label", text: "Expense").click
      expect(page).to have_field("Gives way")
      expect(page).to have_no_field("Counts as typical income")
    end
  end

  # `Category` refuses turning a ruled expense category into income, and the form says so like any
  # other error.
  describe "a ruled expense category that is asked to become income" do
    it "refuses and names the rules", :aggregate_failures do
      create(:rule, :rate, category: category, amount: 400)

      visit edit_category_path(category)
      find("label", text: "Income").click
      click_button "Update Category"

      expect(page).to have_content(Category::RULES_KEEP_IT_AN_EXPENSE)
      expect(page).to have_button("Update Category")
      expect(category.reload).to be_expense
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
