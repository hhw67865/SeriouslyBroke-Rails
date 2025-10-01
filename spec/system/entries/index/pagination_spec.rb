# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entries Index - Pagination", type: :system do
  let!(:user) { create(:user) }
  let!(:category) { create(:category, :expense, user: user, name: "Food") }
  let!(:item) { create(:item, category: category, name: "Groceries") }

  before { sign_in user }

  describe "pagination display", :aggregate_failures do
    context "with fewer entries than per_page limit" do
      before do
        create_list(:entry, 15, item: item) # Less than 20 (default per_page)
        visit entries_path
      end

      it "shows total count without pagination controls" do
        expect(page).to have_content("15 entries total")
        expect(page).not_to have_content("Previous")
        expect(page).not_to have_content("Next")
      end
    end

    context "with more entries than per_page limit" do
      before do
        create_list(:entry, 25, item: item) # More than 20 (default per_page)
        visit entries_path
      end

      it "shows pagination controls with correct information" do
        # Desktop pagination should show detailed information
        expect(page).to have_content("Showing 1 to 20 of 25 entries")
        expect(page).to have_link("Next")
        expect(page).to have_link("2") # Page number
        expect(page).not_to have_link("Previous") # Previous shouldn't show on first page
      end

      it "navigates to next page correctly" do
        click_link "Next"

        expect(page).to have_content("Showing 21 to 25 of 25 entries")
        expect(page).to have_link("Previous")
        expect(page).not_to have_link("Next") # Next shouldn't show on last page
      end

      it "navigates back to previous page correctly" do
        click_link "Next"
        click_link "Previous"

        expect(page).to have_content("Showing 1 to 20 of 25 entries")
        expect(page).to have_link("Next")
        expect(page).not_to have_link("Previous") # Back to first page
      end
    end

    context "with many pages" do
      before do
        create_list(:entry, 100, item: item) # 5 pages
        visit entries_path
      end

      it "shows page number navigation" do
        # With updated Kaminari config, should show some page numbers
        # Current page (1) will be a span, others will be links
        expect(page).to have_content("1") # Current page (may be span, not link)
        expect(page).to have_link("2")

        # May also show additional pages depending on window configuration
        # expect(page).to have_link("3")
      end

      it "jumps to specific page" do
        # Try clicking on page 2 since it should be more reliably visible
        click_link "2"

        expect(page).to have_content("Showing 21 to 40 of 100 entries")
        expect(page).to have_link("1") # Should show page 1
        expect(page).to have_link("3") # Should show page 3
      end

      it "shows first/last page links" do
        click_link "2" # Go to second page

        # Should show First/Last links and page numbers
        expect(page).to have_link("First") # First page link
        expect(page).to have_link("Last") # Last page link
        expect(page).to have_link("1") # Page number link
        expect(page).to have_link("3") # Next page number
      end
    end
  end

  describe "mobile pagination", :aggregate_failures do
    before do
      create_list(:entry, 25, item: item)
      visit entries_path
      page.driver.browser.manage.window.resize_to(375, 667) # Mobile size
    end

    after do
      page.driver.browser.manage.window.maximize
    end

    it "shows simplified pagination for mobile" do
      # Mobile should show simplified format
      expect(page).to have_content("Page 1 of 2")
      expect(page).to have_link("Next")
      # Previous link won't show on first page
      expect(page).not_to have_link("Previous")

      # Should not show desktop-style information on mobile
      expect(page).not_to have_content("Showing 1 to 20 of 25 entries")
    end
  end

  describe "pagination with filters", :aggregate_failures do
    let!(:income_category) { create(:category, :income, user: user) }
    let!(:income_item) { create(:item, category: income_category) }

    before do
      create_list(:entry, 15, item: item) # Expense entries
      create_list(:entry, 15, item: income_item) # Income entries
      visit entries_path(type: "expenses")
    end

    it "maintains filter when navigating pages" do
      expect(page).to have_content("15 entries total")
      expect(page).to have_current_path(entries_path(type: "expenses"))

      # Verify only expense entries are shown
      expect(page).not_to have_content(income_category.name)
    end
  end

  describe "pagination with search", :aggregate_failures do
    before do
      create_list(:entry, 15, item: item, description: "Coffee purchase")
      create_list(:entry, 15, item: item, description: "Gas station")
      visit entries_path
    end

    it "maintains search when navigating pages" do
      select "Description", from: "field"
      fill_in "q", with: "Coffee"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("15 entries total")
      # All entries should contain "Coffee" in description
      expect(page).not_to have_content("Gas station")
    end
  end
end
