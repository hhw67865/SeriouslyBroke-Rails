# frozen_string_literal: true

require "rails_helper"

# THE ALL TAB AFTER DECISION 6 (plan 3, task 4).
#
# WHAT WENT, AND WHAT THE EXAMPLES THAT READ IT WERE PINNING:
#
# * the "Expense Sources" bar — "$200.00 came from savings", "From Income $400.00 / From Savings
#   $200.00". Three examples. The split it drew is the available/envelope split, which the one
#   remaining bar now draws under names that are true; a second bar of the same two figures was
#   the duplicate decision 6 forbids, and "came from savings" was the untruth itself.
# * the "Savings Contrib" segment — one example's legend assertion. It summed savings-typed
#   ENTRIES, of which there are none.
# * the "Net Savings" stat card — two examples, one of them a whole `describe` planting a savings
#   category and an expense category on the same pool to drive the figure negative. Contributions
#   are `AccountMovement`s now; contributions-minus-withdrawals over entries is not a figure this
#   data supports.
# * the "Budget Used" card — already gone with the cap in Task 3, and its `have_no_content("%
#   used")` negative retires with the reader.
#
# WHAT REPLACES THEM is the same money read honestly: income, the two lanes it left through, and
# what is left over. Both directions are kept — the bar's segments are asserted present with their
# figures AND the deleted vocabulary is asserted absent.
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

    it "shows the savings strip with the goal's card" do
      expect(page).to have_content("Savings Goals")
      within("[data-savings-strip]") { expect(page).to have_content("Emergency Fund") }
    end

    it "shows top spending categories" do
      expect(page).to have_content("Top Spending")
      expect(page).to have_link("Groceries")
    end
  end

  # Income $3,000; $400 spent out of what is available (Groceries holds nothing), $200 spent out of
  # a category that holds money (Emergency Fund). Left over = $3,000 − $600 = $2,400.
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

    # THE CASING IS LOAD-BEARING (FINAL review — M-2): these two labels name the same two lanes the
    # Expenses tab heads its sections with, and they must read in the same register on both screens.
    # `have_content` is a case-SENSITIVE substring match, so these three lines are what holds it.
    #
    # THE FIRST LABEL IS "Unbudgeted" (computed-claims spec §§5-6, §3.4). It read "Out of Available",
    # and available is deleted with the movements — free money is `ClaimLedger#free`, derived, not a
    # pot that spending comes out of. What the band counts is unchanged: spending on a category no
    # rule counts against, which is §3.4's own "unbudgeted".
    it "shows three legend amounts: Unbudgeted, Envelope, left over" do
      within money_flow_section do
        expect(page).to have_content("Unbudgeted $400.00")
        expect(page).to have_content("Out of an Envelope $200.00")
        expect(page).to have_content("Left over $2,400.00")
      end
    end

    # The other direction: the savings-entry vocabulary is gone from the page, not merely
    # unreached by the fixture above. A $500 savings entry is planted by the same fixture.
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

  # THE TWO LANES ARE `Category#holder?`'s (two-ledger spec §3, Task 7). `Groceries` holds nothing,
  # so nothing counts its spending against it; `Emergency Fund` is a goal — a category with a target,
  # counting its own spending from a year back — so its $200 comes off what it has.
  #
  # ** THE $500 IS A SET-ASIDE NOW, AND THE ARITHMETIC IS UNCHANGED TO THE CENT (computed-claims spec
  # §3.3). ** It was a $500 entry in a SAVINGS category until plan 3 task 5, an `AccountMovement`
  # until Task 7, and an `allocation` until this one — and the table it last lived in is dropped, so
  # it is the thing an allocation BECAME: a target-only rule (`amount: 0`, the shape §3.2 rules is
  # how "no rate" is spelled) carrying a `+$500` adjustment on the same day. §3.2's walk then reads
  # `clamp(min(0 + 500, 5,000) − 200, 0, 5,000)` = **$300**, which is exactly the balance the old
  # fixture's "$500 in, $200 spent" produced.
  #
  # It is deliberately still here: it is what makes the "no savings vocabulary" negative above a real
  # claim rather than an empty fixture, and it is what puts a card on the savings strip.
  def seed_mixed_financial_data
    goal = create(
      :category,
      :expense,
      user: user,
      name: "Emergency Fund",
      target_amount: 5000,
      funded_since: 1.year.ago.to_date
    )
    expense_cat = create(:category, :expense, user: user, name: "Groceries")

    create_entry_for(create(:category, :income, user: user, name: "Salary"), "Paycheck", 3000.00, 1)
    create_entry_for(expense_cat, "Weekly Shopping", 400.00, 2)
    create_entry_for(goal, "Mechanic", 200.00, 3)
    set_aside(goal, 500.00, on: base_date + 4.days)
  end

  # A GOAL FED BY HAND: the rule that makes the claim possible, and the dated delta that IS the
  # money. `basis: :per_period` with no anchor and no interval is the only shape `Budget` permits a
  # zero amount on (`#set_aside_only?`), which is §3.2's "no rate is spelled as zero".
  def set_aside(category, amount, on:)
    rule = create(
      :budget,
      category: category,
      item: nil,
      amount: 0,
      basis: :per_period,
      interval_months: nil,
      anchor_date: nil
    )
    create(:adjustment, rule: rule, amount: amount, date: on)
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
