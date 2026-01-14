# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Calendar Week - Navigation", type: :system do
  let!(:user) { create(:user) }
  let(:test_date) { Date.new(2024, 6, 15) } # Mid-month Saturday

  before do
    sign_in user, scope: :user
    visit calendar_week_path(date: test_date.strftime("%Y-%m-%d"))
  end

  describe "week navigation buttons", :aggregate_failures do
    it "shows previous and next week buttons" do
      expect(page).to have_css("a[href*='calendar/week']", minimum: 2)
    end
  end

  describe "previous week navigation", :aggregate_failures do
    it "navigates to previous week" do
      prev_week_date = test_date - 7

      find("a[href*='#{prev_week_date.strftime("%Y-%m-%d")}']").click

      expect(page).to have_current_path(
        calendar_week_path(date: prev_week_date.strftime("%Y-%m-%d"))
      )
    end
  end

  describe "next week navigation", :aggregate_failures do
    it "navigates to next week" do
      next_week_date = test_date + 7

      find("a[href*='#{next_week_date.strftime("%Y-%m-%d")}']").click

      expect(page).to have_current_path(
        calendar_week_path(date: next_week_date.strftime("%Y-%m-%d"))
      )
    end
  end

  describe "day columns display", :aggregate_failures do
    it "shows all seven days of the week" do
      week_start = test_date - test_date.wday

      (0..6).each do |offset|
        day = week_start + offset
        expect(page).to have_content(day.strftime("%a"))
        expect(page).to have_content(day.strftime("%-m/%-d"))
      end
    end
  end
end
