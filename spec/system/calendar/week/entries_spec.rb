# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Calendar Week - Entries", type: :system do
  let!(:user) { create(:user) }
  # `pool: checking` EXPLICIT (main-account spec §6, fix round 2): without it this category's
  # implicit-pool factory default mints its OWN anonymous account before `checking` is ever
  # referenced, and the auto-main trait claims that one instead — leaving `checking` non-main for
  # `income_category` below, which names it explicitly and needs it to be.
  let!(:expense_category) { create(:category, :expense, user: user, name: "Food", pool: checking) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let!(:goal) { create(:pool, :savings_pool, user: user, name: "Emergency", account: checking) }
  let!(:income_category) { create(:category, :income, user: user, name: "Salary", pool: checking) }
  let(:test_date) { Date.current }

  before { sign_in user, scope: :user }

  describe "entry display by type", :aggregate_failures do
    before do
      expense_item = create(:item, category: expense_category, name: "Groceries")
      income_item = create(:item, category: income_category, name: "Paycheck")

      create(:entry, item: expense_item, amount: 75.50, date: test_date)
      create(:entry, item: income_item, amount: 2500.00, date: test_date)
      # The contribution, as the movement it is now (plan 3, task 5). The week grid must not show
      # it: `WeeklyCalendarPresenter#fetch_entries` reads `Entry` alone.
      create(:pool_movement, from_pool: checking, to_pool: goal, amount: 500.00, date: test_date)

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

    # BOTH DIRECTIONS: the two entry groups render, and the movement of the same day renders in
    # neither of them and in no group of its own.
    it "shows no row at all for a movement", :aggregate_failures do
      expect(page).to have_no_content("$500.00")
      expect(page).to have_no_content("Emergency")
    end

    it "groups entries by type with labels", :aggregate_failures do
      expect(page).to have_content("Expense")
      expect(page).to have_content("Income")
      expect(page).to have_no_content("Savings")
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
