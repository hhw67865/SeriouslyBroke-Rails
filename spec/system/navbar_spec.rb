# frozen_string_literal: true

require "rails_helper"

# The sidebar: six sections, the user's own profile block and the way out. Everything is scoped to
# the sidebar panel, because the mobile header carries a second copy of the date selector.
RSpec.describe "Navbar", type: :system do
  let!(:user) { create(:user, name: "Ada Lovelace") }

  before do
    sign_in user, scope: :user
    visit authenticated_root_path
  end

  describe "main navigation", :aggregate_failures do
    let(:sidebar_links) do
      {
        "Home" => root_path,
        "Entries" => entries_path,
        "Calendar" => calendar_path,
        "Budget" => budget_page_path,
        "Savings" => savings_path,
        "Activity" => activity_path,
        "Reports" => reports_path,
        "Categories" => categories_path,
        "Settings" => settings_path
      }
    end

    it "links to every section of the app, in four groups" do
      within_sidebar do
        sidebar_links.each { |name, path| expect(page).to have_link(name, href: path) }
        expect(all("nav h3, nav [data-nav-title]").map(&:text)).to eq(["Today", "Plan", "Look back", "Set up"])
        expect(all("nav a").map { |link| link.text.strip }.reject(&:empty?)).to eq(sidebar_links.keys)
      end
    end

    # The other direction: the screens this app used to have are gone from the sidebar, not merely
    # renamed somewhere off it.
    it "names no screen this app no longer has" do
      within_sidebar do
        expect(page).to have_no_link("Dashboard")
        expect(page).to have_no_link("Accounts")
        expect(page).to have_no_link("Statistics")
      end
    end

    it "navigates to a section and back", :aggregate_failures do
      within_sidebar { click_link "Categories" }
      expect(page).to have_current_path(categories_path)

      within_sidebar { click_link "Home" }
      expect(page).to have_current_path(root_path)
    end
  end

  describe "the active section", :aggregate_failures do
    before { visit categories_path }

    it "marks the section the page belongs to, and only that one" do
      within_sidebar do
        expect(page).to have_css("a.bg-white", text: "Categories")
        expect(page).to have_no_css("a.bg-white", text: "Entries")
      end
    end
  end

  describe "the user profile", :aggregate_failures do
    it "names the user and opens Settings" do
      within_sidebar { expect(page).to have_link(user.name, href: settings_path) }

      within_sidebar { click_link user.name }

      expect(page).to have_current_path(settings_path)
    end
  end

  describe "signing out", :aggregate_failures do
    it "returns to the landing page with the app closed behind it" do
      within_sidebar { click_button "Sign out" }

      expect(page).to have_current_path(root_path)
      expect(page).to have_link("Log In")
      expect(page).to have_no_link("Budget")
    end
  end

  describe "month selector", :aggregate_failures do
    let(:current_date) { Date.current }
    let(:next_month_date) { current_date.next_month }

    it "displays the current month and year by default" do
      within_sidebar { expect(page).to have_content(current_date.strftime("%B %Y")) }
    end

    it "steps forward and back a month" do
      next_month
      within_sidebar { expect(page).to have_content(next_month_date.strftime("%B %Y")) }

      within_sidebar { find("button[title='Previous month']").click }
      within_sidebar { expect(page).to have_content(current_date.strftime("%B %Y")) }
    end

    it "keeps the selected month while moving between pages" do
      next_month

      within_sidebar { click_link "Categories" }
      expect(page).to have_current_path(categories_path)
      within_sidebar { expect(page).to have_content(next_month_date.strftime("%B %Y")) }

      within_sidebar { click_link "Home" }
      expect(page).to have_current_path(root_path)
      within_sidebar { expect(page).to have_content(next_month_date.strftime("%B %Y")) }
    end

    it "opens on the current month again in a new session" do
      next_month
      within_sidebar { click_button "Sign out" }
      expect(page).to have_link("Log In")

      sign_in user, scope: :user
      visit authenticated_root_path

      within_sidebar { expect(page).to have_content(current_date.strftime("%B %Y")) }
    end
  end

  private

  def within_sidebar(&) = within("[data-shared--sidebar-target='panel']", &)

  def next_month
    within_sidebar { find("button[title='Next month']").click }
  end
end
