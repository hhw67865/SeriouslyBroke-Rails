# frozen_string_literal: true

require "rails_helper"

# "THIS PERIOD" — one block per category, one row per rule. The grid is biweekly anchored
# 2026-02-06, so the period containing Sep 9 is Sep 4 – Sep 17 and the next opens Sep 18.
RSpec.describe "Home this period", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }

  before do
    create(:account, user: user, name: "Checking", opening_balance: 5_000)
    sign_in user, scope: :user
  end

  def category(name, **attributes) = create(:category, user: user, name: name, **attributes)

  def rule_for(name, rate:, **attributes)
    create(
      :rule,
      :rate,
      amount: rate,
      starts_on: Date.new(2026, 1, 1),
      category: category(name),
      **attributes
    )
  end

  def bill(name, amount:, due:)
    create(
      :rule,
      :bill,
      amount: amount,
      anchor_date: due,
      starts_on: Date.new(2026, 8, 1),
      category: category(name)
    )
  end

  def spend(category, amount, on: today) = create(:entry, item: create(:item, category: category), amount: amount, date: on)

  def read_home = travel_to(today) { visit root_path }

  def block(name) = find("[data-category-block='#{name}']")

  # A RATE RULE'S ROW: what it has of what it allows, what shape it is, and the day it starts again.
  it "says what a rate rule has, what shape it is and when it resets", :aggregate_failures do
    rule = rule_for("Groceries", rate: 400)
    spend(rule.category, 300)

    read_home

    within(block("Groceries")) do
      expect(page).to have_css("[data-rule-figure]", text: "$300.00 of $400.00")
      expect(page).to have_css("[data-rule-shape]", text: "usage · a period")
      expect(page).to have_css("[data-rule-when]", text: "resets Sep 18")
      expect(page).to have_css("[data-rule-bar='75'][data-rule-bar-state='normal']", visible: :all)
      expect(page).to have_css("[data-block-claimed]", text: "$100.00 claimed")
    end
  end

  # A DATED RULE'S ROW: a running total against its target, and the day it is needed on.
  it "says what a dated rule has built up and when it is due", :aggregate_failures do
    bill("Dentist", amount: 300, due: Date.new(2026, 9, 12))

    read_home

    within(block("Dentist")) do
      expect(page).to have_css("[data-rule-figure]", text: "$300.00 of $300.00")
      expect(page).to have_css("[data-rule-shape]", text: "bill · once, Sep 12")
      expect(page).to have_css("[data-rule-when]", text: "Sep 12 · ready")
    end
  end

  # AN ALLOWANCE THAT KEEPS WHAT IT DOESN'T SPEND: no target, so no "of", no bar, and the one thing
  # left to say is what it adds each period.
  it "says a fund's running total and what it adds, with no bar", :aggregate_failures do
    create(:rule, :keeps_unspent, amount: 60, starts_on: Date.new(2026, 8, 1), category: category("Books"))

    read_home

    within(block("Books")) do
      expect(page).to have_css("[data-rule-figure]", text: "built up $240.00")
      expect(page).to have_css("[data-rule-shape]", text: "usage · a period, keeps")
      expect(page).to have_css("[data-rule-when]", text: "+$60.00 a period")
      expect(page).to have_no_css("[data-rule-bar]", visible: :all)
    end
  end

  # SPENDING PAST THE RATE tints the block's header and reddens the figure — the section's own
  # signal, inches from the strip that says the same thing in a sentence.
  it "tints a block whose rule has been overspent", :aggregate_failures do
    rule = rule_for("Groceries", rate: 400)
    spend(rule.category, 450)

    read_home

    expect(block("Groceries")).to have_css("[data-block-header].bg-status-danger-light")
    expect(block("Groceries")).to have_css("[data-rule-figure].text-status-danger")
  end

  # THE BLOCKS ARE IN GIVE-WAY ORDER, AND IT IS THE ONLY SORT ON THE SCREEN: a choice gives way
  # before a bill whatever the categories' priorities say.
  it "puts the block that gives way first at the top", :aggregate_failures do
    rule_for("Rent", rate: 900, rule_type: :bill)
    rule_for("Fun", rate: 300, rule_type: :choice)

    read_home

    expect(page.all("[data-category-block]").pluck("data-category-block")).to eq(["Fun", "Rent"])
    expect(page).to have_css("[data-this-period-claimed]", text: "$1,200.00 claimed")
  end

  # A category no rule claims, with spending this period: the fact, no bar, no pressure.
  it "states spending in a category no rule claims", :aggregate_failures do
    spend(category("Repairs"), 42, on: Date.new(2026, 9, 6))

    read_home

    expect(page).to have_css("[data-unbudgeted-row='Repairs']", text: "spent $42.00")
    expect(page).to have_no_css("[data-unbudgeted-row='Repairs'] [data-rule-bar]", visible: :all)
  end

  # Said plainly rather than left as an empty card: a blank panel on a money screen reads as
  # something that failed to load.
  it "says so when nothing is budgeted and nothing has been spent" do
    read_home

    expect(page).to have_content("Nothing is budgeted yet, and nothing has been spent this period.")
  end

  # THE FIGURE OPENS ONTO THE ENTRIES BEHIND IT, same as on the Budget page. The click is a second
  # request, so the whole example travels rather than just the visit.
  it "opens the entries behind a rule's figure", :aggregate_failures, :js do
    rule = rule_for("Groceries", rate: 400)
    spend(rule.category, 300)

    travel_to(today) do
      visit root_path
      within(block("Groceries")) { find("[data-rule-figure]").click }
      # A leaked narrow viewport from an earlier `:js` example can leave the frame below the fold,
      # where the lazy load never fires — scroll it into view rather than assume a tall window.
      page.scroll_to(find("turbo-frame", visible: :all))

      expect(page).to have_content("Total")
      expect(page).to have_content("$300.00")
    end
  end

  it "carries the kinds legend and a savings block", :aggregate_failures do
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
    read_home

    expect(page).to have_css("[data-kinds-legend]", text: "gives way first → Choice Usage Savings Bill")
    within("[data-savings-block='Emergency']") do
      expect(page).to have_css("[data-block-owed]", text: "$200.00 owed")
      expect(page).to have_css("[data-savings-figure]", text: "$200.00 owed this period")
      expect(page).to have_button("Transfer $200.00")
      expect(page).to have_css("[data-adjust='Emergency']")
    end
  end

  it "renders the frame's src for a ruled block" do
    rule = rule_for("Groceries", rate: 400)

    read_home

    within(block("Groceries")) do
      expect(find("turbo-frame", visible: :all)[:src]).to eq(spending_rule_path(rule))
    end
  end
end
