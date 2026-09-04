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
      expect(page).to have_content("Claiming money")
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

    # ** TWO COLUMNS NOW, WHERE THERE WERE THREE (rules-own-the-budget spec §5/§7). ** Both blank on a
    # new category: a category nothing claims is the honest default, and its spending comes straight
    # out of what's free to spend until it gets a rule. `Funding priority` is `Give-way order` — there
    # is no distribution to be funded first in (§6), and what priority ranks is who gives way when
    # the claims outrun the money (§4).
    #
    # ** THE TARGET FIELD IS GONE, AND ITS ABSENCE IS ASSERTED RATHER THAN LEFT TO THE OTHER
    # EXAMPLES. ** It wrote `categories.target_amount`, a column no claim formula reads:
    # `ClaimCalculator#shape` answers `:building` off the RULE's `carries_over` and caps at the
    # RULE's `target_amount`. A control that wrote nothing any screen reads, with a hint beside it
    # promising otherwise, is the one thing worse than no control. The question is asked on the rules
    # form now — "Unspent money: builds up", and the Target it reveals.
    it "asks what claims the category, and opens on nothing", :aggregate_failures do
      expect(page).to have_field("Claiming since", with: "")
      # `categories.priority` is NOT NULL DEFAULT 0, so the box opens at the front of the order
      # rather than on a blank — the column has no "unset" to render.
      expect(page).to have_field("Give-way order", with: "0")
      expect(page).to have_no_field("Target")
      expect(page).to have_no_select("Where this money lives")
    end

    # ** THE HINT THAT DESCRIBES A CONSEQUENCE, not a field. ** The START DATE MOVES HISTORY in TWO
    # sums: it is the period the accrual walk opens in (`ClaimCalculator#accrual_start`) and the day
    # `Entry.draining` starts attributing this category's receipts.
    #
    # THE TARGET'S HINT IS GONE WITH THE FIELD, and both halves are asserted: the promise it made
    # ("they build up toward this figure") was true of a RULE and false of this form, so a page that
    # deleted the input and kept the sentence would still be lying.
    it "says a start date moves history and promises nothing about a target", :aggregate_failures do
      expect(page).to have_content("changing it moves history in both directions")
      expect(page).to have_no_content("they build up toward this figure")
      expect(page).to have_no_content("swept")
    end

    # ** THE GIVE-WAY HINT NAMES THE TYPE FIRST (rules-own-the-budget spec §3). ** The number in this
    # box no longer decides the whole order: `HomePresenter#give_way_order` reads a rule's TYPE
    # before it reads any category's priority, so a hint that promised "the highest number gives way
    # first" full stop would be describing a ranking the app stopped using.
    # THE DIRECTION IS PINNED IN THE SAME WORDS THE BUDGET PAGE'S INSTRUCTION USES (fix round 1 —
    # LOW-11), and `spec/system/budget_page/rules_spec.rb` pins the other half of the pair — so the
    # two screens cannot drift back into two vocabularies for one rule.
    it "says a rule's type is read before this number is, and which way the number runs" do
      expect(page).to have_content("A rule's type goes first — choice, then usage, then bills")
      expect(page).to have_content("within each type, the highest number gives way first")
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
    # fixed. The controller checks the parameter now, and an unknown type falls back to the default
    # rather than being assigned.
    #
    # THE FORM NOW OPENS ON A DEFAULT (design review H2/H3), and these two examples changed with
    # it rather than merely being re-pinned: "nothing selected" was the old behaviour and it was
    # the defect. Two unringed tiles read as decoration, so a user filled the rest of the form in
    # and met "Category type can't be blank" on submit — over a card they had not registered as a
    # question. Expense is the default because it is what most categories are and it is the tab
    # the New button is pressed from.
    #
    # The retired `?type=savings` still selects no SAVINGS tile — which is the property this
    # example was written for, and it survives the default: the controller checks the parameter
    # against the enum and falls back, rather than assigning it and raising.
    it "falls back to the default when accessed with the retired type=savings", :aggregate_failures do
      visit new_category_path(type: "savings")

      expect(page).to have_content("Create New Category")
      expect(page).to have_checked_field("category_category_type_expense")
      expect(page).not_to have_checked_field("category_category_type_income")
      expect(page).to have_no_field("category_category_type_savings", visible: :all)
    end

    it "opens on Expense when no type parameter is provided", :aggregate_failures do
      visit new_category_path

      expect(page).to have_checked_field("category_category_type_expense")
      expect(page).not_to have_checked_field("category_category_type_income")
    end

    # THE COLOUR IS DEFAULTED TOO, and for a defect one step further downstream: with no swatch
    # ringed, a user who never touched the grid submitted `color: ""` — not nil — and every
    # `category.color || DEFAULT` guard in the app passed the empty string through to
    # `background-color: ;`. The saved category's chip rendered as a transparent hole on the index
    # and its banner icon as a white glyph on white. See `Category::DEFAULT_COLOR`.
    it "opens with the brand colour already chosen", :aggregate_failures do
      visit new_category_path

      expect(page).to have_checked_field(
        "category_color_#{Category::DEFAULT_COLOR.delete("#").downcase}",
        visible: :all
      )
      expect(page).to have_content(Category::DEFAULT_COLOR)
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

    # THE BLANK TYPE IS NO LONGER REACHABLE FROM THIS FORM (design review H2/H3): the tiles open
    # with Expense ringed and a radio cannot be un-picked, so a user who ignores the card entirely
    # now gets a working category rather than a 422 about a question they did not see. What used
    # to be "shows error for missing category type" is therefore the same submission asserted
    # against its new outcome.
    #
    # THE VALIDATION IS STILL THERE and still tested — `Category` refuses a blank type, which is
    # what a scripted or tampered POST meets; `#create` builds from `category_params` and inherits
    # nothing from `#new`. spec/models/category_spec.rb owns that half.
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

    it "creates a category nothing claims when the three boxes are left alone", :aggregate_failures do
      fill_in "Name", with: "Buffer Spending"
      find("label", text: "Expense").click
      click_button "Create Category"

      expect(page).to have_content("Category was successfully created")
      category = Category.find_by(name: "Buffer Spending")
      expect(category).not_to be_holder
      expect([category.target_amount, category.funded_since]).to eq([nil, nil])
    end

    # ** THE TWO COLUMNS THIS FORM STILL WRITES, and the one it does not (rules-own-the-budget spec
    # §5/§7). ** `target_amount` is neither on the form nor in `category_params`, so a category made
    # here names no figure whatever the user does — the figure is the building rule's, written on
    # the rules form.
    it "writes the give-way order and the claiming start, and no target", :aggregate_failures do
      submit_holder

      expect(page).to have_content("Category was successfully created")
      category = Category.find_by(name: "Vacation")
      expect(category.priority).to eq(3)
      expect(category.funded_since).to eq(Date.new(2026, 2, 6))
      expect(category.target_amount).to be_nil
      expect(category.building_rule).to be_nil
    end

    def submit_holder
      fill_in "Name", with: "Vacation"
      find("label", text: "Expense").click
      fill_in "Give-way order", with: "3"
      # A `Date`, NOT a formatted string: Capybara sends a String into a date input as KEYSTROKES,
      # which reads back as the year 60206. See spec/system/budget_page/suggestions_spec.rb.
      fill_in "Claiming since", with: Date.new(2026, 2, 6)
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
