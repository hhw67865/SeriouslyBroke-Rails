# frozen_string_literal: true

require "rails_helper"

# THE TWO MONEY-FLOW TILES, AFTER THE CUTOVER (plan 3, task 5). Every contribution here was an
# entry in a savings CATEGORY and is a `PoolMovement` now — which is what `PoolCalculator
# #contributions` reads, and the whole of what it reads since `savings_entries_total` died with the
# enum value. EVERY FIGURE BELOW IS UNCHANGED: the term moved, the amounts did not.
RSpec.describe "Savings Pools Show - Money Flow", type: :system do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let!(:pool) { create(:pool, user: user, name: "Emergency Fund", target_amount: 10_000, account: checking) }
  let!(:expense_category) { create(:category, user: user, category_type: :expense, pool: pool) }

  before { sign_in user, scope: :user }

  def contribute(amount, on = Date.current)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: amount, date: on)
  end

  def contributions_card = page.all("div.bg-white.rounded", text: "Total Contributions").first

  def withdrawals_card = page.all("div.bg-white.rounded", text: "Total Withdrawals").first

  describe "contributions and withdrawals", :aggregate_failures do
    let!(:expense_item) { create(:item, category: expense_category, name: "Emergency Expense") }

    before do
      # Total Contributions: $200 + $300 + $150 = $650
      contribute(200.0)
      contribute(300.0, Date.current - 1.day)
      contribute(150.0, Date.current - 2.days)

      # Total Withdrawals: $50 + $75 = $125
      create(:entry, item: expense_item, amount: 50.0, date: Date.current)
      create(:entry, item: expense_item, amount: 75.0, date: Date.current - 1.day)

      visit pool_path(pool)
    end

    it "shows correct total contributions" do
      within(contributions_card) { expect(page).to have_content("+$650.00") }
    end

    it "shows correct total withdrawals" do
      within(withdrawals_card) { expect(page).to have_content("-$125.00") }
    end

    # THE STALE NOUN TASK 2 FLAGGED, both directions. The tile credited this figure to "savings
    # categories" — a kind of category that does not exist, about money that arrived as transfers.
    it "credits the contributions to money moved in, not to savings categories", :aggregate_failures do
      within(contributions_card) do
        expect(page).to have_content("Money moved in")
        expect(page).to have_no_content("From savings categories")
      end
    end
  end

  describe "with no withdrawals", :aggregate_failures do
    before do
      4.times { contribute(250.0) }
      visit pool_path(pool)
    end

    it "shows correct contributions" do
      within(contributions_card) { expect(page).to have_content("+$1,000.00") }
    end

    it "shows zero withdrawals" do
      within(withdrawals_card) { expect(page).to have_content("-$0.00") }
    end
  end

  describe "with no contributions", :aggregate_failures do
    let!(:expense_item) { create(:item, category: expense_category) }

    before do
      create_list(:entry, 3, item: expense_item, amount: 100.0)
      visit pool_path(pool)
    end

    it "shows zero contributions" do
      within(contributions_card) { expect(page).to have_content("+$0.00") }
    end

    it "shows correct withdrawals" do
      within(withdrawals_card) { expect(page).to have_content("-$300.00") }
    end
  end
end
