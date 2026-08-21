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
  # POINTED AT THE ACCOUNT, which is where buffer-funded spending lives after plan 3 — the
  # pool-less shape this fixture used to have is refused by `Category belongs_to :pool`, and
  # `Category#buffer_funded?` answers true for both, so the detectors see the same input.
  let(:utilities) { create(:category, :expense, user: user, name: "Utilities", pool: checking) }
  let(:phone) { create(:item, category: utilities, name: "Phone") }
  let(:internet) { create(:item, category: utilities, name: "Internet") }

  # THE NOMINATED ACCOUNT IS WHAT A PROPOSED ENVELOPE WOULD SIT INSIDE — the engine reads
  # `users.default_account_id` for the pool half, `account_matches_pool_type` refuses an
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

    # THE INDEX (Task 7's review): the panel runs to about 5,000px on the demo and §8 forbids both
    # of the usual answers — no truncation, no dismissal — so what is left is navigation.
    #
    # THE COUNTS ARE CHECKED AGAINST THE ROWS THEMSELVES rather than against the engine, because an
    # index that agreed with the engine and disagreed with what is on screen would be exactly the
    # defect: a strip promising three bills over a list of two.
    it "agrees with the rows the panel is actually showing" do
      expect(rendered_keys.map { |key| key.split(":").first }.tally)
        .to eq("dated_bill" => 3, "rate" => 1, "drift" => 1, "dead_rule" => 1)
    end

    # THE WORDING IS PINNED AS LITERALS, not rebuilt from `pluralize` here — an expectation that
    # called the same helper the view calls would pass whatever it returned. It also puts the
    # singular on the screen: three of the four kinds are at one on this fixture, and "1 rates" is
    # the copy nobody notices until it ships.
    it "names each kind with its count" do
      expect(index_link(:dated_bill).text).to eq("3 bills")
      expect(index_link(:rate).text).to eq("1 rate")
      expect(index_link(:drift).text).to eq("1 drifting")
      expect(index_link(:dead_rule).text).to eq("1 dead")
    end

    # HIDING NOTHING IS THE WHOLE CONSTRAINT. The index sums to every suggestion the engine
    # returned, so no kind can quietly fall out of the panel behind a heading that never appeared.
    it "indexes every suggestion on the page" do
      indexed = page.all("[data-suggestions-index-link]").sum { |link| link.text.to_i }

      expect(indexed).to eq(rendered_keys.size)
      expect(indexed).to eq(6)
    end

    # THE ANCHOR HAS TO LAND, and on something that says what it is: a bare `<span id>` would be a
    # jump to a spot with nothing at it. Followed rather than merely asserted, because a fragment
    # that names no element is a link that silently does nothing.
    it "jumps to the run it names" do
      index_link(:drift).click

      # `url: true` because Capybara's `current_path` drops the fragment, and the fragment is the
      # whole of what this link does. The scroll itself is the browser's; what has to be true here
      # is that the fragment names an element that exists and says what it is.
      expect(page).to have_current_path(%r{/budget\#suggestions-drift\z}, url: true)
      expect(find("#suggestions-drift")).to have_content("Rules that have drifted · 1")
    end

    # Each heading sits directly above its own run, which is what makes the jump useful — the
    # engine sorts by kind first, so the runs are contiguous and the heading is not a filter.
    it "heads each run with its kind and its count", :aggregate_failures do
      expect(find("#suggestions-dated_bill")).to have_content("Dated bills · 3")
      expect(find("#suggestions-rate")).to have_content("Rates · 1")
      expect(find("#suggestions-dead_rule")).to have_content("Rules that look dead · 1")
    end

    # HENRY'S RULING OF 2026-08-20 REVERSES §8 HERE, and this example is the inversion of the one
    # that stood in its place — "offers no way to dismiss one", which asserted the absence of
    # exactly this affordance. It is inverted rather than deleted because the fact worth pinning is
    # the same one: whether the panel can hide a row. It can now, on every row, and on purpose.
    it "offers a way to hide every one of them" do
      expect(page.all("[data-suggestion]").size).to eq(6)
      expect(page.all("[data-suggestion] button", text: "Hide").size).to eq(6)
    end

    # NOTHING IS HIDDEN UNTIL THE USER HIDES IT. The foot section is state, so its absence on a
    # panel nobody has touched is what says the list above is complete.
    it "shows no hidden section until something is hidden" do
      expect(page).to have_no_css("[data-hidden-suggestions]")
    end

    # THE RE-POINT, SAID BEFORE THE CLICK: accepting a Phone proposal moves every Utilities entry.
    #
    # THE CAP CLAUSE IS DELETED WITH THE CAP (plan 3, task 3). Three examples named it — one on a
    # dated bill, one on a rate (amendment C's case), and one negative on a category that had none
    # — because accepting used to DESTROY the category's cap as a side effect of the re-point. That
    # deletion cannot happen, so the row has one clause and the negative is the whole panel's.
    it "says what accepting does to the category" do
      within(effect_of(:dated_bill, phone)) do
        expect(page).to have_content("puts all Utilities spending in a new Utilities envelope")
      end
    end

    it "says nothing about a cap anywhere on the panel" do
      within("[data-suggestions]") do
        expect(page).to have_css("[data-suggestion-effect]")
        expect(page).to have_no_css("[data-suggestion-cap]")
        expect(page).to have_no_content("cap here is a spending limit")
      end
    end
  end

  # HIDING ONE, AND GETTING IT BACK (Henry's ruling of 2026-08-20). Two bills are planted rather
  # than one, so "it left the panel" is distinguishable from "the panel stopped rendering".
  describe "hiding a suggestion", :aggregate_failures do
    before do
      plant_bill(phone, 85)
      plant_bill(internet, 65)
      visit budget_page_path
      page.assert_selector("[data-suggestion='dated_bill:#{phone.id}']")
    end

    def hide(kind, subject)
      within(suggestion(kind, subject)) { click_button "Hide" }
      page.assert_selector("[data-hidden-suggestions]")
    end

    # THE SECTION IS A `<details>`, so its rows are in the DOM and NOT VISIBLE until it is opened —
    # which is what "collapsed" means and what these examples have to go through rather than
    # around. `have_content` is visibility-aware, so an assertion that skipped this click would
    # pass on `visible: :all` against a section nobody could read.
    def open_hidden = find("[data-hidden-suggestions] summary").click

    it "takes the row off the panel and leaves the others standing" do
      hide(:dated_bill, phone)

      expect(page).to have_no_css("[data-suggestion='dated_bill:#{phone.id}']")
      expect(page).to have_css("[data-suggestion='dated_bill:#{internet.id}']")
    end

    # A DISMISSAL IS STATE, WHICH IS THE WHOLE OBJECTION §8 MADE TO IT — so the pin is that it
    # SURVIVES, rather than that the row disappeared from a page that had not been reloaded.
    it "stays hidden across a reload" do
      hide(:dated_bill, phone)
      visit budget_page_path

      expect(page).to have_css("[data-suggestions]")
      expect(page).to have_no_css("[data-suggestion='dated_bill:#{phone.id}']")
    end

    # THE FOOT SECTION IS THE ANSWER TO "WHERE DID IT GO". A hidden suggestion that could not be
    # found again would be a deletion wearing a gentler word, which is what §8 feared; it is
    # collapsed rather than absent, and it still says the bill's own sentence.
    it "lists it at the foot of the panel, with its count and its sentence" do
      hide(:dated_bill, phone)

      # THE COUNT IS VISIBLE WHILE THE LIST IS NOT, which is the whole point of collapsing it: the
      # user is told how much is put away without the panel growing back by the height of it.
      within("[data-hidden-suggestions]") do
        expect(page).to have_content("1 hidden suggestion")
        expect(page).to have_no_content("Phone — $85.00 every month")
      end

      open_hidden

      within("[data-hidden-suggestions]") do
        expect(page).to have_content("Phone — $85.00 every month")
      end
    end

    it "puts it back on the panel when shown again" do
      hide(:dated_bill, phone)
      open_hidden
      within("[data-hidden-suggestion='dated_bill:#{phone.id}']") { click_button "Show" }

      expect(page).to have_css("[data-suggestion='dated_bill:#{phone.id}']")
      expect(page).to have_no_css("[data-hidden-suggestions]")
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

    # THE OWNER IS ALREADY IN CONTEXT HERE, so the hand-made form's pool picker (Henry's ruling of
    # 2026-08-20) must not appear on this path: the envelope half names the pool this rule will
    # fill, and a select beside it would offer to send the rule somewhere the panel's own sentence
    # one click earlier did not promise.
    it "offers no pool picker, because the envelope half already names the owner" do
      accept(:dated_bill, phone)

      expect(page).to have_no_select("Pool")
    end

    # The CREATE half of the pair the join case pins from the other side: nothing by this name
    # exists, so the heading says a new envelope and the account picker is a real question the
    # save will answer with.
    it "heads the form as a creation, and asks for the account" do
      accept(:dated_bill, phone)

      expect(page).to have_content("A new Utilities envelope")
      expect(page).to have_select("envelope[account_id]", selected: "Checking")
      expect(page).to have_no_content("Joining your Utilities envelope")
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

    # THE DATE IS CORRECTABLE BEFORE ACCEPTING (Henry's ruling, 2026-08-20). The anchor is an
    # INFERENCE — `SuggestionEngine#next_due_on` walks the last payment forward by the interval —
    # and it rode hidden while the amount beside it was editable, so a bill whose last payment was
    # late wrote a rule whose whole schedule was late with it. The prefill is still the engine's
    # answer; what changed is that the user can see it and say otherwise.
    it "prefills the date the engine inferred" do
      accept(:dated_bill, phone)

      expect(page).to have_field("First due", with: expected_due_on.strftime("%Y-%m-%d"))
    end

    # THE CORRECTION HAS TO REACH THE COLUMN, not merely the input: `anchor_date` was already a
    # permitted param, but it was submitted by a hidden field nothing could change. Corrected to a
    # date the engine would never infer (the inference is a whole-month step off the last payment,
    # so nine days past it is nobody's arithmetic here) and read back off the rule.
    #
    # A `Date`, NOT a formatted string: Capybara's `SettableValue#dateable?` is explicitly false
    # for a String, which sends the characters as KEYSTROKES into a date input that already holds
    # the prefill — the first attempt read back as the year 60830. A Date takes the
    # `update_value_js` path and REPLACES the value, which is what a user picking a date does.
    it "writes the corrected date rather than the inferred one" do
      accept(:dated_bill, phone)
      fill_in "First due", with: corrected_due_on
      click_button "Create Budget"

      expect(page).to have_content("Budget was successfully created")
      expect(Budget.find_by(item_id: phone.id).anchor_date).to eq(corrected_due_on)
    end

    def corrected_due_on = expected_due_on + 9.days
  end

  # A RATE HAS NO DATE CONCEPT AT ALL — `rate_suggestion` carries no `anchor_date`, its rule is
  # per-period, and `shape_must_be_valid` refuses a per-period rule that has one. So the field must
  # be absent rather than blank: a blank date input on this form is an invitation to write a shape
  # the model will refuse.
  describe "accepting a proposed rate", :aggregate_failures do
    before do
      groceries
      visit budget_page_path
    end

    it "offers no date field" do
      accept(:rate, groceries)

      expect(page).to have_field("Rule Amount", with: "300.0")
      expect(page).to have_no_field("First due")
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

    # THE COPY HALF OF THE LOAD-BEARING REQUIREMENT, and the negative is the whole assertion.
    # THREE sentences can appear here and two of them open with "joins your existing Utilities
    # envelope" — the difference is the clause after it. A regression that rendered the RE-POINT
    # sentence ("…and points all Utilities spending at it") would promise a category move that has
    # already happened and will not happen again, and a prefix-only assertion passes green on it.
    # There is no re-point left to do: the category is already pool-covered, and the payload
    # carries `pool_id` and no envelope half at all.
    it "offers the envelope the first acceptance created, without promising to move anything" do
      expect(page).to have_content("Budget was successfully created")
      within(effect_of(:dated_bill, internet)) do
        expect(page).to have_content("alongside what is already in it")
        expect(page).to have_no_content("points all Utilities spending at it")
        expect(page).to have_no_content("in a new Utilities envelope")
      end
    end

    # The cap clause that used to be asserted absent here is absent from the whole panel now; see
    # the rendering block above.

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

  # THE REUSE ARM ACCEPTS ANY NON-ACCOUNT POOL, GOALS INCLUDED, and the sentence used to call every
  # one of them an envelope (plan 3, task 5 — Task 2's second stale noun). The demo read *"This rule
  # joins your existing Vacation to Europe envelope"* about a GOAL, three inches from a category
  # page saying "Goal" about the same pool. `BudgetPagePresenter#joined_pool` hands the record back
  # and the row asks `Pool#noun`, which is the one mapping.
  describe "a category already pointing at a goal", :aggregate_failures do
    let(:vacation) { create(:pool, :savings_pool, user: user, account: checking, name: "Vacation to Europe") }
    let(:travel) { create(:category, :expense, user: user, name: "Travel", pool: vacation) }
    let(:flights) { create(:item, category: travel, name: "Flights") }

    before do
      plant_bill(flights, 180)
      visit budget_page_path
    end

    # BOTH DIRECTIONS ON ONE ROW: the pool's own noun is printed, and the envelope's is not.
    it "calls the goal a goal rather than an envelope" do
      within(effect_of(:dated_bill, flights)) do
        expect(page).to have_content("joins your existing Vacation to Europe goal")
        expect(page).to have_no_content("Vacation to Europe envelope")
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
      within(effect_of(:dated_bill, phone)) do
        expect(page).to have_content("joins your existing Utilities envelope")
          .and have_content("points all Utilities spending at it")
        expect(page).to have_no_content("in a new Utilities envelope")
      end
    end

    # THE FORM MUST AGREE WITH THE ROW THE CLICK CAME FROM. Verbatim it did not: the panel said
    # "joins your existing Utilities envelope" and the very next screen headed "A new Utilities
    # envelope", labelled the field "New envelope" and offered a "Funded from" account picker that
    # `BudgetProposal` never reads on this path — an inert control under a heading contradicting
    # the sentence one click earlier. Both directions, because a heading is only right if the
    # wrong one is gone.
    it "heads the form as a join, and asks nothing it will not read" do
      accept(:dated_bill, phone)

      expect(page).to have_content("Joining your Utilities envelope")
      expect(page).to have_content("You already have this envelope — funded from Checking")
      expect(page).to have_no_field("envelope[name]")
      expect(page).to have_no_select("envelope[account_id]")
      expect(page).to have_no_content("A new Utilities envelope")
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
    # The rule here is per-period, so the two coincide — which is exactly why the monthly case
    # below exists, and why this example alone would prove nothing about units.
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

  # THE UNITS SEPARATED. The anchorless MONTHLY rule is the shape `rate_shape?` deliberately admits
  # alongside `per_period`, and it is the one where `budgets.amount` is NOT a per-period figure:
  # a $260-a-month rule claims $260 * 12 / 26 = $120.00 a period from a biweekly user. Observed
  # $200 a period, so the engine inverts back into the rule's column and the field must read
  # $433.33 — the mixed-unit trap's fifth strike was writing the per-period $200 straight in, which
  # is $92.31 a period, LESS than the figure the user was just told was too low.
  #
  # THREE FACTS, and the absence is the one that matters: the field in the rule's unit, the current
  # figure labelled in the same unit, and the panel's per-period figure NOWHERE on this screen.
  describe "accepting a drift on a monthly rule", :aggregate_failures do
    before do
      plant_monthly_drift
      visit budget_page_path
    end

    it "states the drift in per-period money" do
      within(suggestion(:drift, retirement_rule)) do
        expect(page).to have_content("has averaged $200.00 a period for 4 periods")
          .and have_content("your rule asks for $120.00 a period")
      end
    end

    it "prefills the form in the rule's own unit and labels it there" do
      accept(:drift, retirement_rule)

      expect(page).to have_field("Rule Amount", with: "433.33")
      expect(page).to have_content("Currently $260.00 a month")
      expect(page).to have_no_content("$200.00")
      expect(page).to have_no_content("$120.00")
    end

    # The round trip through the app's own normaliser: what was written reads back as the observed
    # figure, so the rule now asks for what the entries actually say.
    it "writes a rule whose per-period claim is the observed figure" do
      accept(:drift, retirement_rule)
      click_button "Update Budget"

      expect(page).to have_content("Budget was successfully updated")
      expect(retirement_rule.reload.amount).to eq(433.33)
      expect(retirement_rule.steady_ask(user)).to eq(200)
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

  # WHAT ACCEPTING DOES TO `Σ pools == your bank balance` — the consequence `BudgetProposal`'s
  # header used to deny and nothing asserted.
  #
  # THE RE-POINT MOVES NO HISTORY AT ALL, and it USED TO MOVE ALL OF IT. Before the start-date rule
  # (main-account spec §3) `PoolBalanceLedger::ENTRY_POOL_ID` had no date bound, so the instant
  # `category.pool_id` was written every entry that category ever carried fell inside the new
  # envelope's lane and the envelope opened at minus its lifetime spend. That is §1's opening
  # complaint in miniature — Ming's Food & Grocery envelope opened $46,739.63 overdrawn on the day
  # she created it — and this pair of examples pinned it as law.
  #
  # NOW THE ENVELOPE IS DATED TODAY (`Pool#set_default_start_date`) and only counts spending from
  # today onward, so the acceptance moves nothing: the envelope opens at $0 and the buffer keeps
  # the history it always physically held. The examples are INVERTED rather than deleted, because
  # the fact worth pinning is the same one — what accepting does to WHERE the money reads — and a
  # rule that silently went back to dragging history would pass a suite that had merely dropped
  # these.
  #
  # EVERY FIGURE IS A PLANTED LITERAL AND THE TWO SIDES ARE INDEPENDENT. $2,000 goes in, $1,400
  # goes out, $600 is what the bank holds — three literals written here, never one computed from
  # the other two and never `Pool#total` compared against its own parts.
  #
  # THE ANCIENT ENTRY IS STILL THE POINT OF THE FIXTURE, and it now makes the OPPOSITE point. $500
  # spent 400 days ago is outside every window this page measures — `#rates` indexes only the last
  # six periods, so it moves neither the proposed $300 a period nor the "$900.00 spent in 3 of the
  # last 6 periods" the row prints — and under the old law it landed in the envelope anyway. Under
  # the rule it is the entry FURTHEST from qualifying, so an envelope that somehow counted it would
  # be visible at a glance.
  describe "the balance an accepted rate suggestion opens with", :aggregate_failures do
    before do
      deposit(2_000)
      groceries # $900 across the last three periods, which is what the row measures
      create(:entry, item: groceries.items.sole, amount: 500, date: Date.current - 400.days)
      visit budget_page_path
      # A WAITING ASSERTION BEFORE ANY MODEL READ, and `assert_selector` rather than `expect`
      # because a hook is not the place for an expectation (RSpec/ExpectInHook) — it still waits.
      # Two of the examples below assert on records rather than on the page, and `visit` alone
      # leaves the request in flight: the example ends, Capybara's `reset_sessions!` navigates the
      # renderer away underneath it, and the whole file dies of `InvalidSessionIdError` with zero
      # assertion failures. Diagnosed by CLAUDE.md's own procedure rather than written off.
      page.assert_selector("[data-suggestions]")
    end

    def deposit(amount)
      category = create(:category, :income, user: user, pool: checking, name: "Pay")
      create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
    end

    def pool_total = user.pools.reload.sum(0.to_d) { |pool| pool.calculator.balance }

    # THE ROW SAYS SO BEFORE THE CLICK (finding 2c). One clause, on the sentence already naming
    # which spending moves — burying the re-point to make room for it would be worse than omitting
    # it.
    it "says the envelope starts today and leaves earlier spending with main" do
      within(effect_of(:rate, groceries)) do
        expect(page).to have_content("from today onward")
        expect(page).to have_content("spending before today stays with your main account")
      end
    end

    # WHAT THIS PAIR USED TO MEASURE, AND WHAT IT MEASURES NOW. Before plan 3 the category named no
    # pool, so its $1,400 of spending reached NO pool at all: `Σ pools` read $2,000 against a bank
    # holding $600, and the acceptance closed that $1,400 gap. A category with no pool is not a
    # shape the app can hold any more — its spending comes out of the ACCOUNT, and the sum is
    # bank-true from the start — so the claim under test became CONSERVATION. The start-date rule
    # then made even the relocation stop happening: the acceptance moves NOTHING, the $1,400 stays
    # in the buffer, and this example's job is to plant the "before" the two below are measured
    # against rather than to make a claim of its own.
    it "starts with the sum already agreeing with the bank" do
      expect(pool_total).to eq(600)
    end

    it "opens the envelope at nothing, leaving the lifetime spending behind", :aggregate_failures do
      accept_and_create(:rate, groceries)

      expect(page).to have_content("Budget was successfully created")
      within("[data-pool-group='Groceries']") { expect(page).to have_no_content("overdrawn") }
      expect(groceries.reload.pool.calculator.balance).to eq(0)
    end

    # BOTH SIDES OF THE NON-MOVE, INDEPENDENTLY: the buffer still holds every dollar of the history,
    # the total does not move either, and no `pool_movements` row was written. The second and third
    # assertions were already true under the old law — it is the FIRST that inverted, and it is the
    # one that says the history stayed put rather than merely that the sum was conserved.
    it "leaves the history in the buffer without moving the total", :aggregate_failures do
      expect { accept_and_create(:rate, groceries) }.not_to change(PoolMovement, :count)

      expect(page).to have_content("Budget was successfully created")
      expect(checking.calculator.balance).to eq(600)
      expect(pool_total).to eq(600)
    end
  end

  private

  # ---------------------------------------------------------------------------------------------
  # Page readers
  # ---------------------------------------------------------------------------------------------

  def suggestion(kind, subject) = find("[data-suggestion='#{kind}:#{subject.id}']")

  # The two clauses every proposing row carries, addressed by their own hooks rather than by
  # searching the whole row: "puts all X spending in a new Y envelope" and "joins your existing Y
  # envelope" both mention Y, so a row-wide `have_content` cannot tell the two apart — which is
  # precisely the regression the sharing case has to catch.
  def effect_of(kind, subject) = suggestion(kind, subject).find("[data-suggestion-effect]")

  def rendered_keys = page.all("[data-suggestion]").pluck("data-suggestion")

  def index_link(kind) = find("[data-suggestions-index-link='#{kind}']")

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

  # THE THREE CAP STATES THIS USED TO PLANT ARE GONE (plan 3, task 3): a cap is not a shape the app
  # can hold, so the two `create(:budget, category: …)` lines and the row clause they fed are
  # deleted with it.
  def plant_everything
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
    @concert ||= create(:item, category: create(:category, :expense, user: user, name: "Fun", pool: checking), name: "Concert").tap do |item|
      create(:entry, item: item, amount: 200, date: Date.current - 20.days)
    end
  end

  # Three periods of $300, fourteen days apart so no pair is a whole month and the bill detector
  # keeps its hands off. Present in 3 of the last 6 and in the most recent 3, so both rate gates
  # open; measured over 3 periods, which is the span since it first appeared.
  def groceries
    @groceries ||= create(:category, :expense, user: user, name: "Groceries", pool: checking).tap do |category|
      item = create(:item, category: category, name: "Supermarket")
      [5, 19, 33].each { |days| create(:entry, item: item, amount: 300, date: Date.current - days.days) }
    end
  end

  def dining_pool
    @dining_pool ||= create(:pool, :budget_pool, user: user, account: checking, name: "Dining Out", priority: 1)
  end

  def dining_rule
    @dining_rule ||= create(:pool_budget, :per_period_rate, pool: dining_pool, amount: 150)
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

  # A rate rule spelled the OTHER legal way — `basis: monthly`, `interval_months: 1`, no anchor —
  # so `budgets.amount` is a monthly figure and `steady_ask` divides it down to $120.00 a period.
  # $800 of spend across the four-period drift window is $200.00 a period observed.
  def retirement_pool
    @retirement_pool ||= create(:pool, :budget_pool, user: user, account: checking, name: "Retirement", priority: 4)
  end

  def retirement_rule
    @retirement_rule ||= create(:pool_budget, :rate, pool: retirement_pool, amount: 260)
  end

  def plant_monthly_drift
    retirement_rule
    category = create(:category, :expense, user: user, name: "Retirement Extra", pool: retirement_pool)
    item = create(:item, category: category, name: "Brokerage Transfer")
    [5, 19, 33, 47].each { |days| create(:entry, item: item, amount: 200, date: Date.current - days.days) }
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
