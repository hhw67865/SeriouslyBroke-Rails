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

  describe "prorated flag persistence", :aggregate_failures do
    let!(:groceries) { create(:category, category_type: "expense", user: user, name: "Prorated Groceries") }

    it "creates a prorated budget when the checkbox is checked" do
      visit new_budget_path(category_id: groceries.id)
      fill_in "Amount", with: "300.00"
      check "Prorate daily"
      click_button "Create Budget"

      expect(page).to have_current_path(category_path(groceries))
      expect(groceries.reload.budget.prorated).to be(true)
    end

    it "creates a non-prorated budget when the checkbox is left unchecked" do
      visit new_budget_path(category_id: groceries.id)
      fill_in "Amount", with: "300.00"
      click_button "Create Budget"

      expect(groceries.reload.budget.prorated).to be(false)
    end
  end
end
