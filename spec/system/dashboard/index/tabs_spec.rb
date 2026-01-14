# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Index - Tabs", type: :system do
  let!(:user) { create(:user) }

  before do
    sign_in user, scope: :user
    visit root_path
  end

  describe "tab display", :aggregate_failures do
    it "shows all three tabs" do
      expect(page).to have_link("Expenses")
      expect(page).to have_link("Income")
      expect(page).to have_link("Savings")
    end

    it "defaults to Expenses tab" do
      expenses_link = find("nav[aria-label='Tabs'] a", text: "Expenses")
      expect(expenses_link[:class]).to include("border-brand")
    end
  end

  describe "tab navigation", :aggregate_failures do
    it "navigates to Income tab" do
      click_link "Income"

      expect(page).to have_current_path(root_path(tab: "income"))
      income_link = find("nav[aria-label='Tabs'] a", text: "Income")
      expect(income_link[:class]).to include("border-brand")
    end

    it "navigates to Savings tab" do
      click_link "Savings"

      expect(page).to have_current_path(root_path(tab: "savings"))
      savings_link = find("nav[aria-label='Tabs'] a", text: "Savings")
      expect(savings_link[:class]).to include("border-brand")
    end

    it "navigates back to Expenses tab" do
      click_link "Income"
      click_link "Expenses"

      expect(page).to have_current_path(root_path(tab: "expenses"))
    end
  end
end
