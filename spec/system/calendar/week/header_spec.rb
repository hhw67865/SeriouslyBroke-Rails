# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Calendar Week - Header", type: :system do
  let!(:user) { create(:user) }
  let(:test_date) { Date.current }

  before do
    sign_in user, scope: :user
    visit calendar_week_path(date: test_date.strftime("%Y-%m-%d"))
  end

  describe "page header elements", :aggregate_failures do
    it "shows week date range" do
      week_start = test_date - test_date.wday
      expect(page).to have_content("Week of")
      expect(page).to have_content(week_start.strftime("%b %-d"))
    end

    it "shows back to monthly button" do
      expect(page).to have_link("Monthly")
    end

    it "shows create entry button" do
      expect(page).to have_link("Create Entry", href: new_entry_path)
    end
  end

  describe "back to monthly navigation", :aggregate_failures do
    it "returns to monthly calendar view" do
      click_link "Monthly"

      # Navigation goes to /calendar with optional month/year params
      expect(page).to have_current_path(/\/calendar/)
      expect(page).to have_content(test_date.strftime("%B %Y"))
    end
  end

  describe "create entry navigation", :aggregate_failures do
    it "navigates to new entry form" do
      click_link "Create Entry"

      expect(page).to have_current_path(new_entry_path)
    end
  end
end
