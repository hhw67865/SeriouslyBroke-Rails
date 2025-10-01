# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entries Index - Table", type: :system do
  let!(:user) { create(:user) }
  let!(:expense_category) { create(:category, :expense, user: user, name: "Food") }
  let!(:income_category) { create(:category, :income, user: user, name: "Salary") }

  before { sign_in user }

  describe "table display", :aggregate_failures do
    let!(:expense_item) { create(:item, category: expense_category, name: "Groceries") }
    let!(:income_item) { create(:item, category: income_category, name: "Monthly Pay") }

    before do
      create(:entry, item: expense_item, amount: 150.50, description: "Weekly shopping", date: Date.current)
      create(:entry, item: income_item, amount: 3000.00, description: "Salary payment", date: Date.current - 1.day)
      visit entries_path
    end

    it "shows all required table headers" do
      expect(page).to have_content("TYPE")
      expect(page).to have_content("DATE")
      expect(page).to have_content("ITEM & DESCRIPTION")
      expect(page).to have_content("CATEGORY")
      expect(page).to have_content("AMOUNT")
      expect(page).to have_content("ACTIONS")
    end

    it "displays entry information correctly" do
      expect(page).to have_content("Groceries")
      expect(page).to have_content("Weekly shopping")
      expect(page).to have_content("Food")
      expect(page).to have_content("$150.50")

      expect(page).to have_content("Monthly Pay")
      expect(page).to have_content("Salary payment")
      expect(page).to have_content("Salary")
      expect(page).to have_content("$3,000.00")
    end

    it "shows entries in default date order (newest first)" do
      entries = page.all("tbody tr")

      # First entry should be the most recent (current date)
      expect(entries[0]).to have_content("Groceries")
      expect(entries[0]).to have_content("Weekly shopping")

      # Second entry should be older (yesterday)
      expect(entries[1]).to have_content("Monthly Pay")
      expect(entries[1]).to have_content("Salary payment")
    end
  end

  describe "empty state", :aggregate_failures do
    it "shows empty state when no entries exist" do
      visit entries_path

      expect(page).to have_content("No entries found")
    end

    it "shows empty state for specific type filter" do
      visit entries_path(type: "expenses")

      expect(page).to have_content("No entries found")
    end
  end

  describe "entry count display", :aggregate_failures do
    context "with single entry" do
      before do
        expense_item = create(:item, category: expense_category)
        create(:entry, item: expense_item, amount: 100)
        visit entries_path
      end

      it "shows singular entry count" do
        expect(page).to have_content("1 entry total")
      end
    end

    context "with multiple entries" do
      before do
        expense_item = create(:item, category: expense_category)
        create_list(:entry, 3, item: expense_item)
        visit entries_path
      end

      it "shows plural entry count" do
        expect(page).to have_content("3 entries total")
      end
    end
  end
end
