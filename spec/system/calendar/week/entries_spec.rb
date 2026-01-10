# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Calendar Week - Entries", type: :system do
  let!(:user) { create(:user) }
  let!(:expense_category) { create(:category, :expense, user: user, name: "Food") }
  let!(:income_category) { create(:category, :income, user: user, name: "Salary") }
  let!(:savings_category) { create(:category, :savings, user: user, name: "Emergency") }
  let(:test_date) { Date.current }

  before { sign_in user, scope: :user }

  describe "entry display by type", :aggregate_failures do
    before do
      expense_item = create(:item, category: expense_category, name: "Groceries")
      income_item = create(:item, category: income_category, name: "Paycheck")
      savings_item = create(:item, category: savings_category, name: "Deposit")

      create(:entry, item: expense_item, amount: 75.50, date: test_date)
      create(:entry, item: income_item, amount: 2500.00, date: test_date)
      create(:entry, item: savings_item, amount: 500.00, date: test_date)

      visit calendar_week_path(date: test_date.strftime("%Y-%m-%d"))
    end

    it "shows expense entries with item name and amount" do
      expect(page).to have_content("Groceries")
      expect(page).to have_content("$75.50")
    end

    it "shows income entries with item name and amount" do
      expect(page).to have_content("Paycheck")
      expect(page).to have_content("$2,500.00")
    end

    it "shows savings entries with item name and amount" do
      expect(page).to have_content("Deposit")
      expect(page).to have_content("$500.00")
    end

    it "groups entries by type with labels" do
      expect(page).to have_content("Expense")
      expect(page).to have_content("Income")
      expect(page).to have_content("Savings")
    end
  end

  describe "entry actions", :aggregate_failures do
    let!(:expense_item) { create(:item, category: expense_category, name: "Coffee") }
    let!(:entry) { create(:entry, item: expense_item, amount: 5.00, date: test_date) }

    before { visit calendar_week_path(date: test_date.strftime("%Y-%m-%d")) }

    it "has edit and delete links in the DOM" do
      # Edit/Delete links are hidden until hover, but present in the DOM
      expect(page).to have_link("Edit", href: edit_entry_path(entry), visible: :all)
      expect(page).to have_link("Delete", href: entry_path(entry), visible: :all)
    end

    it "navigates to edit form when clicking edit" do
      entry_row = find("li", text: entry.item.name)
      entry_row.hover

      click_link "Edit"

      expect(page).to have_current_path(edit_entry_path(entry))
    end

    it "deletes entry when confirmed" do
      entry_id = entry.id
      entry_row = find("li", text: entry.item.name)
      entry_row.hover

      accept_confirm do
        click_link "Delete"
      end

      expect(page).to have_content("Entry was successfully deleted")
      expect(Entry.exists?(entry_id)).to be(false)
    end
  end

  describe "empty day display", :aggregate_failures do
    before { visit calendar_week_path(date: test_date.strftime("%Y-%m-%d")) }

    it "shows no entry groups when day is empty" do
      # When no entries exist, the type sections should not be rendered
      expect(page).not_to have_css(".rounded.border.border-gray-100", text: "Expense")
    end
  end

  describe "multiple entries same type", :aggregate_failures do
    before do
      expense_item1 = create(:item, category: expense_category, name: "Coffee")
      expense_item2 = create(:item, category: expense_category, name: "Lunch")

      create(:entry, item: expense_item1, amount: 5.00, date: test_date)
      create(:entry, item: expense_item2, amount: 15.00, date: test_date)

      visit calendar_week_path(date: test_date.strftime("%Y-%m-%d"))
    end

    it "shows total for type group" do
      expect(page).to have_content("$20.00")
    end

    it "lists all entries within the type group" do
      expect(page).to have_content("Coffee")
      expect(page).to have_content("Lunch")
    end
  end
end
