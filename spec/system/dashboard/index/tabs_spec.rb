# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Index - Tabs", type: :system do
  let!(:user) { create(:user) }

  before do
    sign_in user, scope: :user
    visit reports_path
  end

  # THREE TABS, NOT FOUR (plan 3, task 5) — the Savings tab is deleted with the category type its
  # every figure summed. Asserted in both directions: the three that remain are links, and the one
  # that went is absent.
  describe "tab display", :aggregate_failures do
    it "shows all three tabs" do
      expect(page).to have_link("All")
      expect(page).to have_link("Expenses")
      expect(page).to have_link("Income")
      expect(page).to have_no_link("Savings")
    end

    it "defaults to All tab" do
      all_link = find("nav[aria-label='Tabs'] a", text: "All")
      expect(all_link[:class]).to include("border-brand")
    end
  end

  describe "tab navigation", :aggregate_failures do
    it "navigates to Income tab" do
      click_link "Income"

      expect(page).to have_current_path(reports_path(tab: "income"))
      income_link = find("nav[aria-label='Tabs'] a", text: "Income")
      expect(income_link[:class]).to include("border-brand")
    end

    # A STALE `?tab=savings` BOOKMARK LANDS ON ALL rather than on an empty panel. `index.html.erb`
    # renders in a `case` with no `else`, so an unrecognised tab used to print the tab strip and the
    # period toggle over nothing at all — a page that looks broken. DashboardController checks the
    # parameter against its own list instead.
    it "sends a stale ?tab=savings bookmark to the All tab", :aggregate_failures do
      visit reports_path(tab: "savings")

      expect(find("nav[aria-label='Tabs'] a", text: "All")[:class]).to include("border-brand")
      expect(page).to have_content("Money Flow")
    end

    it "navigates back to Expenses tab" do
      click_link "Income"
      click_link "Expenses"

      expect(page).to have_current_path(reports_path(tab: "expenses"))
    end
  end
end
