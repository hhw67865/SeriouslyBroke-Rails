# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Show - Period Toggle", type: :system do
  let!(:user) { create(:user) }
  let!(:category) { create(:category, category_type: "expense", user: user, name: "Food") }

  before { sign_in user, scope: :user }

  describe "toggle display", :aggregate_failures do
    before { visit category_path(category) }

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
      visit category_path(category)
      click_link "Year to Date"

      expect(page).to have_current_path(category_path(category, period: "ytd"))
    end

    it "clicking Monthly removes period param" do
      visit category_path(category, period: "ytd")
      click_link "Monthly"

      expect(page).to have_current_path(category_path(category))
    end

    it "Year to Date toggle becomes active after clicking" do
      visit category_path(category)
      click_link "Year to Date"

      # Wait for page to load and verify styling
      expect(page).to have_current_path(category_path(category, period: "ytd"))
      expect(page).to have_css("a.bg-brand", text: "Year to Date")
      expect(page).not_to have_css("a.bg-brand", text: "Monthly")
    end
  end
end
