# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Index - All Tab", type: :system do
  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  describe "default tab", :aggregate_failures do
    before { visit root_path }

    it "defaults to All tab" do
      all_link = find("nav[aria-label='Tabs'] a", text: "All")
      expect(all_link[:class]).to include("border-brand")
    end
  end

  describe "with financial data", :aggregate_failures do
    before do
      pool = create(:savings_pool, user: user, name: "Emergency Fund", target_amount: 5000, start_date: 1.year.ago)
      income_item = create(:item, category: create(:category, :income, user: user, name: "Salary"), name: "Paycheck")
      expense_cat = create(:category, :expense, user: user, name: "Groceries")
      expense_item = create(:item, category: expense_cat, name: "Weekly Shopping")
      pool_expense_item = create(:item, category: create(:category, :expense, user: user, name: "Car Repair", savings_pool: pool), name: "Mechanic")
      savings_item = create(:item, category: create(:category, :savings, user: user, name: "Emergency Savings", savings_pool: pool), name: "Transfer")

      create(:budget, category: expense_cat, amount: 500)
      create(:entry, item: income_item, amount: 3000.00, date: base_date + 1.day)
      create(:entry, item: expense_item, amount: 400.00, date: base_date + 2.days)
      create(:entry, item: pool_expense_item, amount: 200.00, date: base_date + 3.days)
      create(:entry, item: savings_item, amount: 500.00, date: base_date + 4.days)
      visit root_path
    end

    it "shows Where Your Money Went allocation bar" do
      expect(page).to have_content("Where Your Money Went")
      expect(page).to have_content("$3,000.00 earned")
    end

    it "shows health indicators" do
      expect(page).to have_content("Savings Rate")
      expect(page).to have_content("Expense Ratio")
      expect(page).to have_content("used")
    end

    it "shows savings pools section with pool card" do
      expect(page).to have_content("Savings Pools")
      expect(page).to have_content("Emergency Fund")
    end

    it "shows top spending categories" do
      expect(page).to have_content("Top Spending")
      expect(page).to have_link("Groceries")
    end
  end

  describe "top spending order", :aggregate_failures do
    before do
      small_cat = create(:category, :expense, user: user, name: "Coffee")
      large_cat = create(:category, :expense, user: user, name: "Rent")
      medium_cat = create(:category, :expense, user: user, name: "Groceries")

      create(:entry, item: create(:item, category: small_cat, name: "Latte"), amount: 50, date: base_date + 1.day)
      create(:entry, item: create(:item, category: large_cat, name: "Monthly"), amount: 2000, date: base_date + 1.day)
      create(:entry, item: create(:item, category: medium_cat, name: "Food"), amount: 400, date: base_date + 1.day)
      visit root_path
    end

    it "orders top spending by amount descending" do
      within top_spending_section do
        names = all("a").map(&:text)
        expect(names).to eq(["Rent", "Groceries", "Coffee"])
      end
    end
  end

  private

  def top_spending_section
    find("h3", text: "Top Spending").ancestor("div.mb-8")
  end
end
