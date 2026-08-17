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
      within(effect_of(:dated_bill, phone)) do
        expect(page).to have_content("puts all Utilities spending in a new Utilities envelope")
      end
      within(cap_note_of(:dated_bill, phone)) do
        expect(page).to have_content("$40.00 a month cap here is a spending limit")
      end
    end

    # AMENDMENT C, AND IT IS THE CASE THE CONCERN WAS RAISED ABOUT: five of the demo's rate
    # suggestions are for categories the user has already capped, and a rate row that said nothing
    # about the cap would read as the app failing to notice it. `Category.budgetable` is "expense,
    # no pool" and says nothing about caps, so the rate detector fires either way.
    it "names the cap on a rate suggestion too" do
      within(cap_note_of(:rate, groceries)) do
        expect(page).to have_content("$500.00 a month cap here is a spending limit")
      end
    end

    # THE NEGATIVE DIRECTION, on the same rendered screen as both positives: Concert's category was
    # never capped, so there is nothing to replace and the clause must not appear. Without this the
    # cap note could be unconditional and every assertion above would still pass.
    it "says nothing about a cap where the category has none" do
      within(suggestion(:dated_bill, concert)) do
        expect(page).to have_css("[data-suggestion-effect]")
        expect(page).to have_no_css("[data-suggestion-cap]")
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
  end

  # THE MOST LOAD-BEARING CASE ON THIS PAGE. Two bills in ONE category share ONE envelope: the
  # first acceptance creates it, and from then on the engine's payload reuses it by itself, so the
  # second must render and act as ADDING to that envelope rather than making a second one.
  describe "a second bill in the same category", :aggregate_failures do
    before do
      create(:budget, category: utilities, amount: 40)
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

    # And the cap clause goes with it: a pool-covered category cannot hold a cap
    # (`destroy_budget_if_pool_linked` took it on the first acceptance), so there is nothing left
    # to warn about and the row must not warn about it.
    it "stops naming a cap once the category is covered" do
      expect(utilities.reload.budget).to be_nil
      within(suggestion(:dated_bill, internet)) do
        expect(page).to have_no_css("[data-suggestion-cap]")
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
  # THE RE-POINT MOVES THE CATEGORY'S WHOLE ENTRY HISTORY, not its future spending.
  # `PoolBalanceLedger::ENTRY_POOL_ID` is `COALESCE(entries.pool_id, categories.pool_id)` with no
  # date bound and `PoolCalculator#balance` is start-date-agnostic, so the instant
  # `category.pool_id` is written, every entry that category ever carried is inside the new
  # envelope's lane. The envelope has no movements in, so it opens at exactly minus that total.
  #
  # THE DIRECTION IS TOWARD TRUTH, and that is the whole reason the code is right. A pool-less
  # expense category's spending was outside the pool tree: it left the bank and no pool recorded
  # it, so `Σ pools` was OVERSTATING the bank by exactly that lifetime figure. Both sides are
  # asserted, before and after, so the assertion is about the direction and not merely about a
  # number moving.
  #
  # EVERY FIGURE IS A PLANTED LITERAL AND THE TWO SIDES ARE INDEPENDENT. $2,000 goes in, $1,400
  # goes out, $600 is what the bank holds — three literals written here, never one computed from
  # the other two and never `Pool#total` compared against its own parts.
  #
  # THE ANCIENT ENTRY IS THE POINT OF THE FIXTURE. $500 spent 400 days ago is outside every window
  # this page measures — `#rates` indexes only the last six periods, so it moves neither the
  # proposed $300 a period nor the "$900.00 spent in 3 of the last 6 periods" the row prints — and
  # it lands in the envelope anyway. The panel's own figures cannot predict the balance the click
  # produces, which is why the row has to say so in words.
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
    # which spending moves — the row already warns about the re-point and about the cap it would
    # delete, and burying either of those to make room would be worse than omitting this.
    it "warns that the envelope will open carrying the category's past spending" do
      within(effect_of(:rate, groceries)) do
        expect(page).to have_content("past and future")
        expect(page).to have_content("carrying what has already been spent")
      end
    end

    # THE OVERSTATEMENT, MEASURED BEFORE THE CLICK. $2,000 arrived and $1,400 of it has been spent,
    # so the bank holds $600 — and `Σ pools` says $2,000, because a pool-less category's spending
    # reaches no pool at all. This is the gap the acceptance closes, and asserting it here is what
    # keeps the assertion below from reading as a regression.
    it "starts with the sum overstating the bank by the whole unpooled history" do
      expect(pool_total).to eq(2_000)
    end

    it "opens the envelope at minus the category's lifetime spending", :aggregate_failures do
      accept_and_create(:rate, groceries)

      expect(page).to have_content("Budget was successfully created")
      within("[data-pool-group='Groceries']") { expect(page).to have_content("overdrawn $1,400.00") }
      expect(groceries.reload.pool.calculator.balance).to eq(-1_400)
    end

    # THE OTHER SIDE, INDEPENDENTLY PLANTED. $600 is what the bank holds — $2,000 in, $1,400 out —
    # and after the acceptance the pool tree says the same thing for the first time. `Σ pools` fell
    # by exactly the lifetime spend, and no `pool_movements` row was written to make it happen.
    it "lands the sum on the bank-true figure, with no movement written", :aggregate_failures do
      expect { accept_and_create(:rate, groceries) }.not_to change(PoolMovement, :count)

      expect(page).to have_content("Budget was successfully created")
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

  def cap_note_of(kind, subject) = suggestion(kind, subject).find("[data-suggestion-cap]")

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

  # THREE CAP STATES ON ONE SCREEN, deliberately: Utilities capped (a dated bill that names it),
  # Groceries capped (a rate that names it — amendment C), and Concert's category left cap-less so
  # the clause has somewhere to be absent.
  def plant_everything
    create(:budget, category: utilities, amount: 40)
    plant_bill(phone, 85)
    plant_bill(internet, 65)
    concert
    create(:budget, category: groceries, amount: 500)
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
