# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Show - Budget (Expense)", type: :system do
  let!(:user) { create(:user) }

  before { sign_in user, scope: :user }

  context "with existing budget", :aggregate_failures do
    let!(:category) { create(:category, category_type: "expense", user: user, name: "Food") }
    let!(:budget) { create(:budget, category: category, amount: 500) }

    it "shows budget card and Update Budget navigates to edit" do
      visit category_path(category)

      expect(page).to have_content("Budget Management")
      expect(page).to have_content("Budget Amount")
      expect(page).to have_content(ActionController::Base.helpers.number_to_currency(500))

      click_link "Update Budget"
      expect(page).to have_current_path(edit_budget_path(budget))
    end
  end

  context "without existing budget", :aggregate_failures do
    let!(:category) { create(:category, category_type: "expense", user: user, name: "Transport") }

    it "shows create budget call to action and navigates to new budget" do
      visit category_path(category)
      expect(page).to have_content("No budget set")
      click_link "Create Budget"
      expect(page).to have_current_path(new_budget_path(category_id: category.id))
    end
  end

  context "with yearly budget", :aggregate_failures do
    let!(:category) { create(:category, category_type: "expense", user: user, name: "Insurance") }

    before do
      create(:budget, :yearly, category: category, amount: 2025)
      visit category_path(category)
    end

    it "shows monthly conversion text in summary card" do
      # $2,025/year = $168.75/month
      expect(page).to have_content("$168.75/mo from $2,025.00/yr")
    end

    it "shows Year period in budget management card" do
      expect(page).to have_content("Period")
      expect(page).to have_content("Year")
    end
  end

  context "with monthly budget", :aggregate_failures do
    let!(:category) { create(:category, category_type: "expense", user: user, name: "Groceries") }

    before do
      create(:budget, :monthly, category: category, amount: 500)
      visit category_path(category)
    end

    it "does not show monthly conversion text" do
      expect(page).not_to have_content("/mo from")
      expect(page).not_to have_content("/yr")
    end

    it "shows Month period in budget management card" do
      expect(page).to have_content("Period")
      expect(page).to have_content("Month")
    end
  end
end
