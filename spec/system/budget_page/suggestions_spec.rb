# frozen_string_literal: true

require "rails_helper"

# THE BUDGET PAGE'S BOTTOM HALF (spec §8): four detectors over entry history, the sentence each one
# renders, and what accepting one actually writes.
#
# `Capybara.exact` is unset in this suite, so every assertion about a sentence is scoped to its own
# row with `within` — unscoped, "Utilities" matches a suggestion, a group heading and the nav all at
# once, and the guess assertions below would match the wrong row entirely.
#
# The history is planted rather than faked: `SuggestionEngine` is a reading of `entries`, and a
# stubbed engine would pin this page against a fixture instead of against the app.
RSpec.describe "Budget page suggestions", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  # HOLDING NOTHING YET (two-ledger spec §4), which is what a proposing suggestion is about: the
  # category has no `funded_since`, so `CategoryLedger::ENTRY_CATEGORY_ID` sends its every entry to
  # AVAILABLE and accepting is what starts it holding. The pool era spelled the same state as
  # "pointing at an account".
  let(:utilities) { create(:category, :expense, user: user, name: "Utilities") }
  let(:phone) { create(:item, category: utilities, name: "Phone") }
  let(:internet) { create(:item, category: utilities, name: "Internet") }

  before { sign_in user, scope: :user }

  # ** THE PANEL IS PER CATEGORY NOW (two-shapes spec §4), so "the four kinds" is four categories. **
  # `plant_everything` still plants all four at once — the point of the fixture is that the four
  # detectors fire on ONE user — and each example opens the category its own kind belongs to, which
  # is also what pins the partition: a bill's category is its ITEM's, a rate's is the category it
  # IS, and drift's and a dead rule's are their RULE's.
  describe "rendering the four kinds", :aggregate_failures do
    before { plant_everything }

    # §8's dated-bill row: what leaves the account, on what schedule, next when.
    it "states a detected bill with its schedule and its per-period cost" do
      open_category(utilities)

      within(suggestion(:dated_bill, phone)) do
        expect(page).to have_content("Phone — $85.00 every month")
          .and have_content("next due #{expected_due_on.strftime("%b %-d, %Y")}")
          .and have_content("Costs $39.23 a period")
      end
    end

    # BOTH DIRECTIONS ON ONE SCREEN, and the direction has REVERSED (answers-first Home spec §7).
    # A single payment used to be proposed with a guessed yearly interval and disclaimed in its own
    # second line ("one payment is not a schedule, so every 12 months is a guess"); the shape is
    # deleted rather than demoted, so the page renders a measured bill and nothing at all for the
    # one-off — planted here beside it, on the same screen, so the absence is a fact about this
    # render and not about a fixture that was never built.
    it "renders the measured bill and no row at all for a single payment", :aggregate_failures do
      open_category(utilities)
      within(suggestion(:dated_bill, phone)) { expect(page).to have_no_content("guess") }

      # AND THE CONCERT'S OWN CATEGORY IS OPENED to look for its row, because a suggestion absent
      # from Utilities' panel would be absent whether or not the engine had proposed it. The row is
      # asserted missing where it WOULD have been.
      open_category(concert.category)
      expect(page).to have_no_css("[data-suggestion='dated_bill:#{concert.id}']")
      expect(page).to have_no_content("is a guess")
    end

    # §8: `Coffee — $35 a period for 6 months, currently comes out of your buffer`, with the second
    # half re-anchored on what replaced that model and re-worded to the one surviving noun
    # (answers-first Home spec §3 — "buffer" is a dead word; this screen says available). The divisor is named too: the amount is the
    # total over periods LIVED THROUGH, not over appearances.
    it "states a detected rate, its window and that nothing holds it" do
      open_category(groceries)

      within(suggestion(:rate, groceries)) do
        expect(page).to have_content("Groceries — $300.00 a period")
          .and have_content("currently claimed by no rule")
          .and have_content("$900.00 spent in 3 of the last 6 periods")
          .and have_content("averaged over 3 periods")
      end
    end

    # §8: `Groceries has averaged $470 for 4 periods, your rule says $420`. Both figures are per
    # period — the rule's side is `Budget#steady_ask`, never `budgets.amount`.
    it "states drift with both figures in the same unit" do
      open_category(dining)

      within(suggestion(:drift, dining_rule)) do
        expect(page).to have_content("Dining Out has averaged $45.00 a period for 4 periods")
          .and have_content("your rule asks for $150.00 a period")
          .and have_content("reserving $105.00 a period more than you spend")
      end
    end

    # §8: `Netflix stopped in October, the rule is still funding it`.
    it "states a dead rule in the unit the money leaves in" do
      open_category(streaming)

      within(suggestion(:dead_rule, netflix_rule)) do
        expect(page).to have_content("Netflix stopped on")
          .and have_content("nothing for 3 periods")
          # "still CLAIMING $X a period for it", not "still funding it" (fix round LOW-8): nothing
          # funds anything — a claim is computed and no money is moved into a category — so
          # "funding" was the moved-money vocabulary surviving in the one sentence that names what
          # the rule is doing wrong.
          .and have_content("still claiming $55.38 a period for it")
          .and have_content("The rule says $120.00 a month")
      end
    end

    # ** NOTHING IS DROPPED BY THE MOVE INSIDE THE CATEGORIES (two-shapes spec §4). ** The old
    # examples here read one page-wide panel: every suggestion rendered in the engine's order, an
    # index strip that summed to the whole list, and a heading per run. There is no page-wide panel
    # and no index — a category's panel is two or three rows under one heading and has nothing to
    # navigate — so what those examples were really protecting is asserted the way it now exists:
    # every suggestion the engine returns is reachable, in exactly one category, and the BADGE on
    # each row says how many are in it before anything is opened.
    #
    # FIVE, WHERE IT WAS SIX (answers-first Home spec §7). The row that left is the Concert — one
    # $200 payment, which the engine used to propose as a guessed yearly bill and no longer proposes
    # at all.
    it "reaches every suggestion the engine returns, each in exactly one category" do
      found = user.categories.expenses.flat_map do |category|
        open_category(category)
        rendered_keys
      end

      expect(found).to match_array(SuggestionEngine.new(user: user).suggestions.map { |s| "#{s.kind}:#{s.subject.id}" })
      expect(found.size).to eq(5)
      expect(found.uniq.size).to eq(5)
    end

    # ** THE BADGE IS THE INDEX'S SUCCESSOR, AND IT SUMS TO THE SAME LIST. ** The counts are checked
    # against the ROWS the panels actually show rather than against the engine, because a badge that
    # agreed with the engine and disagreed with what is on screen would be exactly the defect the
    # index strip was pinned against: a number promising two bills over a list of one.
    it "counts each category's own suggestions on its row", :aggregate_failures do
      open_category(utilities)

      expect(badge_for(utilities).text).to eq("2 suggestions")
      expect(badge_for(groceries).text).to eq("1 suggestion")
      expect(badge_for(dining).text).to eq("1 suggestion")
      expect(badge_for(streaming).text).to eq("1 suggestion")
      expect(rendered_keys.map { |key| key.split(":").first }.tally).to eq("dated_bill" => 2)
    end

    # ** AND A CATEGORY WITH NOTHING WEARS NO BADGE. ** The singular is on screen here too, which is
    # the copy nobody notices until it ships: "1 suggestions" would pass an assertion about the
    # count alone.
    it "puts no badge on a category the engine has nothing for" do
      quiet = create(:category, :expense, :funded, user: user, name: "Quiet")
      open_category(quiet)

      expect(page).to have_no_css("[data-category-row='Quiet'] [data-suggestion-badge]")
    end

    # ** ONE CATEGORY'S PANEL SHOWS ONLY ITS OWN (§4), which is the whole partition said on screen. **
    # Both directions on one render: the two Utilities bills are there and the three suggestions
    # about other categories are not — a panel rendering the engine's whole list would pass a check
    # for presence alone.
    it "shows only that category's suggestions in its panel", :aggregate_failures do
      open_category(dining)

      expect(rendered_keys).to eq(["drift:#{dining_rule.id}"])
      expect(page).to have_no_css("[data-suggestion='dated_bill:#{phone.id}']")
      expect(page).to have_no_css("[data-suggestion='rate:#{groceries.id}']")
    end

    # HENRY'S RULING OF 2026-08-20 REVERSES §8 HERE, and this example is the inversion of the one
    # that stood in its place — "offers no way to dismiss one", which asserted the absence of
    # exactly this affordance. It is inverted rather than deleted because the fact worth pinning is
    # the same one: whether the panel can hide a row. It can, on every row, and on purpose.
    it "offers a way to hide every one of them" do
      open_category(utilities)

      expect(page.all("[data-suggestion]").size).to eq(2)
      expect(page.all("[data-suggestion] button", text: "Hide").size).to eq(2)
    end

    # NOTHING IS HIDDEN UNTIL THE USER HIDES IT. The foot section is state, so its absence on a
    # panel nobody has touched is what says the list above is complete.
    it "shows no hidden section until something is hidden" do
      open_category(utilities)

      expect(page).to have_no_css("[data-hidden-suggestions]")
    end

    # WHAT ACCEPTING DOES, SAID BEFORE THE CLICK — the sentence that replaced the re-point clause
    # (two-ledger spec §3/§4). Nothing is re-pointed and no envelope is made; what changes besides
    # the rule is which side of the start-date rule this category's future spending falls on.
    it "says what accepting does to the category" do
      open_category(utilities)

      within(effect_of(:dated_bill, phone)) do
        expect(page).to have_content("starts Utilities counting its own spending, from today onward")
      end
    end

    # THE RE-POINT CLAUSE AND THE CAP CLAUSE ARE BOTH GONE FROM THE PANEL. The cap's went in plan 3;
    # the re-point's goes here, and its absence is asserted for the same reason the cap's was — a
    # regression restoring either would be a sentence promising an act this app cannot perform.
    it "says nothing about moving a category into an envelope, or about a cap" do
      open_category(utilities)

      within("[data-suggestions='Utilities']") do
        expect(page).to have_css("[data-suggestion-effect]")
        expect(page).to have_no_css("[data-suggestion-cap]")
        expect(page).to have_no_content("envelope")
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
      open_category(utilities)
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
      open_category(utilities)

      expect(page).to have_css("[data-suggestions='Utilities']")
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
    # ** THE EMPTY STATE IS THE PANEL'S ABSENCE NOW (two-shapes spec §4). ** The page-wide panel had
    # to say "Nothing to suggest" because it was a permanent section with a heading over it; inside
    # a category, a heading over nothing IS the noise, so the "Your entries suggest" block simply is
    # not rendered — and the row above it wears no badge, which is where the same fact is said.
    it "says nothing at all where there is nothing to suggest", :aggregate_failures do
      utilities
      open_category(utilities)

      expect(page).to have_css("[data-category-row='Utilities']")
      expect(page).to have_no_css("[data-suggestions='Utilities']")
      expect(page).to have_no_css("[data-suggestion]")
      expect(page).to have_no_css("[data-suggestion-badge]")
    end
  end

  describe "accepting a proposed bill", :aggregate_failures do
    before do
      plant_bill(phone, 85)
      plant_bill(internet, 65)
      open_category(utilities)
    end

    # THE ENVELOPE HALF IS GONE FROM THIS FORM (two-ledger spec §3), and one example goes with it:
    # "heads the form as a creation, and asks for the account" pinned the `envelope[name]` field,
    # the `envelope[account_id]` picker and the "A new Utilities envelope" heading — three controls
    # for an act this app no longer performs. What is left is the rule's own shape, which is what
    # the engine measured and what the user can correct.
    it "lands on a form prefilled with everything the engine measured" do
      accept(:dated_bill, phone)

      # ** THE FORM IS ITS OWN PAGE, TITLED BY THE CATEGORY THE PANEL NAMED (two-shapes spec §5). **
      # "What Utilities claims each period" was the picker-era subtitle; the accept link carries
      # `category_id` beside its payload, so the page it lands on says whose rule this is going to be.
      expect(page).to have_content("New rule for Utilities")
      expect(page).to have_field("Amount", with: "85.0")
      expect(page).to have_field("Comes round every (months)", with: "1")
      expect(page).to have_select("Pays", selected: "Phone")
    end

    # ** WHICH TYPE A SUGGESTION PROPOSES (rules-own-the-budget spec §3): A DATED BILL PROPOSES
    # `bill`. ** It was measured from payments that actually landed on a cycle, which is what "must
    # be paid" means — and the radio is on screen, checked, so the user confirms before anything is
    # written rather than discovering the classification on the Budget page afterwards. The type
    # decides the GIVE-WAY ORDER when free money goes below zero, so a proposal that guessed
    # silently would be answering a question about what this person is willing to sacrifice.
    it "preselects the type it proposes, and writes it" do
      accept(:dated_bill, phone)

      expect(page).to have_checked_field("Bill")

      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      expect(Budget.find_by(item_id: phone.id)).to be_bill
    end

    # THE SCHEDULE ARRIVES AS THE FORM'S OWN WORDS TOO. A monthly bill WITH a due date is "by a
    # date, repeating every 1 month" — the same pair of controls the half-yearly bill uses — so the
    # radio and the checkbox are both checked and the interval field is revealed rather than the
    # shape riding hidden.
    #
    # ** THE LABELS ARE TWO-SHAPES' (§5), AND THIS EXAMPLE HAD NOT CAUGHT UP. ** It read
    # `have_checked_field("Every N months")` and `have_field("First due")` — the controls of the
    # THREE-shape form Task 1 replaced — and had been failing since that commit; this file was not
    # among the ones re-run for it (see this task's report).
    it "opens on the by-a-date row with its interval revealed", :aggregate_failures do
      accept(:dated_bill, phone)

      expect(page).to have_checked_field("By a date")
      expect(page).to have_checked_field("Repeats every N months")
      expect(page).to have_field("Comes round every (months)", with: "1")
      expect(page).to have_field("Due")
      expect(page).to have_no_content("Unspent money")
    end

    # THE OWNER IS ALREADY IN CONTEXT HERE, so the hand-made form's category picker (Henry's ruling
    # of 2026-08-20) must not appear on this path: the payload names the category this rule will
    # fill, and a select beside it would offer to send the rule somewhere the panel's own sentence
    # one click earlier did not promise.
    it "offers no category picker, because the payload already names the owner" do
      accept(:dated_bill, phone)

      expect(page).to have_no_select("Category")
    end

    # THE ROUND TRIP: accept, and the rule is in the category's table while the suggestion has left
    # its panel — because the item now carries a rule, which is the engine's own retirement test.
    # Both facts are inside ONE category's panel now, which is what the move bought: the rule and
    # the proposal it retired are two inches apart rather than two screens.
    it "writes the rule, which retires its own suggestion", :aggregate_failures do
      accept_and_create(:dated_bill, phone)

      expect(page).to have_content("Budget was successfully created")
      open_category(utilities)
      within("[data-category-panel='Utilities']") do
        expect(page).to have_css("[data-rule='Phone']")
        expect(page).to have_no_css("[data-suggestion='dated_bill:#{phone.id}']")
      end
    end

    # THE SECOND WRITE. "creates the envelope and re-points the category at it" is what stood here,
    # and this is the act that replaced both halves of it: the category starts holding its own money
    # today, which is the whole of what `BudgetProposal` does besides saving the rule.
    it "starts the category holding money from today" do
      accept_and_create(:dated_bill, phone)

      expect(page).to have_content("Budget was successfully created")
      expect(utilities.reload.funded_since).to eq(Date.current)
    end

    # THE DATE IS CORRECTABLE BEFORE ACCEPTING (Henry's ruling, 2026-08-20). The anchor is an
    # INFERENCE — `SuggestionEngine#next_due_on` walks the last payment forward by the interval —
    # and it rode hidden while the amount beside it was editable, so a bill whose last payment was
    # late wrote a rule whose whole schedule was late with it. The prefill is still the engine's
    # answer; what changed is that the user can see it and say otherwise.
    it "prefills the date the engine inferred" do
      accept(:dated_bill, phone)

      expect(page).to have_field("Due", with: expected_due_on.strftime("%Y-%m-%d"))
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
      fill_in "Due", with: corrected_due_on
      click_button "Create rule"

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
      open_category(groceries)
    end

    it "offers no date field" do
      accept(:rate, groceries)

      expect(page).to have_field("Amount", with: "300.0")
      expect(page).to have_no_field("First due")
    end

    # ** A RATE PROPOSES `usage` (§3). ** What this detector found is a category the user spends in
    # every period with no rule for it — a real need whose amount moves with how they live, which is
    # `usage`'s own definition and the column's default besides. A rate that proposed `bill` would
    # be claiming something the spending history does not say, and the give-way order is built on
    # the answer.
    # ** "Every period" IS THE FORM'S WORD SINCE TWO-SHAPES (§5), and the "Resets each period" radio
    # is DELETED WITH THE UNSPENT-MONEY STEP (§7) — an allowance that resets is the only dateless
    # shape left, so there is nothing for that control to choose between. This example named both of
    # the retired controls and had been failing since Task 1.
    it "preselects usage, and opens on the every-period row", :aggregate_failures do
      accept(:rate, groceries)

      expect(page).to have_checked_field("Usage")
      expect(page).to have_checked_field("Every period")
      expect(page).to have_no_content("Unspent money")
    end

    it "writes the type it proposed" do
      accept(:rate, groceries)
      click_button "Create rule"

      expect(page).to have_content("Budget was successfully created")
      expect(groceries.budgets.sole).to be_usage
    end
  end

  # TWO BILLS IN ONE CATEGORY ARE TWO RULES ON ONE OWNER, and it is the case the pool era needed a
  # find-or-create cascade for: the first acceptance made the envelope and the second had to ADD to
  # it rather than make a second one and re-point the category away from the first. There is nothing
  # to reuse and nothing to re-point — but the ROW still says something different the second time,
  # because the category is already holding money by then.
  #
  # THREE EXAMPLES ARE DELETED WITH THE CASCADE (two-ledger spec §5): the whole "a category whose
  # proposed envelope name is already taken" block — the join sentence, the join-headed form and the
  # rule landing in the existing envelope — and "a category already pointing at a goal", which
  # pinned that the reuse arm printed `Pool#noun` rather than calling every pool an envelope. All
  # four named branches of a reuse decision this flow no longer makes.
  describe "a second bill in the same category", :aggregate_failures do
    before do
      plant_bill(phone, 85)
      plant_bill(internet, 65)
      open_category(utilities)
      accept_and_create(:dated_bill, phone)
    end

    # THE COPY HALF, and the negative is the whole assertion. A regression that printed the
    # STARTING sentence here would promise a change of state that has already happened and will not
    # happen again — and it would be telling the user their earlier spending is about to move.
    it "says the category already counts its own spending, without promising to start it again" do
      expect(page).to have_content("Budget was successfully created")
      within(effect_of(:dated_bill, internet)) do
        expect(page).to have_content("Utilities already counts its own spending")
        expect(page).to have_no_content("from today onward")
      end
    end

    it "lands as a second rule on that same category" do
      accept_and_create(:dated_bill, internet)

      expect(page).to have_content("Budget was successfully created")
      expect(utilities.reload.budgets.map { |rule| rule.item.name }).to contain_exactly("Phone", "Internet")
    end

    it "shows both rules in one group on the page" do
      accept_and_create(:dated_bill, internet)

      expect(page).to have_content("Budget was successfully created")
      # ** THE ROW READS THE CLAIM, NOT THE STICKER (§4). ** It asserted `$85.00 a month` twice —
      # `budget_rule_amount`, deleted with the group card — so the two rules are pinned by their
      # own lanes and their shape clauses, which is what the panel actually prints.
      open_category(utilities)
      within("[data-category-panel='Utilities']") do
        expect(page).to have_css("[data-rule='Phone']").and have_css("[data-rule='Internet']")
        expect(page.all("[data-rule-shape]").map(&:text)).to all(include("every month"))
      end
    end
  end

  describe "accepting a drift", :aggregate_failures do
    before do
      plant_drift
      open_category(dining)
    end

    # THE FIGURE ARRIVES IN THE RULE'S OWN UNIT and the form labels it rather than converting it.
    # The rule here is per-period, so the two coincide — which is exactly why the monthly case
    # below exists, and why this example alone would prove nothing about units.
    it "prefills the observed figure beside the current one" do
      accept(:drift, dining_rule)

      expect(page).to have_field("Amount", with: "45.0")
      expect(page).to have_content("Currently $150.00 per period")
    end

    it "changes the rule and retires the drift" do
      accept(:drift, dining_rule)
      click_button "Update rule"

      expect(page).to have_content("Budget was successfully updated")
      expect(dining_rule.reload.amount).to eq(45)
      expect(page).to have_no_css("[data-suggestion='drift:#{dining_rule.id}']")
    end
  end

  # ** THE UNITS SEPARATED, AND THE SEPARATION CLOSED (two-shapes Task 4, fix round 1's ruling). **
  # The anchorless MONTHLY rule is the shape `rate_shape?` deliberately admits alongside
  # `per_period`, and it is the one where `budgets.amount` is NOT a per-period figure: a $260-a-month
  # rule claims `260 × 12 ÷ 26` = $120.00 a period from a biweekly user.
  #
  # The engine used to invert its observed per-period figure back into that column ($200 a period →
  # $433.33 a month) because the FORM's box held the column raw. It does not: `RuleForm.from` reads
  # such a row back as per-period money, so the box, the panel and the engine are all in one unit and
  # the inversion is deleted (`SuggestionEngine#rule_unit_amount`). What the examples below pin is
  # that the drift now writes the money it proposed — $200.00 a period, exactly — and that the two
  # figures a user has to reconcile ($260 a month, $120 a period) are each said once, in their own
  # place.
  describe "accepting a drift on a monthly rule", :aggregate_failures do
    before do
      plant_monthly_drift
      open_category(retirement)
    end

    it "states the drift in per-period money" do
      within(suggestion(:drift, retirement_rule)) do
        expect(page).to have_content("has averaged $200.00 a period for 4 periods")
          .and have_content("your rule asks for $120.00 a period")
      end
    end

    # ** THE FIELD IS IN THE PANEL'S OWN UNIT NOW, AND THE ROW'S UNIT IS SAID BESIDE IT. ** The
    # per-period figure used to be asserted ABSENT from this whole page, because the box held monthly
    # money and two unlabelled units on one screen is how a user comes to write the wrong number. The
    # box holds per-period money, so the panel's $200.00 goes straight into it; what needs labelling
    # is the ROW's $260.00 a month.
    #
    # ** THE NOTE SAYS IT, AND THE "Currently …" LINE STANDS DOWN (fix wave — MED-4). ** Both
    # rendered here, and the note's version was FALSE: "shown here as what it costs each period …
    # Saving keeps that cost" over a box holding $200.00, on the one act whose entire purpose is to
    # change the cost. The note names the three figures instead — what the entries suggest, what the
    # row says, and what the row comes to on this grid — and the duplicate line beside it goes.
    it "prefills the form with the money the panel proposed, and labels the row's own unit", :aggregate_failures do
      accept(:drift, retirement_rule)

      expect(page).to have_field("Amount", with: "200.0")
      expect(page).to have_css(
        "[data-monthly-conversion]",
        text: "Your entries suggest $200.00 a period. This rule was $260.00 a month " \
              "($120.00 a period on your biweekly grid)."
      )
      expect(page).to have_no_css("[data-current-amount]")
      expect(page).to have_css("[data-preview-units]", text: "$260.00 a month · $200.00 a period")
    end

    # ** THE ROUND TRIP CLOSES (Task 1's concern 4, closed by fix round 1's ruling). ** For three
    # tasks this example was pinned AS IT BEHAVED and disclaimed in its own header: the engine put
    # $433.33 a month on the wire, the form saved it as a PER-PERIOD amount, and the rule came out
    # asking 3.6× what the drift row had proposed — with a warning in words as the only defence.
    # Both halves of that are gone. The engine's inversion is deleted and the read-back divides, so
    # accepting a drift writes the money the panel measured: **$200.00 a period**, which is what
    # `Budget#steady_ask` reads back off the saved row. The conversion still happens — the shape
    # changes — and the note now explains it rather than warning about it.
    it "writes the money the drift proposed, and says what it did to the shape", :aggregate_failures do
      accept(:drift, retirement_rule)

      # NOT "Saving keeps that cost" — it does not, and that is the point of accepting a drift
      # (fix wave — MED-4). The note names the row's own figures and promises nothing.
      expect(page).to have_css("[data-monthly-conversion]", text: "This rule was $260.00 a month")
      expect(page).to have_no_content("Saving keeps that cost")

      click_button "Update rule"

      expect(page).to have_content("Budget was successfully updated")
      expect(retirement_rule.reload).to have_attributes(basis: "per_period", amount: 200)
      expect(retirement_rule.steady_ask(user)).to eq(200)
    end
  end

  # THE PAGE DOES NOT DELETE — the user does. Both doors are on the row because entry history
  # cannot tell a cancelled subscription from a replaced card.
  describe "a dead rule", :aggregate_failures do
    before do
      plant_dead_rule
      open_category(streaming)
    end

    it "opens the rule for review rather than deleting it" do
      within(suggestion(:dead_rule, netflix_rule)) { click_link "Review the rule" }

      expect(page).to have_field("Amount", with: "120.0")
      expect(Budget.exists?(netflix_rule.id)).to be true
    end

    it "deletes it only when the user asks" do
      accept_confirm { within(suggestion(:dead_rule, netflix_rule)) { click_button "Delete the rule" } }

      expect(page).to have_content("Budget was successfully deleted")
      expect(Budget.exists?(netflix_rule.id)).to be false
    end
  end

  # ** WHAT ACCEPTING DOES TO THE MONEY — re-anchored on claims (computed-claims spec §2/§3.1). **
  #
  # THE HISTORY DOES NOT MOVE, AND IT USED TO MOVE ALL OF IT. Before the start-date rule the
  # acceptance re-pointed the category at a brand-new envelope with no date bound, so every entry
  # that category had ever carried fell inside the envelope's lane and it opened at minus its
  # lifetime spend — Ming's Food & Grocery envelope opened $46,739.63 overdrawn on the day she made
  # it, which is §1's opening complaint. `BudgetProposal` stamps `funded_since` TODAY, and
  # `CategoryLedger::ENTRY_CATEGORY_ID` counts an expense against its category only from that day
  # on — so the claim opens at the rule's full rate rather than at minus a lifetime.
  #
  # ** WHAT CHANGED WITH THE MODEL, AND IT IS THE SUBJECT OF THE LAST TWO EXAMPLES. ** Under moved
  # money, accepting a rule wrote nothing and `available` did not budge; the envelope filled later,
  # when a distribution ran. Under computed claims there is no later: the rule IS the claim, so
  # `Σ claims` rises by the rule's whole rate the instant it is written (§2). That is not the history
  # moving, which is exactly what the pair below separates: the $1,400 already spent stays spent and
  # stays out of the claim, and the ONLY thing that moves is the new rule's own $300.
  #
  # ** `ClaimLedger#total_claims` RATHER THAN `#free`, AND THE CAP IS WHY. ** `free` is
  # `min(pot, total_money − Σ claims)` and this fixture has no bank account at all — every screen
  # here is about rules — so the pot binds at zero and `free` would read zero before and after,
  # which is true and says nothing about the subject. Σ claims is the purpose side asked directly.
  #
  # EVERY FIGURE IS A PLANTED LITERAL AND THE SIDES ARE INDEPENDENT. $2,000 comes in and $1,400 goes
  # out — two literals written here. The accepted rate is $300 a period (the engine's own proposal
  # off $900 in 3 of the last 6 periods), so Σ claims goes from $0 to exactly $300 and not to
  # $1,700.
  #
  # NOTHING IS SPENT IN THE CURRENT PERIOD, WHICH IS WHY THE CLAIM IS THE WHOLE RATE. The user is
  # biweekly anchored on today, and the three $300 entries are 5, 19 and 33 days back — every one of
  # them in a period already closed. §3.1's `max(0, rate − spent)` therefore has nothing to subtract.
  #
  # THE ANCIENT ENTRY IS THE POINT OF THE FIXTURE. $500 spent 400 days ago is outside every window
  # this page measures — `#rates` indexes only the last six periods, so it moves neither the
  # proposed $300 a period nor the "$900.00 spent in 3 of the last 6 periods" the row prints — and
  # under the old law it landed in the envelope anyway. Under the rule it is the entry FURTHEST from
  # qualifying, so a category that somehow counted it would be visible at a glance.
  describe "what an accepted rate suggestion opens the category with", :aggregate_failures do
    before do
      deposit(2_000)
      groceries # $900 across the last three periods, which is what the row measures
      create(:entry, item: groceries.items.sole, amount: 500, date: Date.current - 400.days)
      open_category(groceries)
      # A WAITING ASSERTION BEFORE ANY MODEL READ, and `assert_selector` rather than `expect`
      # because a hook is not the place for an expectation (RSpec/ExpectInHook) — it still waits.
      # Two of the examples below assert on records rather than on the page, and `visit` alone
      # leaves the request in flight: the example ends, Capybara's `reset_sessions!` navigates the
      # renderer away underneath it, and the whole file dies of `InvalidSessionIdError` with zero
      # assertion failures. Diagnosed by CLAUDE.md's own procedure rather than written off.
      page.assert_selector("[data-suggestions]")
    end

    def deposit(amount)
      category = create(:category, :income, user: user, name: "Pay")
      create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
    end

    def total_claims = ClaimLedger.new(user.reload).total_claims

    def spending_on(category) = category.entries.sum(:amount)

    # THE ROW SAYS SO BEFORE THE CLICK. One clause, on the sentence already naming which category
    # starts counting its own spending — burying it to make room for something else would be worse
    # than omitting it.
    it "says the category starts today and leaves earlier spending out of the claim" do
      within(effect_of(:rate, groceries)) do
        expect(page).to have_content("from today onward")
        expect(page).to have_content("spending before today is money already gone")
      end
    end

    # The "before" the two below are measured against: $1,400 of lifetime spending on Groceries, and
    # no rule claiming a penny of it.
    it "starts with nothing claimed and the whole history already spent", :aggregate_failures do
      expect(total_claims).to eq(0)
      expect(spending_on(groceries)).to eq(1_400)
    end

    it "opens the category claiming its whole rate, not minus its lifetime spending" do
      accept_and_create(:rate, groceries)

      expect(page).to have_content("Budget was successfully created")
      open_category(groceries)
      within("[data-category-panel='Groceries']") { expect(page).to have_no_content("over by") }
      expect(groceries.reload.claim).to eq(300)
    end

    # BOTH HALVES OF "THE HISTORY DID NOT MOVE", INDEPENDENTLY: Σ claims rises by the new rule's rate
    # and by NOTHING else — $300, not $300 + $1,400 — and no dated delta was written, because a rule
    # is not an adjustment and accepting one records no movement of any kind (§5).
    it "claims only the new rule's own rate, and writes no delta", :aggregate_failures do
      expect { accept_and_create(:rate, groceries) }.not_to change(Adjustment, :count)

      expect(page).to have_content("Budget was successfully created")
      expect(total_claims).to eq(300)
      expect(spending_on(groceries)).to eq(1_400)
    end
  end

  private

  # ---------------------------------------------------------------------------------------------
  # Page readers
  # ---------------------------------------------------------------------------------------------

  def suggestion(kind, subject) = find("[data-suggestion='#{kind}:#{subject.id}']")

  # ** EVERY SUGGESTION IS INSIDE THE CATEGORY IT IS ABOUT (two-shapes spec §4), so a spec about one
  # opens that category. ** The closed panels are rendered and `hidden`, which is exactly what
  # Capybara refuses to see; `?open=` is the same parameter the chevron writes, the categories
  # page's pointer carries, and the Hide/Show redirects come back with.
  def open_category(category) = visit(budget_page_path(open: category.id))

  # THE BADGE ON A CATEGORY'S ROW — the count `SuggestionEngine#by_category` puts in the panel, said
  # on the row above it, so a reader can see where the proposals are without opening anything.
  def badge_for(category) = find("[data-category-row='#{category.name}'] [data-suggestion-badge]")

  # The clause every proposing row carries, addressed by its own hook rather than by searching the
  # whole row: the category's name appears in the row's own sentence too, so a row-wide
  # `have_content` cannot tell the two apart — which is precisely the regression the second-bill
  # case has to catch.
  def effect_of(kind, subject) = suggestion(kind, subject).find("[data-suggestion-effect]")

  def rendered_keys = page.all("[data-suggestion]").pluck("data-suggestion")

  # ** `#index_link` IS DELETED WITH THE INDEX STRIP (two-shapes spec §4). ** It found a link into
  # one run of the page-wide panel; there are no runs, and `#badge_for` above is what says how many
  # a category has.

  def accept(kind, subject)
    within(suggestion(kind, subject)) { click_link suggestion_accept_label(kind) }
  end

  def suggestion_accept_label(kind)
    # "Write it →" IS THE MOCK'S OWN WORDING (§4) and replaces "Write this rule": every one of the
    # four opens a form the user then saves, so the noun was a promise the button does not keep.
    { drift: "Update the rule", dead_rule: "Review the rule" }.fetch(kind, "Write it →")
  end

  # `have_content` after the click and BEFORE any model read: `click_button` returns as soon as the
  # click is dispatched, and a bare `expect(model.reload…)` would end the example mid-request.
  def accept_and_create(kind, subject)
    accept(kind, subject)
    click_button "Create rule"
    # THE PAGE COMES BACK WITH NO CATEGORY OPEN (`BudgetsController` redirects to `/budget`), so the
    # waiting assertion is on the LIST rather than on a panel — a `have_css` on a hidden panel would
    # never settle and the example would end mid-request, which is CLAUDE.md's first cause.
    expect(page).to have_css("[data-category-list]")
  end

  # ---------------------------------------------------------------------------------------------
  # The planted history — one detector at a time, and the whole lot for the rendering block
  # ---------------------------------------------------------------------------------------------

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

  # ONE payment, and big enough that the deleted guessed shape would have proposed it ($100 floor).
  # It is still planted, because "no row" is only worth asserting over a fixture that would once
  # have produced one — see the rendering block's dated-bill example.
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

  # A CATEGORY THAT HOLDS MONEY — the drift lane. The spending item lives IN it, which is what the
  # pool era arranged one layer out with a second category pointing at the same envelope.
  def dining
    @dining ||= create(:category, :expense, :funded, user: user, name: "Dining Out", priority: 1)
  end

  def dining_rule
    @dining_rule ||= create(:budget, :per_period_rate, category: dining, amount: 150)
  end

  # A rate rule against a lane that carries far less than it reserves: $180 over the four-period
  # window is $45 a period against $150. Two payments under the $100 bill floor, so nothing here
  # is also proposed as a dated bill.
  def plant_drift
    dining_rule
    item = create(:item, category: dining, name: "Takeout")
    [5, 19].each { |days| create(:entry, item: item, amount: 90, date: Date.current - days.days) }
  end

  # A rate rule spelled the OTHER legal way — `basis: monthly`, `interval_months: 1`, no anchor —
  # so `budgets.amount` is a monthly figure and `steady_ask` divides it down to $120.00 a period.
  # $800 of spend across the four-period drift window is $200.00 a period observed.
  def retirement
    @retirement ||= create(:category, :expense, :funded, user: user, name: "Retirement", priority: 4)
  end

  def retirement_rule
    @retirement_rule ||= create(:budget, :rate, category: retirement, amount: 260)
  end

  def plant_monthly_drift
    retirement_rule
    item = create(:item, category: retirement, name: "Brokerage Transfer")
    [5, 19, 33, 47].each { |days| create(:entry, item: item, amount: 200, date: Date.current - days.days) }
  end

  def streaming
    @streaming ||= create(:category, :expense, :funded, user: user, name: "Streaming", priority: 2)
  end

  def netflix_item
    @netflix_item ||= create(:item, category: streaming, name: "Netflix")
  end

  def netflix_rule
    @netflix_rule ||= create(
      :budget,
      category: streaming,
      item: netflix_item,
      amount: 120,
      interval_months: 1,
      anchor_date: Date.current - 10.days
    )
  end

  # The last payment falls the day before the three-period window opens — the near side of the
  # boundary the engine's own examples pin.
  def plant_dead_rule
    netflix_rule
    create(:entry, item: netflix_item, amount: 120, date: Date.current - 50.days)
  end
end
