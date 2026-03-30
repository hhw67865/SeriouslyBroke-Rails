# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Index - Savings Pools", type: :system do
  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  describe "pool balance reflects selected month", :aggregate_failures do
    let!(:pool) { create(:savings_pool, user: user, name: "Vacation Fund", target_amount: 5000, start_date: 1.year.ago) }
    let!(:savings_cat) { create(:category, :savings, user: user, name: "Vacation Savings", savings_pool: pool) }
    let!(:savings_item) { create(:item, category: savings_cat, name: "Monthly Deposit") }
    let!(:expense_cat) { create(:category, :expense, user: user, name: "Vacation Expense", savings_pool: pool) }
    let!(:expense_item) { create(:item, category: expense_cat, name: "Booking") }

    before do
      # Previous month: $800 in, $200 out => balance $600
      create(:entry, item: savings_item, amount: 800.00, date: base_date - 1.month + 1.day)
      create(:entry, item: expense_item, amount: 200.00, date: base_date - 1.month + 5.days)

      # Current month: $500 in, $100 out => cumulative balance $800
      create(:entry, item: savings_item, amount: 500.00, date: base_date + 1.day)
      create(:entry, item: expense_item, amount: 100.00, date: base_date + 5.days)
    end

    it "shows current month pool balance on savings tab" do
      visit root_path(tab: "savings")

      pool_card = find("a[href='#{savings_pool_path(pool)}']")
      within(pool_card) do
        expect(page).to have_content("Vacation Fund")
        expect(page).to have_content("$1,000.00") # 1300 - 300
      end
    end

    it "shows period In/Out for current month" do
      visit root_path(tab: "savings")

      pool_card = find("a[href='#{savings_pool_path(pool)}']")
      within(pool_card) do
        expect(page).to have_content("$500.00") # In this month
        expect(page).to have_content("$100.00") # Out this month
      end
    end
  end

  describe "total pools balance", :aggregate_failures do
    let!(:pool_a) { create(:savings_pool, user: user, name: "Pool A", target_amount: 5000, start_date: 1.year.ago) }
    let!(:pool_b) { create(:savings_pool, user: user, name: "Pool B", target_amount: 3000, start_date: 1.year.ago) }
    let!(:cat_a) { create(:category, :savings, user: user, name: "Save A", savings_pool: pool_a) }
    let!(:cat_b) { create(:category, :savings, user: user, name: "Save B", savings_pool: pool_b) }
    let!(:item_a) { create(:item, category: cat_a, name: "Deposit A") }
    let!(:item_b) { create(:item, category: cat_b, name: "Deposit B") }

    before do
      create(:entry, item: item_a, amount: 1000.00, date: base_date + 1.day)
      create(:entry, item: item_b, amount: 500.00, date: base_date + 1.day)
    end

    it "shows combined total across all pools" do
      visit root_path(tab: "savings")

      expect(page).to have_content("Total:")
      expect(page).to have_content("$1,500.00")
    end
  end

  describe "status badges", :aggregate_failures do
    it "shows 'funded' badge when pool reaches 100%" do
      pool = create(:savings_pool, user: user, name: "Small Goal", target_amount: 100, start_date: 1.year.ago)
      cat = create(:category, :savings, user: user, name: "Small Savings", savings_pool: pool)
      item = create(:item, category: cat, name: "Deposit")
      create(:entry, item: item, amount: 100.00, date: base_date + 1.day)

      visit root_path(tab: "savings")
      pool_card = find("a[href='#{savings_pool_path(pool)}']")
      within(pool_card) { expect(page).to have_content("funded") }
    end

    it "shows 'low' badge when pool is under 10%" do
      pool = create(:savings_pool, user: user, name: "Big Goal", target_amount: 10_000, start_date: 1.year.ago)
      cat = create(:category, :savings, user: user, name: "Big Savings", savings_pool: pool)
      item = create(:item, category: cat, name: "Deposit")
      create(:entry, item: item, amount: 50.00, date: base_date + 1.day)

      visit root_path(tab: "savings")
      pool_card = find("a[href='#{savings_pool_path(pool)}']")
      within(pool_card) { expect(page).to have_content("low") }
    end

    it "shows 'negative' badge when withdrawals exceed contributions" do
      pool = create(:savings_pool, user: user, name: "Depleted Fund", target_amount: 5000, start_date: 1.year.ago)
      savings_cat = create(:category, :savings, user: user, name: "Depleted Savings", savings_pool: pool)
      savings_item = create(:item, category: savings_cat, name: "Deposit")
      expense_cat = create(:category, :expense, user: user, name: "Depleted Expense", savings_pool: pool)
      expense_item = create(:item, category: expense_cat, name: "Withdrawal")
      create(:entry, item: savings_item, amount: 100.00, date: base_date + 1.day)
      create(:entry, item: expense_item, amount: 500.00, date: base_date + 2.days)

      visit root_path(tab: "savings")
      pool_card = find("a[href='#{savings_pool_path(pool)}']")
      within(pool_card) { expect(page).to have_content("negative") }
    end
  end
end
