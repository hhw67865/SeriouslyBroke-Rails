# frozen_string_literal: true

require "rails_helper"

# ** DISTRIBUTE IS OUT OF THIS FILE (computed-claims spec §§5-6). ** Two assertions went, both in
# "main navigation": `have_link("Distribute")` in the link sweep, and the `"Distribute"` entry
# second in the literal order list below. Both pinned a sidebar item pointing at
# `/distributions/new`, and that route, its controller, its presenter and its views are deleted —
# a category's money is a CLAIM computed from its rules, so there is no paycheck to split. The
# ABSENCE is now pinned instead, beside "Pools", and for the same reason it is pinned at all: a
# deletion nothing asserts is a link that comes back on the next edit to `shared/_sidebar` with
# no example objecting. The surviving nav behaviour is the order list, which is now §2's table
# exactly — Home · Budget · Entries · Categories · Calendar · Reports.
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
      expect(page).to have_link("Budget")
      expect(page).to have_link("Entries")
      expect(page).to have_link("Categories")
      expect(page).to have_link("Calendar")
      expect(page).to have_link("Reports")
      # THE "Pools" ITEM IS GONE (two-ledger spec §5, Task 7), and its ABSENCE is asserted rather
      # than merely unmentioned. The line it replaces was `have_link("Pools").or
      # have_link("Savings")` — an `or` that would have gone on passing under either name — and a
      # deletion nothing pins is a link that comes back on the next edit to `shared/_sidebar`
      # without a single example objecting. A savings goal is a CATEGORY now, so Categories above
      # is where that screen went.
      expect(page).to have_no_link("Pools")
      # AND "Distribute" IS GONE THE SAME WAY (computed-claims §§5-6), asserted for the same
      # reason: `/distributions/new` is deleted, claims are computed, and nothing may quietly
      # link at a route that no longer exists.
      expect(page).to have_no_link("Distribute")
    end

    # SPEC §2'S ORDER, END TO END — Home · Budget · Entries · Categories · Calendar · Reports,
    # with Reports LAST because that is what the demotion means: the charts answer *what
    # happened*, a question you visit deliberately, so nothing may sit below them and read as more
    # incidental than they are.
    #
    # A LITERAL LIST, so neither side is derived from the other — the same shape as
    # budget_page/rules_spec's `first(4)`, which asserts Budget's position inside the Main section
    # and stays green under this. `Pools` used to sit between Categories and Calendar and was in
    # this list because it was on the screen; it is deleted with the layer (Task 8's sweep).
    # `Distribute` sat second, ahead of Budget, and is deleted with the distribution screen
    # (computed-claims §§5-6) — so the list is now exactly §2's own, and the Management section
    # carries one link.
    it "puts the sections in spec §2's order, Reports last" do
      expect(page.all("nav a").map { |link| link.text.strip })
        .to eq(["Home", "Budget", "Entries", "Categories", "Calendar", "Reports"])
    end

    # THE NEGATIVE HALF OF THE ORDER, and it is not redundant with the list above: the list would
    # also pass if `nav a` silently stopped matching the Analysis section altogether. This says the
    # two Analysis items are both there AND which way round.
    it "puts Calendar above Reports rather than below it", :aggregate_failures do
      names = page.all("nav a").map { |link| link.text.strip }

      expect(names.index("Calendar")).to be < names.index("Reports")
      expect(names.last).to eq("Reports")
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
