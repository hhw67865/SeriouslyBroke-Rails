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

  # ── WHAT CLAIMS THIS CATEGORY (two-ledger spec §3, §4, Task 7; re-labelled onto computed claims by
  # Task 4). `Holding since` is `Claiming since` and `Funding priority` is `Give-way order`, because
  # nothing is held and there is no distribution to be funded first in — see
  # `categories/_form.html.erb` for the whole of both renamings.
  #
  # ** TWO COLUMNS NOW (rules-own-the-budget spec §5/§7): `target_amount` has left the form and the
  # permit. ** How much a category builds up toward is a fact about a RULE, and the column this
  # field wrote is one no claim formula has read since the shapes moved onto the rule.
  describe "the claiming fields", :aggregate_failures do
    let(:holder_attributes) do
      { name: "Vacation", priority: 3, funded_since: Date.new(2026, 2, 6) }
    end

    it "pre-fills the give-way order and the claiming start, and offers no target" do
      visit edit_category_path(create(:category, :expense, user: user, **holder_attributes))

      expect(page).to have_field("Give-way order", with: "3")
      expect(page).to have_field("Claiming since", with: "2026-02-06")
      expect(page).to have_no_field("Target")
    end

    # ** A CATEGORY THAT ALREADY CARRIES A FIGURE KEEPS IT THROUGH AN EDIT, AND CANNOT BE GIVEN ONE
    # HERE. ** The migration that moves those figures onto the rules is Task 4's; until it runs, real
    # rows still hold the column, and a form that silently blanked it on every save would destroy the
    # data that migration is going to read. `params.expect` simply never sees the key, so an
    # untouched column stays untouched.
    it "leaves a figure the category already carries alone" do
      vacation = create(:category, :expense, user: user, **holder_attributes, target_amount: 2_400)

      visit edit_category_path(vacation)
      fill_in "Name", with: "Vacation Fund"
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
      expect(vacation.reload.target_amount).to eq(2_400)
      expect(vacation.name).to eq("Vacation Fund")
    end

    it "still writes the claiming start" do
      visit edit_category_path(category)
      fill_in "Claiming since", with: Date.new(2026, 2, 6)
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
      expect(category.reload.funded_since).to eq(Date.new(2026, 2, 6))
    end
  end

  # ** EDITING `funded_since` MOVES A CATEGORY IN AND OUT OF THE GROUPED HALF OF THE BUDGET PAGE
  # (Task 7's ruling, re-anchored on claims). **
  #
  # `BudgetPagePresenter#category_groups` is holders that own a rule, so clearing the date on a
  # category that CARRIES A RULE drops it out of the ordered list — and what it drops INTO is a band
  # whose sentence changed with the model. The rule does not stop claiming: `ClaimCalculator
  # #accrual_start` falls back to the rule's own birthday, so it claims its full $400 every period.
  # What stops is the SPENDING — `CategoryLedger::ENTRY_CATEGORY_ID` attributes an expense to its
  # category only from `funded_since` on — so the rule claims in full while nothing the user spends
  # there ever comes off it. That is what the band says now, and it is the pair the form's hint
  # promises, asserted on the screen that shows the consequence rather than on the record alone.
  describe "clearing and setting the claiming start on a ruled category", :aggregate_failures do
    let!(:groceries) do
      create(:category, :expense, :funded, user: user, name: "Groceries", priority: 0)
    end

    before { create(:budget, :per_period_rate, category: groceries, amount: 400) }

    it "drops the category out of the grouped half and into the band that says why" do
      visit edit_category_path(groceries)
      fill_in "Claiming since", with: ""
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
      expect(groceries.reload.funded_since).to be_nil

      visit budget_page_path
      expect(page).to have_no_css("[data-category-group='Groceries']")
      # The heading names the category (this rule pays no item), so the reason clause beside it
      # does not repeat it — see budget_page/rules_spec.rb for the whole of that rule.
      expect(find("[data-not-filling-rule='Groceries']").text)
        .to include("Groceries", "has no claiming date")
    end

    it "puts it back in the grouped half when the date is set again" do
      groceries.update!(funded_since: nil)

      visit edit_category_path(groceries)
      fill_in "Claiming since", with: Date.new(2026, 2, 6)
      click_button "Update Category"

      expect(page).to have_content("Category was successfully updated")
      expect(groceries.reload.funded_since).to eq(Date.new(2026, 2, 6))

      visit budget_page_path
      expect(page).to have_css("[data-category-group='Groceries']")
      expect(page).to have_no_css("[data-not-filling-rule='Groceries']")
    end
  end

  # ** THE "clearing the funding start on a category holding money" GROUP IS DELETED WHOLE (three
  # examples), WITH THE REFUSAL IT DROVE (computed-claims spec §5, Task 4). ** It asserted that
  # `Category#money_may_not_be_stranded` rejected a cleared date while allocations still sat in the
  # category ("can't be cleared while this category still holds $400.00"), that the clear went
  # through once a reallocation had moved the $400 back to available, and that the field's hint
  # warned about it before the click.
  #
  # NONE OF IT SURVIVES, and not because the guard was removed — because the state it guarded cannot
  # be built. Nothing is ever MOVED into a category (§5), so a cleared date leaves nothing behind and
  # there is nothing for a 422 to protect: the fixture is unwritable by any means and the sentences
  # are unrenderable. What the clear DOES still do is re-read history — spending before the date
  # counts against no rule — and that is the block above's subject.
  #
  # WHAT REPLACED THEM is the block above, which is now the WHOLE behaviour of clearing the date:
  # the category stops claiming and its rules move to the Budget page's band. The form's hint says
  # that instead of the old warning, and `categories/new/form_spec.rb` pins its wording.

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
