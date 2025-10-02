# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings Pools Show - Money Flow", type: :system do
  let(:user) { create(:user) }
  let!(:savings_pool) { create(:savings_pool, user: user, name: "Emergency Fund", target_amount: 10_000) }
  let!(:savings_category) { create(:category, user: user, category_type: :savings, savings_pool: savings_pool) }
  let!(:expense_category) { create(:category, user: user, category_type: :expense, savings_pool: savings_pool) }

  before { sign_in user }

  describe "contributions and withdrawals", :aggregate_failures do
    let!(:savings_item) { create(:item, category: savings_category, name: "Monthly Savings") }
    let!(:expense_item) { create(:item, category: expense_category, name: "Emergency Expense") }

    before do
      # Total Contributions: $200 + $300 + $150 = $650
      create(:entry, item: savings_item, amount: 200.0, date: Date.current)
      create(:entry, item: savings_item, amount: 300.0, date: Date.current - 1.day)
      create(:entry, item: savings_item, amount: 150.0, date: Date.current - 2.days)

      # Total Withdrawals: $50 + $75 = $125
      create(:entry, item: expense_item, amount: 50.0, date: Date.current)
      create(:entry, item: expense_item, amount: 75.0, date: Date.current - 1.day)

      visit savings_pool_path(savings_pool)
    end

    it "shows correct total contributions" do
      contributions_card = page.all("div.bg-white.rounded-xl", text: "Total Contributions").first
      within(contributions_card) do
        expect(page).to have_content("+$650.00")
      end
    end

    it "shows correct total withdrawals" do
      withdrawals_card = page.all("div.bg-white.rounded-xl", text: "Total Withdrawals").first
      within(withdrawals_card) do
        expect(page).to have_content("-$125.00")
      end
    end
  end

  describe "with no withdrawals", :aggregate_failures do
    let!(:savings_item) { create(:item, category: savings_category) }

    before do
      create_list(:entry, 4, item: savings_item, amount: 250.0)
      visit savings_pool_path(savings_pool)
    end

    it "shows correct contributions" do
      contributions_card = page.all("div.bg-white.rounded-xl", text: "Total Contributions").first
      within(contributions_card) do
        expect(page).to have_content("+$1,000.00")
      end
    end

    it "shows zero withdrawals" do
      withdrawals_card = page.all("div.bg-white.rounded-xl", text: "Total Withdrawals").first
      within(withdrawals_card) do
        expect(page).to have_content("-$0.00")
      end
    end
  end

  describe "with no contributions", :aggregate_failures do
    let!(:expense_item) { create(:item, category: expense_category) }

    before do
      create_list(:entry, 3, item: expense_item, amount: 100.0)
      visit savings_pool_path(savings_pool)
    end

    it "shows zero contributions" do
      contributions_card = page.all("div.bg-white.rounded-xl", text: "Total Contributions").first
      within(contributions_card) do
        expect(page).to have_content("+$0.00")
      end
    end

    it "shows correct withdrawals" do
      withdrawals_card = page.all("div.bg-white.rounded-xl", text: "Total Withdrawals").first
      within(withdrawals_card) do
        expect(page).to have_content("-$300.00")
      end
    end
  end
end
