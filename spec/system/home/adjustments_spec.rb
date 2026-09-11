# frozen_string_literal: true

require "rails_helper"

# The adjust panel: one rule's period, changed by a signed amount on a date, or skipped. Each of the
# buttons writes the same (rule, date, signed amount) row, and the word "adjustment" appears nowhere
# on the screen — it is the mechanism's name, not the act's.
#
# The vocabulary splits on the shape: a rate rule's allowance is TOPPED UP or REDUCED for this
# period; an accruing rule's money is SET ASIDE or TAKEN BACK.
#
# `:js` throughout, and the reason is the `<details>`: the panel is opened by the browser's own
# disclosure, which Rack::Test does not have — its fields are invisible until a real summary is
# clicked. Everything under the summary is a plain form to the same endpoint.
RSpec.describe "Home adjustments", :js, type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }

  around { |example| travel_to(today) { example.run } }

  before do
    create(:account, user: user, name: "Checking", opening_balance: 5_000)
    sign_in user, scope: :user
  end

  def rate_rule = create(:rule, :rate, category: groceries, amount: 400, starts_on: Date.new(2026, 1, 1))

  def dated_rule
    create(
      :rule,
      :bill,
      category: groceries,
      amount: 900,
      anchor_date: Date.new(2026, 10, 16),
      starts_on: Date.new(2026, 9, 4)
    )
  end

  def open_panel = visit root_path

  def open_adjust = find("[data-adjust='Groceries'] summary").click

  def adjust(amount, button)
    open_adjust
    within("[data-adjust='Groceries']") do
      fill_in "How much", with: amount
      click_button button
    end
  end

  def claimed = find("[data-category-block='Groceries'] [data-block-claimed]")

  # Both directions on the allowance's own words, and the claim moves with them: $400 topped up by
  # $50 claims $450, and reduced by $50 claims $400 again.
  it "tops up and reduces an allowance in the period's own words", :aggregate_failures do
    rate_rule

    open_panel
    adjust("50", "Top up this period")

    expect(page).to have_content("Topped up Groceries by $50.00 this period.")
    expect(claimed).to have_content("$450.00 claimed")

    adjust("50", "Reduce this period")

    expect(page).to have_content("Reduced Groceries by $50.00 this period.")
    expect(claimed).to have_content("$400.00 claimed")
  end

  # An accruing rule takes the other vocabulary, because its money is set aside toward a day rather
  # than arriving and being spent within the period.
  it "sets aside and takes back on a rule that is saving toward a day", :aggregate_failures do
    dated_rule

    open_panel
    adjust("100", "Set aside")

    expect(page).to have_content("Set aside $100.00 for Groceries.")

    adjust("100", "Take back")

    expect(page).to have_content("Took back $100.00 from Groceries.")
  end

  # A skip carries no figure and no date: the button names what the server will write, which is
  # −accrued rather than −planned, and the row is left accruing nothing this period.
  it "skips a period on the rule that is accruing something", :aggregate_failures do
    dated_rule

    open_panel
    open_adjust

    expect(find("[data-adjust-skip]")).to have_content("Skip this period (−$225.00)")
    find("[data-adjust-skip]").click

    expect(page).to have_content("Skipped this period for Groceries")
    expect(page).to have_css("[data-change-amount]", text: "-$225.00")
  end

  # Every change is listed under the row it was made on, with the door back out — the claim above
  # already counts each one, and the list is what makes that figure explicable.
  it "lists what was done to the period and takes it back", :aggregate_failures do
    rate_rule

    open_panel
    adjust("50", "Top up this period")

    expect(page).to have_css("[data-change-amount]", text: "$50.00")
    within("[data-rule-changes]") { click_button "Remove" }

    expect(page).to have_content("Removed the $50.00 top-up on Groceries.")
    expect(claimed).to have_content("$400.00 claimed")
  end

  # The user meets the bound before the refusal rather than after it: the field carries the row's own
  # countable span, off the same reader AdjustmentForm refuses by, so the control cannot offer a day
  # the door then rejects. The refusal itself is pinned in `spec/requests/adjustments_spec.rb`, where
  # a request can carry a date this field will not.
  it "offers only the days the rule counts", :aggregate_failures do
    rule = rate_rule

    open_panel
    open_adjust

    field = find("#adjust-date-#{rule.id}")
    expect(field[:min]).to eq("2026-09-04")
    expect(field[:max]).to eq("2026-09-09")
    expect(find("[data-adjust-hint]")).to have_content("This period only, up to today.")
  end

  # A savings block's Adjust panel writes through the same door, and carries `return=home` so a
  # refusal or a skip lands back on Home rather than on the Savings page.
  it "skips a savings block's period from Home and returns to Home with the notice", :aggregate_failures do
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))

    open_panel
    within("[data-savings-block='Emergency']") do
      find("[data-adjust='Emergency'] summary").click
      click_button "Skip this period (−$200.00)"
    end

    expect(page).to have_current_path(root_path, ignore_query: true)
    expect(page).to have_content("Skipped this period for Emergency — $200.00 less owed.")
    expect(page).to have_css("#savings-#{emergency.id}")
  end
end
