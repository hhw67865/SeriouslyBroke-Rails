# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entries Forms", type: :system do
  let(:user) { create(:user) }
  let!(:expense_category) { create(:category, user: user, name: "Food", category_type: :expense) }
  let!(:income_category) { create(:category, user: user, name: "Salary", category_type: :income) }
  let!(:groceries_item) { create(:item, category: expense_category, name: "Groceries") }

  before { sign_in user, scope: :user }

  # The control rather than the input inside it: TomSelect sets that input to `opacity: 0` once its
  # select has a value, so a second click on it would land nowhere.
  def open_dropdown(id)
    find("##{id}-ts-control", visible: :all).find(:xpath, "..").click
  end

  # Choosing a category refetches the item list and rebuilds that control, so anything that reaches
  # for it before the fetch lands reaches for an element about to be thrown away. The controller
  # stamps the wrapper with whose list is on screen.
  def select_category(category_name)
    open_dropdown("category_id")
    find("#category_id-ts-dropdown .option", text: category_name).click
    expect(page).to have_css("[data-items-loaded='#{user.categories.find_by!(name: category_name).id}']")
  end

  def select_item(item_name)
    open_dropdown("entry_item_id")
    find("#entry_item_id-ts-dropdown .option", text: item_name).click
  end

  def create_new_item(item_name)
    open_dropdown("entry_item_id")
    find("#entry_item_id-ts-control").send_keys(item_name)
    find("#entry_item_id-ts-dropdown .create").click
    expect(page).to have_no_css("#entry_item_id-ts-dropdown .create")
  end

  def tap_pad(*labels)
    labels.each { |label| click_button(label) }
  end

  describe "New Entry Form" do
    before { visit new_entry_path }

    describe "form display", :aggregate_failures do
      it "shows all form elements" do
        expect(page).to have_content("New Entry")
        expect(page).to have_select("category_id")
        expect(page).to have_select("entry_item_id")
        expect(page).to have_field("Amount")
        expect(page).to have_field("Description")
        expect(page).to have_field("Date")
        expect(page).to have_button("Create Entry")
        expect(page).to have_link("Cancel")
      end
    end

    describe "category select", :aggregate_failures do
      it "shows only user's categories" do
        other_user = create(:user)
        create(:category, user: other_user, name: "Other User Category")

        visit new_entry_path

        expect(page).to have_content("Food")
        expect(page).to have_content("Salary")
        expect(page).not_to have_content("Other User Category")
      end

      # `:js` because a real browser is what selects a select's first option when none is marked.
      it "starts with no category selected", :js do
        expect(page).to have_select("category_id", selected: "Select a category")
      end

      # Two groups, not three — the picker's optgroups are the category types.
      it "groups categories by type", :aggregate_failures, :js do
        visit new_entry_path
        open_dropdown("category_id")

        within("#category_id-ts-dropdown") do
          expect(page).to have_css(".optgroup-header", text: /expenses/i)
          expect(page).to have_css(".optgroup-header", text: /incomes/i)
          expect(page).to have_no_css(".optgroup-header", text: /savings/i)
        end
      end

      it "shows categories under correct group headers", :js do
        visit new_entry_path
        open_dropdown("category_id")

        within("#category_id-ts-dropdown") do
          expenses_group = find(".optgroup", text: /expenses/i)
          expect(expenses_group).to have_content("Food")

          incomes_group = find(".optgroup", text: /incomes/i)
          expect(incomes_group).to have_content("Salary")
        end
      end
    end

    describe "category and item interaction", :aggregate_failures, :js do
      it "populates items when category is selected" do
        create(:item, category: expense_category, name: "Coffee")
        select_category("Food")

        open_dropdown("entry_item_id")
        within("#entry_item_id-ts-dropdown") do
          expect(page).to have_content("Groceries")
          expect(page).to have_content("Coffee")
        end
      end

      it "shows only items from selected category" do
        create(:item, category: income_category, name: "Paycheck")
        select_category("Food")

        open_dropdown("entry_item_id")
        within("#entry_item_id-ts-dropdown") do
          expect(page).to have_content("Groceries")
          expect(page).not_to have_content("Paycheck")
        end
      end
    end

    describe "filling the amount from an item's history", :aggregate_failures, :js do
      it "fills the amount and hint on pick, and hides the hint once typed over" do
        create(:entry, item: groceries_item, date: Date.current - 1, amount: 18.99)
        select_category("Food")

        select_item("Groceries")
        expect(page).to have_field("Amount", with: "18.99")
        expect(page).to have_css("[data-amount-hint]", text: "Filled from the last time")

        fill_in "Amount", with: "5"
        expect(page).to have_no_css("[data-amount-hint]", text: "Filled from the last time")
      end
    end

    describe "successful submission with existing item", :aggregate_failures, :js do
      it "creates entry and redirects to entries index" do
        select_category("Food")
        select_item("Groceries")
        fill_in "Amount", with: "50.00"
        fill_in "Description", with: "Weekly shopping"
        click_button "Create Entry"

        expect(page).to have_current_path(entries_path)
        expect(page).to have_content("Entry was successfully created")
        expect(Entry.count).to eq(1)
        expect(user.entries.sole.item).to eq(groceries_item)
      end
    end

    describe "successful submission with new item", :aggregate_failures, :js do
      it "creates entry with new item and redirects" do
        select_category("Food")
        create_new_item("Brand New Item 123")
        fill_in "Amount", with: "25.00"
        fill_in "Description", with: "Test entry"
        click_button "Create Entry"

        expect(page).to have_current_path(entries_path)
        expect(page).to have_content("Entry was successfully created")
        expect(user.entries.sole.item.name).to eq("Brand New Item 123")
        expect(user.entries.sole.item.category).to eq(expense_category)
      end
    end

    describe "form validation", :aggregate_failures do
      it "shows error for missing amount", :js do
        select_category("Food")
        select_item("Groceries")
        click_button "Create Entry"

        expect(page).to have_current_path(new_entry_path)
        expect(page).to have_content("can't be blank")
      end

      it "shows error when category is not selected" do
        fill_in "Amount", with: "50.00"
        click_button "Create Entry"

        expect(page).to have_content("must be selected")
      end

      it "shows error when item name is not selected", :js do
        select_category("Food")
        fill_in "Amount", with: "50.00"
        click_button "Create Entry"

        expect(page).to have_content("must be selected")
      end

      it "shows required indicators on category and name fields" do
        expect(page).to have_css("label", text: "* Category")
        expect(page).to have_css("label", text: "* Name")
      end
    end

    describe "formula support", :aggregate_failures, :js do
      it "evaluates a multiplication formula and saves the result" do
        select_category("Food")
        select_item("Groceries")
        fill_in "Amount", with: "10*5"
        click_button "Create Entry"

        expect(page).to have_current_path(entries_path)
        expect(page).to have_content("Entry was successfully created")
        expect(user.entries.sole.amount).to eq(50)
      end

      it "evaluates a formula with parentheses" do
        select_category("Food")
        select_item("Groceries")
        fill_in "Amount", with: "10*(5+2)"
        click_button "Create Entry"

        expect(page).to have_current_path(entries_path)
        expect(Entry.count).to eq(1)
        expect(user.entries.sole.amount).to eq(70)
      end

      it "evaluates decimal subtraction" do
        select_category("Food")
        select_item("Groceries")
        fill_in "Amount", with: "192.92-85.02"
        click_button "Create Entry"

        expect(page).to have_current_path(entries_path)
        expect(Entry.count).to eq(1)
        expect(user.entries.sole.amount).to eq(BigDecimal("107.9"))
      end

      it "still accepts a plain number" do
        select_category("Food")
        select_item("Groceries")
        fill_in "Amount", with: "50"
        click_button "Create Entry"

        expect(page).to have_current_path(entries_path)
        expect(Entry.count).to eq(1)
        expect(user.entries.sole.amount).to eq(50)
      end

      it "shows a validation error for an invalid formula" do
        select_category("Food")
        select_item("Groceries")
        fill_in "Amount", with: "abc"
        click_button "Create Entry"

        expect(page).to have_current_path(new_entry_path)
        expect(page).to have_content("is not a number")
        expect(Entry.count).to eq(0)
      end
    end

    describe "calculator pad", :aggregate_failures, :js do
      it "is hidden until toggled open with the Calculator button" do
        expect(page).not_to have_button("7")
        expect(page).not_to have_button("×")

        click_button "Calculator"
        expect(page).to have_button("7")
        expect(page).to have_button("×")

        click_button "Calculator"
        expect(page).not_to have_button("7")
      end

      it "builds a formula from the buttons and saves the evaluated result" do
        select_category("Food")
        select_item("Groceries")
        click_button "Calculator"
        tap_pad("1", "0", "×", "5")
        click_button "Create Entry"

        expect(page).to have_current_path(entries_path)
        expect(user.entries.sole.amount).to eq(50)
      end

      it "clears the amount with the C button" do
        click_button "Calculator"
        tap_pad("9", "9", "C")
        expect(page).to have_field("Amount", with: "")
      end

      it "suppresses the mobile keyboard while the pad is open" do
        expect(find_field("Amount")["inputmode"]).to be_blank

        click_button "Calculator"
        expect(find_field("Amount")["inputmode"]).to eq("none")

        click_button "Calculator"
        expect(find_field("Amount")["inputmode"]).to be_blank
      end
    end

    describe "navigation", :aggregate_failures do
      it "returns to entries index when clicking cancel" do
        click_link "Cancel"
        expect(page).to have_current_path(entries_path)
      end

      it "returns to entries index when clicking the Entries breadcrumb" do
        within("nav[aria-label='Breadcrumb']") { click_link "Entries" }
        expect(page).to have_current_path(entries_path)
      end
    end
  end

  describe "Edit Entry Form" do
    let!(:entry) do
      create(
        :entry,
        item: groceries_item,
        amount: 50.00,
        description: "Weekly shopping",
        date: Date.parse("2024-01-15")
      )
    end

    before { visit edit_entry_path(entry) }

    describe "form display", :aggregate_failures do
      it "shows all form elements" do
        expect(page).to have_content("Edit Entry")
        expect(page).to have_select("category_id")
        expect(page).to have_select("entry_item_id")
        expect(page).to have_field("Amount")
        expect(page).to have_field("Description")
        expect(page).to have_field("Date")
        expect(page).to have_button("Update Entry")
        expect(page).to have_link("Cancel")
      end
    end

    describe "form pre-population", :aggregate_failures do
      it "pre-fills all entry fields with existing data" do
        expect(page).to have_field("Amount", with: "50.0")
        expect(page).to have_field("Description", with: "Weekly shopping")
        expect(page).to have_field("Date", with: "2024-01-15")
      end

      it "shows items from the current category" do
        expect(page).to have_select("entry_item_id", selected: "Groceries")
      end
    end

    describe "category select", :aggregate_failures do
      it "shows only user's categories" do
        other_user = create(:user)
        create(:category, user: other_user, name: "Other User Category")

        visit edit_entry_path(entry)

        expect(page).to have_content("Food")
        expect(page).to have_content("Salary")
        expect(page).not_to have_content("Other User Category")
      end
    end

    describe "form validation", :aggregate_failures do
      it "shows error for missing amount" do
        fill_in "Amount", with: ""
        click_button "Update Entry"

        expect(page).to have_content("can't be blank")
        expect(page).to have_button("Update Entry")
      end

      it "shows error for invalid amount" do
        fill_in "Amount", with: "-10"
        click_button "Update Entry"

        expect(page).to have_content("must be greater than 0")
        expect(page).to have_button("Update Entry")
      end
    end

    describe "navigation", :aggregate_failures do
      it "returns to entries index when clicking cancel" do
        click_link "Cancel"
        expect(page).to have_current_path(entries_path)
      end

      it "returns to entries index when clicking the Entries breadcrumb" do
        within("nav[aria-label='Breadcrumb']") { click_link "Entries" }
        expect(page).to have_current_path(entries_path)
      end
    end

    describe "preserves data on validation error", :aggregate_failures do
      it "keeps form values after validation failure" do
        fill_in "Amount", with: ""
        fill_in "Description", with: "Updated description"
        click_button "Update Entry"

        expect(page).to have_field("Description", with: "Updated description")
      end
    end
  end
end
