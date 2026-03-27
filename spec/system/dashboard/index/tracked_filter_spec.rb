# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Index - Tracked Filter", type: :system do
  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  describe "expenses tab", :aggregate_failures do
    let!(:groceries) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:groceries_item) { create(:item, category: groceries, name: "Weekly Shopping") }
    let!(:dining) { create(:category, :expense, user: user, name: "Dining") }
    let!(:dining_item) { create(:item, category: dining, name: "Restaurants") }

    before do
      create(:budget, category: groceries, amount: 800)
      create(:budget, category: dining, amount: 200)
      create(:entry, item: groceries_item, amount: 300.00, date: base_date + 1.day)
      create(:entry, item: dining_item, amount: 150.00, date: base_date + 2.days)
    end

    it "shows all expenses as tracked by default" do
      visit root_path

      within_stat_card("Tracked Expenses") { expect(page).to have_content("$450.00") }
      within_stat_card("Total Expenses") { expect(page).to have_content("$450.00") }
      within_stat_card("Monthly Budget") { expect(page).to have_content("$1,000.00") }
    end

    it "reduces tracked total and budget when a budgeted category is untracked" do
      dining.update!(tracked: false)
      visit root_path

      within_stat_card("Tracked Expenses") { expect(page).to have_content("$300.00") }
      within_stat_card("Total Expenses") { expect(page).to have_content("$450.00") }
      within_stat_card("Monthly Budget") { expect(page).to have_content("$800.00") }
    end

    it "shows untracked category separately in breakdown" do
      dining.update!(tracked: false)
      visit root_path

      expect(page).to have_content("Groceries")
      expect(page).to have_css("p.uppercase", text: /untracked/i)
      expect(page).to have_content("Dining")
    end

    it "shows only expense categories in the tracked filter" do
      create(:category, :income, user: user, name: "Salary")
      visit root_path

      open_tracked_filter
      expect(page).to have_content("Groceries")
      expect(page).to have_content("Dining")
      expect(page).not_to have_content("Salary")
    end

    it "toggles a category via the filter popover" do
      visit root_path
      open_tracked_filter
      toggle_tracked("Dining")

      expect(page).to have_content("$300.00") # wait for page reload
      within_stat_card("Tracked Expenses") { expect(page).to have_content("$300.00") }
      within_stat_card("Total Expenses") { expect(page).to have_content("$450.00") }
      within_stat_card("Monthly Budget") { expect(page).to have_content("$800.00") }
    end

    it "shows untracked count badge" do
      dining.update!(tracked: false)
      visit root_path

      expect(find("summary")).to have_content("1")
    end
  end

  describe "income tab", :aggregate_failures do
    let!(:salary) { create(:category, :income, user: user, name: "Salary") }
    let!(:salary_item) { create(:item, category: salary, name: "Paycheck") }
    let!(:freelance) { create(:category, :income, user: user, name: "Freelance") }
    let!(:freelance_item) { create(:item, category: freelance, name: "Project") }

    before do
      create(:entry, item: salary_item, amount: 5000.00, date: base_date + 1.day)
      create(:entry, item: freelance_item, amount: 1000.00, date: base_date + 2.days)
    end

    it "reduces tracked income total when a category is untracked" do
      freelance.update!(tracked: false)
      visit root_path(tab: "income")

      within_stat_card("Tracked Income") { expect(page).to have_content("$5,000.00") }
      within_stat_card("Total Income") { expect(page).to have_content("$6,000.00") }
    end

    it "shows untracked category separately in breakdown" do
      freelance.update!(tracked: false)
      visit root_path(tab: "income")

      expect(page).to have_content("Salary")
      expect(page).to have_css("p.uppercase", text: /untracked/i)
      expect(page).to have_content("Freelance")
    end

    it "shows only income categories in the tracked filter" do
      create(:category, :expense, user: user, name: "Groceries")
      visit root_path(tab: "income")

      open_tracked_filter
      expect(page).to have_content("Salary")
      expect(page).to have_content("Freelance")
      expect(page).not_to have_content("Groceries")
    end
  end

  describe "savings tab", :aggregate_failures do
    let!(:emergency_pool) { create(:savings_pool, user: user, name: "Emergency") }
    let!(:emergency) { create(:category, :savings, user: user, name: "Emergency Fund", savings_pool: emergency_pool) }
    let!(:emergency_item) { create(:item, category: emergency, name: "Monthly Transfer") }
    let!(:vacation_pool) { create(:savings_pool, user: user, name: "Vacation") }
    let!(:vacation) { create(:category, :savings, user: user, name: "Vacation Fund", savings_pool: vacation_pool) }
    let!(:vacation_item) { create(:item, category: vacation, name: "Deposit") }

    before do
      create(:entry, item: emergency_item, amount: 500.00, date: base_date + 1.day)
      create(:entry, item: vacation_item, amount: 200.00, date: base_date + 2.days)
    end

    it "reduces tracked savings totals when a category is untracked" do
      vacation.update!(tracked: false)
      visit root_path(tab: "savings")

      within_stat_card("Contributed") { expect(page).to have_content("$500.00") }
    end

    it "shows untracked category separately in breakdown" do
      vacation.update!(tracked: false)
      visit root_path(tab: "savings")

      expect(page).to have_content("Emergency Fund")
      expect(page).to have_css("p.uppercase", text: /untracked/i)
      expect(page).to have_content("Vacation Fund")
    end

    it "shows only savings categories in the tracked filter" do
      create(:category, :expense, user: user, name: "Groceries")
      visit root_path(tab: "savings")

      open_tracked_filter
      expect(page).to have_content("Emergency Fund")
      expect(page).to have_content("Vacation Fund")
      expect(page).not_to have_content("Groceries")
    end
  end

  private

  def within_stat_card(label, &)
    card = find("div.md\\:grid-cols-3 > div", text: label)
    within(card, &)
  end

  def open_tracked_filter
    find("summary", text: /Tracked/).click
  end

  def toggle_tracked(category_name)
    within("details") do
      find("span", text: category_name, exact_text: true)
        .ancestor(".flex.items-center")
        .find("button[type='submit']")
        .click
    end
  end
end
