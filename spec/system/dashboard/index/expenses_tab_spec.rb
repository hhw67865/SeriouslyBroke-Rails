# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Index - Expenses Tab", type: :system do
  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  describe "empty state", :aggregate_failures do
    before { visit root_path }

    it "shows empty message when no expense data" do
      expect(page).to have_content("No expense data")
      expect(page).to have_content("No expenses recorded")
    end
  end

  describe "with expense data", :aggregate_failures do
    let!(:expense_category) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:expense_item) { create(:item, category: expense_category, name: "Weekly Shopping") }

    before do
      create(:budget, category: expense_category, amount: 500)
      create(:entry, item: expense_item, amount: 150.00, date: base_date + 5.days)
      create(:entry, item: expense_item, amount: 75.50, date: base_date + 10.days)
      visit root_path
    end

    it "shows Monthly Spending heading in default view" do
      expect(page).to have_content("Monthly Spending")
    end

    it "shows summary stats with correct amounts" do
      expect(page).to have_content("Total Expenses")
      expect(page).to have_content("$225.50")
      expect(page).to have_content("Monthly Budget")
      expect(page).to have_content("$500.00")
    end

    it "shows category breakdown with linked expense categories" do
      expect(page).to have_content("By Category")
      expect(page).to have_link("Groceries", href: category_path(expense_category))
      expect(page).to have_content("$225.50")
    end
  end

  describe "untracked categories in breakdown", :aggregate_failures do
    let!(:groceries) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:groceries_item) { create(:item, category: groceries, name: "Weekly Shopping") }
    let!(:dining) { create(:category, :expense, user: user, name: "Dining", tracked: false) }
    let!(:dining_item) { create(:item, category: dining, name: "Restaurants") }

    before do
      create(:entry, item: groceries_item, amount: 300.00, date: base_date + 1.day)
      create(:entry, item: dining_item, amount: 150.00, date: base_date + 2.days)
      visit root_path
    end

    it "shows tracked and untracked categories separately with links" do
      within_stat_card("Tracked Expenses") { expect(page).to have_content("$300.00") }
      within_stat_card("Total Expenses") { expect(page).to have_content("$450.00") }
      expect(page).to have_css("p.uppercase", text: /untracked/i)
      expect(page).to have_link("Groceries", href: category_path(groceries))
      expect(page).to have_link("Dining", href: category_path(dining))
    end
  end

  describe "show/hide total toggle", :aggregate_failures do
    let!(:expense_category) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:expense_item) { create(:item, category: expense_category, name: "Weekly Shopping") }

    before do
      create(:budget, category: expense_category, amount: 500)
      create(:entry, item: expense_item, amount: 150.00, date: base_date + 5.days)
      visit root_path
    end

    it "shows 'Show Total' button by default" do
      expect(page).to have_link("Show Total")
      expect(page).not_to have_link("Hide Total")
    end

    it "toggles to 'Hide Total' when clicked" do
      click_link "Show Total"

      expect(page).to have_link("Hide Total")
      expect(page).not_to have_link("Show Total")
    end

    it "returns to 'Show Total' when toggled back" do
      click_link "Show Total"
      click_link "Hide Total"

      expect(page).to have_link("Show Total")
    end
  end

  describe "YTD view", :aggregate_failures do
    let!(:expense_category) { create(:category, :expense, user: user, name: "Utilities") }
    let!(:expense_item) { create(:item, category: expense_category, name: "Electric") }

    before do
      create(:budget, category: expense_category, amount: 200)
      create(:entry, item: expense_item, amount: 100.00, date: base_date)
      create(:entry, item: expense_item, amount: 120.00, date: base_date - 1.month)
      visit root_path(period: "ytd")
    end

    it "shows YTD Spending heading" do
      expect(page).to have_content("YTD Spending")
    end

    it "shows YTD Tracked label in summary stats" do
      expect(page).to have_content("YTD Tracked")
    end

    it "shows YTD Budget label" do
      expect(page).to have_content("YTD Budget")
    end
  end

  private

  def within_stat_card(label, &)
    card = find("p", text: label).ancestor("div.bg-gray-50")
    within(card, &)
  end
end
