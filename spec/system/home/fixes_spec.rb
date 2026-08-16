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

    def problem_row(name) = find("[data-problem-pool='#{name}']")

    # Checking holds $810 of unclaimed cash and Dentist needs $300 it will never reach in time.
    # The account is a legitimate source — it stands in as its own container (PoolMovement) and the
    # buffer is the money no envelope has claimed — and at $810 free it is also the richest thing
    # in the account, so "richest first" and "the buffer first" happen to agree here.
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
    # Both directions on one screen: Car is refused, Checking is offered, and Car's $1,000 is
    # pinned so the negative cannot be passing because Car is empty.
    it "leaves out a pool whose money its own rules are holding", :aggregate_failures do
      visit root_path

      within(problem_row("Dentist")) do
        expect(page).to have_no_link(text: /from Car/)
        expect(page).to have_link("Take $300.00 from Checking buffer")
      end
      expect(balance_of("Car")).to eq(1_000)
      expect(Pool.find(car.id).calculator.free_amount).to eq(200)
    end

    # A pool in trouble on its own terms is excluded outright, however rich it is: Vet holds $1,500
    # with only $200 of it spoken for, which makes it far and away the richest source in the
    # account — and it is overdue, so proposing to rob it is not a fix.
    #
    # The positive halves matter as much as the negative: Vet really is a problem (it has its own
    # row saying so), it really would have won on free money alone, and Dentist still gets a button.
    describe "a richer pool that is itself overdue" do
      let(:vet) { create(:pool, :budget_pool, user: user, account: checking, name: "Vet", priority: 8) }

      before do
        deposit(1_500)
        fund(vet, 1_500)
        dated_rule(vet, "Vet Bill", 200, due_in: -10)
        visit root_path
      end

      it "leaves out a pool whose own status needs attention", :aggregate_failures do
        within(problem_row("Vet")) { expect(page).to have_content("overdue") }
        within(problem_row("Dentist")) do
          expect(page).to have_no_link(text: /from Vet/)
          expect(page).to have_link("Take $300.00 from Checking buffer")
        end
        # $1,300 free is more than Checking's $810: nothing but the status exclusion kept it out.
        expect(Pool.find(vet.id).calculator.free_amount).to eq(1_300)
      end
    end

    # AMENDMENT D. Two pools with identical free money must not reorder between renders, so the
    # tie falls to `[priority, name]` — the same key #by_priority uses.
    #
    # The names are assigned AFTER the ids exist and deliberately against them: the pool with the
    # smaller id is called "Zebra Fund", so a read that fell through to id order would offer Zebra
    # and a name-ordered one offers Apple. Both pools are pinned at $900 so the example cannot be
    # passing because one is richer.
    describe "two sources holding identical free money" do
      let(:tied) do
        deposit(1_800)
        ["Tie A", "Tie B"].map { |name| envelope(name, priority: 9, funded: 900) }.sort_by(&:id)
      end

      before do
        tied.first.update!(name: "Zebra Fund")
        tied.last.update!(name: "Apple Fund")
        visit root_path
      end

      it "breaks a tie on free money by name, not by id", :aggregate_failures do
        within(problem_row("Dentist")) do
          expect(page).to have_link("Take $300.00 from Apple Fund")
          expect(page).to have_no_link(text: /from Zebra Fund/)
        end
        expect(tied.map { |pool| Pool.find(pool.id).calculator.free_amount }).to eq([900, 900])
        expect(tied.first.reload.name).to eq("Zebra Fund")
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

    # THE OTHER NO-BUTTON CASE, and it is a different answer rather than the same one twice. No
    # account's money can reach a pool that sits in no account, whatever anyone moves — and the
    # gap sentence would be nonsense here anyway, since PoolStatus#amount on an owed savings goal
    # is the pool's own BALANCE. So the band names the step that does fix it.
    it "tells a pool with no account to get one, rather than offering a move", :aggregate_failures do
      stranded = create(:pool, user: user, name: "Old Goal", target_amount: 5_000, priority: 8)
      create(:pool_budget, :per_paycheck_rate, pool: stranded, amount: 200)

      visit root_path

      within(problem_row("Old Goal")) do
        expect(page).to have_content("Assign it to an account before any money can reach it.")
        expect(page).to have_no_link(text: /\ATake/)
        expect(page).to have_no_content("Nothing in")
      end
      within(problem_row("Dentist")) { expect(page).to have_link("Take $300.00 from Checking buffer") }
    end

    # AN ACCOUNT IS A DESTINATION TOO. An overdraft is the loudest state in the app and it is the
    # one problem whose fix comes from INSIDE it: the envelopes it funded are the only things that
    # can put the money back. `PoolMovement#containing_account` is what makes the account its own
    # container on both ends, which is why this works without a second notion of "same account".
    #
    # $900 spent straight out of Checking against $810 of buffer leaves it $90 down. Cushion's $500
    # is the richest thing left — Checking itself is excluded as the destination, and every other
    # envelope's money is held by a rule.
    it "fixes an overdrawn account out of an envelope inside it", :aggregate_failures do
      category = create(:category, :expense, user: user, pool: checking, name: "Big Spend")
      create(:entry, item: create(:item, category: category), amount: 900, date: Date.current)

      visit root_path

      within(problem_row("Checking")) do
        expect(page).to have_content("overdrawn $90.00")
        expect(page).to have_link("Take $90.00 from Cushion")
        expect(page).to have_content("Cushion $500.00 → $410.00")
      end
      expect(balance_of("Checking")).to eq(-90)
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
      create(:pool_budget, :per_paycheck_rate, pool: pool, amount: rate)
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
    end
  end
end
