# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entries Index - Sorting", type: :system do
  let!(:user) { create(:user) }
  let!(:category) { create(:category, :expense, user: user, name: "Food") }
  let!(:item) { create(:item, category: category, name: "Groceries") }

  before do
    sign_in user
    # Create entries with different dates and amounts for sorting tests
    create(:entry, item: item, amount: 100, date: Date.parse("2024-01-10"), description: "First entry")
    create(:entry, item: item, amount: 300, date: Date.parse("2024-01-15"), description: "Third entry")
    create(:entry, item: item, amount: 200, date: Date.parse("2024-01-05"), description: "Second entry")
    visit entries_path
  end

  describe "default sorting", :aggregate_failures do
    it "sorts by date descending by default" do
      entries = page.all("tbody tr")

      # Should be ordered by date DESC (newest first)
      expect(entries[0]).to have_content("Third entry") # 2024-01-15
      expect(entries[1]).to have_content("First entry") # 2024-01-10
      expect(entries[2]).to have_content("Second entry") # 2024-01-05
    end

    it "shows sortable headers" do
      expect(page).to have_link("Date")
      expect(page).to have_link("Amount")
    end
  end

  describe "date sorting", :aggregate_failures do
    it "sorts by date ascending when clicked" do
      click_link "Date"

      expect(page).to have_current_path(entries_path(sort: "date", direction: "asc"))

      entries = page.all("tbody tr")
      expect(entries[0]).to have_content("Second entry") # 2024-01-05
      expect(entries[1]).to have_content("First entry") # 2024-01-10
      expect(entries[2]).to have_content("Third entry") # 2024-01-15
    end

    it "toggles to date descending when clicked again" do
      click_link "Date" # First click - ascending
      click_link "Date" # Second click - descending

      expect(page).to have_current_path(entries_path(sort: "date", direction: "desc"))

      entries = page.all("tbody tr")
      expect(entries[0]).to have_content("Third entry") # 2024-01-15
      expect(entries[1]).to have_content("First entry") # 2024-01-10
      expect(entries[2]).to have_content("Second entry") # 2024-01-05
    end
  end

  describe "amount sorting", :aggregate_failures do
    it "sorts by amount ascending when clicked" do
      click_link "Amount"

      expect(page).to have_current_path(entries_path(sort: "amount", direction: "asc"))

      entries = page.all("tbody tr")
      expect(entries[0]).to have_content("$100.00") # First entry
      expect(entries[1]).to have_content("$200.00") # Second entry
      expect(entries[2]).to have_content("$300.00") # Third entry
    end

    it "toggles to amount descending when clicked again" do
      click_link "Amount" # First click - ascending
      click_link "Amount" # Second click - descending

      expect(page).to have_current_path(entries_path(sort: "amount", direction: "desc"))

      entries = page.all("tbody tr")
      expect(entries[0]).to have_content("$300.00") # Third entry
      expect(entries[1]).to have_content("$200.00") # Second entry
      expect(entries[2]).to have_content("$100.00") # First entry
    end
  end

  describe "sorting with type filtering", :aggregate_failures do
    let!(:income_category) { create(:category, :income, user: user) }
    let!(:income_item) { create(:item, category: income_category) }

    before do
      create(:entry, item: income_item, amount: 1000, date: Date.parse("2024-01-12"))
    end

    it "maintains type filter when sorting" do
      visit entries_path(type: "expenses")
      click_link "Amount"

      expect(page).to have_current_path(entries_path(type: "expenses", sort: "amount", direction: "asc"))

      # Should only show expense entries, not income
      expect(page).to have_content("$100.00")
      expect(page).to have_content("$200.00")
      expect(page).to have_content("$300.00")
      expect(page).not_to have_content("$1,000.00")
    end
  end

  describe "sorting with search", :aggregate_failures do
    it "maintains search when sorting" do
      select "Description", from: "field"
      fill_in "q", with: "entry"
      find("input[name='q']").send_keys(:return)

      click_link "Amount"

      expect(page).to have_current_path(entries_path(field: "description", q: "entry", sort: "amount", direction: "asc"))

      # Should show search results sorted by amount
      entries = page.all("tbody tr")
      expect(entries[0]).to have_content("$100.00")
      expect(entries[1]).to have_content("$200.00")
      expect(entries[2]).to have_content("$300.00")
    end
  end

  describe "sorting with pagination", :aggregate_failures do
    before do
      # Create 20 entries with amount $50 (will be on page 1 when sorted by amount asc)
      20.times { |i| create(:entry, item: item, amount: 50, description: "Low amount #{i}") }

      # Create 1 entry with amount $1000 (should be on page 2 when sorted by amount asc)
      create(:entry, item: item, amount: 1000, description: "High amount entry", date: Date.parse("2024-02-01"))
    end

    it "shows correct entries on page 2 when sorted by amount" do
      click_link "Amount"

      # Page 1 should show the first 20 entries (the $50 entries + some from before block)
      expect(page).to have_content("Showing 1 to 20")
      expect(page).to have_content("$50.00")
      expect(page).not_to have_content("$1,000.00") # High amount should NOT be on page 1

      click_link "Next"

      expect(page).to have_current_path(entries_path(sort: "amount", direction: "asc", page: 2))

      # Page 2 should show the high amount entry
      expect(page).to have_content("High amount entry")
      expect(page).to have_content("$1,000.00")
    end
  end

  describe "sort direction indicators", :aggregate_failures do
    it "shows visual indicators for sort direction" do
      # Check default state (date desc)
      expect(page).to have_css("a[href*='sort=date']")

      click_link "Date"
      # After clicking, should show ascending indicator
      expect(page).to have_css("a[href*='direction=desc']") # Link should now point to desc

      click_link "Amount"
      # Amount should now be the active sort
      expect(page).to have_css("a[href*='sort=amount'][href*='direction=desc']")
    end
  end
end
