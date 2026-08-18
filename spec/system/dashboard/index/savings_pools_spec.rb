# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Index - Savings Pools", type: :system do
  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  describe "pool balance reflects selected month", :aggregate_failures do
    let!(:pool) { create(:pool, user: user, name: "Vacation Fund", target_amount: 5000, start_date: 1.year.ago) }
    let!(:savings_cat) { create(:category, :savings, user: user, name: "Vacation Savings", pool: pool) }
    let!(:savings_item) { create(:item, category: savings_cat, name: "Monthly Deposit") }
    let!(:expense_cat) { create(:category, :expense, user: user, name: "Vacation Expense", pool: pool) }
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
      visit reports_path(tab: "savings")

      pool_card = find("a[href='#{pool_path(pool)}']")
      within(pool_card) do
        expect(page).to have_content("Vacation Fund")
        expect(page).to have_content("$1,000.00") # 1300 - 300
      end
    end

    # THE PER-PERIOD "In / Out" ROW IS DELETED (plan 3, task 4), and the example that read it goes
    # with the behaviour. "In" was `Pool#contribution_entries` — savings-TYPED entries — so on the
    # post-cutover demo it printed $0.00 on every card while those goals were receiving $525 a
    # period as PoolMovements. This fixture, which plants a savings CATEGORY, is one of the last
    # places the figure was still non-zero, and that is exactly why it could not be trusted.
    it "shows the card's balance against its target, and no per-period flow" do
      visit reports_path(tab: "savings")

      pool_card = find("a[href='#{pool_path(pool)}']")
      within(pool_card) do
        expect(page).to have_content("$1,000.00")
        expect(page).to have_content("of $5,000.00")
        expect(page).to have_no_content("In")
        expect(page).to have_no_content("Out")
      end
    end
  end

  describe "total pools balance", :aggregate_failures do
    let!(:pool_a) { create(:pool, user: user, name: "Pool A", target_amount: 5000, start_date: 1.year.ago) }
    let!(:pool_b) { create(:pool, user: user, name: "Pool B", target_amount: 3000, start_date: 1.year.ago) }
    let!(:cat_a) { create(:category, :savings, user: user, name: "Save A", pool: pool_a) }
    let!(:cat_b) { create(:category, :savings, user: user, name: "Save B", pool: pool_b) }
    let!(:item_a) { create(:item, category: cat_a, name: "Deposit A") }
    let!(:item_b) { create(:item, category: cat_b, name: "Deposit B") }

    before do
      create(:entry, item: item_a, amount: 1000.00, date: base_date + 1.day)
      create(:entry, item: item_b, amount: 500.00, date: base_date + 1.day)
    end

    it "shows combined total across all pools" do
      visit reports_path(tab: "savings")

      expect(page).to have_content("Total:")
      expect(page).to have_content("$1,500.00")
    end
  end

  describe "status badges", :aggregate_failures do
    it "shows 'funded' badge when pool reaches 100%" do
      pool = create(:pool, user: user, name: "Small Goal", target_amount: 100, start_date: 1.year.ago)
      cat = create(:category, :savings, user: user, name: "Small Savings", pool: pool)
      item = create(:item, category: cat, name: "Deposit")
      create(:entry, item: item, amount: 100.00, date: base_date + 1.day)

      visit reports_path(tab: "savings")
      pool_card = find("a[href='#{pool_path(pool)}']")
      within(pool_card) { expect(page).to have_content("funded") }
    end

    it "shows 'low' badge when pool is under 10%" do
      pool = create(:pool, user: user, name: "Big Goal", target_amount: 10_000, start_date: 1.year.ago)
      cat = create(:category, :savings, user: user, name: "Big Savings", pool: pool)
      item = create(:item, category: cat, name: "Deposit")
      create(:entry, item: item, amount: 50.00, date: base_date + 1.day)

      visit reports_path(tab: "savings")
      pool_card = find("a[href='#{pool_path(pool)}']")
      within(pool_card) { expect(page).to have_content("low") }
    end

    it "shows 'negative' badge when withdrawals exceed contributions" do
      pool = create(:pool, user: user, name: "Depleted Fund", target_amount: 5000, start_date: 1.year.ago)
      savings_cat = create(:category, :savings, user: user, name: "Depleted Savings", pool: pool)
      savings_item = create(:item, category: savings_cat, name: "Deposit")
      expense_cat = create(:category, :expense, user: user, name: "Depleted Expense", pool: pool)
      expense_item = create(:item, category: expense_cat, name: "Withdrawal")
      create(:entry, item: savings_item, amount: 100.00, date: base_date + 1.day)
      create(:entry, item: expense_item, amount: 500.00, date: base_date + 2.days)

      visit reports_path(tab: "savings")
      pool_card = find("a[href='#{pool_path(pool)}']")
      within(pool_card) { expect(page).to have_content("negative") }
    end
  end
end
