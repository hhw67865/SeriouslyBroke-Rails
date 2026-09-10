# frozen_string_literal: true

require "rails_helper"

# THE MONEY ROW — Home's first two answers as three stat tiles: how much is in checking, how much of
# that is FREE, and what sits outside it. The arithmetic behind the figures is
# `spec/presenters/home_presenter_spec.rb`'s; what is measured here is what the tiles say.
RSpec.describe "Home money row", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }

  # Checking is created first, so it is the account that becomes main.
  before do
    create(:account, user: user, name: "Checking", opening_balance: 1_000)
    sign_in user, scope: :user
  end

  def envelope(name, rate:)
    create(
      :rule,
      :rate,
      amount: rate,
      category: create(:category, user: user, name: name),
      starts_on: Date.new(2026, 1, 1)
    )
  end

  def elsewhere(name, balance) = create(:account, user: user, name: name, opening_balance: balance)

  def spend(category, amount, on: today) = create(:entry, item: create(:item, category: category), amount: amount, date: on)

  def read_home = travel_to(today) { visit root_path }

  def tile_rect(name) = page.find("[data-tile='#{name}']").native.rect

  # THE MID-PERIOD BUDGETER: $1,000 in the bank, $400 the rules still ask for, $600 free. The three
  # figures are planted rather than derived, so a card that stopped subtracting would fail rather
  # than agree with itself.
  it "answers what is in checking and what of it is free", :aggregate_failures do
    envelope("Groceries", rate: 400)

    read_home

    expect(page).to have_css("[data-in-checking]", text: "$1,000.00")
    expect(page).to have_css("[data-free]", text: "$600.00")
    expect(page).to have_css("[data-free-subline]", text: "$400.00 claimed by your rules")
    # The words this row does not say. Case-insensitive, because a substring match would pass over
    # the app's own capitalised spelling — which is the spelling that could slip in.
    within("[data-money]") do
      expect(page).to have_no_content(/available|unclaimed|buffer|set aside|spoken for/i)
    end
  end

  # The bar is the subline as a picture: two segments of the pot off ONE figure, so they cannot add
  # up to something that is not the whole.
  it "draws what is claimed as a fraction of what is in checking" do
    envelope("Groceries", rate: 400)

    read_home

    expect(page).to have_css("[data-claimed-bar='40']")
  end

  it "names the accounts the rest of the money sits in", :aggregate_failures do
    elsewhere("Ally", 222_000)
    elsewhere("Vanguard", 544.87)

    read_home

    expect(page).to have_css("[data-other-accounts-total]", text: "$222,544.87")
    expect(page).to have_css("[data-account-chip='Ally']")
    expect(page).to have_css("[data-account-chip='Vanguard']")
    # Main is not a chip, for the reason its balance is not in the total: that figure is the tile
    # beside it, and naming it here would answer one question twice.
    expect(page).to have_no_css("[data-account-chip='Checking']")
  end

  # The other direction: one account is no tile at all. "$0.00 in 0 other accounts" would be the app
  # inventing an absence.
  it "leaves the tile off a screen with only one account" do
    read_home

    expect(page).to have_no_css("[data-other-accounts]")
  end

  # Both halves of the negative arm, on two fixtures: money elsewhere is a thing to move, and a
  # single-account user is simply past what they had.
  it "is honest when the rules ask for more than there is", :aggregate_failures do
    envelope("Rent", rate: 1_200)
    elsewhere("Ally", 500)

    read_home

    expect(page).to have_css("[data-free]", text: "-$200.00")
    expect(page).to have_css("[data-free].text-status-danger")
    expect(page).to have_css("[data-free-subline]", text: "Your rules claim $200.00 more than checking holds")
    expect(page).to have_css("[data-free-subline]", text: "Move some in from your other accounts")
  end

  it "tells a single-account user they have spent past what they had", :aggregate_failures do
    envelope("Rent", rate: 1_200)

    read_home

    expect(page).to have_css("[data-free]", text: "-$200.00")
    expect(page).to have_css("[data-free-subline]", text: "You have spent past what you had")
  end

  # A physical overdraft is money that has already gone, which no claim on this screen can say.
  it "turns the checking figure red when the account is overdrawn", :aggregate_failures do
    spend(create(:category, user: user, name: "Repairs"), 1_400)

    read_home

    expect(page).to have_css("[data-in-checking].text-status-danger", text: "-$400.00")
    expect(page).to have_css("[data-checking-overdrawn]")
    # No bar: an overdrawn account is not a quantity for a fraction to be of.
    expect(page).to have_no_css("[data-claimed-bar]")
  end

  # A TRUE 375px LAYOUT VIEWPORT, AND CDP IS THE ONLY WAY TO GET ONE. Chrome refuses to make a
  # headless window narrower than 500px — `resize_to(375, 667)` reports 500, measured — so every
  # window-based spelling of this test is a 500px test wearing a 375 label.
  describe "on a narrow screen", :js do
    before do
      page.driver.browser.execute_cdp(
        "Emulation.setDeviceMetricsOverride", width: 375, height: 667, deviceScaleFactor: 1, mobile: false
      )
    end

    # Three tiles stacked is most of a phone screen spent on three figures, with the runway starting
    # below the fold. The geometry is the whole ruling: free is above both of the others and as wide
    # as the row, and the two below share a top edge and split it.
    #
    # Selenium's own geometry rather than a trailing `evaluate_script`, which leaves the session in
    # a state Capybara's teardown does not survive here.
    it "spans the free tile and halves the other two inside a 375px viewport", :aggregate_failures do
      envelope("Groceries", rate: 400)
      elsewhere("Vanguard", 100)

      read_home

      expect(page).to have_css("[data-free]", text: "$600.00")

      free, checking_tile, other = ["free", "checking", "elsewhere"].map { |tile| tile_rect(tile) }

      expect(checking_tile.y).to be > free.y + free.height - 1
      expect(other.y).to eq(checking_tile.y)
      expect(other.x).to be > checking_tile.x
      expect(other.x + other.width).to be <= 375
      # The chips are not drawn at this width: three names in half of 375px is three ellipses.
      expect(page).to have_no_css("[data-account-chip]")
    end
  end
end
