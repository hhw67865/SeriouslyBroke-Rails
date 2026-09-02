# frozen_string_literal: true

require "rails_helper"

# THE BUDGET PAGE IS WHERE FUNDING PRIORITY IS SET (spec §8), and this is the file that says what
# that means.
#
# ── THE MONEY HALF IS WITHDRAWN, AND TASK 5 (or 6) RESTORES IT. Three examples measured this
# screen's ▲▼ buttons against `AllocationCalculator#rows` — "a DIFFERENT ENVELOPE GETS THE MONEY",
# not merely a list in a new order — and that claim is not true of this endpoint today: Task 4 moved
# the waterfall onto `Category.in_fill_order`, so reordering POOL priority changes nothing about who
# is funded. The screen still reorders pools and still says so, which is what the assertions below
# now cover; the claim comes back the moment the Budget page reorders CATEGORIES, measured the same
# way against the same reader. Three `expect(fill)` lines and the `#fill` helper were removed, and
# nothing else in this file changed.
#
# THROUGH THE ▲▼ BUTTONS, deliberately. They are plain forms carrying the whole band in its new
# order, so they are the path that works with scripting off; the drag controller builds the same
# `pool_ids[]` out of the DOM and submits the same PATCH. Testing the buttons tests the endpoint,
# the refusal and the fill without synthesising HTML5 drag events.
#
# `Capybara.exact` is unset in this suite, so every row assertion is scoped to its band or its
# group — an unscoped `have_content("Groceries")` matches a heading, a rule row and the nav.
RSpec.describe "Budget page reorder", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 500)
  end
  let!(:gifts) { envelope("Holiday Gifts", rate: 50, priority: 7, account: savings) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:savings) { create(:pool, :account, user: user, name: "Savings") }

  before do
    # MAIN-ACCOUNT SPEC §6, FIX ROUND 2: `#deposit` below names Checking unconditionally, so it
    # has to be the user's main account — forced unconditionally rather than relying on creation
    # order, because `gifts` above (a `let!`) mints `savings` first and the auto-main factory
    # trait would otherwise claim it instead. `update!` overrides whatever the trait already
    # decided, so it works regardless of which hook actually runs first.
    user.update!(default_account: checking)
    sign_in user, scope: :user
    envelope("Groceries", rate: 400, priority: 1)
    envelope("Fun Money", rate: 300, priority: 2)
    # $500 into Checking against $700 of rules: the account is $200 short, so the order is the
    # only thing deciding who goes without.
    deposit(500)
    visit budget_page_path
  end

  describe "moving a pool up the fill order", :aggregate_failures do
    # The order the cards come back in, which is what this endpoint still decides. The `fill`
    # assertions that used to bracket this one are named in the file header.
    it "changes the order of the cards" do
      click_button "Move Fun Money up"

      expect(page).to have_content("Checking fills in that order now.")
      expect(cards_in("Checking")).to eq(["Fun Money", "Groceries"])
    end

    it "restates each pool's new position on the page it comes back to" do
      click_button "Move Fun Money up"

      expect(page).to have_content("Checking fills in that order now.")
      within(group("Fun Money")) { expect(page).to have_content("priority 0") }
      within(group("Groceries")) { expect(page).to have_content("priority 1") }
    end

    # The reindex is dense over ONE account. A pool of the same user in another account is named
    # nowhere on the wire and must read exactly as it did — otherwise a drag in Checking would
    # quietly reshuffle Savings.
    it "leaves the same user's other account exactly where it was" do
      click_button "Move Fun Money up"

      expect(page).to have_content("Checking fills in that order now.")
      expect(gifts.reload.priority).to eq(7)
      within(group("Holiday Gifts")) { expect(page).to have_content("priority 7") }
    end
  end

  # ▼ IS NOT ▲ READ BACKWARDS: each button carries its own already-swapped list, and a helper
  # that got the sign wrong would move the wrong row while still producing a valid order.
  describe "moving a pool down the fill order", :aggregate_failures do
    it "arrives at the same order as moving the other one up" do
      click_button "Move Groceries down"

      expect(page).to have_content("Checking fills in that order now.")
      expect(cards_in("Checking")).to eq(["Fun Money", "Groceries"])
    end
  end

  describe "the ends of the order", :aggregate_failures do
    # Both directions on both rows, on one screen: an unconditionally disabled pair would pass
    # half of this and an unconditionally enabled one the other half.
    it "offers no move off either end" do
      within(band("Checking")) do
        expect(page).to have_button("Move Groceries up", disabled: true)
        expect(page).to have_button("Move Groceries down", disabled: false)
        expect(page).to have_button("Move Fun Money up", disabled: false)
        expect(page).to have_button("Move Fun Money down", disabled: true)
      end
    end

    # A band is one account, and priority is only ever compared inside one — so the lone pool in
    # Savings has nowhere to go and Checking's pools are not offered as somewhere to go.
    it "keeps each account's order to itself" do
      expect(cards_in("Savings")).to eq(["Holiday Gifts"])
      within(band("Savings")) do
        expect(page).to have_button("Move Holiday Gifts up", disabled: true)
        expect(page).to have_button("Move Holiday Gifts down", disabled: true)
        expect(page).to have_no_button("Move Groceries up")
      end
    end
  end

  private

  def envelope(name, rate:, priority:, account: checking)
    pool = create(:pool, :budget_pool, user: user, account: account, name: name, priority: priority)
    create(:pool_budget, :per_period_rate, pool: pool, amount: rate)
    pool
  end

  def deposit(amount)
    category = create(:category, :income, user: user, pool: checking)
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  def band(name) = find("[data-reorder-account='#{name}']")

  def group(name) = find("[data-pool-group='#{name}']")

  def cards_in(account) = band(account).all("[data-pool-group]").pluck("data-pool-group")
end
