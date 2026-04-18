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

    it "shows the Money Flow section with income earned" do
      expect(page).to have_content("Income Allocation")
      expect(page).to have_content("$3,000.00 earned")
    end

    it "shows health indicators with Net Savings (not Savings Rate)" do
      expect(page).to have_content("Net Savings")
      expect(page).not_to have_content("Savings Rate")
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
  # savings contribution $500. Income Allocation segments: Budgeted $400,
  # Savings Contrib $500, Remaining $2,100 (= $3,000 − $400 − $500).
  describe "Income Allocation bar — number accuracy", :aggregate_failures do
    before do
      seed_mixed_financial_data
      visit root_path
    end

    it "shows income earned and remaining headers" do
      within income_allocation_section do
        expect(page).to have_content("$3,000.00 earned")
        expect(page).to have_content("$2,100.00 remaining")
      end
    end

    it "shows three legend amounts: Budgeted, Savings Contrib, Remaining" do
      within income_allocation_section do
        expect(page).to have_content("Budgeted $400.00")
        expect(page).to have_content("Savings Contrib $500.00")
        expect(page).to have_content("Remaining $2,100.00")
      end
    end

    it "shows expense ratio against income (all expenses)" do
      within_stat_card("Expense Ratio") { expect(page).to have_content("20.0%") }
    end
  end

  describe "Expense Sources bar — number accuracy", :aggregate_failures do
    before do
      seed_mixed_financial_data
      visit root_path
    end

    it "shows total spent and amount covered by savings" do
      within expense_sources_section do
        expect(page).to have_content("$600.00 spent")
        expect(page).to have_content("$200.00 came from savings")
      end
    end

    it "shows two legend amounts: From Income, From Savings" do
      within expense_sources_section do
        expect(page).to have_content("From Income $400.00")
        expect(page).to have_content("From Savings $200.00")
      end
    end
  end

  describe "Expense Sources bar — visibility", :aggregate_failures do
    before do
      income_item = create(:item, category: create(:category, :income, user: user, name: "Salary"), name: "Paycheck")
      expense_cat = create(:category, :expense, user: user, name: "Groceries")
      create(:entry, item: income_item, amount: 1000, date: base_date + 1.day)
      create(:entry, item: create(:item, category: expense_cat, name: "Food"), amount: 200, date: base_date + 2.days)
      visit root_path
    end

    it "is hidden when there are no pool-covered expenses" do
      expect(page).not_to have_content("Expense Sources")
    end
  end

  describe "Net Savings stat card — number accuracy", :aggregate_failures do
    before do
      seed_mixed_financial_data
      visit root_path
    end

    it "shows net savings as contributions minus withdrawals" do
      within_stat_card("Net Savings") { expect(page).to have_content("$300.00") }
    end
  end

  describe "Net Savings stat card — negative delta", :aggregate_failures do
    let!(:pool) { create(:savings_pool, user: user, name: "Buffer", target_amount: 1000, start_date: 1.year.ago) }
    let!(:savings_item) { create(:item, category: create(:category, :savings, user: user, name: "Buffer In", savings_pool: pool), name: "Deposit") }
    let!(:withdrawal_item) { create(:item, category: create(:category, :expense, user: user, name: "Buffer Out", savings_pool: pool), name: "Spend") }

    it "renders a negative net change when withdrawals exceed contributions" do
      create(:entry, item: savings_item, amount: 100.00, date: base_date + 1.day)
      create(:entry, item: withdrawal_item, amount: 300.00, date: base_date + 2.days)
      visit root_path

      within_stat_card("Net Savings") { expect(page).to have_content("-$200.00") }
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

  def income_allocation_section
    find("h4", text: "Income Allocation").ancestor("div.bg-gray-50")
  end

  def expense_sources_section
    find("h4", text: "Expense Sources").ancestor("div.bg-gray-50")
  end

  def top_spending_section
    find("h3", text: "Top Spending").ancestor("div.mb-8")
  end

  def within_stat_card(label, &)
    card = find("p", text: label).ancestor("div.bg-gray-50")
    within(card, &)
  end
end
