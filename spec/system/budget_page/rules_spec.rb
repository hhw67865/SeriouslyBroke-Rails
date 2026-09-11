# frozen_string_literal: true

require "rails_helper"

# The open panel's rules table. Each row is a ClaimLine — Home's own row — rendered through the same
# three readers, so one rule reads the same on both screens: `shape_words`, `figure_words` and
# `when_words`.
#
# The grid is biweekly anchored 2026-02-06, so Sep 9 sits in Sep 4 – Sep 17 and the next period
# opens Sep 18.
RSpec.describe "Budget page rules", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }

  around { |example| travel_to(today) { example.run } }

  before do
    create(:account, user: user, name: "Checking", opening_balance: 5_000)
    sign_in user, scope: :user
  end

  def category(name) = create(:category, user: user, name: name)

  def rate_rule(owner) = create(:rule, :rate, category: owner, amount: 400, starts_on: Date.new(2026, 1, 1))

  # A $50 choice on one of the category's items — the lane a second rule on one category needs.
  def lane_rule(owner, item_name)
    create(
      :rule,
      :rate,
      :choice,
      category: owner,
      amount: 50,
      starts_on: Date.new(2026, 1, 1),
      item: create(:item, category: owner, name: item_name)
    )
  end

  # $900 wanted on Oct 16, counted from the day this period opened: four periods to save it in.
  def one_off_bill(owner)
    create(
      :rule,
      :bill,
      category: owner,
      amount: 900,
      anchor_date: Date.new(2026, 10, 16),
      starts_on: Date.new(2026, 9, 4)
    )
  end

  # Started after the April due date, so October 1 is the first due date in its window.
  def rolling_bill(owner)
    create(
      :rule,
      :bill,
      category: owner,
      amount: 600,
      anchor_date: Date.new(2026, 10, 1),
      interval_months: 6,
      starts_on: Date.new(2026, 4, 2)
    )
  end

  # $60 a period since the period before this one: two periods in, nothing spent, $120 built up.
  def fund(owner) = create(:rule, :keeps_unspent, category: owner, amount: 60, starts_on: Date.new(2026, 8, 21))

  # $100 a period from Jul 24: Jul 24, Aug 7, Aug 21, Sep 4 → 100, 200, 250 (capped), 250 — full.
  def capped_fund(owner) = create(:rule, :keeps_unspent, category: owner, amount: 100, cap: 250, starts_on: Date.new(2026, 7, 24))

  def spend(owner, amount) = create(:entry, item: create(:item, category: owner), amount: amount, date: today)

  def open_panel(owner) = visit budget_page_path(open: owner.id)

  def rule_row(name) = find("[data-rule='#{name}']")

  # A rate rule: what it has of what it allows, what shape it is, and the day it starts again.
  it "says what a rate rule has, what shape it is and when it resets", :aggregate_failures do
    rate_rule(groceries)
    spend(groceries, 300)

    open_panel(groceries)

    expect(rule_row("Groceries")).to have_content("All of Groceries")
    expect(rule_row("Groceries")).to have_css("[data-rule-figure]", text: "$400.00")
    expect(rule_row("Groceries")).to have_css("[data-rule-steady]", text: "same every period")
    expect(rule_row("Groceries")).to have_css("[data-rule-shape]", text: "usage · a period")
    expect(rule_row("Groceries")).to have_css("[data-rule-when]", text: "resets Sep 18 · $300.00 of $400.00")
    expect(rule_row("Groceries")).to have_css("[data-rule-bar='75'][data-rule-bar-state='normal']")
  end

  # A one-off bill: what it takes this period toward the money it needs, and the day it is wanted.
  it "says what a one-off bill has built up and when it is due", :aggregate_failures do
    rent = category("Rent")
    one_off_bill(rent)

    open_panel(rent)

    expect(rule_row("Rent")).to have_css("[data-rule-shape]", text: "bill · once, Oct 16")
    expect(rule_row("Rent")).to have_css("[data-rule-figure]", text: "$225.00")
    expect(rule_row("Rent")).to have_css("[data-rule-steady]", text: "until Oct 16")
    expect(rule_row("Rent")).to have_css("[data-rule-when]", text: "Oct 16")
    expect(rule_row("Rent")).to have_css("[data-rule-when]", text: "$225.00 of $900.00")
  end

  # A rolling bill names its interval rather than a single day, because the day moves with the
  # cycle — and, started well before today, it is still catching up: this period takes less than
  # its steady ask.
  it "says a rolling bill's interval, and what it takes while catching up", :aggregate_failures do
    insurance = category("Insurance")
    rolling_bill(insurance)

    open_panel(insurance)

    expect(rule_row("Insurance")).to have_css("[data-rule-shape]", text: "bill · every 6 months")
    expect(rule_row("Insurance")).to have_css("[data-rule-when]", text: "Oct 1")
    expect(rule_row("Insurance")).to have_css("[data-rule-figure]", text: "$42.86")
    expect(rule_row("Insurance")).to have_css("[data-rule-steady]", text: "$46.15 a period once caught up")
  end

  # A fund aims at nothing, so its sentence stops early and names its noun instead — and there is no
  # bar, because there is no figure for the fill to be a fraction of.
  it "says what a fund has built up and draws it no bar", :aggregate_failures do
    pets = category("Pet Care")
    fund(pets)

    open_panel(pets)

    expect(rule_row("Pet Care")).to have_css("[data-rule-shape]", text: "usage · a period, keeps")
    expect(rule_row("Pet Care")).to have_css("[data-rule-figure]", text: "$60.00")
    expect(rule_row("Pet Care")).to have_css("[data-rule-steady]", text: "same every period")
    expect(rule_row("Pet Care")).to have_css("[data-rule-when]", text: "+$60.00 a period · built up $120.00")
    expect(rule_row("Pet Care")).to have_no_css("[data-rule-bar]")
  end

  # A capped fund that has reached its cap asks nothing and says so, in both the steady line and the
  # When cell — and its bar, unlike an uncapped fund's, has a target to draw against.
  it "says a full capped fund is full, and draws its bar against the cap", :aggregate_failures do
    pantry = category("Pantry")
    capped_fund(pantry)

    open_panel(pantry)

    expect(rule_row("Pantry")).to have_css("[data-rule-steady]", text: "full at $250.00")
    expect(rule_row("Pantry")).to have_css("[data-rule-when]", text: "full at $250.00")
    expect(rule_row("Pantry")).to have_css("[data-rule-when]", text: "built up $250.00 of $250.00")
    expect(rule_row("Pantry")).to have_css("[data-rule-bar='100'][data-rule-bar-state='full']")
  end

  # An item-backed rule names its item; the item-less one beside it is the lane no other rule pays.
  # The row hook is the name a selector can tell two rows apart by, and the visible name is the
  # lane's own word.
  it "names an item's rule by the item and the catch-all by its lane", :aggregate_failures do
    rate_rule(groceries)
    lane_rule(groceries, "Wine")

    open_panel(groceries)

    expect(rule_row("Wine")).to have_content("Wine")
    expect(rule_row("Groceries")).to have_content("Everything else in Groceries")
  end

  # Spending past what the rule had is the news, so the When cell wears the danger colour — and the
  # category's own takes-this-period figure goes red with it.
  it "marks a rule that has been overspent", :aggregate_failures do
    rate_rule(groceries)
    spend(groceries, 450)

    open_panel(groceries)

    expect(rule_row("Groceries")).to have_css("[data-rule-bar-state='over']")
    expect(rule_row("Groceries").find("[data-rule-when]")[:class]).to include("text-status-danger")
    expect(find("[data-category-row='Groceries'] [data-category-takes]")[:class]).to include("text-status-danger")
  end

  # The door onto a rule's declaration is inside the panel the rule is listed in.
  it "opens the rule's own form from the row it is on", :aggregate_failures do
    rate_rule(groceries)

    open_panel(groceries)
    within(rule_row("Groceries")) { click_link "Edit" }

    expect(page).to have_content("edit rule")
    expect(page).to have_field("Amount", with: "400.0")
  end

  it "opens a new rule form on the category it was clicked in" do
    rate_rule(groceries)

    open_panel(groceries)
    click_link "+ New rule for Groceries"

    expect(page).to have_content("New rule for Groceries")
  end

  # The other door on the row: the rule goes and the row goes with it. The confirm is a data
  # attribute, so Rack::Test submits the `button_to` form without one.
  it "deletes a rule from its own row", :aggregate_failures do
    rate_rule(groceries)

    open_panel(groceries)
    within(rule_row("Groceries")) { click_button "Delete" }

    expect(page).to have_content("Rule deleted.")
    expect(page).to have_no_css("[data-rule='Groceries']")
  end
end
