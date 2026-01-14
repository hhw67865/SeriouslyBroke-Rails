# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Index - Period Toggle", type: :system do
  let!(:user) { create(:user) }

  before do
    sign_in user, scope: :user
    visit root_path
  end

  describe "toggle display", :aggregate_failures do
    it "shows Monthly and Year to Date options" do
      expect(page).to have_link("Monthly")
      expect(page).to have_link("Year to Date")
    end

    it "Monthly is active by default with correct styling" do
      monthly_link = find("a", text: "Monthly")
      ytd_link = find("a", text: "Year to Date")

      expect(monthly_link[:class]).to include("bg-brand")
      expect(monthly_link[:class]).to include("text-white")
      expect(ytd_link[:class]).not_to include("bg-brand")
    end
  end

  describe "toggle navigation", :aggregate_failures do
    it "clicking Year to Date adds period=ytd to URL" do
      click_link "Year to Date"

      expect(page).to have_current_path(root_path(tab: "expenses", period: "ytd"))
    end

    it "clicking Monthly removes period param" do
      visit root_path(tab: "expenses", period: "ytd")
      click_link "Monthly"

      expect(page).to have_current_path(root_path(tab: "expenses"))
    end

    it "Year to Date toggle becomes active after clicking" do
      click_link "Year to Date"

      expect(page).to have_css("a.bg-brand", text: "Year to Date")
      expect(page).not_to have_css("a.bg-brand", text: "Monthly")
    end
  end

  describe "period resets when switching tabs", :aggregate_failures do
    it "resets to Monthly when switching to Income tab" do
      click_link "Year to Date"
      within("nav[aria-label='Tabs']") { click_link "Income" }

      expect(page).to have_current_path(root_path(tab: "income"))
      expect(page).to have_css("a.bg-brand", text: "Monthly")
    end

    it "resets to Monthly when switching to Savings tab" do
      click_link "Year to Date"
      within("nav[aria-label='Tabs']") { click_link "Savings" }

      expect(page).to have_current_path(root_path(tab: "savings"))
      expect(page).to have_css("a.bg-brand", text: "Monthly")
    end
  end
end
