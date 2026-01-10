# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entries Forms", type: :system do
  let(:user) { create(:user) }
  let!(:expense_category) { create(:category, user: user, name: "Food", category_type: :expense) }
  let!(:income_category) { create(:category, user: user, name: "Salary", category_type: :income) }
  let!(:groceries_item) { create(:item, category: expense_category, name: "Groceries") }

  before { sign_in user, scope: :user }

  # Helper methods
  def select_category(category_name)
    find("#category_id-ts-control").click
    find("#category_id-ts-dropdown .option", text: category_name).click
    sleep 0.5
  end

  def select_item(item_name)
    find("#entry_item_id-ts-control").click
    find("#entry_item_id-ts-dropdown .option", text: item_name).click
  end

  def create_new_item(item_name)
    item_input = find("#entry_item_id-ts-control")
    item_input.click
    sleep 0.2
    item_input.send_keys(item_name)
    sleep 0.3
    item_input.send_keys(:enter)
    sleep 0.3
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

      it "starts with no category selected" do
        expect(page).to have_select("category_id", selected: "Select a category")
      end
    end

    describe "category and item interaction", :aggregate_failures do
      it "populates items when category is selected" do
        create(:item, category: expense_category, name: "Coffee")
        select_category("Food")

        find("#entry_item_id-ts-control").click
        within("#entry_item_id-ts-dropdown") do
          expect(page).to have_content("Groceries")
          expect(page).to have_content("Coffee")
        end
      end

      it "shows only items from selected category" do
        create(:item, category: income_category, name: "Paycheck")
        select_category("Food")

        find("#entry_item_id-ts-control").click
        within("#entry_item_id-ts-dropdown") do
          expect(page).to have_content("Groceries")
          expect(page).not_to have_content("Paycheck")
        end
      end
    end

    describe "successful submission with existing item", :aggregate_failures do
      it "creates entry and redirects to entries index" do
        select_category("Food")
        select_item("Groceries")
        fill_in "Amount", with: "50.00"
        fill_in "Description", with: "Weekly shopping"
        click_button "Create Entry"

        expect(page).to have_current_path(entries_path)
        expect(page).to have_content("Entry was successfully created")
        expect(Entry.count).to eq(1)
        expect(Entry.last.item).to eq(groceries_item)
      end
    end

    describe "successful submission with new item", :aggregate_failures do
      it "creates entry with new item and redirects" do
        select_category("Food")
        create_new_item("Brand New Item 123")
        fill_in "Amount", with: "25.00"
        fill_in "Description", with: "Test entry"
        click_button "Create Entry"

        expect(page).to have_current_path(entries_path)
        expect(page).to have_content("Entry was successfully created")
        expect(Entry.last.item.name).to eq("Brand New Item 123")
        expect(Entry.last.item.category).to eq(expense_category)
      end
    end

    describe "form validation", :aggregate_failures do
      it "shows error for missing amount" do
        select_category("Food")
        select_item("Groceries")
        click_button "Create Entry"

        expect(page).to have_current_path(new_entry_path)
        expect(page).to have_content("can't be blank")
      end
    end

    describe "navigation", :aggregate_failures do
      it "returns to entries index when clicking cancel" do
        click_link "Cancel"
        expect(page).to have_current_path(entries_path)
      end

      it "returns to entries index when clicking back" do
        click_link "Back to Entries"
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

    before do
      visit edit_entry_path(entry)
      # Wait for TomSelect to initialize by checking for the wrapper
      page.has_css?(".ts-wrapper", wait: 5)
    end

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

        expect(page).to have_current_path(edit_entry_path(entry))
        expect(page).to have_content("can't be blank")
      end

      it "shows error for invalid amount" do
        fill_in "Amount", with: "-10"
        click_button "Update Entry"

        expect(page).to have_current_path(edit_entry_path(entry))
        expect(page).to have_content("must be greater than 0")
      end
    end

    describe "navigation", :aggregate_failures do
      it "returns to entries index when clicking cancel" do
        click_link "Cancel"
        expect(page).to have_current_path(entries_path)
      end

      it "returns to entries index when clicking back" do
        click_link "Back to Entries"
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
