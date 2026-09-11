# frozen_string_literal: true

require "rails_helper"

# THE FOUR TILES — Home's whole first answer: free to spend, what is in checking and what was spent
# this period, claimed with its budget/savings split, and savings with what is owed. The arithmetic
# behind the figures is `spec/presenters/home_presenter_spec.rb`'s; what is measured here is what
# the tiles say.
RSpec.describe "Home tiles", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }

  # Checking is created first, so it is the account that becomes main.
  before do
    create(:account, user: user, name: "Checking", opening_balance: 1_000)
    sign_in user, scope: :user
  end

  def rule_for(name, rate:)
    create(
      :rule,
      :rate,
      amount: rate,
      category: create(:category, user: user, name: name),
      starts_on: Date.new(2026, 1, 1)
    )
  end

  def read_home = travel_to(today) { visit root_path }

  # One four-figure page seeded once, so the example itself stays a list of what each tile says
  # rather than the fixtures that produce it.
  def seed_four_tiles!
    rule_for("Groceries", rate: 400)
    emergency = create(:account, user: user, name: "Emergency", opening_balance: 500)
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
    create(:entry, item: create(:item, category: create(:category, user: user, name: "Fuel")), amount: 25, date: today)
  end

  def expect_free_tile
    expect(page).to have_css("[data-tile='free'] [data-free]", text: "$375.00")
    expect(page).to have_css("[data-tile='free']", text: "after everything claimed is set aside")
  end

  def expect_checking_tile
    expect(page).to have_css("[data-in-checking]", text: "$975.00")
    expect(page).to have_css("[data-spent-this-period]", text: "spent $25.00 this period")
  end

  def expect_claimed_tile
    expect(page).to have_css("[data-claimed]", text: "$600.00")
    expect(page).to have_css("[data-claimed-split]", text: "Budget $400.00 · Savings $200.00")
  end

  def expect_savings_tile
    expect(page).to have_css("[data-savings-total]", text: "$500.00")
    expect(page).to have_css("[data-tile='savings']", text: "1 account · owed $200.00")
  end

  it "shows the four tiles with their sublines", :aggregate_failures do
    seed_four_tiles!

    read_home

    expect(page).to have_css("h1", text: "Wednesday, September 9")
    expect(page).to have_content("Day 6 of 14 in this period · next payday Sep 18")
    expect_free_tile
    expect_checking_tile
    expect_claimed_tile
    expect_savings_tile
    # No per-day pace figure anywhere on the tiles themselves — the Adjust panels below them say
    # "a day" in an unrelated sense ("Today unless you pick a day"), so the check is scoped here.
    within("[data-tiles]") { expect(page).to have_no_content("a day") }
  end

  # A user with no cadence has no period, so `spent this period` would state one as fact — the
  # header already says there is none.
  it "has no spent-this-period line for a user who has declared no cadence", :aggregate_failures do
    undeclared = create(:user)
    create(:account, user: undeclared, name: "Checking", opening_balance: 1_000)
    sign_in undeclared, scope: :user

    visit root_path

    expect(page).to have_content("No period set yet")
    expect(page).to have_no_css("[data-spent-this-period]")
  end
end
