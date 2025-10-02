# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Budgets Forms", type: :system do
  let(:user) { create(:user) }
  let!(:expense_category) { create(:category, user: user, name: "Groceries", category_type: :expense) }

  before { sign_in user }

  describe "New Budget Form - From Category Page", :aggregate_failures do
    before { visit new_budget_path(category_id: expense_category.id) }

    it "shows all form elements" do
      expect(page).to have_content("New Budget")
      expect(page).to have_content("Set spending limits for Groceries")
      expect(page).to have_field("Amount")
      expect(page).to have_select("Period")
      expect(page).to have_button("Create Budget")
      expect(page).to have_link("Cancel")
    end

    it "does not show category select" do
      expect(page).not_to have_select("Category")
      expect(page).to have_content("Groceries")
    end

    it "shows available period options" do
      expect(page).to have_select("Period", options: ["", "Month", "Year"])
    end

    it "creates budget and redirects to category page" do
      fill_in "Amount", with: "500.00"
      select "Month", from: "Period"
      click_button "Create Budget"

      expect(page).to have_current_path(category_path(expense_category))
      expect(page).to have_content("Budget was successfully created")
      expect(Budget.count).to eq(1)
      expect(Budget.last.amount).to eq(500.00)
      expect(Budget.last.period).to eq("month")
      expect(Budget.last.category).to eq(expense_category)
    end

    it "shows error for missing amount" do
      select "Month", from: "Period"
      click_button "Create Budget"

      expect(current_path).to eq(new_budget_path)
      expect(page).to have_content("can't be blank")
    end

    it "shows error for missing period" do
      fill_in "Amount", with: "500.00"
      click_button "Create Budget"

      expect(current_path).to eq(new_budget_path)
      expect(page).to have_content("can't be blank")
    end

    it "returns to category page when clicking cancel" do
      click_link "Cancel"
      expect(page).to have_current_path(category_path(expense_category))
    end
  end

  describe "New Budget Form - Standalone", :aggregate_failures do
    before { visit new_budget_path }

    it "shows category select" do
      expect(page).to have_content("New Budget")
      expect(page).to have_select("Category")
      expect(page).to have_field("Amount")
      expect(page).to have_select("Period")
    end

    it "shows only expense categories" do
      create(:category, user: user, name: "Salary", category_type: :income)
      visit new_budget_path

      within "#budget_category_id" do
        expect(page).to have_content("Groceries")
        expect(page).not_to have_content("Salary")
      end
    end

    it "shows only user's categories" do
      other_user = create(:user)
      create(:category, user: other_user, name: "Other User Category", category_type: :expense)
      visit new_budget_path

      within "#budget_category_id" do
        expect(page).to have_content("Groceries")
        expect(page).not_to have_content("Other User Category")
      end
    end

    it "creates budget and redirects to category page" do
      select "Groceries", from: "Category"
      fill_in "Amount", with: "750.00"
      select "Year", from: "Period"
      click_button "Create Budget"

      expect(page).to have_current_path(category_path(expense_category))
      expect(page).to have_content("Budget was successfully created")
      expect(Budget.count).to eq(1)
    end

    it "shows error for missing category" do
      fill_in "Amount", with: "500.00"
      select "Month", from: "Period"
      click_button "Create Budget"

      expect(current_path).to eq(new_budget_path)
      expect(page).to have_content("must exist")
    end
  end

  describe "Edit Budget Form", :aggregate_failures do
    let!(:budget) do
      create(
        :budget,
        category: expense_category,
        amount: 500.00,
        period: :month
      )
    end

    before { visit edit_budget_path(budget) }

    it "shows all form elements" do
      expect(page).to have_content("Edit Budget")
      expect(page).to have_content("Set spending limits for Groceries")
      expect(page).to have_field("Amount")
      expect(page).to have_select("Period")
      expect(page).to have_button("Update Budget")
      expect(page).to have_link("Cancel")
    end

    it "shows category name without select dropdown" do
      expect(page).to have_content("Groceries")
      expect(page).not_to have_select("Category")
    end

    it "pre-fills all budget fields with existing data" do
      expect(page).to have_field("Amount", with: "500.0")
      expect(page).to have_select("Period", selected: "Month")
    end

    it "updates budget and redirects to category page" do
      fill_in "Amount", with: "750.00"
      select "Year", from: "Period"
      click_button "Update Budget"

      expect(page).to have_current_path(category_path(expense_category))
      expect(page).to have_content("Budget was successfully updated")

      budget.reload
      expect(budget.amount).to eq(750.00)
      expect(budget.period).to eq("year")
    end

    it "shows error for missing amount" do
      fill_in "Amount", with: ""
      click_button "Update Budget"

      expect(page).to have_current_path(edit_budget_path(budget))
      expect(page).to have_content("can't be blank")
    end

    it "shows error for missing period" do
      select "", from: "Period"
      click_button "Update Budget"

      expect(page).to have_current_path(edit_budget_path(budget))
      expect(page).to have_content("can't be blank")
    end

    it "returns to category page when clicking cancel" do
      click_link "Cancel"
      expect(page).to have_current_path(category_path(expense_category))
    end

    it "keeps form values after validation failure" do
      fill_in "Amount", with: ""
      select "Year", from: "Period"
      click_button "Update Budget"

      expect(page).to have_select("Period", selected: "Year")
    end
  end
end
