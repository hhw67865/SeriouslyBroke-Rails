# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Calendar Index - Header", type: :system do
  let!(:user) { create(:user) }

  before do
    sign_in user, scope: :user
    visit calendar_path
  end

  describe "page header elements", :aggregate_failures do
    it "shows current month and year" do
      expect(page).to have_content(Date.current.strftime("%B %Y"))
    end

    # Two types in the legend: it is `CategoryTypeHelper::CATEGORY_TYPES`, and there is no third.
    it "displays legend with all entry types", :aggregate_failures do
      within(".calendar-legend") do
        expect(page).to have_content("Expense")
        expect(page).to have_content("Income")
        expect(page).to have_no_content("Savings")
      end
    end
  end

  describe "legend color indicators", :aggregate_failures do
    it "shows colored swatches for each type" do
      expect(page).to have_css(".calendar-legend__swatch.bg-status-danger")
      expect(page).to have_css(".calendar-legend__swatch.bg-status-success")
      expect(page).to have_no_css(".calendar-legend__swatch.bg-brand-dark")
    end
  end
end
