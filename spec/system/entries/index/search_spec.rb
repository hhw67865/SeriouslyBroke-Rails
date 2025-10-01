# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entries Index - Search", type: :system do
  let!(:user) { create(:user) }
  let!(:expense_category) { create(:category, :expense, user: user, name: "Food") }
  let!(:income_category) { create(:category, :income, user: user, name: "Salary") }

  let!(:expense_item) { create(:item, category: expense_category, name: "Groceries") }
  let!(:income_item) { create(:item, category: income_category, name: "Freelance Work") }

  before do
    sign_in user
    # 2024 entries
    create(:entry, item: expense_item, amount: 150, description: "Coffee and pastries", date: Date.parse("2024-01-15"))
    create(:entry, item: expense_item, amount: 75, description: "Gas station", date: Date.parse("2024-01-10"))
    create(:entry, item: income_item, amount: 2000, description: "Web development project", date: Date.parse("2024-01-20"))

    # 2023 entries
    create(:entry, item: expense_item, amount: 100, description: "Holiday shopping", date: Date.parse("2023-12-25"))
    create(:entry, item: income_item, amount: 1500, description: "Freelance work", date: Date.parse("2023-06-15"))

    # 2025 entries
    create(:entry, item: expense_item, amount: 200, description: "New year groceries", date: Date.parse("2025-01-05"))
    create(:entry, item: income_item, amount: 3000, description: "Bonus payment", date: Date.parse("2025-03-10"))

    # Different months in 2024
    create(:entry, item: expense_item, amount: 80, description: "February utilities", date: Date.parse("2024-02-28"))
    create(:entry, item: expense_item, amount: 120, description: "March rent", date: Date.parse("2024-03-01"))

    visit entries_path
  end

  describe "search form display", :aggregate_failures do
    it "shows search form with field selector" do
      expect(page).to have_field("q")
      expect(page).to have_select("field")
    end

    it "shows all search field options" do
      expect(page).to have_select("field", options: ["Description", "Date", "Item", "Category"])
    end
  end

  describe "search by description", :aggregate_failures do
    it "finds entries by description text" do
      select "Description", from: "field"
      fill_in "q", with: "Coffee"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("Coffee and pastries")
      expect(page).not_to have_content("Gas station")
      expect(page).not_to have_content("Web development project")
    end

    it "handles partial matches" do
      select "Description", from: "field"
      fill_in "q", with: "development"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("Web development project")
      expect(page).not_to have_content("Coffee and pastries")
    end

    it "shows no results for non-matching description" do
      select "Description", from: "field"
      fill_in "q", with: "NonexistentDescription"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("No entries found")
    end
  end

  describe "search by date", :aggregate_failures do
    it "finds entries by date" do
      select "Date", from: "field"
      fill_in "q", with: "2024-01-15"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("Coffee and pastries")
      expect(page).not_to have_content("Gas station")
      expect(page).not_to have_content("Web development project")
    end

    it "handles different date formats" do
      select "Date", from: "field"
      fill_in "q", with: "01/20/2024"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("Web development project")
    end

    it "searches by year" do
      select "Date", from: "field"
      fill_in "q", with: "2024"
      find("input[name='q']").send_keys(:return)

      # Should find 2024 entries
      expect(page).to have_content("Coffee and pastries")
      expect(page).to have_content("February utilities")
      expect(page).to have_content("March rent")
      # Should not find entries from other years
      expect(page).not_to have_content("Holiday shopping") # 2023
      expect(page).not_to have_content("Bonus payment") # 2025
    end

    it "searches by year-month format (YYYY-MM)" do
      select "Date", from: "field"
      fill_in "q", with: "2024-01"
      find("input[name='q']").send_keys(:return)

      # Should find only January 2024 entries
      expect(page).to have_content("Coffee and pastries")
      expect(page).to have_content("Gas station")
      expect(page).to have_content("Web development project")

      # Should not find other months or years
      expect(page).not_to have_content("February utilities")
      expect(page).not_to have_content("March rent")
      expect(page).not_to have_content("Holiday shopping")
      expect(page).not_to have_content("New year groceries")
    end

    it "searches by different year" do
      select "Date", from: "field"
      fill_in "q", with: "2023"
      find("input[name='q']").send_keys(:return)

      # Should find all 2023 entries
      expect(page).to have_content("Holiday shopping")
      expect(page).to have_content("Freelance work")

      # Should not find 2024 or 2025 entries
      expect(page).not_to have_content("Coffee and pastries")
      expect(page).not_to have_content("New year groceries")
    end

    it "searches by specific month in different year" do
      select "Date", from: "field"
      fill_in "q", with: "2023-12"
      find("input[name='q']").send_keys(:return)

      # Should find December 2023 entries
      expect(page).to have_content("Holiday shopping")

      # Should not find other entries
      expect(page).not_to have_content("Freelance work") # June 2023
      expect(page).not_to have_content("Coffee and pastries")
    end

    it "searches by single digit month (YYYY-M)" do
      select "Date", from: "field"
      fill_in "q", with: "2024-3"
      find("input[name='q']").send_keys(:return)

      # Should find March 2024 entries
      expect(page).to have_content("March rent")

      # Should not find other months
      expect(page).not_to have_content("February utilities")
      expect(page).not_to have_content("Coffee and pastries")
    end
  end

  describe "search by item", :aggregate_failures do
    it "finds entries by item name" do
      select "Item", from: "field"
      fill_in "q", with: "Groceries"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("Coffee and pastries")
      expect(page).to have_content("Gas station")
      expect(page).not_to have_content("Web development project")
    end

    it "finds entries by partial item name" do
      select "Item", from: "field"
      fill_in "q", with: "Freelance"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("Web development project")
      expect(page).not_to have_content("Coffee and pastries")
    end
  end

  describe "search by category", :aggregate_failures do
    it "finds entries by category name" do
      select "Category", from: "field"
      fill_in "q", with: "Food"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("Coffee and pastries")
      expect(page).to have_content("Gas station")
      expect(page).not_to have_content("Web development project")
    end

    it "finds entries by partial category name" do
      select "Category", from: "field"
      fill_in "q", with: "Sal"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("Web development project")
      expect(page).not_to have_content("Coffee and pastries")
    end
  end

  describe "search results and navigation", :aggregate_failures do
    it "shows search results information" do
      select "Description", from: "field"
      fill_in "q", with: "Coffee"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("Found 1 result for \"Coffee\" in Description")
    end

    it "provides clear search functionality" do
      select "Description", from: "field"
      fill_in "q", with: "Coffee"
      find("input[name='q']").send_keys(:return)

      click_link "Clear search"

      expect(page).to have_current_path(entries_path)
      expect(page).to have_content("Coffee and pastries")
      expect(page).to have_content("Gas station")
      expect(page).to have_content("Web development project")
    end
  end

  describe "search with type filtering", :aggregate_failures do
    it "searches within selected type only" do
      visit entries_path(type: "expenses")

      select "Description", from: "field"
      fill_in "q", with: "Coffee"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("Coffee and pastries")
      expect(page).not_to have_content("Web development project") # Income entry excluded
    end

    it "maintains type filter when clearing search" do
      visit entries_path(type: "expenses")

      select "Description", from: "field"
      fill_in "q", with: "Coffee"
      find("input[name='q']").send_keys(:return)

      click_link "Clear search"

      expect(page).to have_current_path(entries_path(type: "expenses"))
      expect(page).to have_content("Coffee and pastries")
      expect(page).to have_content("Gas station")
      expect(page).not_to have_content("Web development project") # Still filtered by type
    end
  end

  describe "search with pagination", :aggregate_failures do
    before do
      # Create many entries with "Coffee" in description
      create_list(:entry, 25, item: expense_item, description: "Coffee purchase")
    end

    it "paginates search results correctly" do
      select "Description", from: "field"
      fill_in "q", with: "Coffee"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("Showing 1 to 20 of 26 entries") # 25 + 1 from before block

      click_link "Next"
      expect(page).to have_content("Showing 21 to 26 of 26 entries")
    end
  end
end
