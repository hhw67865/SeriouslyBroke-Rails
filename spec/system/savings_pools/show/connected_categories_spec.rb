# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings Pools Show - Connected Categories", type: :system do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { create(:user) }
  let!(:savings_pool) { create(:savings_pool, user: user, name: "Emergency Fund", target_amount: 10_000) }

  before { sign_in user }

  describe "with connected categories", :aggregate_failures do
    before do
      create(:category, user: user, name: "Monthly Savings", category_type: :savings, savings_pool: savings_pool)
      create(:category, user: user, name: "Bonus Income", category_type: :savings, savings_pool: savings_pool)
      create(:category, user: user, name: "Medical Bills", category_type: :expense, savings_pool: savings_pool)
      visit savings_pool_path(savings_pool)
    end

    it "shows connected categories section" do
      expect(page).to have_content("Connected Categories")
      expect(page).to have_link("Manage Categories")
    end

    it "shows correct count of contributing categories" do
      within("h4", text: "Contributing Categories") do
        expect(page).to have_content("Contributing Categories (2)")
      end
    end

    it "shows correct count of withdrawing categories" do
      within("h4", text: "Withdrawing Categories") do
        expect(page).to have_content("Withdrawing Categories (1)")
      end
    end

    it "displays savings category names" do
      contributing_section = page.all("div", text: /Contributing Categories/).first.find(:xpath, "..")
      within(contributing_section) do
        expect(page).to have_content("Monthly Savings")
        expect(page).to have_content("Bonus Income")
      end
    end

    it "displays expense category name" do
      withdrawing_section = page.all("div", text: /Withdrawing Categories/).first.find(:xpath, "..")
      within(withdrawing_section) do
        expect(page).to have_content("Medical Bills")
      end
    end

    it "shows category type labels" do
      expect(page).to have_content("Savings category")
      expect(page).to have_content("Expense category")
    end
  end

  describe "with category amounts", :aggregate_failures do
    let!(:savings_category) { create(:category, user: user, name: "Monthly Savings", category_type: :savings, savings_pool: savings_pool) }
    let!(:savings_item) { create(:item, category: savings_category) }
    let!(:expense_category) { create(:category, user: user, name: "Medical Bills", category_type: :expense, savings_pool: savings_pool) }
    let!(:expense_item) { create(:item, category: expense_category) }

    before do
      # Create entries for this month
      travel_to Date.current.beginning_of_month do
        create(:entry, item: savings_item, amount: 250.0, date: Date.current)
        create(:entry, item: savings_item, amount: 150.0, date: Date.current + 5.days)
        create(:entry, item: expense_item, amount: 90.0, date: Date.current + 1.day)
        create(:entry, item: expense_item, amount: 60.0, date: Date.current + 6.days)
      end

      # Create entries for previous month
      prev_month = Date.current.prev_month
      travel_to prev_month.beginning_of_month do
        create(:entry, item: savings_item, amount: 120.0, date: prev_month.beginning_of_month + 2.days)
        create(:entry, item: savings_item, amount: 80.0, date: prev_month.beginning_of_month + 10.days)
        create(:entry, item: expense_item, amount: 40.0, date: prev_month.beginning_of_month + 3.days)
        create(:entry, item: expense_item, amount: 30.0, date: prev_month.beginning_of_month + 9.days)
      end

      visit savings_pool_path(savings_pool)
    end

    it "shows correct total for contributing category" do
      within("div.bg-green-50", text: "Monthly Savings") do
        expect(page).to have_content("+$400.00")
        expect(page).to have_content(Date.current.strftime("%B %Y"))
      end
    end

    it "shows current month category amounts" do
      within("div.bg-green-50", text: "Monthly Savings") do
        expect(page).to have_content("+$400.00")
      end
      within("div.bg-red-50", text: "Medical Bills") do
        expect(page).to have_content("-$150.00")
      end
    end

    it "updates category amounts when navigating to previous month" do
      find("button[title='Previous month']").click

      within("div.bg-green-50", text: "Monthly Savings") do
        expect(page).to have_content("+$200.00")
        expect(page).to have_content(Date.current.prev_month.strftime("%B %Y"))
      end
      within("div.bg-red-50", text: "Medical Bills") do
        expect(page).to have_content("-$70.00")
        expect(page).to have_content(Date.current.prev_month.strftime("%B %Y"))
      end
    end
  end

  describe "with only savings categories", :aggregate_failures do
    before do
      create(:category, user: user, name: "Monthly Savings", category_type: :savings, savings_pool: savings_pool)
      visit savings_pool_path(savings_pool)
    end

    it "shows contributing categories" do
      contributing_section = page.all("div", text: /Contributing Categories/).first.find(:xpath, "..")
      within(contributing_section) do
        expect(page).to have_content("Monthly Savings")
      end
    end

    it "shows empty state for withdrawing categories" do
      withdrawing_section = page.all("div", text: /Withdrawing Categories/).first.find(:xpath, "..")
      within(withdrawing_section) do
        expect(page).to have_content("No withdrawing categories connected")
      end
    end
  end

  describe "with only expense categories", :aggregate_failures do
    before do
      create(:category, user: user, name: "Emergency Expenses", category_type: :expense, savings_pool: savings_pool)
      visit savings_pool_path(savings_pool)
    end

    it "shows empty state for contributing categories" do
      contributing_section = page.all("div", text: /Contributing Categories/).first.find(:xpath, "..")
      within(contributing_section) do
        expect(page).to have_content("No contributing categories connected")
      end
    end

    it "shows withdrawing categories" do
      withdrawing_section = page.all("div", text: /Withdrawing Categories/).first.find(:xpath, "..")
      within(withdrawing_section) do
        expect(page).to have_content("Emergency Expenses")
      end
    end
  end

  describe "with no connected categories", :aggregate_failures do
    before { visit savings_pool_path(savings_pool) }

    it "shows empty state message" do
      expect(page).to have_content("No categories connected")
      expect(page).to have_content("Connect categories to start tracking your progress automatically")
    end

    it "shows connect first category button" do
      expect(page).to have_link("Connect Your First Category")
    end
  end

  describe "manage categories link", :aggregate_failures do
    before do
      create(:category, user: user, category_type: :savings, savings_pool: savings_pool)
      visit savings_pool_path(savings_pool)
    end

    it "navigates to categories management page" do
      click_link "Manage Categories"
      expect(page).to have_current_path(categories_savings_pool_path(savings_pool))
    end
  end
end
