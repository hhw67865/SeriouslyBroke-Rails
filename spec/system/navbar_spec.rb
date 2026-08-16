# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Navbar", type: :system do
  let!(:user) { create(:user) }

  before do
    sign_in user, scope: :user
    visit authenticated_root_path
  end

  describe "main navigation", :aggregate_failures do
    it "shows all main navigation links" do
      # Check for navigation links anywhere on the page (sidebar or mobile nav)
      expect(page).to have_link("Home")
      expect(page).to have_link("Categories")
      expect(page).to have_link("Entries")
      expect(page).to have_link("Pools").or have_link("Savings")
      expect(page).to have_link("Reports")
      expect(page).to have_link("Calendar")
    end

    it "navigates to main sections correctly", :aggregate_failures do
      click_link "Categories"
      expect(page).to have_current_path(categories_path)

      click_link "Home"
      expect(page).to have_current_path(authenticated_root_path)
    end
  end

  describe "active navigation state" do
    it "highlights current section", :aggregate_failures do
      visit categories_path

      # Check for active navigation link with the specific styling classes
      expect(page).to have_css("a.bg-white").or have_css("a[class*='bg-white']")
    end
  end

  describe "month selector", :aggregate_failures do
    let(:current_date) { Date.current }
    let(:next_month_date) { current_date.next_month }
    let(:prev_month_date) { current_date.prev_month }

    it "displays current month and year by default" do
      # Check for month display in sidebar (desktop) and mobile header
      expect(page).to have_content(current_date.strftime("%B %Y")).or have_content(current_date.strftime("%b %Y"))
    end

    it "has functional previous and next month buttons" do
      # Test next month navigation
      expect(page).to have_css("button[title='Next month']")
      expect(page).to have_css("button[title='Previous month']")

      find("button[title='Next month']").click
      expect(page).to have_content(next_month_date.strftime("%B %Y")).or have_content(next_month_date.strftime("%b %Y"))

      # Test previous month navigation
      find("button[title='Previous month']").click
      expect(page).to have_content(current_date.strftime("%B %Y")).or have_content(current_date.strftime("%b %Y"))
    end

    it "persists selected month when navigating between pages" do
      # Navigate to next month
      find("button[title='Next month']").click
      expect(page).to have_content(next_month_date.strftime("%B %Y")).or have_content(next_month_date.strftime("%b %Y"))

      # Navigate to different page
      click_link "Categories"
      expect(page).to have_current_path(categories_path)

      # Month selection should persist
      expect(page).to have_content(next_month_date.strftime("%B %Y")).or have_content(next_month_date.strftime("%b %Y"))

      # Navigate to another page
      click_link "Home"
      expect(page).to have_current_path(authenticated_root_path)

      # Month selection should still persist
      expect(page).to have_content(next_month_date.strftime("%B %Y")).or have_content(next_month_date.strftime("%b %Y"))
    end

    it "resets to current month for new user sessions" do
      # Navigate to a different month
      find("button[title='Next month']").click
      expect(page).to have_content(next_month_date.strftime("%B %Y")).or have_content(next_month_date.strftime("%b %Y"))

      # Sign out and back in (simulating new session)
      click_button "Sign out"
      sleep 0.5

      sign_in user, scope: :user
      visit authenticated_root_path

      # Should show current month again for new session
      expect(page).to have_content(current_date.strftime("%B %Y")).or have_content(current_date.strftime("%b %Y"))
    end

    # INVALID HTML, AND A SILENT TRAP FOR EVERY OTHER SCREEN. This partial renders FOUR forms on
    # every page — two here, twice over, because _sidebar renders both the `sidebar` and the
    # `mobile` variant — and each one emits a hidden field per preserved query parameter plus
    # `month` and `year`. Written with ids, `month`, `year` and every scalar param appeared four
    # times over as ids on every page in the app.
    #
    # `label for=` and `document.getElementById` both resolve to the FIRST match in a document, so
    # any screen naming a form field after its own query parameter got one of these hidden inputs
    # rather than the box the user types in. Measured on the reallocation screen:
    # `getElementById("amount")` returned `<input type="hidden" name="amount" value="300">`.
    #
    # Both directions, because dropping the ids must not drop the FIELDS: the parameter is still
    # carried across a month arrow, which is the whole reason these hidden inputs exist.
    it "carries query parameters across a month change without duplicating a DOM id" do
      visit categories_path(q: "Rent", field: "name")

      expect(duplicate_dom_ids).to be_empty
      expect(page).to have_css("form input[type=hidden][name=q]", visible: :all)
      find("button[title='Next month']").click
      expect(page).to have_current_path(/q=Rent/)
    end
  end
end
