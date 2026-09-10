# frozen_string_literal: true

require "rails_helper"

# The All tab: income, the two lanes it left through, and what is left over. Both directions are
# kept throughout — the bar's segments are asserted present with their figures, and the retired
# savings-entry vocabulary is asserted absent.
RSpec.describe "Dashboard Index - All Tab", type: :system do
  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  describe "default tab", :aggregate_failures do
    before { visit reports_path }

    it "defaults to All tab" do
      all_link = find("nav[aria-label='Tabs'] a", text: "All")
      expect(all_link[:class]).to include("border-brand")
    end
  end

  describe "with financial data", :aggregate_failures do
    before do
      seed_mixed_financial_data
      visit reports_path
    end

    it "shows the Money Flow section with income earned" do
      expect(page).to have_content("Money Flow")
      expect(page).to have_content("$3,000.00 earned")
    end

    it "shows the two health indicators and none of the retired ones" do
      expect(page).to have_content("Expense Ratio")
      expect(page).to have_content("Spent")
      expect(page).to have_no_content("Net Savings")
      expect(page).to have_no_content("Savings Rate")
      expect(page).to have_no_content("% used")
    end

    # The band lists rules saving toward a day, and its heading is "Savings": "Savings Goals" named
    # a kind of category, and the shape is what says a thing is being saved for now.
    it "shows the savings strip with the fund's card", :aggregate_failures do
      expect(page).to have_content("Savings")
      expect(page).to have_no_content("Savings Goals")
      expect(Rule.saving_toward_a_date.map { |rule| rule.category.name }).to include("Emergency Fund")
      within("[data-savings-strip]") { expect(page).to have_content("Emergency Fund") }
    end

    it "shows top spending categories" do
      expect(page).to have_content("Top Spending")
      expect(page).to have_link("Groceries")
    end
  end

  # Income $3,000; $400 spent on a category no rule speaks for (Groceries), $200 on one a rule
  # claims money for (Emergency Fund). Left over = $3,000 − $600 = $2,400.
  describe "the money flow bar — number accuracy", :aggregate_failures do
    before do
      seed_mixed_financial_data
      visit reports_path
    end

    it "shows income earned and what is left over" do
      within money_flow_section do
        expect(page).to have_content("$3,000.00 earned")
        expect(page).to have_content("$2,400.00 left over")
      end
    end

    # The casing is load-bearing: these two labels name the same two lanes the Expenses tab heads
    # its sections with, and `have_content` is a case-sensitive substring match.
    it "shows three legend amounts: Unbudgeted, Envelope, left over" do
      within money_flow_section do
        expect(page).to have_content("Unbudgeted $400.00")
        expect(page).to have_content("Out of an Envelope $200.00")
        expect(page).to have_content("Left over $2,400.00")
      end
    end

    # The other direction: the savings-entry vocabulary is gone from the page rather than merely
    # unreached by the fixture.
    it "names no savings contribution, source or net anywhere on the tab" do
      expect(page).to have_no_content("Savings Contrib")
      expect(page).to have_no_content("Expense Sources")
      expect(page).to have_no_content("came from savings")
      expect(page).to have_no_content("From Savings")
      expect(page).to have_no_content("From Income")
    end

    it "shows spent and the expense ratio against income (all expenses)" do
      within_stat_card("Spent") { expect(page).to have_content("$600.00") }
      within_stat_card("Expense Ratio") { expect(page).to have_content("20.0%") }
    end
  end

  describe "the money flow bar — no income", :aggregate_failures do
    before do
      expense_cat = create(:category, :expense, user: user, name: "Groceries")
      create(:entry, item: create(:item, category: expense_cat, name: "Food"), amount: 200, date: base_date + 2.days)
      visit reports_path
    end

    it "says so, and prints what was spent instead" do
      within money_flow_section do
        expect(page).to have_content("No income recorded this month")
        expect(page).to have_content("Spent: $200.00")
      end
    end
  end

  describe "top spending order", :aggregate_failures do
    before do
      small_cat = create(:category, :expense, user: user, name: "Coffee")
      large_cat = create(:category, :expense, user: user, name: "Rent")
      medium_cat = create(:category, :expense, user: user, name: "Groceries")

      create(:entry, item: create(:item, category: small_cat, name: "Latte"), amount: 50, date: base_date + 1.day)
      create(:entry, item: create(:item, category: large_cat, name: "Monthly"), amount: 2000, date: base_date + 1.day)
      create(:entry, item: create(:item, category: medium_cat, name: "Food"), amount: 400, date: base_date + 1.day)
      visit reports_path
    end

    it "orders top spending by amount descending" do
      within top_spending_section do
        names = all("a").map(&:text)
        expect(names).to eq(["Rent", "Groceries", "Coffee"])
      end
    end
  end

  private

  # The two lanes are `Category#ruled?`'s: nothing claims Groceries' spending, while Emergency Fund
  # is a goal — an item-less rule with a date on it — so its $200 comes out of what that rule
  # claims. The goal's own date is far out so no figure on this tab moves with the day the suite
  # runs; it is here to make the "no savings vocabulary" negative a real claim and to put a card on
  # the strip.
  def seed_mixed_financial_data
    goal = create(:category, :expense, user: user, name: "Emergency Fund")
    saving_toward_a_date(goal, 5_000)
    expense_cat = create(:category, :expense, user: user, name: "Groceries")

    create_entry_for(create(:category, :income, user: user, name: "Salary"), "Paycheck", 3000.00, 1)
    create_entry_for(expense_cat, "Weekly Shopping", 400.00, 2)
    create_entry_for(goal, "Mechanic", 200.00, 3)
  end

  def saving_toward_a_date(category, target)
    create(
      :rule,
      category: category,
      item: nil,
      amount: target,
      starts_on: base_date,
      anchor_date: Date.current + 10.years,
      interval_months: nil
    )
  end

  def create_entry_for(category, item_name, amount, day_offset)
    item = create(:item, category: category, name: item_name)
    create(:entry, item: item, amount: amount, date: base_date + day_offset.days)
  end

  def money_flow_section
    find("h4", text: "Where your income went").ancestor("div.bg-gray-50")
  end

  def top_spending_section
    find("h3", text: "Top Spending").ancestor("div.mb-8")
  end

  def within_stat_card(label, &)
    card = find("div.bg-gray-50 p.text-sm", text: label, exact_text: true).ancestor("div.bg-gray-50")
    within(card, &)
  end
end
