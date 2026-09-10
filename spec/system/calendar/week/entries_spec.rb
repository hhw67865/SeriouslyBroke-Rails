# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Calendar Week - Entries", type: :system do
  let!(:user) { create(:user) }
  let!(:expense_category) { create(:category, :expense, user: user, name: "Food") }
  let!(:income_category) { create(:category, :income, user: user, name: "Salary") }
  let!(:checking) { create(:account, user: user, name: "Checking") }
  let!(:savings_account) { create(:account, user: user, name: "Emergency") }
  let(:test_date) { Date.current }

  before { sign_in user, scope: :user }

  describe "entry display by type", :aggregate_failures do
    before do
      expense_item = create(:item, category: expense_category, name: "Groceries")
      income_item = create(:item, category: income_category, name: "Paycheck")

      create(:entry, item: expense_item, amount: 75.50, date: test_date)
      create(:entry, item: income_item, amount: 2500.00, date: test_date)
      create(:transfer, from_account: checking, to_account: savings_account, amount: 500.00, date: test_date)

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

    # Both directions: the two entry groups render, and the transfer of the same day renders in
    # neither of them and in no group of its own.
    it "shows no row at all for a transfer", :aggregate_failures do
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
      # Edit/Delete links are revealed on hover, but present in the DOM
      expect(page).to have_link("Edit", href: edit_entry_path(entry), visible: :all)
      expect(page).to have_link("Delete", href: entry_path(entry), visible: :all)
    end

    it "navigates to edit form when clicking edit" do
      click_link "Edit"

      expect(page).to have_current_path(edit_entry_path(entry))
    end

    it "asks Turbo to confirm before deleting" do
      delete_link = find("a", text: "Delete", visible: :all)

      expect(delete_link["data-turbo-method"]).to eq("delete")
      expect(delete_link["data-turbo-confirm"]).to be_present
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

  # A day this wide of a claim (rent-sized) prints ten characters plus a sign — "-$1,690.00" —
  # which does not fit beside the "Expense" label at the column's width. Wrapped onto its own line
  # it stays inside the column; left on one line it used to run under the next day's white
  # background, which is a clip, not a crop.
  describe "a type total wide enough to fill the narrow day column", :js do
    before do
      rent_item = create(:item, category: expense_category, name: "Rent")
      cafe_item = create(:item, category: expense_category, name: "Cafe")

      create(:entry, item: rent_item, amount: 1_500.00, date: test_date)
      create(:entry, item: cafe_item, amount: 190.00, date: test_date)

      visit calendar_week_path(date: test_date.strftime("%Y-%m-%d"))
    end

    it "keeps the total inside its own day column instead of overflowing into the next one", :aggregate_failures do
      expect(page).to have_css("[data-type-total='expense']", text: "$1,690.00")

      column = page.find("[data-day-column='#{test_date.iso8601}']").native.rect
      total = page.find("[data-type-total='expense']").native.rect

      expect(total.x).to be >= column.x
      expect(total.x + total.width).to be <= column.x + column.width
    end
  end
end
