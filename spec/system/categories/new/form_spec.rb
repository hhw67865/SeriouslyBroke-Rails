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
      expect(page).to have_content("Claiming money")
      expect(page).to have_content("Appearance")
      expect(page).to have_button("Create Category")
    end

    # Two tiles, not three: the form loops `Category.category_types`.
    it "shows category type options", :aggregate_failures do
      within("main") do
        expect(page).to have_content("Expense")
        expect(page).to have_content("Income")
        expect(page).to have_no_content("Savings")
      end
      expect(page).to have_no_field("category_category_type_savings", visible: :all)
    end

    it "shows color selection options" do
      expect(page).to have_content("Selected:")
      expect(page).to have_css("[data-app--category--form-target='colorOption']", count: 16)
    end

    it "shows navigation elements" do
      expect(page).to have_link("Categories", href: categories_path)
      expect(page).to have_link("Cancel")
    end

    # `categories.priority` is NOT NULL DEFAULT 0, so the box opens at the front of the order
    # rather than on a blank — the column has no "unset" to render.
    it "asks only what the record can answer, and opens on the default order", :aggregate_failures do
      expect(page).to have_field("Gives way", with: "0")
      expect(page).to have_no_field("Claiming since")
      expect(page).to have_no_field("Target")
      expect(page).to have_no_select("Where this money lives")
    end

    it "says which way the give-way number runs" do
      expect(page).to have_content(
        "Lower numbers are filled first; when money is short, the highest number gives way first."
      )
    end
  end

  describe "type prepopulation", :aggregate_failures do
    it "prepopulates expense type when accessed with type=expense" do
      visit new_category_path(type: "expense")

      expect(page).to have_checked_field("category_category_type_expense")
      expect(page).to have_no_checked_field("category_category_type_income")
    end

    it "prepopulates income type when accessed with type=income" do
      visit new_category_path(type: "income")

      expect(page).to have_checked_field("category_category_type_income")
      expect(page).to have_no_checked_field("category_category_type_expense")
    end

    # `?type=savings` names a type the enum no longer has. The controller checks the parameter
    # against the enum, so a stale bookmark falls back to the default instead of raising.
    it "falls back to the default when accessed with the retired type=savings", :aggregate_failures do
      visit new_category_path(type: "savings")

      expect(page).to have_content("Create New Category")
      expect(page).to have_checked_field("category_category_type_expense")
      expect(page).to have_no_checked_field("category_category_type_income")
      expect(page).to have_no_field("category_category_type_savings", visible: :all)
    end

    it "opens on Expense when no type parameter is provided", :aggregate_failures do
      visit new_category_path

      expect(page).to have_checked_field("category_category_type_expense")
      expect(page).to have_no_checked_field("category_category_type_income")
    end

    # With no swatch ringed a user who never touched the grid submitted `color: ""` — not nil —
    # and every `color ||` guard in the app passed the empty string through to `background-color:`.
    it "opens with the brand colour already chosen", :aggregate_failures do
      visit new_category_path

      expect(page).to have_checked_field(
        "category_color_#{Category::DEFAULT_COLOR.delete("#").downcase}",
        visible: :all
      )
      expect(page).to have_content(Category::DEFAULT_COLOR)
    end
  end

  # The server hides the wrong section on first paint, so the non-JS path is right on its own.
  describe "the sections only one type can answer", :aggregate_failures do
    it "asks an expense category for its give-way order and nothing about income" do
      visit new_category_path(type: "expense")

      expect(page).to have_field("Gives way")
      expect(page).to have_no_field("Counts as typical income")
    end

    it "asks an income category about typical income and nothing about giving way" do
      visit new_category_path(type: "income")

      expect(page).to have_field("Counts as typical income")
      expect(page).to have_no_field("Gives way")
    end
  end

  # `:js`: both sections are rendered and the form's Stimulus controller swaps them as the tiles
  # change, so without a browser the first paint is the whole story.
  describe "the type-only sections under script", :js do
    it "swaps the two sections as the tiles change", :aggregate_failures do
      visit new_category_path

      expect(page).to have_field("Gives way")
      expect(page).to have_no_field("Counts as typical income")

      find("label", text: "Income").click
      expect(page).to have_field("Counts as typical income")
      expect(page).to have_no_field("Gives way")

      find("label", text: "Expense").click
      expect(page).to have_field("Gives way")
      expect(page).to have_no_field("Counts as typical income")
    end
  end

  # `:js`: the swatch grid writes the hex box and the preview through the form's Stimulus
  # controller, and rings the chosen swatch by its `.color-option` class.
  describe "the colour picker", :js do
    it "writes the chosen swatch into the hex box, the preview and the ring", :aggregate_failures do
      visit new_category_path

      find("[data-app--category--form-target='colorOption'][data-color='#2196F3']").click

      expect(page).to have_field("Color", with: "#2196F3")
      expect(find("[data-app--category--form-target='selectedColorCode']").text).to eq("#2196F3")
      expect(page).to have_css("[data-color='#2196F3'].ring-2")
    end
  end

  describe "form validation", :aggregate_failures do
    before { visit new_category_path }

    # Rack::Test follows the POST, so the refused form is re-rendered at /categories rather than
    # at /categories/new — the assertion is that the form came back, not where it lives.
    it "shows error for missing name" do
      find("label", text: "Expense").click
      click_button "Create Category"

      expect(page).to have_content("can't be blank")
      expect(page).to have_button("Create Category")
    end

    # The tiles open with Expense ringed and a radio cannot be un-picked, so a user who ignores
    # the card gets a working category rather than a 422 about a question they did not see.
    it "creates the category with the default type when the tiles are left alone" do
      fill_in "Name", with: "Test Category"
      click_button "Create Category"

      expect(page).to have_content("Category was successfully created")
      expect(user.categories.find_by(name: "Test Category")).to be_expense
    end

    it "shows error for duplicate name" do
      create(:category, name: "Groceries", user: user)

      fill_in "Name", with: "Groceries"
      find("label", text: "Expense").click
      click_button "Create Category"

      expect(page).to have_content("has already been taken")
      expect(page).to have_field("Name", with: "Groceries")
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

    it "creates a category nothing claims when the boxes are left alone", :aggregate_failures do
      fill_in "Name", with: "Spare Spending"
      find("label", text: "Expense").click
      click_button "Create Category"

      expect(page).to have_content("Category was successfully created")
      category = Category.find_by(name: "Spare Spending")
      expect(category).not_to be_ruled
      expect(category.rules).to be_empty
    end

    # How much a category is saving toward is a fact about a RULE, so no target is written here.
    it "writes the give-way order and no target", :aggregate_failures do
      fill_in "Name", with: "Vacation"
      find("label", text: "Expense").click
      fill_in "Gives way", with: "3"
      click_button "Create Category"

      expect(page).to have_content("Category was successfully created")
      category = Category.find_by(name: "Vacation")
      expect(category.priority).to eq(3)
      expect(Category.column_names).not_to include("target_amount")
      expect(category.rules).to be_empty
    end

    it "creates category with custom color" do
      fill_in "Name", with: "Colorful Category"
      find("label", text: "Expense").click
      fill_in "Color", with: "#FF5733"
      click_button "Create Category"

      expect(page).to have_content("Category was successfully created")
      expect(Category.find_by(name: "Colorful Category").color).to eq("#FF5733")
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
