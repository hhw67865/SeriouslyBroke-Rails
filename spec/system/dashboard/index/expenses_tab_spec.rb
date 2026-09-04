# frozen_string_literal: true

require "rails_helper"

# THE EXPENSES TAB AFTER DECISION 6 (plan 3, task 4).
#
# The two sections are the two lanes spending comes out of: "Out of Available" (a category that
# holds no money of its own — nothing reserved it, so it drains AVAILABLE) and "Out of an Envelope"
# (a category that holds its own money). The FIGURES are unchanged from the bridge Task 3 left; the
# words "Monthly Budget", "Budgeted" and "Pool-Covered" are not.
#
# THE PREDICATE IS `Category#holder?` SINCE TASK 7, where it was `Category#buffer_funded?` — "this
# category points at an ACCOUNT". Under the two-ledger model a category's pool says nothing about
# whether it holds money (the layer is being deleted, and a holder's pool is nil), so the old
# reader had inverted on exactly the shapes this fixture now plants.
#
# WHAT WENT WITH THE CAP HERE: the "Budget" line drawn across the chart, the Monthly/YTD Budget
# stat card (already gated away in Task 3, deleted with its reader here) and the two column totals
# that paired a breakdown's sum with a cap. The column totals are also the second reader decision 6
# forbids — each printed the sum of the category rows, which is the same figure as the "Tracked"
# stat card directly above the list.
RSpec.describe "Dashboard Index - Expenses Tab", type: :system do
  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  describe "empty state", :aggregate_failures do
    before { visit reports_path(tab: "expenses") }

    it "shows empty messages for both lanes" do
      expect(page).to have_content("No unbudgeted spending")
      expect(page).to have_content("No envelope spending")
    end
  end

  describe "available vs envelope split", :aggregate_failures do
    let!(:groceries) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:groceries_item) { create(:item, category: groceries, name: "Weekly Shopping") }

    let!(:car_repair) { create(:category, :expense, :funded, user: user, name: "Car Repair") }
    let!(:car_repair_item) { create(:item, category: car_repair, name: "Mechanic") }

    before do
      create(:entry, item: groceries_item, amount: 150.00, date: base_date + 5.days)
      create(:entry, item: car_repair_item, amount: 200.00, date: base_date + 10.days)
      visit reports_path(tab: "expenses")
    end

    it "shows the available section with only the categories that hold nothing" do
      within available_section do
        expect(page).to have_link("Groceries")
        expect(page).to have_content("$150.00")
        expect(page).not_to have_link("Car Repair")
      end
    end

    it "shows the envelope section with only the categories that hold money" do
      within envelope_section do
        expect(page).to have_link("Car Repair")
        expect(page).to have_content("$200.00")
        expect(page).not_to have_link("Groceries")
      end
    end

    it "keeps each lane's spending out of the other lane's totals" do
      within_stat_card("Tracked Unbudgeted Spending") { expect(page).to have_content("$150.00") }
      within_stat_card("Total Unbudgeted Spending") { expect(page).to have_content("$150.00") }
      within_stat_card("Tracked Envelope Spending") { expect(page).to have_content("$200.00") }
      within_stat_card("Total Envelope Spending") { expect(page).to have_content("$200.00") }
    end

    # The other direction: the cap-era vocabulary is gone from the page, headings included.
    it "names no budget, cap or pool-covered spending anywhere" do
      expect(page).to have_no_content("Monthly Budget")
      expect(page).to have_no_content("Pool-Covered")
      expect(page).to have_no_content("Budgeted")
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

    it "shows tracked and total available stats with category links" do
      within_stat_card("Tracked Unbudgeted Spending") { expect(page).to have_content("$300.00") }
      within_stat_card("Total Unbudgeted Spending") { expect(page).to have_content("$450.00") }
      expect(page).to have_css("p.uppercase", text: /untracked/i)
      expect(page).to have_link("Groceries", href: category_path(groceries))
      expect(page).to have_link("Dining", href: category_path(dining))
    end
  end

  describe "rows in the available section", :aggregate_failures do
    let!(:groceries) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:groceries_item) { create(:item, category: groceries, name: "Weekly Shopping") }
    let!(:utilities) { create(:category, :expense, user: user, name: "Utilities") }
    let!(:utilities_item) { create(:item, category: utilities, name: "Electric") }

    before do
      create(:entry, item: groceries_item, amount: 650, date: base_date + 1.day)
      create(:entry, item: utilities_item, amount: 80, date: base_date + 2.days)

      visit reports_path(tab: "expenses")
    end

    # A name and a figure, exactly — no "$650.00 / $500.00" pair, no "+$150.00 over" / "$120.00
    # left" clause, and no column total under the list (the "Tracked Available Spending" card above
    # it is the one reader of that figure).
    it "prints a name and a figure per row, highest first, and closes the list there" do
      within available_section do
        rows = all("div.space-y-3 > div").map { |row| row.text.split("\n") }
        expect(rows).to eq([["Groceries", "$650.00"], ["Utilities", "$80.00"]])
        expect(page).to have_no_css("div.border-t")
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

    it "carries the YTD prefix into the chart heading and the stat cards", :aggregate_failures do
      expect(page).to have_content("YTD Unbudgeted Spending")
      within_stat_card("YTD Tracked Unbudgeted Spending") { expect(page).to have_content("$220.00") }
      within_stat_card("YTD Total Unbudgeted Spending") { expect(page).to have_content("$220.00") }
    end

    it "shows no YTD Budget card" do
      expect(page).to have_no_css("div.bg-gray-50 p.text-sm", text: "YTD Budget", exact_text: true)
    end
  end

  private

  def available_section
    find("h2", text: "Unbudgeted").ancestor("section")
  end

  def envelope_section
    find("h2", text: "Out of an Envelope").ancestor("section")
  end

  def within_stat_card(label, &)
    card = find("div.bg-gray-50 p.text-sm", text: label, exact_text: true).ancestor("div.bg-gray-50")
    within(card, &)
  end
end
