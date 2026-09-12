# frozen_string_literal: true

require "rails_helper"

# The three tiles: what the rules need of a period, what the entries say comes in, and the
# subtraction. Every figure is `ask` — a constant of the rules and the grid — never Σ
# claims, which is this afternoon's answer and would report a different split tomorrow with nothing
# edited.
#
# The grid is biweekly anchored 2026-02-06, so Sep 9 sits in Sep 4 – Sep 17 and the two complete
# periods behind it are Aug 7 – Aug 20 and Aug 21 – Sep 3. Income is measured over those two, which
# is why every fixture that wants a typical income earns twice.
RSpec.describe "Budget page tiles", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:salary) { create(:category, :income, user: user, name: "Salary") }

  around { |example| travel_to(today) { example.run } }

  before do
    create(:account, user: user, name: "Checking", opening_balance: 5_000)
    sign_in user, scope: :user
  end

  def rule_on(name, amount:, type: :usage, priority: 0)
    create(
      :rule,
      :rate,
      rule_type: type,
      amount: amount,
      starts_on: Date.new(2026, 1, 1),
      category: create(:category, user: user, name: name, priority: priority)
    )
  end

  def a_period_of_income(amount)
    [Date.new(2026, 8, 7), Date.new(2026, 8, 25)].each do |on|
      create(:entry, item: create(:item, category: salary), amount: amount, date: on)
    end
  end

  # A rolling bill still catching up: it plans more this period than its steady ask.
  def catching_up_bill
    create(
      :rule,
      :bill,
      amount: 1_200,
      anchor_date: Date.new(2027, 2, 11),
      interval_months: 12,
      starts_on: today,
      category: create(:category, user: user, name: "Insurance")
    )
  end

  def tile(name) = find("[data-tile='#{name}']")

  # $900 of bills and $400 of usage: the tile's figure is the sum and the bands under it are the
  # split, off one reader, so the bands cannot fail to add up to the figure above them.
  it "adds up what the rules need and splits it by type", :aggregate_failures do
    rule_on("Rent", amount: 900, type: :bill)
    rule_on("Groceries", amount: 400, type: :usage)

    visit budget_page_path

    within(tile("where")) do
      expect(page).to have_css("[data-tile-figure]", text: "$1,300.00")
      expect(page).to have_css("[data-type-total='bill']", text: "$900.00")
      expect(page).to have_css("[data-type-total='usage']", text: "$400.00")
      # A type with no rules is absent rather than printed as $0.00 — a figure that is true and
      # reports nothing, on a line whose whole job is the split.
      expect(page).to have_no_css("[data-type-total='choice']")
    end
  end

  it "reads the income it measured, and says the budget fits", :aggregate_failures do
    rule_on("Rent", amount: 900, type: :bill)
    a_period_of_income(2_000)

    visit budget_page_path

    expect(tile("income")).to have_css("[data-tile-figure]", text: "$2,000.00")
    expect(tile("income")).to have_css("[data-tile-cadence]", text: "Biweekly")
    expect(tile("leftover")).to have_css("[data-tile-figure]", text: "$1,100.00")
    expect(tile("leftover")).to have_css("[data-tile-verdict]", text: "Your savings and your budget fit what you bring in.")
    expect(tile("leftover")).to have_no_link("What could you cut?")
  end

  # Not enough history is not zero: zero would be a claim about the user's income, and this is the
  # absence of one. The verdict tile waits with it rather than calling an unmeasured budget broken.
  it "says so rather than guessing before a period has completed", :aggregate_failures do
    rule_on("Rent", amount: 900, type: :bill)

    visit budget_page_path

    expect(tile("income")).to have_css("[data-tile-figure]", text: "not enough history yet")
    within(tile("leftover")) do
      expect(page).to have_content("a full one has passed")
      expect(page).to have_no_css("[data-tile-verdict]")
    end
  end

  # The door onto the sacrifice page is on the third tile, and `sacrifice_path` refuses in exactly
  # the two states the button is not shown in — so the route's gate and this one are one condition
  # read twice.
  it "opens the door to the cuts when the rules ask for more than comes in", :aggregate_failures do
    rule_on("Rent", amount: 3_000, type: :bill)
    a_period_of_income(2_000)

    visit budget_page_path

    within(tile("leftover")) do
      expect(page).to have_css("[data-tile-figure]", text: "-$1,000.00")
      expect(page).to have_css("[data-tile-verdict]", text: "Your savings and your budget ask for more than you bring in.")
    end

    click_link "What could you cut?"

    expect(page).to have_content("underwater every period")
  end

  it "puts savings first in the bar and in the split line", :aggregate_failures do
    a_period_of_income(2_000)
    rule_on("Groceries", amount: 400)
    create(:savings_target, account: create(:account, user: user, name: "Emergency"), amount: 100, starts_on: Date.new(2026, 9, 4))

    visit budget_page_path

    within(tile("where")) do
      expect(page).to have_css("[data-tile-figure]", text: "$500.00")
      expect(all("[data-type-band]").first["data-type-band"]).to eq("savings")
      expect(page).to have_css("[data-type-total='savings']", text: "$100.00")
    end
    expect(tile("leftover")).to have_css("[data-tile-figure]", text: "$1,500.00")
  end

  # A rolling bill still catching up plans more this period than its steady ask, so the tiles say
  # both: the "this period" figure up top, the steady one once caught up beneath it, and what
  # leftover looks like this period rather than only once every bill is caught up.
  it "shows the steady figure and this period's leftover for a rule still catching up", :aggregate_failures do
    catching_up_bill
    a_period_of_income(2_000)

    visit budget_page_path

    within(tile("where")) do
      expect(page).to have_css("[data-tile-figure]", text: "$100.00 this period")
      expect(page).to have_css("[data-tile-split]", text: "once caught up")
      expect(page).to have_css("[data-tile-steady]", text: "$46.15 a period once every bill is caught up")
    end
    expect(tile("leftover")).to have_css("[data-tile-leftover-now]", text: "This period leaves $1,900.00")
  end

  it "invites a user who has said nothing to set a period", :aggregate_failures do
    undeclared = create(:user)
    create(:account, user: undeclared)
    sign_in undeclared, scope: :user

    visit budget_page_path

    expect(tile("income")).to have_css("[data-tile-figure]", text: "Not said yet")

    click_link "Set your period"

    expect(page).to have_current_path(budget_income_path)
  end
end
