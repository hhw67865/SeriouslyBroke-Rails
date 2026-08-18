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

    # THE STAT CARDS ARE NAMED FOR THE LANE NOW (plan 3, task 4): both categories point at an
    # ACCOUNT (the factory's default), so both spend out of the buffer. The FIGURES are untouched —
    # they are entry sums, which is what this file is actually about.
    before do
      create(:entry, item: groceries_item, amount: 300.00, date: base_date + 1.day)
      create(:entry, item: dining_item, amount: 150.00, date: base_date + 2.days)
    end

    it "shows all expenses as tracked by default" do
      visit reports_path(tab: "expenses")

      within_stat_card("Tracked Buffer Spending") { expect(page).to have_content("$450.00") }
      within_stat_card("Total Buffer Spending") { expect(page).to have_content("$450.00") }
    end

    it "reduces the tracked total when a category is untracked" do
      dining.update!(tracked: false)
      visit reports_path(tab: "expenses")

      within_stat_card("Tracked Buffer Spending") { expect(page).to have_content("$300.00") }
      within_stat_card("Total Buffer Spending") { expect(page).to have_content("$450.00") }
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
      within_stat_card("Tracked Buffer Spending") { expect(page).to have_content("$300.00") }
      within_stat_card("Total Buffer Spending") { expect(page).to have_content("$450.00") }
    end

    it "applies multiple toggle changes in a single submission" do
      visit reports_path(tab: "expenses")
      open_tracked_filter
      toggle_tracked("Dining")
      toggle_tracked("Groceries")
      apply_tracked

      expect(page).to have_content("$0.00")
      within_stat_card("Tracked Buffer Spending") { expect(page).to have_content("$0.00") }
      within_stat_card("Total Buffer Spending") { expect(page).to have_content("$450.00") }
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

  # THE STAT CARD'S OWN LABEL. Scoped to the card's <p> rather than matched page-wide: a section
  # HEADING can carry the same words, and a page-wide dollar assertion passes and fails for
  # unrelated reasons the day any other figure moves.
  #
  # The three "Monthly Budget" card negatives that stood beside these figures are deleted with the
  # card (plan 3, task 4) — `spec/system/dashboard/index/expenses_tab_spec.rb` holds the one
  # page-wide negative that says the cap vocabulary is gone.
  def stat_card_label = "div.bg-gray-50 p.text-sm"

  def within_stat_card(label, &)
    card = find(stat_card_label, text: label, exact_text: true).ancestor("div.bg-gray-50")
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
