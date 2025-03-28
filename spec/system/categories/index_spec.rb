# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Index", type: :system do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  include ActionView::Helpers::NumberHelper

  before do
    sign_in user
  end

  describe "categories display" do
    context "with categories" do
      let!(:expense_category) { create(:category, :expense, user: user) }
      let!(:other_user_category) { create(:category, :expense, user: other_user) }

      before { visit categories_path }

      it "shows only the current user's categories", :aggregate_failures do
        expect(page).to have_content(expense_category.name)
        expect(page).not_to have_content(other_user_category.name)
      end
    end

    context "with no categories" do
      before do
        user.categories.destroy_all
        visit categories_path
      end

      it "shows the empty state message", :aggregate_failures do
        expect(page).to have_content("No Expense Categories")
        expect(page).to have_content("Get started by creating your first expense category")
      end
    end
  end

  describe "filter functionality" do
    let!(:housing_expense_category) { create(:category, :expense, user: user, name: "Housing Expenses") }
    let!(:salary_income_category) { create(:category, :income, user: user, name: "Salary Income") }
    let!(:emergency_savings_category) { create(:category, :savings, user: user, name: "Emergency Savings") }

    it "defaults to showing expense categories", :aggregate_failures do
      visit categories_path
      expect(page).to have_content(housing_expense_category.name)
      expect(page).not_to have_content(salary_income_category.name)
      expect(page).not_to have_content(emergency_savings_category.name)
    end

    it "filters to show only income categories", :aggregate_failures do
      visit categories_path(type: :income)
      expect(page).not_to have_content(housing_expense_category.name)
      expect(page).to have_content(salary_income_category.name)
      expect(page).not_to have_content(emergency_savings_category.name)
    end

    it "filters to show only savings categories", :aggregate_failures do
      visit categories_path(type: :savings)
      expect(page).not_to have_content(housing_expense_category.name)
      expect(page).not_to have_content(salary_income_category.name)
      expect(page).to have_content(emergency_savings_category.name)
    end
  end

  describe "search functionality" do
    let!(:housing_search_expense_category) { create(:category, :expense, user: user, name: "Housing Expenses") }
    let!(:food_search_expense_category) { create(:category, :expense, user: user, name: "Food Expenses") }
    let!(:housing_search_income_category) { create(:category, :income, user: user, name: "Housing Income") }

    it "finds categories with matching names", :aggregate_failures do
      visit categories_path
      fill_in "query", with: "Housing"
      find("body").click

      expect(page).to have_content(housing_search_expense_category.name)
      expect(page).not_to have_content(food_search_expense_category.name)
    end

    it "respects the current filter type", :aggregate_failures do
      visit categories_path(type: :income)
      fill_in "query", with: "Housing"
      find("body").click

      expect(page).to have_content(housing_search_income_category.name)
      expect(page).not_to have_content(housing_search_expense_category.name)
    end

    it "shows empty state when no search results" do
      visit categories_path
      fill_in "query", with: "NonExistentCategory"
      find("body").click

      expect(page).to have_content("No Expense Categories")
    end

    it "is case-insensitive" do
      visit categories_path
      fill_in "query", with: "housing"
      find("body").click

      expect(page).to have_content(housing_search_expense_category.name)
    end
  end

  describe "category card content" do
    describe "expense category card" do
      let(:category) { create(:category, :expense, user: user) }

      before do
        rent_amount = 700
        groceries_amount = 200
        utilities_amount = 0
        budget_amount = 1000

        create(:budget, category: category, amount: budget_amount)
        rent_item = create(:item, category: category, name: "Rent")
        groceries_item = create(:item, category: category, name: "Groceries")
        utilities_item = create(:item, category: category, name: "Utilities")

        create(:entry, item: rent_item, amount: rent_amount, date: Date.current.beginning_of_month + 5.days)
        create(:entry, item: groceries_item, amount: groceries_amount, date: Date.current.beginning_of_month + 10.days)
        create(:entry, item: utilities_item, amount: utilities_amount, date: Date.current.beginning_of_month + 15.days)

        visit categories_path
      end

      it "displays the correct total expense amount vs budget" do
        within(".bg-white", text: category.name) do
          rent_amount = 700
          groceries_amount = 200
          budget_amount = 1000
          total_expense_amount = rent_amount + groceries_amount
          expected_budget_string = "#{number_to_currency(total_expense_amount)} / #{number_to_currency(budget_amount)}"
          expect(page).to have_content(expected_budget_string)
        end
      end

      it "displays the correct budget percentage used" do
        within(".bg-white", text: category.name) do
          rent_amount = 700
          groceries_amount = 200
          budget_amount = 1000
          total_expense_amount = rent_amount + groceries_amount
          budget_percentage = (total_expense_amount.to_f / budget_amount * 100).round
          expect(page).to have_content("#{budget_percentage}% used")
        end
      end

      it "shows the name of the top expense item (Rent)" do
        within(".bg-white", text: category.name) do
          rent_item = category.items.find_by!(name: "Rent")
          expect(page).to have_content(rent_item.name)
        end
      end

      it "shows the amount of the top expense item (Rent)" do
        within(".bg-white", text: category.name) do
          rent_amount = 700
          expect(page).to have_content(number_to_currency(-rent_amount))
        end
      end

      it "shows the name of the second expense item (Groceries)" do
        within(".bg-white", text: category.name) do
          groceries_item = category.items.find_by!(name: "Groceries")
          expect(page).to have_content(groceries_item.name)
        end
      end

      it "shows the amount of the second expense item (Groceries)" do
        within(".bg-white", text: category.name) do
          groceries_amount = 200
          expect(page).to have_content(number_to_currency(-groceries_amount))
        end
      end

      it "does not show the zero-amount expense item (Utilities)" do
        within(".bg-white", text: category.name) do
          utilities_item = category.items.find_by!(name: "Utilities")
          expect(page).not_to have_content(utilities_item.name)
        end
      end
    end

    describe "income category card" do
      let(:category) { create(:category, :income, user: user) }

      before do
        current_salary_amount = 5000
        current_bonus_amount = 1000
        prev_salary_amount = (current_salary_amount * 0.9).round
        prev_bonus_amount = (current_bonus_amount * 0.91).round

        salary_item = create(:item, category: category, name: "Salary")
        bonus_item = create(:item, category: category, name: "Bonus")

        create(:entry, item: salary_item, amount: current_salary_amount, date: Date.current.beginning_of_month + 1.day)
        create(:entry, item: bonus_item, amount: current_bonus_amount, date: Date.current.beginning_of_month + 15.days)
        create(:entry, item: salary_item, amount: prev_salary_amount, date: 1.month.ago.beginning_of_month + 1.day)
        create(:entry, item: bonus_item, amount: prev_bonus_amount, date: 1.month.ago.beginning_of_month + 15.days)

        visit categories_path(type: :income)
      end

      it "displays the correct total income amount" do
        within(".bg-white", text: category.name) do
          current_salary_amount = 5000
          current_bonus_amount = 1000
          current_total_income = current_salary_amount + current_bonus_amount
          expect(page).to have_content(number_to_currency(current_total_income))
        end
      end

      it "displays the correct comparison percentage to previous month" do
        within(".bg-white", text: category.name) do
          current_salary_amount = 5000
          current_bonus_amount = 1000
          prev_salary_amount = (current_salary_amount * 0.9).round
          prev_bonus_amount = (current_bonus_amount * 0.91).round
          current_total_income = current_salary_amount + current_bonus_amount
          prev_total_income = prev_salary_amount + prev_bonus_amount
          percentage_change = prev_total_income.zero? ? 0 : ((current_total_income - prev_total_income) / prev_total_income.to_f * 100).round
          expect(page).to have_content("#{percentage_change}%")
        end
      end

      it "shows the name of the top income item (Salary)" do
        within(".bg-white", text: category.name) do
          salary_item = category.items.find_by!(name: "Salary")
          expect(page).to have_content(salary_item.name)
        end
      end

      it "shows the amount of the top income item (Salary)" do
        within(".bg-white", text: category.name) do
          current_salary_amount = 5000
          expect(page).to have_content("+#{number_to_currency(current_salary_amount)}")
        end
      end

      it "shows the name of the second income item (Bonus)" do
        within(".bg-white", text: category.name) do
          bonus_item = category.items.find_by!(name: "Bonus")
          expect(page).to have_content(bonus_item.name)
        end
      end

      it "shows the amount of the second income item (Bonus)" do
        within(".bg-white", text: category.name) do
          current_bonus_amount = 1000
          expect(page).to have_content("+#{number_to_currency(current_bonus_amount)}")
        end
      end
    end

    describe "savings category card" do
      it "displays the correct contribution amount when linked to a savings pool" do
        contribution_amount = 300
        savings_pool = create(:savings_pool, name: "Emergency Fund", user: user)
        category = create(:category, :savings, user: user, savings_pool: savings_pool)
        item = create(:item, category: category, name: "Monthly Contribution")
        create(:entry, item: item, amount: contribution_amount, date: Date.current.beginning_of_month + 1.day)

        visit categories_path(type: :savings)

        within(".bg-white", text: category.name) do
          expect(page).to have_content(number_to_currency(contribution_amount))
        end
      end

      it "displays the savings pool name when linked" do
        savings_pool = create(:savings_pool, name: "Emergency Fund", user: user)
        category = create(:category, :savings, user: user, savings_pool: savings_pool)
        item = create(:item, category: category, name: "Monthly Contribution")
        create(:entry, item: item, amount: 1, date: Date.current.beginning_of_month + 1.day)

        visit categories_path(type: :savings)

        within(".bg-white", text: category.name) do
          expect(page).to have_content("Savings Pool: #{savings_pool.name}")
        end
      end

      it "displays card correctly when not linked to a savings pool", :aggregate_failures do
        no_pool_amount = 200
        category_no_pool = create(:category, :savings, user: user, name: "Travel Fund", savings_pool: nil)
        item_no_pool = create(:item, category: category_no_pool, name: "Travel Savings")
        create(:entry, item: item_no_pool, amount: no_pool_amount, date: Date.current.beginning_of_month + 2.days)

        visit categories_path(type: :savings)

        within(".bg-white", text: category_no_pool.name) do
          expect(page).to have_content(number_to_currency(no_pool_amount))
          expect(page).not_to have_content("Savings Pool:")
        end
      end
    end
  end
end
