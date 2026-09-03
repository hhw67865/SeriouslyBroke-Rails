# frozen_string_literal: true

require "rails_helper"

# HOME'S PROBLEMS ARE ACTIONABLE (spec §4.2), and Home adopts the distribution's post-sweep view so
# the figure it prints and the figure the button acts on are the same one.
#
# CONVERTED TO THE PURPOSE LEDGER (Task 6). Every fixture here was an envelope inside Checking and
# every button opened `/account_movements/new`; the fixture is now `spec/support/allocation_move_
# context.rb` — the same eight shapes at the same figures — and the buttons open `/allocations/new`.
# The pool-era context and the screen it served are deleted.
#
# `Capybara.exact` is unset, so `have_content("$300.00")` also matches "$1,300.00" and the sidebar.
# Every figure below is scoped to the problem row that owns it via `[data-problem-category]`.
#
# Every example body makes a Capybara call after its `visit`. A body that asserts only against the
# database finishes before the page settles and races `spec/support/capybara.rb`'s per-example
# driver quit, which surfaces as `InvalidSessionIdError` with no assertion failure at all.
RSpec.describe "Home Fixes", type: :system do
  # ────────────────────────────────────────────────────────────────────────────────────────────
  describe "the fix a problem offers" do
    include_context "with categories to reallocate between"

    # THE PERIOD HAS TO BE SHORT BEFORE THE MONEY REACHES DENTIST, or every example below would be
    # measuring the wrong branch. Dentist is priority 1 in that fixture, so the waterfall funds its
    # whole $300 out of the $960 post-sweep root — and a problem the next distribution solves by
    # itself is deliberately given no button (see the last describe in this file). This example group
    # is about which SOURCE a genuine problem is offered, so the problem has to be genuine.
    #
    # A $5,000 tuition bill at priority 0 is the household's own answer to "what comes first", and it
    # takes the root before anything below it: `required` spreads it over the five biweekly
    # boundaries before its due date, so it asks $1,000 against a $960 root and Dentist gets nothing.
    # It never becomes a problem row of its own (a bill with periods left to run is `on_track`) and it
    # is never a candidate (nothing funded it, so `free_amount` is zero), so it changes no other
    # figure in this file.
    before { dated_rule(holder("Tuition", priority: 0), "Autumn Term", 5_000, due_in: 60) }

    def problem_row(name) = find("[data-problem-category='#{name}']")

    # AVAILABLE holds $810 of unclaimed cash and Dentist needs $300 it will never reach in time.
    # The root is a legitimate source and the FIRST one — idle money costs nothing to move, while a
    # category's money is money the user decided to protect.
    it "names a source that can cover it, and says what the move would cost", :aggregate_failures do
      visit root_path

      within(problem_row("Dentist")) do
        expect(page).to have_content("This has to come from money you already have.")
        expect(page).to have_link("Take $300.00 from Available")
        expect(page).to have_link("Take from somewhere else…")
        # The consequence, off ReallocationPresenter::Candidate — the same sentence the screen this
        # button opens will print. Available holds money for no rule, so the balance arrow is the
        # whole of what this move costs, and the row says so rather than inventing a per-period
        # figure.
        expect(page).to have_content("Available $810.00 → $510.00")
      end
    end

    # THE LINK CARRIES ALL THREE SCALARS, and the amount as plain digits: `BigDecimal("300").to_s`
    # is "0.3e3", which would reach the query string verbatim.
    #
    # `from_category_id=available` IS THE ROOT'S OWN ID — a string, deliberately not a uuid, so it
    # can never collide with a category (`ReallocationPresenter::Root#id`).
    it "links to the reallocation screen with both ends and the amount", :aggregate_failures do
      visit root_path

      href = within(problem_row("Dentist")) { find_link("Take $300.00 from Available")[:href] }
      expect(href).to include("to_category_id=#{dentist.id}", "from_category_id=available", "amount=300.00")
      expect(href).to include(new_allocation_path)
    end

    # THE WHOLE POINT OF THE TASK, end to end: the button is one click from a screen that is one
    # click from writing. The damage sentence has to survive the trip unchanged, because it is the
    # same Data object read through the same helper on both screens.
    it "arrives at the reallocation screen prefilled and agreeing with itself", :aggregate_failures do
      visit root_path
      within(problem_row("Dentist")) { click_on "Take $300.00 from Available" }
      await("How much")

      expect(page).to have_select("Envelope", selected: "Dentist")
      expect(page).to have_field("How much", with: "300.00")
      expect(find_by_id("from-available")).to be_checked
      within("[data-damage='Available']") { expect(page).to have_content("$810.00 → $510.00") }
    end

    # "Enough free money" is `free_amount` — holding less what EVERY rule holds — and Car is the
    # category that separates it from the holding: $1,000 in it, $800 of that held by Maintenance, so
    # $200 free against a $300 ask. A USER may take it and be told the damage; a SUGGESTION must not
    # propose robbing a category that is counting on the money.
    #
    # Both directions in the candidate SET, which is where the rule lives — only the head of the list
    # gets a button, so "no link from Car" alone would pass for any category that merely ranks
    # second. Car's $1,000 is pinned so the negative cannot be passing because Car is empty.
    it "leaves out a category whose money its own rules are holding", :aggregate_failures do
      visit root_path

      within(problem_row("Dentist")) { expect(page).to have_link("Take $300.00 from Available") }
      candidates = HomePresenter.new(user: user).fix_candidates_for(dentist)
      expect(candidates).not_to include(car)
      expect(candidates).to include(ReallocationPresenter::ROOT)
      expect(holding_of("Car")).to eq(1_000)
      expect(Category.find(car.id).holding_calculator.free_amount).to eq(200)
    end

    # A category in trouble on its own terms is excluded outright, however well placed it is: Vet
    # holds $1,500 with only $200 of it spoken for and sits at priority 0 — so under the shared
    # ordering it would outrank every other category — and it is overdue, so proposing to rob it is
    # not a fix.
    #
    # Available is deliberately spent down to $210, below the $300 ask, so the root cannot mask the
    # question. What is offered instead is Cushion, the next category that qualifies.
    #
    # The positive halves matter as much as the negative: Vet really is a problem (its own row says
    # so), it really would have outranked Cushion, and Dentist still gets a button.
    describe "a well-placed category that is itself overdue" do
      let(:vet) { category("Vet") }

      before do
        deposit(900)
        dated_rule(holder("Vet", priority: 0, funded: 1_500), "Vet Bill", 200, due_in: -10)
        visit root_path
      end

      it "leaves out a category whose own status needs attention", :aggregate_failures do
        within(problem_row("Vet")) { expect(page).to have_content("overdue") }
        within(problem_row("Dentist")) do
          expect(page).to have_no_link(text: /from Vet/)
          expect(page).to have_link("Take $300.00 from Cushion")
        end
        expect(HomePresenter.new(user: user).fix_candidates_for(dentist)).not_to include(Category.find(vet.id))
        # It had the money and the rank: $1,300 free, and ahead of Cushion in the shared ordering.
        # Nothing but the status exclusion kept it out.
        expect(Category.find(vet.id).holding_calculator.free_amount).to eq(1_300)
        expect(ReallocationPresenter.source_order(vet) <=> ReallocationPresenter.source_order(category("Cushion")))
          .to eq(-1)
        expect(available).to eq(210)
      end
    end

    # THE ORDER COMES FROM THE SCREEN THE BUTTON OPENS, and this is the fixture where richest-first
    # and the shared ranking give different answers: House Fund is a savings goal holding $2,000 with
    # no rules against it, so `free_amount` reports the lot and it beats the $810 root on money
    # alone. It is also money the user decided to protect, while available is idle cash — and,
    # decisively, `ReallocationPresenter#sources` ranks the root first, so a button naming House Fund
    # would open a screen that disagrees with it.
    describe "a savings goal richer than available" do
      before do
        deposit(2_000)
        savings("House Fund", funded: 2_000)
        visit root_path
      end

      it "offers available, not the richer goal", :aggregate_failures do
        within(problem_row("Dentist")) do
          expect(page).to have_link("Take $300.00 from Available")
          expect(page).to have_no_link(text: /from House Fund/)
        end
        # Pinned so the negative cannot be passing because House Fund is poor or ineligible: it has
        # more free money than the root and it IS in Home's candidate set, just not first.
        expect(Category.find(category("House Fund").id).holding_calculator.free_amount).to eq(2_000)
        expect(HomePresenter.new(user: user).fix_candidates_for(dentist).map(&:name))
          .to include("House Fund")
      end

      # THE ASSERTION THAT KEEPS THE TWO FROM DRIFTING. Home filters harder than the reallocation
      # screen does — it drops categories in attention and categories without enough free money — so
      # the two lists are not equal. What must hold is that Home's surviving candidates appear in the
      # SCREEN'S OWN ORDER, head included. Both sides are computed independently here: `ranked` from
      # ReallocationPresenter's own offer list, `candidates` from HomePresenter's filter. Diverge the
      # two orderings and this fails.
      it "ranks its candidates exactly as the reallocation screen ranks them", :aggregate_failures do
        expect(page).to have_css("[data-problem-category='Dentist']")
        candidates = HomePresenter.new(user: user).fix_candidates_for(dentist)
        ranked = ReallocationPresenter.new(user: user, to_category: dentist).sources.map do |source|
          source.root? ? ReallocationPresenter::ROOT : source.category
        end

        expect(candidates).to eq(ranked & candidates)
        expect(candidates.first).to eq(ReallocationPresenter::ROOT)
        expect(candidates.size).to be > 1
      end
    end

    # AMENDMENT D, carried by `ReallocationPresenter.source_order`'s `[priority, name]`. Two
    # categories at the same priority must not reorder between renders.
    #
    # The names are assigned AFTER the ids exist and deliberately against them: the category with the
    # smaller id is called "Zebra Fund", so a read that fell through to id order would offer Zebra
    # and a name-ordered one offers Apple.
    #
    # Available is deliberately spent down to $10 — below the $300 ask — so the root is not a
    # candidate and the category ordering is the thing being observed. The tied pair sit at priority
    # 0 so they outrank Cushion (priority 6, $500 free), which is the only other survivor.
    describe "two sources tied on priority" do
      let(:tied) do
        deposit(1_000)
        ["Tie A", "Tie B"].map { |name| holder(name, priority: 0, funded: 900) }.sort_by(&:id)
      end

      before do
        tied.first.update!(name: "Zebra Fund")
        tied.last.update!(name: "Apple Fund")
        visit root_path
      end

      it "breaks a tie by name, not by id", :aggregate_failures do
        within(problem_row("Dentist")) do
          expect(page).to have_link("Take $300.00 from Apple Fund")
          expect(page).to have_no_link(text: /from Zebra Fund/)
        end
        expect(tied.map { |c| Category.find(c.id).holding_calculator.free_amount }).to eq([900, 900])
        expect(tied.first.reload.name).to eq("Zebra Fund")
        # The root really is out of the running, so the pair are being ranked against each other.
        expect(available).to eq(10)
      end
    end

    # RULING 4. An overdue bill fires on a DATE and a missing payment, so a category holding every
    # penny of it is still red — and offering to move money in would have the user make a real
    # mistake to fix an imaginary problem. HoldingStatus#funding_gap is the gate.
    #
    # BOTH DIRECTIONS ON ONE SCREEN: Water is overdue and empty and keeps its button; Council Tax is
    # overdue and fully funded and loses it, saying why. A gate asserted in one direction only would
    # pass on an app that had simply stopped offering fixes to overdue bills.
    describe "an overdue bill" do
      before do
        deposit(200)
        dated_rule(holder("Water", priority: 8), "Water Bill", 150, due_in: -10)
        dated_rule(holder("Council Tax", priority: 9, funded: 200), "Council Bill", 200, due_in: -10)
        visit root_path
      end

      it "keeps its button while the category is short", :aggregate_failures do
        within(problem_row("Water")) do
          expect(page).to have_content("overdue")
          expect(page).to have_link("Take $150.00 from Available")
          expect(page).to have_no_content("needs paying, not funding")
        end
        expect(holding_of("Water")).to eq(0)
      end

      it "loses its button once the money is already there, and says why", :aggregate_failures do
        within(problem_row("Council Tax")) do
          expect(page).to have_content("overdue")
          expect(page).to have_content("Its money is already there — this needs paying, not funding.")
          expect(page).to have_no_link(text: /\ATake/)
          expect(page).to have_no_content("This has to come from money you already have.")
        end
        # The category holds the whole bill, and a source that could have funded it exists — so the
        # missing button is the gap being zero, not a shortage of candidates.
        expect(holding_of("Council Tax")).to eq(200)
        expect(available).to eq(810)
      end
    end

    # AMENDMENT C. The dead-button case, said plainly and with the figure, so the reader can see what
    # would have had to be there. Roof needs $9,000 in three days and the richest thing the user has
    # is $810 of available.
    #
    # NO CONTAINER IN THE SENTENCE (Task 6): it read "Nothing in Checking has $9,000.00 spare",
    # because a move could not leave the account the envelope sat in. An allocation crosses nothing
    # (§2), so the set that was asked is everything the user has and naming an account would narrow a
    # sentence that is no longer narrow.
    #
    # Asserted as PRESENT and explanatory, never as the mere absence of a button: the row is scoped,
    # the sentence is quoted, and Dentist's button on the same screen proves the band still renders.
    it "says plainly when nothing can cover it", :aggregate_failures do
      dated_rule(holder("Roof", priority: 8), "Roof Repair", 9_000, due_in: 3)

      visit root_path

      within(problem_row("Roof")) do
        expect(page).to have_content("Nothing has $9,000.00 spare to move.")
        expect(page).to have_no_link(text: /\ATake/)
        expect(page).to have_no_content("This has to come from money you already have.")
      end
      within(problem_row("Dentist")) { expect(page).to have_link("Take $300.00 from Available") }
    end

    # ── DELETED (Task 6), two examples:
    #
    #   * "tells a pool with no account to get one, rather than offering a move" (already deleted in
    #     plan 3 task 6 and now unrecoverable: `HomePresenter#fix_for`'s nil arm and the
    #     "Assign it to an account" copy are gone with the orphan concept).
    #   * "an overdrawn account is fixed out of an envelope inside it, ranked by the user's own
    #     priorities". An overdrawn ACCOUNT is not a problem row any more, and cannot be: the fix
    #     beside a row is an ALLOCATION, which moves nothing physical (§2), so it could not repay a
    #     bank overdraft whatever it named. The example turned on `AccountMovement#containing_account`
    #     making an account its own container on both ends — a concept with no successor. The debt is
    #     still named, by the standing band and by the accounts band; see
    #     `spec/system/home/attention_spec.rb`'s "names an overdrawn account without counting it as
    #     something that needs you".
  end

  # ────────────────────────────────────────────────────────────────────────────────────────────
  # AMENDMENT F. Home used to compute `required` off the LIVE holding while the distribution screen
  # computed it net of the sweep, so a closed category read `needs $315` here and `needs $400` there
  # — a screen disagreeing with the action it was offering.
  #
  # Both halves move together, and the fixtures below pin each half against a literal derived from
  # the OTHER reading, so neither can have moved alone.
  describe "the post-sweep view" do
    let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }
    # rubocop:disable RSpec/LetSetup -- nothing NAMES this account and every example needs it:
    # the `:account` trait's `after(:create)` is what makes the user's first account their MAIN
    # one, and the pot is where every entry below lands.
    let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
    # rubocop:enable RSpec/LetSetup

    before { sign_in user, scope: :user }

    # ** WAS `find("div[aria-labelledby='waterfall-heading']")` (answers-first Task 2). ** Home no
    # longer RENDERS the waterfall — "Where your money goes", the fill order and the cutoff were the
    # system describing itself, which spec §1 rules off this screen — but the ROWS are still the ones
    # `HomePresenter#remaining_plan` and the fix branches are derived from, and they are exactly what
    # this describe is pinning against `AllocationCalculator`. So the figures are read off the
    # presenter instead of off markup, at the same planted literals, and the cross-screen comparison
    # in each block is untouched.
    def waterfall_row(name)
      HomePresenter.new(user: user).waterfall.find { |row| row.category.name == name }
    end

    def deposit(amount)
      category = create(:category, :income, user: user)
      create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
    end

    def envelope(name, rate:, priority:, funded: 0, funded_on: Date.current)
      category = create(:category, :expense, :funded, user: user, name: name, priority: priority)
      create(:budget, :per_period_rate, category: category, amount: rate)
      create(:allocation, to_category: category, amount: funded, date: funded_on) if funded.positive?
      category
    end

    # A fortnight back is one biweekly boundary, so the money belongs to a period that has ended and
    # HoldingCalculator#period_closed? is true.
    def closed_envelope(name, rate:, funded:, priority:)
      envelope(name, rate: rate, priority: priority, funded: funded, funded_on: Date.current - 14)
    end

    describe "a closed category's ask", :aggregate_failures do
      # The brief's own shape: Groceries holds $85 of last period's money against a $400 rate rule,
      # and $200 of unclaimed cash is left in available.
      #
      # Gas is the control: funded today, nothing to sweep, so its ask must NOT move.
      #
      #   live holding : Groceries asks 400 − 85 = 315, Gas asks 110, out of $200
      #                  → Groceries short 115, Gas short 110         = $225 short
      #   post-sweep   : Groceries asks 400, Gas asks 110, out of 200 + 85 = $285
      #                  → Groceries short 115, Gas short 110         = $225 short
      before do
        deposit(200 + 85 + 40)
        closed_envelope("Groceries", rate: 400, funded: 85, priority: 1)
        envelope("Gas", rate: 150, priority: 2, funded: 40)
        visit root_path
      end

      it "asks for the whole rule, because the leftover is about to be taken back", :aggregate_failures do
        # THE WAITING ASSERTION FIRST, and it is load-bearing rather than decorative (CLAUDE.md's
        # first `InvalidSessionIdError` cause): every other assertion in this example reads Postgres
        # through the presenter, which does not wait on the browser, so without one Capybara-side
        # expectation the example ends mid-request and `reset_sessions!` navigates the renderer away
        # underneath it. Measured: these examples failed exactly this way when the band they used to
        # read markup from was removed.
        expect(page).to have_css("[data-this-period]")
        expect(waterfall_row("Groceries").funded).to eq(285)
        expect(waterfall_row("Groceries").needed).to eq(400)
        # The live-holding reading, asserted absent: $400 less the $85 it is still sitting on.
        expect(waterfall_row("Groceries").needed).not_to eq(315)
      end

      it "leaves a category whose period is still open reading its live ask", :aggregate_failures do
        expect(page).to have_css("[data-this-period]")
        # $150 rate less the $40 it is holding. Same reader, no sweep, unchanged figure.
        expect(waterfall_row("Gas").funded).to eq(0)
        expect(waterfall_row("Gas").needed).to eq(110)
        expect(waterfall_row("Gas").needed).not_to eq(150)
      end

      # THE INVARIANCE, and it holds here: required rose by $85 (315 → 400) and available rose by the
      # same $85 (200 → 285), so the gap is the same $225 read either way.
      # WAS "$225.00 short this period" over "You need $510.00 to stay on schedule. You have
      # $285.00." (answers-first Task 1). The standing band's two sentences are deleted with it —
      # "need"/"have" is the system explaining its own subtraction — and the invariance they pinned
      # is unchanged and still measurable: free is `available − remaining_plan`, so $285 against a
      # $510 ask IS the same $225, printed once instead of derived from two figures beside it.
      it "reports the same gap the live-holding reading did", :aggregate_failures do
        expect(page).to have_css("[data-free-to-spend]", text: "-$225.00")
        expect(HomePresenter.new(user: user).available).to eq(285)
        expect(HomePresenter.new(user: user).remaining_plan).to eq(510)
      end

      # ** THE CROSS-SCREEN PIN, RESTORED (Task 6). ** It was withdrawn by two-ledger Task 4, when
      # Home filled POOLS out of an account's pot while `AllocationCalculator` filled CATEGORIES out
      # of available — two fills over two ledgers, so comparing them was not a weaker check, it was a
      # different question. Home's rows are categories now and the two answer one question again, at
      # the same figures. Three of these were withdrawn in this file; all three are back.
      it "agrees with the distribution screen it is offering", :aggregate_failures do
        expect(page).to have_css("[data-this-period]")
        home = HomePresenter.new(user: user)
        proposal = AllocationCalculator.new(user: user, today: Date.current)

        # `waterfall.sum(&:short)` WHERE THIS READ `#shortfall` (answers-first Task 2). That reader
        # is deleted with the band that printed its figure, and the sum is character-for-character
        # what it was — so the cross-pin below is unchanged, and the money-type guarantee it also
        # carried is asserted here off the sum instead.
        expect(home.waterfall.sum(&:short)).to eq(225)
        expect(home.waterfall.sum(&:short)).to eq(proposal.rows.sum(&:short))
        expect(home.available).to eq(proposal.available)
        expect(home.waterfall.sum(0.to_d, &:short)).to be_a(BigDecimal)
      end
    end

    # THE OTHER DIRECTION. Amendment F said #shortfall "must not move at all" because both sides rise
    # by the same swept total. That is true only while the leftover is no larger than what the rule
    # re-asks for.
    #
    # Coffee holds $150 against a $100 rate rule. `sweepable_amount` takes the WHOLE $150 — a
    # category's surplus is not its rule's money — while the post-sweep ask rises only to $100. So
    # available gains $150 and required gains $100, and the gap legitimately CLOSES by the $50 of
    # surplus that was invisible while it sat inside the category:
    #
    #   live holding : Rent $300 + Coffee $0 asked, out of $0    → $300 short (Coffee has no row)
    #   post-sweep   : Rent $300 + Coffee $100,   out of $150    → $250 short
    describe "a closed category holding more than its rule wants", :aggregate_failures do
      before do
        deposit(150)
        envelope("Rent", rate: 300, priority: 1)
        closed_envelope("Coffee", rate: 100, funded: 150, priority: 2)
        visit root_path
      end

      # WAS the standing band's "$250.00 short this period" / "You have $150.00" (answers-first
      # Task 1). Same three figures through the card that replaced it: $150 available less the $400
      # the post-sweep ask comes to. The negative assertion is what the example is really about — a
      # pre-sweep reading would say $300 — so it is kept, in the new spelling.
      it "puts the surplus back into available and closes the gap by exactly that much", :aggregate_failures do
        expect(page).to have_css("[data-free-to-spend]", text: "-$250.00")
        expect(HomePresenter.new(user: user).available).to eq(150)
        expect(page).to have_no_css("[data-free-to-spend]", text: "-$300.00")
      end

      # The pre-sweep reading gave Coffee no row at all: it held $150 against a $100 rule, so it
      # asked for nothing and the fill rejects a zero-need row. Rendering $0 for a category that is
      # about to hand $150 back was the same defect class in the other direction.
      it "gives the closed category a row, asking for its whole rate", :aggregate_failures do
        expect(page).to have_css("[data-this-period]")
        expect(waterfall_row("Coffee")).to be_present
        expect(waterfall_row("Coffee").funded).to eq(0)
        expect(waterfall_row("Coffee").needed).to eq(100)
      end

      # THE SECOND RESTORED CROSS-SCREEN PIN, on the shape where the shortfall legitimately MOVES.
      it "still agrees with the distribution screen", :aggregate_failures do
        expect(page).to have_css("[data-this-period]")
        home = HomePresenter.new(user: user)
        proposal = AllocationCalculator.new(user: user, today: Date.current)

        expect(home.waterfall.sum(&:short)).to eq(250)
        expect(home.available).to eq(150)
        expect(home.waterfall.sum(&:short)).to eq(proposal.rows.sum(&:short))
        expect(home.available).to eq(proposal.available)
      end
    end

    # ** THE CLAMP IS DELETED, AND THE DIVERGENCE WITH IT (Task 6). **
    #
    # `HomePresenter#account_pots` clamped each account's pot at zero before summing, because Home
    # AGGREGATED across accounts and an unclamped negative would have let one overdrawn account
    # cancel another's surplus. `AllocationCalculator` is deliberately unclamped, having no sibling
    # to cancel against — so the two screens legitimately read `$0.00` here and `-$200.00` there, and
    # that stated divergence was pinned in this file rather than left latent.
    #
    # There is ONE root now (§2), so there is no sibling anywhere and no reason to clamp. The two
    # readers are the same expression, and this example asserts the agreement where it used to assert
    # the difference.
    describe "a root the sweep only partly repays" do
      before do
        deposit(150)
        envelope("Rent", rate: 300, priority: 1)
        closed_envelope("Coffee", rate: 100, funded: 150, priority: 2)
        overspend = create(:category, :expense, user: user, name: "Overspend")
        create(:entry, item: create(:item, category: overspend), amount: 350, date: Date.current)
        visit root_path
      end

      it "funds nothing, because the swept money lands inside the hole", :aggregate_failures do
        expect(page).to have_css("[data-this-period]")
        expect(waterfall_row("Rent").funded).to eq(0)
        expect(waterfall_row("Rent").needed).to eq(300)
        expect(waterfall_row("Coffee").funded).to eq(0)
        expect(waterfall_row("Coffee").needed).to eq(100)
        # The POT is $200 down — income $150 against $350 of spending. The allocation into Coffee
        # moved nothing physical, which is why the account is not $350 down as it was in the pool era.
        #
        # WAS "Checking is overdrawn $200.00", the standing band's strip (answers-first Task 1).
        # Checking is MAIN, so the debt is now the hero's own "In Checking" figure in red (spec §2);
        # the strip and its copy survive for a non-main account, covered in `home/hero_spec.rb`.
        expect(page).to have_css("[data-in-checking].text-status-danger", text: "-$200.00")
      end

      # THE THIRD RESTORED CROSS-SCREEN PIN, and the one that changed meaning: a negative available
      # is now stated rather than clamped, and it is stated identically on both screens.
      it "states a negative available rather than clamping it, exactly as the distribution does",
         :aggregate_failures do
           expect(page).to have_css("[data-this-period]")
           home = HomePresenter.new(user: user)
           proposal = AllocationCalculator.new(user: user, today: Date.current)

           expect(home.available).to eq(-200)
           expect(home.available).to eq(proposal.available)
           expect(home.waterfall.sum(&:short)).to eq(400)
           expect(home.waterfall.sum(&:short)).to eq(proposal.rows.sum(&:short))
         end
    end
  end

  # ────────────────────────────────────────────────────────────────────────────────────────────
  # THE LAST REASON A PROBLEM HAS NO BUTTON: the next distribution already solves it.
  #
  # Ruling 4 said do not offer money to a bill that already has it. This is the same principle one
  # step out — do not offer money to a bill that is ABOUT to have it. The move is not free: the
  # source loses money it was holding for its own rule.
  #
  # A DEDICATED FIXTURE, because both directions have to be on ONE screen at figures that DIFFER —
  # an example where "funded in full" and "funded in part" coincided would pass either way.
  #
  #   Available $400 · no sweeps
  #   1 Dentist  $300 due in 3 days, empty  →  funded $300 of $300  ·  short $0    → COVERED
  #   2 Roof     $500 due in 3 days, empty  →  funded $100 of $500  ·  short $400  → still short
  #   3 Cushion  a savings goal holding $700, no rules — asks nothing, and is the source Roof needs
  describe "a problem the next distribution already solves" do
    let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }
    # rubocop:disable RSpec/LetSetup -- nothing NAMES this account and every example needs it:
    # the `:account` trait's `after(:create)` is what makes the user's first account their MAIN
    # one, and the pot is where every entry below lands.
    let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
    # rubocop:enable RSpec/LetSetup

    before do
      sign_in user, scope: :user
      deposit(1_100)
      bill(holder("Dentist", priority: 1), "Dental Work", 300)
      bill(holder("Roof", priority: 2), "Roof Repair", 500)
      cushion
      visit root_path
    end

    def problem_row(name) = find("[data-problem-category='#{name}']")

    # The presenter's rows rather than the deleted waterfall band's markup — see the same helper in
    # "the post-sweep view" above for why.
    def waterfall_row(name)
      HomePresenter.new(user: user).waterfall.find { |row| row.category.name == name }
    end

    def deposit(amount)
      category = create(:category, :income, user: user)
      create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
    end

    def holder(name, priority:, **attrs)
      create(:category, :expense, :funded, user: user, name: name, priority: priority, **attrs)
    end

    # Due inside three days with a biweekly cadence anchored today: no boundary falls between
    # tomorrow and the due date, so the rule is unreachable and the category reads `won't make it`.
    def bill(category, item_name, amount)
      create(
        :budget,
        category: category,
        item: create(:item, category: category, name: item_name),
        amount: amount,
        interval_months: nil,
        anchor_date: Date.current + 3
      )
    end

    def cushion
      holder("Cushion", priority: 3, target_amount: 5_000).tap do |category|
        create(:allocation, to_category: category, amount: 700, date: Date.current)
      end
    end

    # THE TWO DIRECTIONS, ON ONE SCREEN, AT DIFFERENT FIGURES. Dentist's $300 arrives in full, so it
    # says so and offers nothing; Roof gets $100 of its $500 and keeps a real button. Both rows are
    # still red — the states are unchanged and the band still counts them as problems.
    it "drops the button on a category the waterfall funds in full", :aggregate_failures do
      within(problem_row("Dentist")) do
        expect(page).to have_content("won't make it")
        expect(page).to have_content("Its money is coming — the next distribution funds this in full.")
        expect(page).to have_no_link(text: /\ATake/)
        expect(page).to have_no_content("This has to come from money you already have.")
      end
      expect(waterfall_row("Dentist").funded).to eq(300)
      expect(waterfall_row("Dentist").needed).to eq(300)
    end

    it "keeps the button on a category the waterfall funds only in part", :aggregate_failures do
      within(problem_row("Roof")) do
        expect(page).to have_content("won't make it")
        expect(page).to have_link("Take $500.00 from Cushion")
        expect(page).to have_no_content("the next distribution funds this in full")
      end
      expect(waterfall_row("Roof").funded).to eq(100)
      expect(waterfall_row("Roof").needed).to eq(500)
    end

    # ** THE FOURTH RESTORED CROSS-SCREEN PIN. ** This branch reads Home's own waterfall, and the
    # comparison against `AllocationCalculator` — "the object the distribution screen is built on" —
    # was withdrawn in Task 4 when the two fills answered two questions. They answer one again.
    it "turns on a shortfall that is zero on one row and positive on the other", :aggregate_failures do
      expect(page).to have_css("[data-problem-category='Roof']")
      home = HomePresenter.new(user: user)
      proposal = AllocationCalculator.new(user: user, today: Date.current)
      by_name = proposal.rows.to_h { |row| [row.category.name, row.short] }

      expect(home.fix_for(user.categories.find_by!(name: "Dentist"))).to be_covered
      expect(home.fix_for(user.categories.find_by!(name: "Roof"))).not_to be_covered
      expect(by_name).to eq("Dentist" => 0, "Roof" => 400)
    end

    # The two branches must not be one branch wearing two labels. Roof needs $500 and holds nothing,
    # so HoldingStatus#funding_gap is $500 on BOTH categories' terms — what separates them is the
    # waterfall alone. Pinned so a future edit cannot satisfy this file by folding ruling 4 and this
    # one together.
    it "separates this from the money-already-there case", :aggregate_failures do
      home = HomePresenter.new(user: user)
      dentist = user.categories.find_by!(name: "Dentist")

      expect(home.fix_for(dentist).amount).to eq(300)
      expect(home.fix_for(dentist)).to be_needs_money
      expect(home.fix_for(dentist)).to be_covered
      within(problem_row("Dentist")) do
        expect(page).to have_no_content("this needs paying, not funding")
      end
    end
  end
end
