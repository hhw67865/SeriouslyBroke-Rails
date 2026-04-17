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
      seed_mixed_financial_data
      visit root_path
    end

    it "shows Income vs Expenses allocation bar" do
      expect(page).to have_content("Income vs Expenses")
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

  # Income $3,000, budgetable expense $400, pool-covered expense $200,
  # savings contribution $500. Both expense types are real money out — bar
  # totals must include the pool-covered amount.
  describe "Income vs Expenses bar — number accuracy", :aggregate_failures do
    before do
      seed_mixed_financial_data
      visit root_path
    end

    it "totals all expenses (budgetable + pool-covered) into the bar" do
      within income_vs_expenses_section do
        expect(page).to have_content("$3,000.00 earned")
        expect(page).to have_content("Expenses $600.00")
      end
    end

    it "computes remaining as income minus all expenses (savings excluded)" do
      within income_vs_expenses_section do
        expect(page).to have_content("$2,400.00 remaining")
        expect(page).to have_content("Remaining $2,400.00")
      end
    end

    it "shows expense ratio against income (all expenses)" do
      within_stat_card("Expense Ratio") { expect(page).to have_content("20.0%") }
    end
  end

  describe "Savings Flow — number accuracy", :aggregate_failures do
    before do
      seed_mixed_financial_data
      visit root_path
    end

    it "shows the gross contribution amount" do
      within savings_flow_section { expect(page).to have_content("Contributed +$500.00") }
    end

    it "shows the gross withdrawal amount (pool-covered expenses)" do
      within savings_flow_section { expect(page).to have_content("Withdrawn −$200.00") }
    end

    it "shows the net change as contributions minus withdrawals" do
      within savings_flow_section { expect(page).to have_content("+$300.00") }
    end
  end

  describe "Savings Flow — net delta sign", :aggregate_failures do
    let!(:pool) { create(:savings_pool, user: user, name: "Buffer", target_amount: 1000, start_date: 1.year.ago) }
    let!(:savings_item) { create(:item, category: create(:category, :savings, user: user, name: "Buffer In", savings_pool: pool), name: "Deposit") }
    let!(:withdrawal_item) { create(:item, category: create(:category, :expense, user: user, name: "Buffer Out", savings_pool: pool), name: "Spend") }

    it "renders a negative net change when withdrawals exceed contributions" do
      create(:entry, item: savings_item, amount: 100.00, date: base_date + 1.day)
      create(:entry, item: withdrawal_item, amount: 300.00, date: base_date + 2.days)
      visit root_path

      within savings_flow_section do
        expect(page).to have_content("-$200.00")
        expect(page).to have_content("Contributed +$100.00")
        expect(page).to have_content("Withdrawn −$300.00")
      end
    end
  end

  describe "Savings Flow — visibility", :aggregate_failures do
    before do
      income_item = create(:item, category: create(:category, :income, user: user, name: "Salary"), name: "Paycheck")
      create(:entry, item: income_item, amount: 1000, date: base_date + 1.day)
      visit root_path
    end

    it "is hidden when there are no contributions or withdrawals" do
      expect(page).not_to have_content("Savings Flow")
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

  def seed_mixed_financial_data
    pool = create(:savings_pool, user: user, name: "Emergency Fund", target_amount: 5000, start_date: 1.year.ago)
    expense_cat = create(:category, :expense, user: user, name: "Groceries")
    create(:budget, category: expense_cat, amount: 500)

    create_entry_for(create(:category, :income, user: user, name: "Salary"), "Paycheck", 3000.00, 1)
    create_entry_for(expense_cat, "Weekly Shopping", 400.00, 2)
    create_entry_for(create(:category, :expense, user: user, name: "Car Repair", savings_pool: pool), "Mechanic", 200.00, 3)
    create_entry_for(create(:category, :savings, user: user, name: "Emergency Savings", savings_pool: pool), "Transfer", 500.00, 4)
  end

  def create_entry_for(category, item_name, amount, day_offset)
    item = create(:item, category: category, name: item_name)
    create(:entry, item: item, amount: amount, date: base_date + day_offset.days)
  end

  def income_vs_expenses_section
    find("h3", text: "Income vs Expenses").ancestor("div.mb-8")
  end

  def savings_flow_section
    find("h3", text: "Savings Flow").ancestor("div.mb-8")
  end

  def top_spending_section
    find("h3", text: "Top Spending").ancestor("div.mb-8")
  end

  def within_stat_card(label, &)
    card = find("p", text: label).ancestor("div.bg-gray-50")
    within(card, &)
  end
end
