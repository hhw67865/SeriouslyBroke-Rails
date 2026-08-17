# frozen_string_literal: true

require "rails_helper"

# THE CAP IS DELETED (plan 3, task 3) AND THIS PAGE IS TASK 4's TO REWORK. What this task owes it
# is that it renders; what these examples pin is what it renders NOW.
#
# `DashboardPresenter`'s FINDING-1 bridge re-points the two bands: "budgeted" is buffer-funded
# spending (a category pointing at an ACCOUNT) and "pool-covered" is enveloped spending, where the
# split used to be "no pool" against "any pool". The figures in the split examples are unchanged
# because the fixture already divided that way.
#
# WHAT WENT WITH THE CAP: every example reading a per-category budget figure — "$650.00 / $500.00",
# "+$150.00 over", "$120.00 left", the over-budget ordering, the budget totals, the whole prorated
# scenario, and the "Monthly Budget"/"YTD Budget" stat card, which is gated on
# `total_budget.positive?` and `total_budget` sums a category's cap. They are deleted with the
# behaviour rather than rewritten against a cap that cannot exist.
RSpec.describe "Dashboard Index - Expenses Tab", type: :system do
  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  describe "empty state", :aggregate_failures do
    before { visit reports_path(tab: "expenses") }

    it "shows empty message when no expense data" do
      expect(page).to have_content("No budgeted expense data")
      expect(page).to have_content("No budgeted expenses")
      expect(page).to have_content("No pool-covered expenses")
    end
  end

  describe "budgeted vs pool-covered split", :aggregate_failures do
    let!(:pool) { create(:pool, user: user, name: "Car Fund", target_amount: 5000, start_date: 1.year.ago) }

    # Budgeted expense category
    let!(:groceries) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:groceries_item) { create(:item, category: groceries, name: "Weekly Shopping") }

    # Pool-covered expense category
    let!(:car_repair) { create(:category, :expense, user: user, name: "Car Repair", pool: pool) }
    let!(:car_repair_item) { create(:item, category: car_repair, name: "Mechanic") }

    before do
      create(:entry, item: groceries_item, amount: 150.00, date: base_date + 5.days)
      create(:entry, item: car_repair_item, amount: 200.00, date: base_date + 10.days)
      visit reports_path(tab: "expenses")
    end

    it "shows Monthly Budget section with only buffer-funded categories" do
      within monthly_budget_section do
        expect(page).to have_link("Groceries")
        expect(page).to have_content("$150.00")
        expect(page).not_to have_link("Car Repair")
      end
    end

    it "shows Pool-Covered section with only pool-linked categories" do
      within pool_covered_section do
        expect(page).to have_link("Car Repair")
        expect(page).to have_content("$200.00")
        expect(page).not_to have_link("Groceries")
      end
    end

    # THE STAT CARD IS GONE UNTIL TASK 4: it printed the sum of the user's caps and is gated on
    # that sum being positive, which it can no longer be. The section HEADING of the same name
    # stays, so the negative is on the figure rather than on the words.
    it "no longer prints a budget total" do
      expect(page).to have_content("Monthly Budget")
      expect(page).to have_no_content("$500.00")
    end

    it "excludes pool-covered spending from budgeted totals" do
      within_stat_card("Tracked Budgeted") { expect(page).to have_content("$150.00") }
      within_stat_card("Total Budgeted") { expect(page).to have_content("$150.00") }
    end
  end

  describe "show/hide total toggle", :aggregate_failures do
    let!(:expense_category) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:expense_item) { create(:item, category: expense_category, name: "Weekly Shopping") }

    before do
      create(:entry, item: expense_item, amount: 150.00, date: base_date + 5.days)
      visit reports_path(tab: "expenses")
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
  end

  describe "untracked categories in breakdown", :aggregate_failures do
    let!(:groceries) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:groceries_item) { create(:item, category: groceries, name: "Weekly Shopping") }
    let!(:dining) { create(:category, :expense, user: user, name: "Dining", tracked: false) }
    let!(:dining_item) { create(:item, category: dining, name: "Restaurants") }

    before do
      create(:entry, item: groceries_item, amount: 300.00, date: base_date + 1.day)
      create(:entry, item: dining_item, amount: 150.00, date: base_date + 2.days)
      visit reports_path(tab: "expenses")
    end

    it "shows tracked and total budgeted stats with category links" do
      within_stat_card("Tracked Budgeted") { expect(page).to have_content("$300.00") }
      within_stat_card("Total Budgeted") { expect(page).to have_content("$450.00") }
      expect(page).to have_css("p.uppercase", text: /untracked/i)
      expect(page).to have_link("Groceries", href: category_path(groceries))
      expect(page).to have_link("Dining", href: category_path(dining))
    end
  end

  # WHAT THE ROWS SAY NOW. Four examples stood here reading each category's cap off the row —
  # "$650.00 / $500.00", "+$150.00 over" / "$120.00 left", the ordering by most-over-budget and the
  # column total — and `DashboardPresenter#enrich_with_budget` writes none of those keys any more,
  # because `CategoryCalculator#effective_budget` is nil for every category. One example replaces
  # them, and it is the negative the bridge has to keep true: the rows render, with the spending
  # and nothing that claims to be a budget.
  describe "rows in the budgeted section", :aggregate_failures do
    let!(:groceries) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:groceries_item) { create(:item, category: groceries, name: "Weekly Shopping") }
    let!(:utilities) { create(:category, :expense, user: user, name: "Utilities") }
    let!(:utilities_item) { create(:item, category: utilities, name: "Electric") }

    before do
      create(:entry, item: groceries_item, amount: 650, date: base_date + 1.day)
      create(:entry, item: utilities_item, amount: 80, date: base_date + 2.days)

      visit reports_path(tab: "expenses")
    end

    it "prints the spending, and no budget clause of any kind" do
      within monthly_budget_section do
        expect(page).to have_link("Groceries")
        expect(page).to have_content("$650.00")
        expect(page).to have_link("Utilities")
        expect(page).to have_content("$80.00")

        expect(page).to have_no_content(" / $")
        expect(page).to have_no_content("over")
        expect(page).to have_no_content("left")
      end
    end
  end

  describe "YTD view", :aggregate_failures do
    let!(:expense_category) { create(:category, :expense, user: user, name: "Utilities") }
    let!(:expense_item) { create(:item, category: expense_category, name: "Electric") }

    before do
      create(:entry, item: expense_item, amount: 100.00, date: base_date)
      create(:entry, item: expense_item, amount: 120.00, date: base_date - 1.month)
      visit reports_path(tab: "expenses", period: "ytd")
    end

    it "shows YTD Budgeted Spending heading" do
      expect(page).to have_content("YTD Budgeted Spending")
    end

    it "shows YTD Tracked Budgeted label in summary stats" do
      expect(page).to have_content("YTD Tracked Budgeted")
    end

    # "YTD Budget" was the stat card printing the sum of the user's caps; it is gated on that sum
    # being positive and is gone with the cap. "YTD Budgeted Spending" above is the chart heading
    # and is unrelated, which is why the negative is scoped to the stat strip.
    it "no longer shows the YTD Budget stat card" do
      expect(page).to have_no_css("p.text-sm.text-gray-500", text: "YTD Budget", exact_text: true)
    end
  end

  # THE PRORATED SCENARIO IS DELETED with `budgets.prorated` (plan 3, task 3): it planted a $300
  # prorated cap beside a $200 flat one and read "over pace", "expected today: $150.00" and the
  # flat row's "$150.00 left" off the same screen. Neither cap nor ramp exists.

  private

  def monthly_budget_section
    find("h2", text: "Monthly Budget").ancestor("section")
  end

  def pool_covered_section
    find("h2", text: "Pool-Covered Spending").ancestor("section")
  end

  def within_stat_card(label, &)
    card = find("p", text: label).ancestor("div.bg-gray-50")
    within(card, &)
  end
end
