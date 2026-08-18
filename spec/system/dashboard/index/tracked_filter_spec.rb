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

    # THE TWO CAPS THIS PLANTED ARE DELETED (plan 3, task 3), and with them the "Monthly Budget"
    # stat card they fed — it is gated on `total_budget.positive?`, which sums a category's cap. The
    # tracked/untracked totals below are entry sums and are untouched, which is what this file is
    # actually about.
    before do
      create(:entry, item: groceries_item, amount: 300.00, date: base_date + 1.day)
      create(:entry, item: dining_item, amount: 150.00, date: base_date + 2.days)
    end

    it "shows all expenses as tracked by default" do
      visit reports_path(tab: "expenses")

      within_stat_card("Tracked Budgeted") { expect(page).to have_content("$450.00") }
      within_stat_card("Total Budgeted") { expect(page).to have_content("$450.00") }
      expect(page).to have_no_css(stat_card_label, text: "Monthly Budget", exact_text: true)
    end

    it "reduces tracked total and budget when a budgeted category is untracked" do
      dining.update!(tracked: false)
      visit reports_path(tab: "expenses")

      within_stat_card("Tracked Budgeted") { expect(page).to have_content("$300.00") }
      within_stat_card("Total Budgeted") { expect(page).to have_content("$450.00") }
      expect(page).to have_no_css(stat_card_label, text: "Monthly Budget", exact_text: true)
    end

    it "shows untracked category separately in breakdown" do
      dining.update!(tracked: false)
      visit reports_path(tab: "expenses")

      expect(page).to have_content("Groceries")
      expect(page).to have_css("p.uppercase", text: /untracked/i)
      expect(page).to have_content("Dining")
    end

    it "shows only expense categories in the tracked filter" do
      create(:category, :income, user: user, name: "Salary")
      visit reports_path(tab: "expenses")

      open_tracked_filter
      expect(page).to have_content("Groceries")
      expect(page).to have_content("Dining")
      expect(page).not_to have_content("Salary")
    end

    it "toggles a category via the filter popover" do
      visit reports_path(tab: "expenses")
      open_tracked_filter
      toggle_tracked("Dining")
      apply_tracked

      expect(page).to have_content("$300.00") # wait for page reload
      within_stat_card("Tracked Budgeted") { expect(page).to have_content("$300.00") }
      within_stat_card("Total Budgeted") { expect(page).to have_content("$450.00") }
      expect(page).to have_no_css(stat_card_label, text: "Monthly Budget", exact_text: true)
    end

    it "applies multiple toggle changes in a single submission" do
      visit reports_path(tab: "expenses")
      open_tracked_filter
      toggle_tracked("Dining")
      toggle_tracked("Groceries")
      apply_tracked

      expect(page).to have_content("$0.00")
      within_stat_card("Tracked Budgeted") { expect(page).to have_content("$0.00") }
      within_stat_card("Total Budgeted") { expect(page).to have_content("$450.00") }
      expect(groceries.reload).not_to be_tracked
      expect(dining.reload).not_to be_tracked
    end

    it "shows untracked count badge" do
      dining.update!(tracked: false)
      visit reports_path(tab: "expenses")

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
      visit reports_path(tab: "income")

      within_stat_card("Tracked Income") { expect(page).to have_content("$5,000.00") }
      within_stat_card("Total Income") { expect(page).to have_content("$6,000.00") }
    end

    it "shows untracked category separately in breakdown" do
      freelance.update!(tracked: false)
      visit reports_path(tab: "income")

      expect(page).to have_content("Salary")
      expect(page).to have_css("p.uppercase", text: /untracked/i)
      expect(page).to have_content("Freelance")
    end

    it "shows only income categories in the tracked filter" do
      create(:category, :expense, user: user, name: "Groceries")
      visit reports_path(tab: "income")

      open_tracked_filter
      expect(page).to have_content("Salary")
      expect(page).to have_content("Freelance")
      expect(page).not_to have_content("Groceries")
    end
  end

  describe "savings tab", :aggregate_failures do
    let!(:emergency_pool) { create(:pool, user: user, name: "Emergency") }
    let!(:emergency) { create(:category, :savings, user: user, name: "Emergency Fund", pool: emergency_pool) }
    let!(:emergency_item) { create(:item, category: emergency, name: "Monthly Transfer") }
    let!(:vacation_pool) { create(:pool, user: user, name: "Vacation") }
    let!(:vacation) { create(:category, :savings, user: user, name: "Vacation Fund", pool: vacation_pool) }
    let!(:vacation_item) { create(:item, category: vacation, name: "Deposit") }

    before do
      create(:entry, item: emergency_item, amount: 500.00, date: base_date + 1.day)
      create(:entry, item: vacation_item, amount: 200.00, date: base_date + 2.days)
    end

    it "reduces tracked savings totals when a category is untracked" do
      vacation.update!(tracked: false)
      visit reports_path(tab: "savings")

      within_stat_card("Contributed") { expect(page).to have_content("$500.00") }
    end

    it "shows untracked category separately in breakdown" do
      vacation.update!(tracked: false)
      visit reports_path(tab: "savings")

      expect(page).to have_content("Emergency Fund")
      expect(page).to have_css("p.uppercase", text: /untracked/i)
      expect(page).to have_content("Vacation Fund")
    end

    it "shows only savings categories in the tracked filter" do
      create(:category, :expense, user: user, name: "Groceries")
      visit reports_path(tab: "savings")

      open_tracked_filter
      expect(page).to have_content("Emergency Fund")
      expect(page).to have_content("Vacation Fund")
      expect(page).not_to have_content("Groceries")
    end
  end

  private

  # THE STAT CARD'S OWN LABEL, so the negatives above say "this card is gone" rather than "this
  # figure appears nowhere on the page". A page-wide `have_no_content("$800.00")` would pass for
  # the wrong reason the day any unrelated figure changed, and would fail for the wrong reason the
  # day an unrelated one landed on $800. The section HEADING is an <h2> of the same words, which is
  # exactly why this is scoped to the card's <p>.
  def stat_card_label = "div.bg-gray-50 p.text-sm"

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
        .find("label")
        .click
    end
  end

  def apply_tracked
    within("details") { click_button "Apply" }
  end
end
