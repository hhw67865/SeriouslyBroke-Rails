# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Navbar", type: :system do
  let!(:user) { create(:user) }

  before do
    sign_in user
    visit authenticated_root_path
  end

  describe "main navigation", :aggregate_failures do
    it "shows all main navigation links" do
      # Check for navigation links anywhere on the page (sidebar or mobile nav)
      expect(page).to have_link("Dashboard")
      expect(page).to have_link("Categories")
      expect(page).to have_link("Entries")
      expect(page).to have_link("Savings Pools").or have_link("Savings")
      expect(page).to have_link("Statistics")
      expect(page).to have_link("Calendar")
    end

    it "navigates to main sections correctly", :aggregate_failures do
      click_link "Categories"
      expect(page).to have_current_path(categories_path)
      
      click_link "Dashboard"
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
      click_link "Dashboard"
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
      
      sign_in user
      visit authenticated_root_path
      
      # Should show current month again for new session
      expect(page).to have_content(current_date.strftime("%B %Y")).or have_content(current_date.strftime("%b %Y"))
    end

  end
end
