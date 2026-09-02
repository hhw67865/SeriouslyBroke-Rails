# frozen_string_literal: true

require "rails_helper"

# THE BUDGET PAGE IS WHERE FUNDING PRIORITY IS SET (spec §8), and this is the file that says what
# that means.
#
# ── THE MONEY HALF IS RESTORED (two-ledger spec §2). Three examples once measured this screen's ▲▼
# buttons against `AllocationCalculator#rows` — "a DIFFERENT ENVELOPE GETS THE MONEY", not merely a
# list in a new order — and they were withdrawn in Task 4, when the waterfall moved onto
# `Category.in_fill_order` and this endpoint was still reordering POOLS. The endpoint reorders
# categories now, so the claim is true again and is measured the same way against the same reader:
# `#fill` below reads the waterfall directly, and the assertion is which category the last dollar
# reaches.
#
# ── AND THE BANDS ARE GONE WITH THE PER-ACCOUNT FILL. Two examples went with them, named in
# "the ends of the order" below.
#
# THROUGH THE ▲▼ BUTTONS, deliberately. They are plain forms carrying the whole order, so they are
# the path that works with scripting off; the drag controller builds the same `category_ids[]` out
# of the DOM and submits the same PATCH. Testing the buttons tests the endpoint, the refusal and
# the fill without synthesising HTML5 drag events.
#
# `Capybara.exact` is unset in this suite, so every row assertion is scoped to its group — an
# unscoped `have_content("Groceries")` matches a heading, a rule row and the nav.
RSpec.describe "Budget page reorder", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 500)
  end

  before do
    sign_in user, scope: :user
    holder("Groceries", rate: 400, priority: 1)
    holder("Fun Money", rate: 300, priority: 2)
    # $500 of available against $700 of rules: the user is $200 short, so the order is the only
    # thing deciding who goes without.
    deposit(500)
    visit budget_page_path
  end

  describe "moving a category up the fill order", :aggregate_failures do
    it "changes the order of the cards" do
      click_button "Move Fun Money up"

      expect(page).to have_content("Your money fills them in that order now.")
      expect(cards).to eq(["Fun Money", "Groceries"])
    end

    it "restates each category's new position on the page it comes back to" do
      click_button "Move Fun Money up"

      expect(page).to have_content("Your money fills them in that order now.")
      within(group("Fun Money")) { expect(page).to have_content("priority 0") }
      within(group("Groceries")) { expect(page).to have_content("priority 1") }
    end

    # THE MONEY, NOT THE LIST. $500 of available cannot fill $700 of rules, so exactly one of the
    # two goes short — and which one is what this button decides. Read off
    # `AllocationCalculator`, the waterfall itself, rather than off the page that ordered it.
    it "sends the money to the category that moved up" do
      expect(fill).to eq("Groceries" => 400, "Fun Money" => 100)

      click_button "Move Fun Money up"
      expect(page).to have_content("Your money fills them in that order now.")

      expect(fill).to eq("Fun Money" => 300, "Groceries" => 200)
    end
  end

  # ▼ IS NOT ▲ READ BACKWARDS: each button carries its own already-swapped list, and a helper
  # that got the sign wrong would move the wrong row while still producing a valid order.
  describe "moving a category down the fill order", :aggregate_failures do
    it "arrives at the same order as moving the other one up" do
      click_button "Move Groceries down"

      expect(page).to have_content("Your money fills them in that order now.")
      expect(cards).to eq(["Fun Money", "Groceries"])
    end
  end

  describe "the ends of the order", :aggregate_failures do
    # TWO EXAMPLES ARE DELETED HERE (two-ledger spec §2). "leaves the same user's other account
    # exactly where it was" and "keeps each account's order to itself" both pinned that a reorder
    # in one band could not reach another — a property of the per-account fill, which
    # `AllocationCalculator` replaced with one root. There is one list, so there is no second one
    # to leak into and no fixture that could express the leak.

    # Both directions on both rows, on one screen: an unconditionally disabled pair would pass
    # half of this and an unconditionally enabled one the other half.
    it "offers no move off either end" do
      within("[data-fill-order]") do
        expect(page).to have_button("Move Groceries up", disabled: true)
        expect(page).to have_button("Move Groceries down", disabled: false)
        expect(page).to have_button("Move Fun Money up", disabled: false)
        expect(page).to have_button("Move Fun Money down", disabled: true)
      end
    end
  end

  private

  def holder(name, rate:, priority:)
    category = create(:category, :expense, :funded, user: user, name: name, priority: priority)
    create(:budget, :per_period_rate, category: category, amount: rate)
    category
  end

  def deposit(amount)
    category = create(:category, :income, user: user)
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end

  # WHAT THE WATERFALL WOULD ACTUALLY HAND OUT, `{ category name => amount }`, read off the same
  # reader the distribution screen renders. Never off the page: the page is what is being ordered,
  # and asking it what the order means would be one screen agreeing with itself.
  def fill
    AllocationCalculator.new(user: user.reload, today: Date.current)
      .rows.to_h { |row| [row.category.name, row.funded] }
  end

  def group(name) = find("[data-category-group='#{name}']")

  def cards = page.all("[data-category-group]").pluck("data-category-group")
end
