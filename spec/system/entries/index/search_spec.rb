# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entries Index - Search", type: :system do
  let(:user) { create(:user) }
  let(:expense_category) { create(:category, :expense, user: user, name: "Food") }
  let(:income_category) { create(:category, :income, user: user, name: "Salary") }
  # `start_date:` EXPLICIT, BEFORE EVERY PLANTED ENTRY (main-account spec §3, fix round 2): the
  # factory default is `1.year.ago`, which on any run day is AFTER these entries' 2023/2024
  # literals — the start-date rule would read every one of them as pre-start and resolve it to
  # the user's main account instead of to the goal, so a search for "Vacation Fund" or
  # "Emergency" found nothing at all.
  let(:vacation_pool) { create(:pool, user: user, name: "Vacation Fund", start_date: Date.parse("2023-01-01")) }
  let(:emergency_pool) { create(:pool, user: user, name: "Emergency Fund", start_date: Date.parse("2023-01-01")) }
  let(:expense_item) { create(:item, category: expense_category, name: "Groceries") }
  let(:income_item) { create(:item, category: income_category, name: "Freelance Work") }

  before do
    sign_in user, scope: :user

    # Categories pointing at the two GOALS. They were savings-typed until plan 3 task 5; the
    # search this file exercises resolves an entry through `ENTRY_POOL_ID`, which does not care
    # what type the category is, so every result below is unchanged.
    vacation_category = create(:category, :expense, user: user, name: "Vacation Savings", pool: vacation_pool)
    emergency_category = create(:category, :expense, user: user, name: "Emergency Savings", pool: emergency_pool)
    vacation_item = create(:item, category: vacation_category, name: "Vacation Contribution")
    emergency_item = create(:item, category: emergency_category, name: "Emergency Contribution")

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

    # Pool entries
    create(:entry, item: vacation_item, amount: 500, description: "Monthly vacation savings", date: Date.parse("2024-01-15"))
    create(:entry, item: vacation_item, amount: 300, description: "Bonus to vacation", date: Date.parse("2024-02-10"))
    create(:entry, item: emergency_item, amount: 1000, description: "Emergency fund deposit", date: Date.parse("2024-01-20"))

    visit entries_path
  end

  describe "search form display", :aggregate_failures do
    it "shows search form with field selector" do
      expect(page).to have_field("q")
      expect(page).to have_select("field")
    end

    it "shows all search field options" do
      expect(page).to have_select("field", options: ["Description", "Date", "Item", "Category", "Pool"])
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

  describe "search by savings pool", :aggregate_failures do
    it "finds all entries in categories belonging to the savings pool" do
      select "Pool", from: "field"
      fill_in "q", with: "Vacation Fund"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("Monthly vacation savings")
      expect(page).to have_content("Bonus to vacation")
      expect(page).not_to have_content("Emergency fund deposit")
      expect(page).not_to have_content("Coffee and pastries")
    end

    it "finds entries by partial savings pool name" do
      select "Pool", from: "field"
      fill_in "q", with: "Emergency"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("Emergency fund deposit")
      expect(page).not_to have_content("Monthly vacation savings")
      expect(page).not_to have_content("Web development project")
    end

    context "with multiple categories in same pool" do
      before do
        another_vacation_category = create(:category, :expense, user: user, name: "Travel Savings", pool: vacation_pool)
        another_vacation_item = create(:item, category: another_vacation_category, name: "Travel Fund")
        create(:entry, item: another_vacation_item, amount: 250, description: "Travel contribution", date: Date.parse("2024-03-15"))

        visit entries_path
        select "Pool", from: "field"
        fill_in "q", with: "Vacation"
        find("input[name='q']").send_keys(:return)
      end

      it "finds all entries from all categories in the pool" do
        expect(page).to have_content("Monthly vacation savings")
        expect(page).to have_content("Bonus to vacation")
        expect(page).to have_content("Travel contribution")
        expect(page).not_to have_content("Emergency fund deposit")
      end
    end

    it "shows no results for non-matching savings pool" do
      select "Pool", from: "field"
      fill_in "q", with: "NonexistentPool"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("No entries found")
    end

    # AN ENTRY MAY NAME ITS OWN POOL, AND THE SEARCH MUST READ THE SAME LANE EVERY BALANCE READS.
    #
    # `PoolBalanceLedger::ENTRY_POOL_ID` is `COALESCE(entries.pool_id, categories.pool_id)` — the
    # entry's override FIRST — and it is what `PoolCalculator`, the ledger and the suggestion
    # engine all resolve an entry through. This search used to walk `item → category → pool`, the
    # second half of that COALESCE with the first half dropped, so an overriding entry was listed
    # under the envelope it had been moved AWAY FROM and was missing from the one holding its money.
    # Nothing in the UI writes `entries.pool_id` yet; the seeds and the factories do.
    #
    # BOTH DIRECTIONS, and both are needed: a search that returned everything would pass the first
    # example, and one that returned nothing would pass the second. The two entries sit on the SAME
    # item, so the only thing separating them is the override.
    context "with an entry that names its own pool" do
      before do
        travel_category = create(:category, :expense, user: user, name: "Travel Savings", pool: vacation_pool)
        travel_item = create(:item, category: travel_category, name: "Travel Fund")
        create(
          :entry,
          item: travel_item,
          amount: 400,
          pool: emergency_pool,
          description: "Rerouted to emergency",
          date: Date.parse("2024-04-02")
        )
        create(
          :entry,
          item: travel_item,
          amount: 250,
          description: "Left where the category points",
          date: Date.parse("2024-04-03")
        )
        visit entries_path
      end

      def search_pool(name)
        select "Pool", from: "field"
        fill_in "q", with: name
        find("input[name='q']").send_keys(:return)
      end

      it "finds it under the pool it named" do
        search_pool("Emergency Fund")

        expect(page).to have_content("Rerouted to emergency")
        expect(page).to have_no_content("Left where the category points")
      end

      it "does not find it under its category's pool" do
        search_pool("Vacation Fund")

        expect(page).to have_content("Left where the category points")
        expect(page).to have_no_content("Rerouted to emergency")
      end
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
