# frozen_string_literal: true

require "rails_helper"

# THE BUDGET PAGE'S BOTTOM HALF (spec §8): four detectors over entry history, the sentence each one
# renders, and what accepting one actually writes.
#
# `Capybara.exact` is unset in this suite, so every assertion about a sentence is scoped to its own
# row with `within` — unscoped, "Utilities" matches a suggestion, a pool group heading and the nav
# all at once, and the guess assertions below would match the wrong row entirely.
#
# The history is planted rather than faked: `SuggestionEngine` is a reading of `entries`, and a
# stubbed engine would pin this page against a fixture instead of against the app.
RSpec.describe "Budget page suggestions", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:utilities) { create(:category, :expense, user: user, name: "Utilities") }
  let(:phone) { create(:item, category: utilities, name: "Phone") }
  let(:internet) { create(:item, category: utilities, name: "Internet") }

  # THE NOMINATED ACCOUNT IS WHAT A PROPOSED ENVELOPE WOULD SIT INSIDE — the engine reads
  # `users.default_account_id` for the pool half, `require_account_for_budget_pools` refuses an
  # account-less budget pool, and a user who has nominated none is the case the form ASKS about
  # rather than submits blank (pinned in spec/requests/budgets_spec.rb, not here).
  before do
    user.update!(default_account: checking)
    sign_in user, scope: :user
  end

  describe "rendering the four kinds", :aggregate_failures do
    before do
      plant_everything
      visit budget_page_path
    end

    # §8's dated-bill row: what leaves the account, on what schedule, next when.
    it "states a detected bill with its schedule and its per-period cost" do
      within(suggestion(:dated_bill, phone)) do
        expect(page).to have_content("Phone — $85.00 every month")
          .and have_content("next due #{expected_due_on.strftime("%b %-d, %Y")}")
          .and have_content("Costs $39.23 a period")
      end
    end

    # BOTH DIRECTIONS ON ONE SCREEN. A single-occurrence item is proposed with a GUESSED interval
    # (§8), and if a guessed row read the same as a measured one the panel's evidence would be
    # indistinguishable from its arithmetic.
    it "says 'guess' on the guessed interval and not on the measured one" do
      within(suggestion(:dated_bill, concert)) do
        expect(page).to have_content("every 12 months is a guess")
      end
      within(suggestion(:dated_bill, phone)) { expect(page).to have_no_content("guess") }
    end

    # §8: `Coffee — $35 a period for 6 months, currently comes out of your buffer`. The divisor is
    # named too: the amount is the total over periods LIVED THROUGH, not over appearances.
    it "states a detected rate, its window and that nothing funds it" do
      within(suggestion(:rate, groceries)) do
        expect(page).to have_content("Groceries — $300.00 a period")
          .and have_content("currently comes out of your buffer")
          .and have_content("$900.00 spent in 3 of the last 6 periods")
          .and have_content("averaged over 3 periods")
      end
    end

    # §8: `Groceries has averaged $470 for 4 periods, your rule says $420`. Both figures are per
    # period — the rule's side is `Budget#steady_ask`, never `budgets.amount`.
    it "states drift with both figures in the same unit" do
      within(suggestion(:drift, dining_rule)) do
        expect(page).to have_content("Dining Out has averaged $45.00 a period for 4 periods")
          .and have_content("your rule asks for $150.00 a period")
          .and have_content("reserving $105.00 a period more than you spend")
      end
    end

    # §8: `Netflix stopped in October, the rule is still funding it`.
    it "states a dead rule in the unit the money leaves in" do
      within(suggestion(:dead_rule, netflix_rule)) do
        expect(page).to have_content("Netflix stopped on")
          .and have_content("nothing for 3 periods")
          .and have_content("still funding it at $55.38 a period")
          .and have_content("The rule says $120.00 a month")
      end
    end

    # Everything the engine returns, in the engine's order (kind, then per-period cost) — nothing
    # truncated, nothing re-sorted here.
    it "renders every suggestion the engine returns, in its order" do
      expect(rendered_keys).to eq(SuggestionEngine.new(user: user).suggestions.map { |s| "#{s.kind}:#{s.subject.id}" })
      expect(rendered_keys.size).to eq(6)
    end

    # SPEC §8: suggestions cannot be dismissed, so there is deliberately no control that would.
    # Asserted as an absence of the affordance rather than of a word, because the risk is a button
    # arriving later that hides a real drift.
    it "offers no way to dismiss one" do
      within("[data-suggestions]") do
        expect(page).to have_no_css("button", text: /dismiss|hide|ignore/i)
        expect(page).to have_no_css("a", text: /dismiss|hide|ignore/i)
      end
    end

    # THE RE-POINT, SAID BEFORE THE CLICK: accepting a Phone proposal moves every Utilities entry,
    # and the cap it destroys on the way is named with its own figure.
    it "says what accepting does to the category, and which cap it replaces" do
      within(suggestion(:dated_bill, phone)) do
        expect(page).to have_content("puts all Utilities spending in a new Utilities envelope")
          .and have_content("$40.00 a month cap here is a spending limit")
      end
    end
  end

  describe "the empty state", :aggregate_failures do
    # A user with a declared period and no history at all: the detectors ran and found nothing,
    # which is a different sentence from "this section failed to render".
    it "says there is nothing to suggest" do
      visit budget_page_path

      within("[data-suggestions]") do
        expect(page).to have_content("Nothing to suggest")
        expect(page).to have_no_css("[data-suggestion]")
      end
    end
  end

  describe "accepting a proposed bill", :aggregate_failures do
    before do
      plant_bill(phone, 85)
      plant_bill(internet, 65)
      visit budget_page_path
    end

    it "lands on a form prefilled with everything the engine measured" do
      accept(:dated_bill, phone)

      expect(page).to have_field("envelope[name]", with: "Utilities")
      expect(page).to have_field("Rule Amount", with: "85.0")
      expect(page).to have_field("Comes round every (months)", with: "1")
      expect(page).to have_content("Pays").and have_content("Phone")
    end

    # THE ROUND TRIP: accept, and the rule is in the top half while the suggestion has left the
    # bottom one — because the item now carries a rule, which is the engine's own retirement test.
    it "writes the rule, which retires its own suggestion" do
      accept_and_create(:dated_bill, phone)

      expect(page).to have_content("Budget was successfully created")
      within("[data-pool-group='Utilities']") { expect(page).to have_content("$85.00 a month") }
      expect(page).to have_no_css("[data-suggestion='dated_bill:#{phone.id}']")
    end

    it "creates the envelope and re-points the category at it" do
      accept_and_create(:dated_bill, phone)

      expect(page).to have_content("Budget was successfully created")
      expect(utilities.reload.pool.name).to eq("Utilities")
      expect(utilities.pool.pool_type).to eq("budget")
      expect(utilities.pool.account).to eq(checking)
    end
  end

  # THE MOST LOAD-BEARING CASE ON THIS PAGE. Two bills in ONE category share ONE envelope: the
  # first acceptance creates it, and from then on the engine's payload reuses it by itself, so the
  # second must render and act as ADDING to that envelope rather than making a second one.
  describe "a second bill in the same category", :aggregate_failures do
    before do
      plant_bill(phone, 85)
      plant_bill(internet, 65)
      visit budget_page_path
      accept_and_create(:dated_bill, phone)
    end

    it "offers the envelope the first acceptance created" do
      expect(page).to have_content("Budget was successfully created")
      within(suggestion(:dated_bill, internet)) do
        expect(page).to have_content("joins your existing Utilities envelope")
        expect(page).to have_no_content("in a new Utilities envelope")
      end
    end

    it "lands as a second rule in that same envelope" do
      accept_and_create(:dated_bill, internet)

      expect(page).to have_content("Budget was successfully created")
      expect(user.pools.where(name: "Utilities").count).to eq(1)
      expect(utilities.reload.pool.budgets.map { |rule| rule.item.name }).to contain_exactly("Phone", "Internet")
    end

    it "shows both rules in one group on the page" do
      accept_and_create(:dated_bill, internet)

      expect(page).to have_content("Budget was successfully created")
      within("[data-pool-group='Utilities']") do
        expect(page).to have_content("$85.00 a month").and have_content("$65.00 a month")
      end
    end
  end

  # THE DEMO SEEDS' OWN SHAPE, and it is why this branch exists at all: the engine names a proposed
  # envelope after the CATEGORY, and the demo already holds a "Utilities" envelope beside a
  # "Utilities" category pointing at nothing — so every one of its three bills proposed a pool
  # whose name was already taken, and `Pool`'s uniqueness validation refused all three. Measured in
  # the browser before it was fixed.
  describe "a category whose proposed envelope name is already taken", :aggregate_failures do
    before do
      create(:pool, :budget_pool, user: user, account: checking, name: "Utilities", priority: 3)
      plant_bill(phone, 85)
      visit budget_page_path
    end

    # The sentence has to match what the save will do, in both directions on one row.
    it "offers to join that envelope rather than to make a second" do
      within(suggestion(:dated_bill, phone)) do
        expect(page).to have_content("joins your existing Utilities envelope")
          .and have_content("points all Utilities spending at it")
        expect(page).to have_no_content("in a new Utilities envelope")
      end
    end

    it "lands the rule in it and points the category at it" do
      accept_and_create(:dated_bill, phone)

      expect(page).to have_content("Budget was successfully created")
      expect(user.pools.where(name: "Utilities").count).to eq(1)
      expect(utilities.reload.pool.budgets.sole.item).to eq(phone)
    end
  end

  describe "accepting a drift", :aggregate_failures do
    before do
      plant_drift
      visit budget_page_path
    end

    # THE FIGURE ARRIVES IN THE RULE'S OWN UNIT and the form labels it rather than converting it.
    # The rule here is per-paycheck, so the two coincide; the monthly case is pinned on the engine.
    it "prefills the observed figure beside the current one" do
      accept(:drift, dining_rule)

      expect(page).to have_field("Rule Amount", with: "45.0")
      expect(page).to have_content("Currently $150.00 / period")
    end

    it "changes the rule and retires the drift" do
      accept(:drift, dining_rule)
      click_button "Update Budget"

      expect(page).to have_content("Budget was successfully updated")
      expect(dining_rule.reload.amount).to eq(45)
      expect(page).to have_no_css("[data-suggestion='drift:#{dining_rule.id}']")
    end
  end

  # THE PAGE DOES NOT DELETE — the user does. Both doors are on the row because entry history
  # cannot tell a cancelled subscription from a replaced card.
  describe "a dead rule", :aggregate_failures do
    before do
      plant_dead_rule
      visit budget_page_path
    end

    it "opens the rule for review rather than deleting it" do
      within(suggestion(:dead_rule, netflix_rule)) { click_link "Review the rule" }

      expect(page).to have_field("Rule Amount", with: "120.0")
      expect(Budget.exists?(netflix_rule.id)).to be true
    end

    it "deletes it only when the user asks" do
      accept_confirm { within(suggestion(:dead_rule, netflix_rule)) { click_button "Delete the rule" } }

      expect(page).to have_content("Budget was successfully deleted")
      expect(Budget.exists?(netflix_rule.id)).to be false
    end
  end

  private

  # ---------------------------------------------------------------------------------------------
  # Page readers
  # ---------------------------------------------------------------------------------------------

  def suggestion(kind, subject) = find("[data-suggestion='#{kind}:#{subject.id}']")

  def rendered_keys = page.all("[data-suggestion]").pluck("data-suggestion")

  def accept(kind, subject)
    within(suggestion(kind, subject)) { click_link suggestion_accept_label(kind) }
  end

  def suggestion_accept_label(kind)
    { drift: "Update the rule", dead_rule: "Review the rule" }.fetch(kind, "Write this rule")
  end

  # `have_content` after the click and BEFORE any model read: `click_button` returns as soon as the
  # click is dispatched, and a bare `expect(model.reload…)` would end the example mid-request.
  def accept_and_create(kind, subject)
    accept(kind, subject)
    click_button "Create Budget"
    expect(page).to have_css("[data-suggestions]")
  end

  # ---------------------------------------------------------------------------------------------
  # The planted history — one detector at a time, and the whole lot for the rendering block
  # ---------------------------------------------------------------------------------------------

  def plant_everything
    create(:budget, category: utilities, amount: 40)
    plant_bill(phone, 85)
    plant_bill(internet, 65)
    concert
    groceries
    plant_drift
    plant_dead_rule
  end

  # TWO PAYMENTS A WHOLE MONTH APART, the same size: the measured dated-bill shape.
  def plant_bill(item, amount)
    create(:entry, item: item, amount: amount, date: Date.current - 2.months)
    create(:entry, item: item, amount: amount, date: Date.current - 1.month)
  end

  def expected_due_on = (Date.current - 1.month) >> 1

  # ONE payment, and big enough to be a bill at all ($100 floor) — the guessed shape.
  def concert
    @concert ||= create(:item, category: create(:category, :expense, user: user, name: "Fun"), name: "Concert").tap do |item|
      create(:entry, item: item, amount: 200, date: Date.current - 20.days)
    end
  end

  # Three periods of $300, fourteen days apart so no pair is a whole month and the bill detector
  # keeps its hands off. Present in 3 of the last 6 and in the most recent 3, so both rate gates
  # open; measured over 3 periods, which is the span since it first appeared.
  def groceries
    @groceries ||= create(:category, :expense, user: user, name: "Groceries").tap do |category|
      item = create(:item, category: category, name: "Supermarket")
      [5, 19, 33].each { |days| create(:entry, item: item, amount: 300, date: Date.current - days.days) }
    end
  end

  def dining_pool
    @dining_pool ||= create(:pool, :budget_pool, user: user, account: checking, name: "Dining Out", priority: 1)
  end

  def dining_rule
    @dining_rule ||= create(:pool_budget, :per_paycheck_rate, pool: dining_pool, amount: 150)
  end

  # A rate rule against a lane that carries far less than it reserves: $180 over the four-period
  # window is $45 a period against $150. Two payments under the $100 bill floor, so nothing here
  # is also proposed as a dated bill.
  def plant_drift
    dining_rule
    category = create(:category, :expense, user: user, name: "Restaurants", pool: dining_pool)
    item = create(:item, category: category, name: "Takeout")
    [5, 19].each { |days| create(:entry, item: item, amount: 90, date: Date.current - days.days) }
  end

  def netflix_pool
    @netflix_pool ||= create(:pool, :budget_pool, user: user, account: checking, name: "Streaming", priority: 2)
  end

  def netflix_item
    @netflix_item ||= create(
      :item,
      category: create(:category, :expense, user: user, name: "Subscriptions", pool: netflix_pool),
      name: "Netflix"
    )
  end

  def netflix_rule
    @netflix_rule ||= create(
      :pool_budget, pool: netflix_pool, item: netflix_item, amount: 120, interval_months: 1, anchor_date: Date.current - 10.days
    )
  end

  # The last payment falls the day before the three-period window opens — the near side of the
  # boundary the engine's own examples pin.
  def plant_dead_rule
    netflix_rule
    create(:entry, item: netflix_item, amount: 120, date: Date.current - 50.days)
  end
end
