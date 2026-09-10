# frozen_string_literal: true

require "rails_helper"

# The Expenses tab's two sections are the two lanes spending comes out of: "Unruled spending" (a
# category no rule claims money for) and "Ruled spending" (a category a rule speaks for). The
# predicate is `Category#ruled?`.
RSpec.describe "Dashboard Index - Expenses Tab", type: :system do
  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  describe "empty state", :aggregate_failures do
    before { visit reports_path(tab: "expenses") }

    it "shows empty messages for both lanes" do
      expect(page).to have_content("No unruled spending")
      expect(page).to have_content("No ruled spending")
    end
  end

  describe "unruled vs ruled split", :aggregate_failures do
    let!(:groceries) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:groceries_item) { create(:item, category: groceries, name: "Weekly Shopping") }

    let!(:car_repair) { create(:category, :expense, user: user, name: "Car Repair") }
    let!(:car_repair_item) { create(:item, category: car_repair, name: "Mechanic") }

    before do
      create(:rule, :rate, category: car_repair, amount: 300)
      create(:entry, item: groceries_item, amount: 150.00, date: base_date + 5.days)
      create(:entry, item: car_repair_item, amount: 200.00, date: base_date + 10.days)
      visit reports_path(tab: "expenses")
    end

    it "shows the unruled section with only the categories no rule speaks for" do
      within unruled_section do
        expect(page).to have_link("Groceries")
        expect(page).to have_content("$150.00")
        expect(page).not_to have_link("Car Repair")
      end
    end

    it "shows the ruled section with only the categories a rule claims for" do
      within ruled_section do
        expect(page).to have_link("Car Repair")
        expect(page).to have_content("$200.00")
        expect(page).not_to have_link("Groceries")
      end
    end

    it "keeps each lane's spending out of the other lane's totals" do
      within_stat_card("Tracked Unruled Spending") { expect(page).to have_content("$150.00") }
      within_stat_card("Total Unruled Spending") { expect(page).to have_content("$150.00") }
      within_stat_card("Tracked Ruled Spending") { expect(page).to have_content("$200.00") }
      within_stat_card("Total Ruled Spending") { expect(page).to have_content("$200.00") }
    end

    # The other direction: the cap-era vocabulary is gone from the page, headings included.
    it "names no budget or cap anywhere" do
      expect(page).to have_no_content("Monthly Budget")
      expect(page).to have_no_content("YTD Budget")
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

    it "shows tracked and total unruled stats with category links" do
      within_stat_card("Tracked Unruled Spending") { expect(page).to have_content("$300.00") }
      within_stat_card("Total Unruled Spending") { expect(page).to have_content("$450.00") }
      expect(page).to have_css("p.uppercase", text: /untracked/i)
      expect(page).to have_link("Groceries", href: category_path(groceries))
      expect(page).to have_link("Dining", href: category_path(dining))
    end
  end

  describe "rows in the unruled section", :aggregate_failures do
    let!(:groceries) { create(:category, :expense, user: user, name: "Groceries") }
    let!(:groceries_item) { create(:item, category: groceries, name: "Weekly Shopping") }
    let!(:utilities) { create(:category, :expense, user: user, name: "Utilities") }
    let!(:utilities_item) { create(:item, category: utilities, name: "Electric") }

    before do
      create(:entry, item: groceries_item, amount: 650, date: base_date + 1.day)
      create(:entry, item: utilities_item, amount: 80, date: base_date + 2.days)

      visit reports_path(tab: "expenses")
    end

    # A name and a figure, exactly — no cap beside the figure, no "over" clause, and no column
    # total under the list: the stat card above it is the one reader of that figure.
    it "prints a name and a figure per row, highest first, and closes the list there" do
      within unruled_section do
        rows = all("div.space-y-3 > div").map(&:text)
        expect(rows).to eq(["Groceries $650.00", "Utilities $80.00"])
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
      expect(page).to have_content("YTD Unruled Spending")
      within_stat_card("YTD Tracked Unruled Spending") { expect(page).to have_content("$220.00") }
      within_stat_card("YTD Total Unruled Spending") { expect(page).to have_content("$220.00") }
    end

    it "shows no YTD Budget card" do
      expect(page).to have_no_css("div.bg-gray-50 p.text-sm", text: "YTD Budget", exact_text: true)
    end
  end

  private

  def unruled_section
    find("h2", text: "Unruled spending").ancestor("section")
  end

  def ruled_section
    find("h2", text: "Ruled spending", exact_text: true).ancestor("section")
  end

  def within_stat_card(label, &)
    card = find("div.bg-gray-50 p.text-sm", text: label, exact_text: true).ancestor("div.bg-gray-50")
    within(card, &)
  end
end
