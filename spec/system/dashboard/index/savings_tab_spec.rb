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

    it "shows tracked and total contribution summary stats" do
      within_stat_card("Tracked Contribution") { expect(page).to have_content("$500.00") }
      within_stat_card("Total Contribution") { expect(page).to have_content("$500.00") }
    end

    it "shows Total Balance summary stat" do
      expect(page).to have_content("Total Balance")
      expect(page).to have_content("$900.00")
    end

    it "shows category breakdown with linked name, balance, and contribution" do
      expect(page).to have_content("By Category")
      expect(page).to have_link("Emergency", href: category_path(savings_category))
      expect(page).to have_content("Balance: $900.00")
      expect(page).to have_content("+$500.00")
    end
  end

  describe "untracked categories in breakdown", :aggregate_failures do
    let!(:emergency_pool) { create(:savings_pool, user: user, name: "Emergency") }
    let!(:emergency) { create(:category, :savings, user: user, name: "Emergency Fund", savings_pool: emergency_pool) }
    let!(:emergency_item) { create(:item, category: emergency, name: "Monthly Transfer") }
    let!(:vacation_pool) { create(:savings_pool, user: user, name: "Vacation") }
    let!(:vacation) { create(:category, :savings, user: user, name: "Vacation Fund", tracked: false, savings_pool: vacation_pool) }
    let!(:vacation_item) { create(:item, category: vacation, name: "Deposit") }

    before do
      create(:entry, item: emergency_item, amount: 500.00, date: base_date + 1.day)
      create(:entry, item: vacation_item, amount: 200.00, date: base_date + 2.days)
      visit root_path(tab: "savings")
    end

    it "shows tracked and untracked categories separately with links" do
      within_stat_card("Tracked Contribution") { expect(page).to have_content("$500.00") }
      within_stat_card("Total Contribution") { expect(page).to have_content("$700.00") }
      expect(page).to have_css("p.uppercase", text: /untracked/i)
      expect(page).to have_link("Emergency Fund", href: category_path(emergency))
      expect(page).to have_link("Vacation Fund", href: category_path(vacation))
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

    it "shows YTD Tracked label in summary stats" do
      expect(page).to have_content("YTD Tracked")
    end
  end

  private

  def within_stat_card(label, &)
    card = find("p", text: label).ancestor("div.bg-gray-50")
    within(card, &)
  end
end
