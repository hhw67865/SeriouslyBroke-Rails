# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Index - Savings Tab", type: :system do
  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  describe "empty state", :aggregate_failures do
    before { visit root_path(tab: "savings") }

    it "shows empty messages when no savings data" do
      expect(page).to have_content("No savings flow data available")
      expect(page).to have_content("No savings categories")
    end
  end

  describe "stat cards reflect selected month", :aggregate_failures do
    let!(:pool) { create(:savings_pool, user: user, name: "Emergency Fund", target_amount: 5000, start_date: 1.year.ago) }
    let!(:savings_cat) { create(:category, :savings, user: user, name: "Emergency", savings_pool: pool) }
    let!(:savings_item) { create(:item, category: savings_cat, name: "Monthly Transfer") }
    let!(:withdrawal_cat) { create(:category, :expense, user: user, name: "Emergency Withdrawal", savings_pool: pool) }
    let!(:withdrawal_item) { create(:item, category: withdrawal_cat, name: "ATM") }

    before do
      create(:entry, item: savings_item, amount: 500.00, date: base_date + 5.days)
      create(:entry, item: savings_item, amount: 300.00, date: base_date - 1.month + 5.days)
      create(:entry, item: withdrawal_item, amount: 100.00, date: base_date + 10.days)
      visit root_path(tab: "savings")
    end

    it "shows current month contributed and withdrawn totals" do
      within_stat_card("Contributed") { expect(page).to have_content("$500.00") }
      within_stat_card("Withdrawn") { expect(page).to have_content("$100.00") }
    end
  end

  describe "contributions by category shows total up to selected date", :aggregate_failures do
    let!(:pool) { create(:savings_pool, user: user, name: "Vacation Fund", target_amount: 3000, start_date: 1.year.ago) }
    let!(:savings_cat) { create(:category, :savings, user: user, name: "Vacation Savings", savings_pool: pool) }
    let!(:savings_item) { create(:item, category: savings_cat, name: "Deposit") }

    before do
      create(:entry, item: savings_item, amount: 200.00, date: base_date - 2.months + 1.day)
      create(:entry, item: savings_item, amount: 300.00, date: base_date - 1.month + 1.day)
      create(:entry, item: savings_item, amount: 400.00, date: base_date + 1.day)
      visit root_path(tab: "savings")
    end

    it "shows period contribution and total contributed through end of selected month" do
      expect(page).to have_content("Total Contributed: $900.00")
      expect(page).to have_content("+$400.00")
    end
  end

  describe "savings pool numbers", :aggregate_failures do
    let!(:pool) { create(:savings_pool, user: user, name: "House Fund", target_amount: 10_000, start_date: 1.year.ago) }
    let!(:savings_cat) { create(:category, :savings, user: user, name: "House Savings", savings_pool: pool) }
    let!(:savings_item) { create(:item, category: savings_cat, name: "Deposit") }
    let!(:withdrawal_cat) { create(:category, :expense, user: user, name: "House Withdrawal", savings_pool: pool) }
    let!(:withdrawal_item) { create(:item, category: withdrawal_cat, name: "Withdrawal") }

    before do
      create(:entry, item: savings_item, amount: 1000.00, date: base_date - 1.month + 1.day)
      create(:entry, item: savings_item, amount: 600.00, date: base_date + 1.day)
      create(:entry, item: withdrawal_item, amount: 200.00, date: base_date + 5.days)
      visit root_path(tab: "savings")
    end

    it "shows pool balance, progress, and period flow" do
      pool_card = find("a[href='#{savings_pool_path(pool)}']")
      within(pool_card) do
        expect(page).to have_content("House Fund")
        expect(page).to have_content("$1,400.00")
        expect(page).to have_content("$10,000.00")
        expect(page).to have_content("14%")
        expect(page).to have_content("$600.00")
        expect(page).to have_content("$200.00")
      end
    end
  end

  describe "includes entries before pool start_date", :aggregate_failures do
    let!(:pool) { create(:savings_pool, user: user, name: "New Pool", target_amount: 5000, start_date: base_date) }
    let!(:savings_cat) { create(:category, :savings, user: user, name: "Pool Savings", savings_pool: pool) }
    let!(:savings_item) { create(:item, category: savings_cat, name: "Transfer") }

    before do
      create(:entry, item: savings_item, amount: 250.00, date: base_date - 2.months + 1.day)
      create(:entry, item: savings_item, amount: 350.00, date: base_date + 1.day)
      visit root_path(tab: "savings")
    end

    it "counts contributions from before pool start_date in totals" do
      within_stat_card("Contributed") { expect(page).to have_content("$350.00") }
      expect(page).to have_content("Total Contributed: $600.00")
    end
  end

  describe "YTD view", :aggregate_failures do
    let!(:pool) { create(:savings_pool, user: user, name: "Vacation Fund", target_amount: 3000, start_date: 1.year.ago) }
    let!(:savings_cat) { create(:category, :savings, user: user, name: "Vacation", savings_pool: pool) }
    let!(:savings_item) { create(:item, category: savings_cat, name: "Deposit") }

    before do
      create(:entry, item: savings_item, amount: 300.00, date: base_date)
      create(:entry, item: savings_item, amount: 250.00, date: base_date - 1.month)
      visit root_path(tab: "savings", period: "ytd")
    end

    it "shows YTD in chart heading" do
      expect(page).to have_content("Contributions vs Withdrawals")
      expect(page).to have_content("YTD")
    end

    it "shows YTD Contributed label in summary stats" do
      expect(page).to have_content("YTD Contributed")
    end
  end

  describe "untracked categories in breakdown", :aggregate_failures do
    let!(:emergency_pool) { create(:savings_pool, user: user, name: "Emergency", target_amount: 5000, start_date: 1.year.ago) }
    let!(:emergency) { create(:category, :savings, user: user, name: "Emergency Fund", savings_pool: emergency_pool) }
    let!(:emergency_item) { create(:item, category: emergency, name: "Monthly Transfer") }
    let!(:vacation_pool) { create(:savings_pool, user: user, name: "Vacation", target_amount: 3000, start_date: 1.year.ago) }
    let!(:vacation) { create(:category, :savings, user: user, name: "Vacation Fund", tracked: false, savings_pool: vacation_pool) }
    let!(:vacation_item) { create(:item, category: vacation, name: "Deposit") }

    before do
      create(:entry, item: emergency_item, amount: 500.00, date: base_date + 1.day)
      create(:entry, item: vacation_item, amount: 200.00, date: base_date + 2.days)
      visit root_path(tab: "savings")
    end

    it "shows tracked and untracked categories separately with links" do
      within_stat_card("Contributed") { expect(page).to have_content("$500.00") }
      expect(page).to have_css("p.uppercase", text: /untracked/i)
      expect(page).to have_link("Emergency Fund", href: category_path(emergency))
      expect(page).to have_link("Vacation Fund", href: category_path(vacation))
    end
  end

  private

  def within_stat_card(label, &)
    card = find("div.md\\:grid-cols-3 > div", text: label)
    within(card, &)
  end
end
