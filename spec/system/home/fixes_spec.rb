# frozen_string_literal: true

require "rails_helper"

# Task 8: Home's problems become actionable (spec §4.2), and Home adopts the distribution's
# post-sweep view so the figure it prints and the figure the button acts on are the same one.
#
# `Capybara.exact` is unset, so `have_content("$300.00")` also matches "$1,300.00" and the sidebar.
# Every figure below is scoped to the problem row that owns it via `[data-problem-pool]`.
#
# Every example body makes a Capybara call after its `visit`. A body that asserts only against the
# database finishes before the page settles and races `spec/support/capybara.rb`'s per-example
# driver quit, which surfaces as `InvalidSessionIdError` with no assertion failure at all.
RSpec.describe "Home Fixes", type: :system do
  # ────────────────────────────────────────────────────────────────────────────────────────────
  describe "the fix a problem offers" do
    include_context "with a Checking account to reallocate in"

    # THE PERIOD HAS TO BE SHORT BEFORE THE MONEY REACHES DENTIST, or every example below would be
    # measuring the wrong branch. Dentist is priority 1 in that fixture, so the waterfall funds its
    # whole $300 out of Checking's $960 post-sweep pot — and a problem the next distribution solves
    # by itself is deliberately given no button (see the last describe in this file). This example
    # group is about which SOURCE a genuine problem is offered, so the problem has to be genuine.
    #
    # A $5,000 tuition bill at priority 0 is the household's own answer to "what comes first", and
    # it takes the pot before anything below it: `required` spreads it over the five biweekly
    # boundaries before its due date, so it asks $1,000 against a $960 pot and Dentist gets nothing.
    # It never becomes a problem row of its own (a bill with periods left to run is `on_track`) and
    # it is never a candidate (nothing funded it, so `free_amount` is zero), so it changes no other
    # figure in this file.
    before { dated_rule(envelope("Tuition", priority: 0), "Autumn Term", 5_000, due_in: 60) }

    def problem_row(name) = find("[data-problem-pool='#{name}']")

    # Checking holds $810 of unclaimed cash and Dentist needs $300 it will never reach in time.
    # The account is a legitimate source — it stands in as its own container (PoolMovement) and the
    # buffer is the money no envelope has claimed.
    it "names a source that can cover it, and says what the move would cost", :aggregate_failures do
      visit root_path

      within(problem_row("Dentist")) do
        expect(page).to have_content("This has to come from money you already have.")
        expect(page).to have_link("Take $300.00 from Checking buffer")
        expect(page).to have_link("Take from another pool…")
        # The consequence, off ReallocationPresenter::Candidate — the same sentence the screen
        # this button opens will print. Checking has no rules, so the balance arrow is the whole
        # of what this move costs, and the row says so rather than inventing a per-period figure.
        expect(page).to have_content("Checking buffer $810.00 → $510.00")
      end
    end

    # THE LINK CARRIES ALL THREE SCALARS, and the amount as plain digits: `BigDecimal("300").to_s`
    # is "0.3e3", which would reach the query string verbatim.
    it "links to the reallocation screen with both ends and the amount", :aggregate_failures do
      visit root_path

      href = within(problem_row("Dentist")) { find_link("Take $300.00 from Checking buffer")[:href] }
      expect(href).to include("to_pool_id=#{dentist.id}", "from_pool_id=#{checking.id}", "amount=300.00")
      expect(href).to include(new_pool_movement_path)
    end

    # THE WHOLE POINT OF THE TASK, end to end: the button is one click from a screen that is one
    # click from writing. The damage sentence has to survive the trip unchanged, because it is the
    # same Data object read through the same helper on both screens.
    it "arrives at the reallocation screen prefilled and agreeing with itself", :aggregate_failures do
      visit root_path
      within(problem_row("Dentist")) { click_on "Take $300.00 from Checking buffer" }
      await("How much")

      expect(page).to have_select("Envelope", selected: "Dentist")
      expect(page).to have_field("How much", with: "300.00")
      expect(find_by_id("from-#{checking.id}")).to be_checked
      within("[data-damage='Checking']") { expect(page).to have_content("$810.00 → $510.00") }
    end

    # "Enough free money" is `free_amount` — balance less what EVERY rule holds — and Car is the
    # pool that separates it from the balance: $1,000 in it, $800 of that held by Maintenance, so
    # $200 free against a $300 ask. Task 7 would let a user take it and state the damage; a
    # SUGGESTION must not propose robbing an envelope that is counting on the money.
    #
    # Both directions on one screen and in the candidate SET, which is where the rule lives — only
    # the head of the list gets a button, so "no link from Car" alone would pass for any pool that
    # merely ranks second. Car's $1,000 is pinned so the negative cannot be passing because Car is
    # empty.
    it "leaves out a pool whose money its own rules are holding", :aggregate_failures do
      visit root_path

      within(problem_row("Dentist")) { expect(page).to have_link("Take $300.00 from Checking buffer") }
      candidates = HomePresenter.new(user: user).fix_candidates_for(dentist)
      expect(candidates).not_to include(car)
      expect(candidates).to include(checking)
      expect(balance_of("Car")).to eq(1_000)
      expect(Pool.find(car.id).calculator.free_amount).to eq(200)
    end

    # A pool in trouble on its own terms is excluded outright, however well placed it is: Vet holds
    # $1,500 with only $200 of it spoken for and sits at priority 0 — so under the shared ordering
    # it would be the head of the list — and it is overdue, so proposing to rob it is not a fix.
    #
    # Checking is deliberately spent down to $210, below the $300 ask, so the account cannot mask
    # the question. What is offered instead is Cushion, the next envelope that qualifies.
    #
    # The positive halves matter as much as the negative: Vet really is a problem (its own row says
    # so), it really would have outranked Cushion, and Dentist still gets a button.
    describe "a well-placed pool that is itself overdue" do
      let(:vet) { create(:pool, :budget_pool, user: user, account: checking, name: "Vet", priority: 0) }

      before do
        deposit(900)
        fund(vet, 1_500)
        dated_rule(vet, "Vet Bill", 200, due_in: -10)
        visit root_path
      end

      it "leaves out a pool whose own status needs attention", :aggregate_failures do
        within(problem_row("Vet")) { expect(page).to have_content("overdue") }
        within(problem_row("Dentist")) do
          expect(page).to have_no_link(text: /from Vet/)
          expect(page).to have_link("Take $300.00 from Cushion")
        end
        expect(HomePresenter.new(user: user).fix_candidates_for(dentist)).not_to include(Pool.find(vet.id))
        # It had the money and the rank: $1,300 free, and ahead of Cushion in the shared ordering.
        # Nothing but the status exclusion kept it out.
        expect(Pool.find(vet.id).calculator.free_amount).to eq(1_300)
        expect(ReallocationPresenter.source_order(vet) <=> ReallocationPresenter.source_order(pool("Cushion")))
          .to eq(-1)
        expect(balance_of("Checking")).to eq(210)
      end
    end

    # THE ORDER COMES FROM THE SCREEN THE BUTTON OPENS, and this is the fixture where the old
    # richest-first rule and Task 7's ranking give different answers: House Fund is a savings goal
    # holding $2,000 with no rules against it, so `free_amount` reports the lot and it beats the
    # $810 buffer on money alone. It is also money the user decided to protect, while the buffer is
    # idle cash — and, decisively, `ReallocationPresenter#sources` ranks the buffer first, so a
    # button naming House Fund would open a screen that disagrees with it.
    describe "a savings goal richer than the buffer" do
      before do
        deposit(2_000)
        house = create(
          :pool,
          :savings_pool,
          user: user,
          account: checking,
          name: "House Fund",
          target_amount: 50_000,
          priority: 8
        )
        fund(house, 2_000)
        visit root_path
      end

      it "offers the buffer, not the richer goal", :aggregate_failures do
        within(problem_row("Dentist")) do
          expect(page).to have_link("Take $300.00 from Checking buffer")
          expect(page).to have_no_link(text: /from House Fund/)
        end
        # Pinned so the negative cannot be passing because House Fund is poor or ineligible: it has
        # more free money than the buffer and it IS in Home's candidate set, just not first.
        expect(Pool.find(pool("House Fund").id).calculator.free_amount).to eq(2_000)
        expect(HomePresenter.new(user: user).fix_candidates_for(dentist).map(&:name))
          .to include("House Fund")
      end

      # THE ASSERTION THAT KEEPS THE TWO FROM DRIFTING. Home filters harder than the reallocation
      # screen does — it drops pools in attention and pools without enough free money — so the two
      # lists are not equal. What must hold is that Home's surviving candidates appear in the
      # SCREEN'S OWN ORDER, head included. Both sides are computed independently here: `ranked`
      # from ReallocationPresenter's sort over its own list, `candidates` from HomePresenter's
      # filter. Diverge the two sort keys and this fails.
      it "ranks its candidates exactly as the reallocation screen ranks them", :aggregate_failures do
        expect(page).to have_css("[data-problem-pool='Dentist']")
        candidates = HomePresenter.new(user: user).fix_candidates_for(dentist)
        ranked = ReallocationPresenter.new(user: user, to_pool: dentist).sources.map(&:pool)

        expect(candidates).to eq(ranked & candidates)
        expect(candidates.first).to eq(ranked.first)
        expect(candidates.size).to be > 1
      end
    end

    # AMENDMENT D, now carried by ReallocationPresenter::source_order's `[priority, name]` tail.
    # Two envelopes at the same priority must not reorder between renders.
    #
    # The names are assigned AFTER the ids exist and deliberately against them: the pool with the
    # smaller id is called "Zebra Fund", so a read that fell through to id order would offer Zebra
    # and a name-ordered one offers Apple.
    #
    # The buffer is deliberately spent down to $10 — below the $300 ask — so the account is not a
    # candidate and the envelope ordering is the thing being observed. The tied pair sit at
    # priority 0 so they outrank Cushion (priority 6, $500 free), which is the only other survivor.
    describe "two sources tied on priority" do
      let(:tied) do
        deposit(1_000)
        ["Tie A", "Tie B"].map { |name| envelope(name, priority: 0, funded: 900) }.sort_by(&:id)
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
        expect(tied.map { |pool| Pool.find(pool.id).calculator.free_amount }).to eq([900, 900])
        expect(tied.first.reload.name).to eq("Zebra Fund")
        # The buffer really is out of the running, so the pair are being ranked against each other.
        expect(balance_of("Checking")).to eq(10)
      end
    end

    # RULING 4. An overdue bill fires on a DATE and a missing payment, so an envelope holding every
    # penny of it is still red — and offering to move money in would have the user make a real
    # mistake to fix an imaginary problem. PoolStatus#funding_gap is the gate.
    #
    # BOTH DIRECTIONS ON ONE SCREEN, which is the whole point: Water is overdue and empty and keeps
    # its button; Council Tax is overdue and fully funded and loses it, saying why. A gate asserted
    # in one direction only would pass on an app that had simply stopped offering fixes to overdue
    # bills, which is the opposite defect.
    describe "an overdue bill" do
      before do
        deposit(200)
        dated_rule(envelope("Water", priority: 8), "Water Bill", 150, due_in: -10)
        dated_rule(envelope("Council Tax", priority: 9, funded: 200), "Council Bill", 200, due_in: -10)
        visit root_path
      end

      it "keeps its button while the envelope is short", :aggregate_failures do
        within(problem_row("Water")) do
          expect(page).to have_content("overdue")
          expect(page).to have_link("Take $150.00 from Checking buffer")
          expect(page).to have_no_content("needs paying, not funding")
        end
        expect(balance_of("Water")).to eq(0)
      end

      it "loses its button once the money is already there, and says why", :aggregate_failures do
        within(problem_row("Council Tax")) do
          expect(page).to have_content("overdue")
          expect(page).to have_content("Its money is already there — this needs paying, not funding.")
          expect(page).to have_no_link(text: /\ATake/)
          expect(page).to have_no_content("This has to come from money you already have.")
        end
        # The envelope holds the whole bill, and a source that could have funded it exists — so the
        # missing button is the gap being zero, not a shortage of candidates.
        expect(balance_of("Council Tax")).to eq(200)
        expect(Pool.find(checking.id).calculator.free_amount).to eq(810)
      end
    end

    # AMENDMENT C. The dead-button case, said plainly and with both the account and the figure, so
    # the reader can see what would have had to be there. Roof needs $9,000 in three days and the
    # richest thing in Checking is its own $810 buffer.
    #
    # Asserted as PRESENT and explanatory, never as the mere absence of a button: the row is scoped,
    # the sentence is quoted, and Dentist's button on the same screen proves the band still renders.
    it "says plainly when nothing in the account can cover it", :aggregate_failures do
      roof = create(:pool, :budget_pool, user: user, account: checking, name: "Roof", priority: 8)
      dated_rule(roof, "Roof Repair", 9_000, due_in: 3)

      visit root_path

      within(problem_row("Roof")) do
        expect(page).to have_content("Nothing in Checking has $9,000.00 spare to move.")
        expect(page).to have_no_link(text: /\ATake/)
        expect(page).to have_no_content("This has to come from money you already have.")
      end
      within(problem_row("Dentist")) { expect(page).to have_link("Take $300.00 from Checking buffer") }
    end

    # DELETED (plan 3, task 6): "tells a pool with no account to get one, rather than offering a
    # move". It was the other no-button case — no account's money can reach a pool that sits in no
    # account, so the band named the step that does fix it ("Assign it to an account before any
    # money can reach it") instead of a move. `HomePresenter#fix_for` still returns nil for an
    # orphan and the copy is still in `home/_pool_row`; the pool cannot exist, because
    # `Pool#account_matches_pool_type` and `CHECK ((pool_type = 0) = (account_id IS NULL))` refuse
    # it. The no-button case above — a gap nothing has the spare cash for — is the one that
    # survives. See `Pool::REFUSALS` and the task 6 report.

    # AN ACCOUNT IS A DESTINATION TOO. An overdraft is the loudest state in the app and it is the
    # one problem whose fix comes from INSIDE it: the envelopes it funded are the only things that
    # can put the money back. `PoolMovement#containing_account` is what makes the account its own
    # container on both ends, which is why this works without a second notion of "same account".
    #
    # $900 spent straight out of Checking against $810 of buffer leaves it $90 down. Checking itself
    # is the destination, so it is excluded as a source; two envelopes have $90 spare — Car ($200
    # free, priority 2) and Cushion ($500 free, priority 6) — and the user's own ranking decides,
    # not the money. Richest-first would have taken from Cushion; the shared ordering takes from the
    # envelope the user ranked higher, and the reallocation screen would offer the same one first.
    describe "an overdrawn account" do
      before do
        category = create(:category, :expense, user: user, pool: checking, name: "Big Spend")
        create(:entry, item: create(:item, category: category), amount: 900, date: Date.current)
        visit root_path
      end

      it "is fixed out of an envelope inside it, ranked by the user's own priorities",
         :aggregate_failures do
           within(problem_row("Checking")) do
             expect(page).to have_content("overdrawn $90.00")
             expect(page).to have_link("Take $90.00 from Car")
             expect(page).to have_content("Car $1,000.00 → $910.00")
             expect(page).to have_no_link(text: /from Cushion/)
           end
           expect(balance_of("Checking")).to eq(-90)
           expect(HomePresenter.new(user: user).fix_candidates_for(Pool.find(checking.id)).map(&:name))
             .to eq(["Car", "Cushion"])
         end
    end
  end

  # ────────────────────────────────────────────────────────────────────────────────────────────
  # AMENDMENT F. Home used to compute `required` off the LIVE balance while the distribution screen
  # computed it net of the sweep, so a closed envelope read `needs $315` here and `needs $400`
  # there — a screen disagreeing with the action it was offering. It was NOT already done: at
  # 04f4b41 `HomePresenter#required_for` called a plain calculator and `#account_pots` knew nothing
  # about sweeps.
  #
  # Both halves move together, and the fixtures below pin each half against a literal derived from
  # the OTHER reading, so neither can have moved alone.
  describe "the post-sweep view" do
    let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }
    let(:checking) { create(:pool, :account, user: user, name: "Checking") }

    before { sign_in user, scope: :user }

    def waterfall_section = find("div[aria-labelledby='waterfall-heading']")

    def deposit(amount)
      category = create(:category, :income, user: user, pool: checking)
      create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
    end

    def envelope(name, rate:, priority:, funded: 0, funded_on: Date.current)
      pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
      create(:pool_budget, :per_period_rate, pool: pool, amount: rate)
      create(:pool_movement, from_pool: checking, to_pool: pool, amount: funded, date: funded_on) if funded.positive?
      pool
    end

    # A fortnight back is one biweekly boundary, so the money belongs to a period that has ended
    # and PoolCalculator#period_closed? is true.
    def closed_envelope(name, rate:, funded:, priority:)
      envelope(name, rate: rate, priority: priority, funded: funded, funded_on: Date.current - 14)
    end

    describe "a closed envelope's ask", :aggregate_failures do
      # The brief's own shape: Groceries holds $85 of last period's money against a $400 rate rule,
      # and $200 of unclaimed cash sits in Checking.
      #
      # Gas is the control: funded today, nothing to sweep, so its ask must NOT move.
      #
      #   live balance : Groceries asks 400 − 85 = 315, Gas asks 110, out of $200
      #                  → Groceries short 115, Gas short 110         = $225 short
      #   post-sweep   : Groceries asks 400, Gas asks 110, out of 200 + 85 = $285
      #                  → Groceries short 115, Gas short 110         = $225 short
      before do
        deposit(200 + 85 + 40)
        closed_envelope("Groceries", rate: 400, funded: 85, priority: 1)
        envelope("Gas", rate: 150, priority: 2, funded: 40)
        visit root_path
      end

      it "asks for the whole rule, because the leftover is about to be taken back" do
        expect(waterfall_section).to have_content("Groceries")
        expect(waterfall_section).to have_content("$285.00 of $400.00")
        expect(waterfall_section).to have_no_content("of $315.00")
      end

      it "leaves an envelope whose period is still open reading its live ask" do
        # $150 rate less the $40 it is holding. Same reader, no sweep, unchanged figure.
        expect(waterfall_section).to have_content("$0.00 of $110.00")
        expect(waterfall_section).to have_no_content("of $150.00")
      end

      # THE INVARIANCE, and it holds here: required rose by $85 (315 → 400) and available rose by
      # the same $85 (200 → 285), so the gap is the same $225 read either way.
      it "reports the same gap the live-balance reading did" do
        expect(page).to have_content("$225.00 short this period")
        expect(page).to have_content("You need $510.00 to stay on schedule. You have $285.00.")
      end

      # THE FIGURE THE BUTTON WOULD ACT ON. Two independent fills — HomePresenter#fill_waterfall
      # spans accounts, AllocationCalculator#fill spends one account's pot — and they now answer
      # the same question. Before this task they did not.
      it "agrees with the distribution screen it is offering" do
        expect(page).to have_content("Where your money goes")
        proposal = AllocationCalculator.new(user: user, account: Pool.find(checking.id))
        home = HomePresenter.new(user: user)
        expect(home.shortfall).to eq(proposal.rows.sum(0.to_d, &:short))
        expect(home.shortfall).to be_a(BigDecimal)
        expect(home.available).to eq(proposal.available)
      end
    end

    # THE OTHER DIRECTION, AND A CORRECTION TO THE BRIEF — mine, not the plan's, so it is stated
    # rather than folded in quietly. Amendment F says #shortfall "must not move at all" because
    # both sides rise by the same swept total. That is true only while the leftover is no larger
    # than what the rule re-asks for.
    #
    # Coffee holds $150 against a $100 rate rule. `sweepable_amount` takes the WHOLE $150 — an
    # envelope's surplus is not its rule's money — while the post-sweep ask rises only to $100. So
    # available gains $150 and required gains $100, and the gap legitimately CLOSES by the $50 of
    # surplus that was invisible while it sat inside the envelope:
    #
    #   live balance : Rent $300 + Coffee $0 asked, out of $0    → $300 short (Coffee has no row)
    #   post-sweep   : Rent $300 + Coffee $100,   out of $150    → $250 short
    #
    # Measured on the demo seeds too, where Pet Care's $50 sweep against a $25 rise took Home's
    # shortfall from $713.43 to $688.43. The property that actually holds — and the one worth
    # having — is the agreement with the distribution asserted below, which is exact in both cases.
    describe "a closed envelope holding more than its rule wants", :aggregate_failures do
      before do
        deposit(150)
        envelope("Rent", rate: 300, priority: 1)
        closed_envelope("Coffee", rate: 100, funded: 150, priority: 2)
        visit root_path
      end

      it "puts the surplus into the buffer and closes the gap by exactly that much" do
        expect(page).to have_content("$250.00 short this period")
        expect(page).to have_content("You have $150.00")
        expect(page).to have_no_content("$300.00 short this period")
      end

      # The pre-sweep reading gave Coffee no row at all: it held $150 against a $100 rule, so it
      # asked for nothing and #fill_waterfall rejects a zero-need row. Rendering $0 for an envelope
      # that is about to hand $150 back was the same defect class in the other direction.
      it "gives the closed envelope a row, asking for its whole rate" do
        expect(waterfall_section).to have_content("Coffee")
        expect(waterfall_section).to have_content("$0.00 of $100.00")
      end

      it "still agrees with the distribution screen" do
        expect(page).to have_content("Where your money goes")
        proposal = AllocationCalculator.new(user: user, account: Pool.find(checking.id))
        home = HomePresenter.new(user: user)
        expect(home.shortfall).to eq(proposal.rows.sum(0.to_d, &:short))
        expect(home.available).to eq(proposal.available)
      end
    end

    # AN OVERDRAWN ACCOUNT IS NOT A SOURCE, and a sweep that does not clear the overdraft does not
    # make it one. The clamp has to sit OUTSIDE the addition: `max(balance, 0) + sweeps` would give
    # this account a $150 pot to fund envelopes out of while it is still $200 in the red.
    #
    # Checking is $350 down and Coffee's closed $150 comes back to it, leaving −$200: nothing may be
    # funded, exactly as AllocationCalculator#fill produces from its own unclamped `balance + swept`.
    describe "an overdraft the sweep only partly repays" do
      before do
        deposit(150)
        envelope("Rent", rate: 300, priority: 1)
        closed_envelope("Coffee", rate: 100, funded: 150, priority: 2)
        category = create(:category, :expense, user: user, pool: checking, name: "Overspend")
        create(:entry, item: create(:item, category: category), amount: 350, date: Date.current)
        visit root_path
      end

      it "funds nothing, because the swept money lands inside the hole", :aggregate_failures do
        expect(waterfall_section).to have_content("$0.00 of $300.00")
        expect(waterfall_section).to have_content("$0.00 of $100.00")
        expect(page).to have_content("Checking is overdrawn $350.00")
        home = HomePresenter.new(user: user)
        expect(home.available).to eq(0)
        expect(home.available).to be_a(BigDecimal)
      end

      # THE ONE ACCOUNT STATE WHERE THE TWO SCREENS DELIBERATELY DISAGREE, pinned rather than left
      # latent. `HomePresenter#account_pots` clamps at zero because Home AGGREGATES across
      # accounts, where an unclamped negative would let one overdrawn account cancel another's
      # surplus; `AllocationCalculator#available` is deliberately unclamped because the
      # distribution screen is per-account and has no sibling to cancel against. Both are argued
      # and neither is going to change — and an unpinned deliberate difference is indistinguishable
      # from a bug the next time someone reads it.
      #
      # Checking is $350 down and Coffee's closed $150 comes back to it: -$200 on the distribution
      # screen, $0 here. Measured on the demo seeds too, where Side Gig Checking reads $0.00 on
      # Home and -$300.00 on `/distributions/new`, while the other three accounts agree exactly.
      #
      # THE SHORTFALL STILL AGREES, which is the property that holds in every shape and the one
      # worth having: both sides compute it independently — Home fills across accounts,
      # AllocationCalculator spends one account's pot — and nothing about this divergence moves it.
      it "clamps its own available while the distribution screen states the overdraft",
         :aggregate_failures do
           expect(page).to have_content("Checking is overdrawn $350.00")
           proposal = AllocationCalculator.new(user: user, account: Pool.find(checking.id))
           home = HomePresenter.new(user: user)

           expect(proposal.available).to eq(-200)
           expect(home.available).to eq(0)
           expect(home.shortfall).to eq(proposal.rows.sum(0.to_d, &:short))
           expect(home.shortfall).to eq(400)
         end
    end
  end

  # ────────────────────────────────────────────────────────────────────────────────────────────
  # THE LAST REASON A PROBLEM HAS NO BUTTON: the next distribution already solves it.
  #
  # Ruling 4 said do not offer money to a bill that already has it. This is the same principle one
  # step out — do not offer money to a bill that is ABOUT to have it. The move is not free: the
  # source loses money it was holding for its own rule, so proposing it is the app talking the user
  # into an unnecessary loss.
  #
  # A DEDICATED FIXTURE, because both directions have to be on ONE screen at figures that DIFFER —
  # an example where "funded in full" and "funded in part" coincided would pass either way.
  #
  #   Checking $400 · no sweeps, so the pot is exactly $400
  #   1 Dentist  $300 due in 3 days, empty  →  funded $300 of $300  ·  short $0    → COVERED
  #   2 Roof     $500 due in 3 days, empty  →  funded $100 of $500  ·  short $400  → still short
  #   3 Cushion  a savings goal holding $700, no rules — asks nothing, and is the source Roof needs
  describe "a problem the next distribution already solves" do
    let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }
    let(:checking) { create(:pool, :account, user: user, name: "Checking") }

    before do
      sign_in user, scope: :user
      deposit(1_100)
      bill(envelope("Dentist", priority: 1), "Dental Work", 300)
      bill(envelope("Roof", priority: 2), "Roof Repair", 500)
      cushion
      visit root_path
    end

    def problem_row(name) = find("[data-problem-pool='#{name}']")

    def waterfall_section = find("div[aria-labelledby='waterfall-heading']")

    def deposit(amount)
      category = create(:category, :income, user: user, pool: checking)
      create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
    end

    def envelope(name, priority:)
      create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    end

    # Due inside three days with a biweekly cadence anchored today: no boundary falls between
    # tomorrow and the due date, so the rule is unreachable and the pool reads `won't make it`.
    def bill(pool, item_name, amount)
      category = create(:category, :expense, user: user, pool: pool)
      create(
        :pool_budget,
        pool: pool,
        item: create(:item, category: category, name: item_name),
        amount: amount,
        interval_months: nil,
        anchor_date: Date.current + 3
      )
    end

    def cushion
      pool = create(
        :pool,
        :savings_pool,
        user: user,
        account: checking,
        name: "Cushion",
        target_amount: 5_000,
        priority: 3
      )
      create(:pool_movement, from_pool: checking, to_pool: pool, amount: 700, date: Date.current)
      pool
    end

    # THE TWO DIRECTIONS, ON ONE SCREEN, AT DIFFERENT FIGURES. Dentist's $300 arrives in full, so
    # it says so and offers nothing; Roof gets $100 of its $500 and keeps a real button. Both rows
    # are still red — the states are unchanged and the band still counts them as problems.
    it "drops the button on a pool the waterfall funds in full", :aggregate_failures do
      within(problem_row("Dentist")) do
        expect(page).to have_content("won't make it")
        expect(page).to have_content("Its money is coming — the next distribution funds this in full.")
        expect(page).to have_no_link(text: /\ATake/)
        expect(page).to have_no_content("This has to come from money you already have.")
      end
      expect(waterfall_section).to have_content("$300.00 of $300.00")
    end

    it "keeps the button on a pool the waterfall funds only in part", :aggregate_failures do
      within(problem_row("Roof")) do
        expect(page).to have_content("won't make it")
        expect(page).to have_link("Take $500.00 from Cushion")
        expect(page).to have_no_content("the next distribution funds this in full")
      end
      expect(waterfall_section).to have_content("$100.00 of $500.00")
    end

    # THE BRANCH READS THE PROPOSAL THE DISTRIBUTION SCREEN WOULD RENDER, not a second answer to
    # "will this be funded". Asserted against AllocationCalculator directly — the object that
    # screen is built on — so the two figures the branch turns on are pinned to it rather than to
    # Home's own copy of the fill. `short` is zero on exactly the pool that lost its button and
    # positive on exactly the pool that kept one.
    it "turns on the same figures the distribution screen would show", :aggregate_failures do
      expect(page).to have_css("[data-problem-pool='Roof']")
      rows = AllocationCalculator.new(user: user, account: Pool.find(checking.id)).rows.index_by { |r| r.pool.name }

      expect(rows.fetch("Dentist").short).to eq(0)
      expect(rows.fetch("Roof").short).to eq(400)
      expect(rows.fetch("Roof").short).to be_a(BigDecimal)
    end

    # The two branches must not be one branch wearing two labels. Roof needs $500 and holds nothing,
    # so PoolStatus#funding_gap is $500 on BOTH pools' terms — what separates them is the waterfall
    # alone. Pinned so a future edit cannot satisfy this file by folding ruling 4 and this one
    # together.
    it "separates this from the money-already-there case", :aggregate_failures do
      home = HomePresenter.new(user: user)
      dentist = user.pools.find_by!(name: "Dentist")

      expect(home.fix_for(dentist).amount).to eq(300)
      expect(home.fix_for(dentist)).to be_needs_money
      expect(home.fix_for(dentist)).to be_covered
      within(problem_row("Dentist")) do
        expect(page).to have_no_content("this needs paying, not funding")
      end
    end
  end
end
