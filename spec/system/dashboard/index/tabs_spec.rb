# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Index - Tabs", type: :system do
  let!(:user) { create(:user) }

  before do
    sign_in user, scope: :user
    visit reports_path
  end

  # Three tabs, in both directions: the three that remain are links, and the one that went is
  # absent.
  describe "tab display", :aggregate_failures do
    it "shows all three tabs" do
      within("nav[aria-label='Tabs']") do
        expect(page).to have_link("All")
        expect(page).to have_link("Expenses")
        expect(page).to have_link("Income")
        expect(page).to have_no_link("Savings")
      end
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

    # A stale `?tab=savings` bookmark lands on All rather than on an empty panel: index.html.erb
    # renders in a `case` with no `else`.
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
