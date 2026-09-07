# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entries Index - Filtering", type: :system do
  let!(:user) { create(:user) }
  let!(:expense_category) { create(:category, :expense, user: user, name: "Food") }
  let!(:income_category) { create(:category, :income, user: user, name: "Salary") }

  let!(:expense_item) { create(:item, category: expense_category, name: "Groceries") }
  let!(:income_item) { create(:item, category: income_category, name: "Monthly Pay") }

  before do
    sign_in user, scope: :user
    create(:entry, item: expense_item, amount: 150, description: "Weekly shopping")
    create(:entry, item: income_item, amount: 3000, description: "Salary payment")
  end

  describe "type tab filtering", :aggregate_failures do
    it "shows all entries by default" do
      visit entries_path

      expect(page).to have_content("All")
      expect(page).to have_content("Groceries")
      expect(page).to have_content("Monthly Pay")
    end

    it "filters to expense entries only" do
      visit entries_path(type: "expenses")

      expect(page).to have_content("Expenses")
      expect(page).to have_content("Groceries")
      expect(page).to have_content("Food")
      expect(page).not_to have_content("Monthly Pay")
    end

    # ** AN OPENING RECORD IS NOT SPENDING, AND THE `all` TAB IS STILL WHERE IT LIVES (fix round —
    # MED-2). ** `Opening Shortfall` is an EXPENSE category by construction — that is how a negative
    # opening lowers the pot — so this tab listed the record of what an account started with among
    # the household's receipts. Both directions AND both tabs in one example, because hiding the row
    # everywhere would hide the door: deleting an opening entry is what puts the question back on
    # the account's card (`HomePresenter#awaiting_opening?`), and `all` is where a user finds it.
    it "keeps an opening record out of the expenses tab and in the all tab", :aggregate_failures do
      checking = create(:pool, :account, user: user, name: "Checking")
      opening = create(:category, :opening_shortfall, user: user)
      item = create(:item, category: opening, name: "Initial balance")
      create(:entry, item: item, amount: 777, description: "Checking opening balance", opening_account: checking)

      visit entries_path(type: "expenses")
      expect(page).to have_content("Groceries")
      expect(page).to have_no_content("Initial balance")

      visit entries_path
      expect(page).to have_content("Initial balance")
    end

    it "filters to income entries only" do
      visit entries_path(type: "income")

      expect(page).to have_content("Income")
      expect(page).to have_content("Monthly Pay")
      expect(page).to have_content("Salary")
      expect(page).not_to have_content("Groceries")
    end

    # A STALE `?type=savings` LINK FALLS THROUGH TO EVERYTHING (plan 3, task 5). The filter's
    # `case` has no savings arm any more and its `else` returns the unfiltered scope, which is the
    # same answer the All tab gives — a bookmark that shows the user their entries rather than an
    # empty list under a tab that is not there.
    it "has no savings tab, and a stale savings link shows everything", :aggregate_failures do
      visit entries_path

      expect(page).to have_no_link("Savings")

      visit entries_path(type: "savings")

      expect(page).to have_content("Groceries")
      expect(page).to have_content("Monthly Pay")
    end
  end

  describe "tab navigation", :aggregate_failures do
    before { visit entries_path }

    it "switches to expenses tab" do
      click_link "Expenses"
      expect(page).to have_current_path(entries_path(type: "expenses"))
      expect(page).to have_css("a.border-brand.text-brand", text: "Expenses")
    end

    it "switches to income tab" do
      click_link "Income"
      expect(page).to have_current_path(entries_path(type: "income"))
      expect(page).to have_css("a.border-brand.text-brand", text: "Income")
    end

    it "switches back to all tab" do
      click_link "Expenses"
      click_link "All"
      expect(page).to have_current_path(entries_path)
      expect(page).to have_css("a.border-brand.text-brand", text: "All")
    end
  end

  describe "empty states for filtered types", :aggregate_failures do
    before do
      # Clear all entries and create only expense entries
      Entry.destroy_all
      create(:entry, item: expense_item, amount: 100)
    end

    it "shows empty state for income when none exist" do
      visit entries_path(type: "income")

      expect(page).to have_content("No entries found")
    end
  end

  describe "type filtering with pagination", :aggregate_failures do
    before do
      # Create many entries of different types
      create_list(:entry, 15, item: expense_item)
      create_list(:entry, 25, item: income_item) # More than per_page limit
    end

    it "paginates within filtered type" do
      visit entries_path(type: "income")

      expect(page).to have_content("Showing 1 to 20 of 26 entries") # 25 + 1 from before block
      expect(page).to have_link("Next")

      click_link "Next"
      expect(page).to have_content("Showing 21 to 26 of 26 entries")
      expect(page).to have_current_path(entries_path(type: "income", page: 2))
    end
  end
end
