# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Index - Savings Tab", type: :system do
  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  describe "empty state", :aggregate_failures do
    before { visit root_path(tab: "savings") }

    it "shows empty message when no savings data" do
      expect(page).to have_content("No savings data available")
      expect(page).to have_content("No savings categories")
    end
  end

  describe "with savings data", :aggregate_failures do
    let!(:savings_pool) { create(:savings_pool, user: user, name: "Emergency Fund") }
    let!(:savings_category) { create(:category, :savings, user: user, name: "Emergency", savings_pool: savings_pool) }
    let!(:savings_item) { create(:item, category: savings_category, name: "Monthly Transfer") }

    before do
      create(:entry, item: savings_item, amount: 500.00, date: base_date + 5.days)
      create(:entry, item: savings_item, amount: 400.00, date: base_date - 1.month + 5.days)
      visit root_path(tab: "savings")
    end

    it "shows savings chart heading" do
      expect(page).to have_content("Savings Balance")
      expect(page).to have_content("6 months")
    end

    it "shows Monthly Contribution summary stat" do
      expect(page).to have_content("Monthly Contribution")
      expect(page).to have_content("$500.00")
    end

    it "shows Total Balance summary stat" do
      expect(page).to have_content("Total Balance")
      expect(page).to have_content("$900.00")
    end

    it "shows category breakdown with name, balance, and contribution" do
      expect(page).to have_content("By Category")
      expect(page).to have_content("Emergency")
      expect(page).to have_content("Balance: $900.00")
      expect(page).to have_content("+$500.00")
    end
  end

  describe "YTD view", :aggregate_failures do
    let!(:savings_pool) { create(:savings_pool, user: user, name: "Vacation Fund") }
    let!(:savings_category) { create(:category, :savings, user: user, name: "Vacation", savings_pool: savings_pool) }
    let!(:savings_item) { create(:item, category: savings_category, name: "Deposit") }

    before do
      create(:entry, item: savings_item, amount: 300.00, date: base_date)
      create(:entry, item: savings_item, amount: 250.00, date: base_date - 1.month)
      visit root_path(tab: "savings", period: "ytd")
    end

    it "shows YTD in chart heading" do
      expect(page).to have_content("Savings Balance")
      expect(page).to have_content("YTD")
    end

    it "shows YTD Contribution label in summary stats" do
      expect(page).to have_content("YTD Contribution")
    end
  end
end
