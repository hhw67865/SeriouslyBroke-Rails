# frozen_string_literal: true

require "rails_helper"

# Task 6: the button that actually splits the paycheck, and the loop it closes — distribute,
# land on Home, find the envelopes funded and the buffer down by exactly what left it.
#
# THE INVARIANT IS `Σ pools == your bank balance`, and every example below reads it out of the
# database AFTER the write, never off the proposal — a proposal agreeing with itself was true
# before this task existed. `Pool#total` is *defined* as the account's balance plus its
# envelopes', so summing those parts against it is `x == x` and passes after any write
# whatsoever: the totals here are pinned against the LITERAL deposits the fixture planted, and
# every part is pinned against its own literal beside them.
#
# `Capybara.exact` is unset, so `have_content("$400.00")` also matches "$1,400.00" and matches
# whatever the sidebar prints. Every figure below is scoped to the row, the account header or
# the sentence that owns it.
RSpec.describe "Distribution Confirm", type: :system do
  # Biweekly, anchored today: this period is today..+13, and money paid a fortnight ago belongs
  # to a period that has closed — which is what makes Groceries' leftover sweepable.
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before { sign_in user, scope: :user }

  # THE WHOLE LOOP, on the simplest shape that can carry it: one paycheck, two rate envelopes,
  # no sweep. No sweep deliberately — with one, "the buffer dropped by exactly the allocated
  # total" is false by exactly the swept amount, and the sweep is asserted on its own terms
  # further down. Here the subtraction is clean and every figure is a literal.
  describe "an all-clear distribution", :aggregate_failures do
    before do
      envelope("Groceries", 400, priority: 1)
      envelope("Car", 1_500, priority: 2)
      deposit(2_400, on: Date.current)
      visit new_distribution_path
    end

    # The state BEFORE, asserted rather than assumed: without it every assertion after the
    # confirm would also pass on a screen that funded the envelopes on page load.
    it "moves nothing until the button is pressed" do
      expect(page).to have_css("h2", text: "Distribute $2,400.00")
      expect(page).to have_button("Confirm distribution")
      expect(PoolMovement.count).to eq(0)
      expect(balance_of("Groceries")).to eq(0)
      expect(balance_of("Car")).to eq(0)
      expect(buffer).to eq(2_400)
    end

    context "when it has been pressed" do
      before do
        click_on "Confirm distribution"
        await("stays in your buffer")
      end

      it "lands on Home and says what it did" do
        expect(page).to have_content("Distributed $1,900.00 into 2 envelopes. $500.00 stays in your buffer.")
        expect(page).to have_css("h1", text: "Home")
      end

      # The envelopes hold what the proposal promised them, in Home's own row vocabulary, and
      # the account header carries the same buffer the sentence above just quoted.
      it "shows the envelopes funded" do
        within("[data-pool-group='Checking']") do
          expect(page).to have_content("buffer now $500.00")
          within("[data-pool-name='Groceries']") { expect(page).to have_content("$400.00 left") }
          within("[data-pool-name='Car']") { expect(page).to have_content("$1,500.00 left") }
        end
      end

      # The ledger's half of the same two figures, read fresh from the database.
      it "writes one allocation per funded envelope" do
        expect(PoolMovement.distributed.count).to eq(2)
        expect(PoolMovement.kind_allocation.sum(:amount)).to eq(1_900)
        expect(balance_of("Groceries")).to eq(400)
        expect(balance_of("Car")).to eq(1_500)
      end

      # $2,400 went in, $1,900 was handed out, $500 is left. The left-hand figure is the
      # fixture's deposit; the right-hand one is the account read back after the write.
      it "drops the buffer by exactly the allocated total" do
        expect(buffer).to eq(500)
        expect(2_400 - buffer).to eq(PoolMovement.kind_allocation.sum(:amount))
      end

      # THE INVARIANT. $2,400 is the paycheck the fixture planted and nothing else has entered
      # this user's life, so that is what the bank holds before and after. The movements moved
      # it between pools; none of them made any.
      it "creates no money" do
        expect(bank_balance).to eq(2_400)
      end
    end
  end

  # The short screen, which is the one with a waterfall, a sweep and editable boxes. $500 arrived
  # last period and $85 of it went to Groceries, leaving $415 carried over; $2,400 landed this
  # period; the $85 comes back. $400 + $2,600 + $150 of asks then drain the $2,900 and run out
  # inside Car.
  describe "a short distribution with a sweep", :aggregate_failures do
    before do
      envelope("Groceries", 400, funded: 85, priority: 1)
      envelope("Car", 2_600, priority: 2)
      envelope("Vacation", 150, priority: 3)
      deposit(500, on: Date.current - 14)
      deposit(2_400, on: Date.current)
      visit new_distribution_path
    end

    # The proposal this fixture makes, before anything is pressed: the money runs out inside Car
    # and Vacation gets nothing. Every context below is about what happens to THAT split, so it
    # is asserted once here rather than assumed five times.
    it "proposes the split before anything is pressed" do
      within("[data-pool-name='Car']") { expect(page).to have_content("$2,500.00 of $2,600.00") }
      within("[data-pool-name='Vacation']") { expect(page).to have_content("$0.00 of $150.00") }
      # `distributed`, not every movement: the fixture's own funding of Groceries a fortnight ago
      # is a `transfer`, and it is what makes this envelope sweepable in the first place.
      expect(PoolMovement.distributed.count).to eq(0)
    end

    context "when confirmed as proposed" do
      before do
        click_on "Confirm distribution"
        await("stays in your buffer")
      end

      it "names the sweep in what it says it did" do
        expect(page).to have_content(
          "Distributed $2,900.00 into 2 envelopes, $85.00 swept back first. $0.00 stays in your buffer."
        )
      end

      # $85 left Groceries and $400 came back, so the envelope holds its full rate rather than
      # $485 — and the envelope below the cutoff got nothing, which Home says rather than
      # staying silent about.
      it "shows the swept envelope topped up and the starved one empty" do
        within("[data-pool-group='Checking']") do
          expect(page).to have_content("buffer now $0.00")
          within("[data-pool-name='Groceries']") { expect(page).to have_content("$400.00 left") }
          within("[data-pool-name='Car']") { expect(page).to have_content("$2,500.00 left") }
          within("[data-pool-name='Vacation']") { expect(page).to have_content("$0.00 left") }
        end
      end

      # Three movements: the sweep out of Groceries and two allocations. Vacation's $0.00 row is
      # not a movement — PoolMovement refuses a zero amount, and one starved envelope must not
      # roll the whole split back.
      it "writes the sweep as a movement of its own" do
        expect(PoolMovement.kind_sweep.pluck(:amount)).to eq([85])
        expect(PoolMovement.kind_allocation.pluck(:amount)).to contain_exactly(400, 2_500)
        expect(balance_of("Vacation")).to eq(0)
      end

      # WITH A SWEEP THE BRIEF'S SUBTRACTION NEEDS ITS SECOND TERM: the buffer fell $2,815, not
      # $2,900, because $85 came back INTO the account on its way out to the envelopes. The left
      # side is the account's own balance, the right side the two ledgers the confirm wrote.
      it "drops the buffer by the allocations less the sweep" do
        expect(buffer).to eq(0)
        expect(2_815 - buffer).to eq(
          PoolMovement.kind_allocation.sum(:amount) - PoolMovement.kind_sweep.sum(:amount)
        )
      end

      # $500 + $2,400 of pay, and not a cent of it created or destroyed by three movements.
      it "creates no money" do
        expect(bank_balance).to eq(2_900)
      end
    end

    # HTML'S IMPLICIT SUBMISSION, and no other example on this screen can see it. Enter pressed in
    # a text or number field activates THE FIRST SUBMIT BUTTON IN TREE ORDER — so with the confirm
    # rendered first inside the waterfall's form, the most natural keystroke there is in a numeric
    # box POSTED THE SPLIT, with the boxes below the caret possibly still empty. Measured with the
    # two buttons the other way round: this example landed on `/` with 4 movements written and
    # $1,550.00 allocated, and no click on Confirm.
    #
    # Both halves, on the same keystroke: nothing was written, AND the recompute that should have
    # happened did. The path assertion is the sharp one — `overrides` in the QUERY STRING is a GET
    # to `new`, which a POST to `create` could not produce.
    it "recomputes rather than confirming when Enter is pressed in a box" do
      fill_in "Amount for Car", with: "1000"
      find_field("Amount for Car").send_keys(:enter)

      expect(page).to have_current_path(/overrides/)
      within("[data-pool-name='Vacation']") { expect(page).to have_content("$150.00") }
      expect(PoolMovement.distributed.count).to eq(0)
      expect(page).to have_css("#confirm-distribution")
    end

    # THE EDIT IS WHAT GETS WRITTEN, and specifically an edit the user never pressed "Update
    # figures" on. The confirm is a submitter inside the waterfall's own form for exactly this
    # reason: a separate form carrying the already-applied overrides would have written $2,500
    # into an envelope the user had just typed 1000 into, silently. It also pins the cascade at
    # write time — cutting Car by $1,500 funds Vacation, which the untouched proposal left at $0.
    context "with a figure typed into a box and nothing else pressed" do
      before do
        fill_in "Amount for Car", with: "1000"
        click_on "Confirm distribution"
        await("stays in your buffer")
      end

      it "writes the figure in the box, and the cascade it caused" do
        expect(page).to have_content(
          "Distributed $1,550.00 into 3 envelopes, $85.00 swept back first. $1,350.00 stays in your buffer."
        )
        expect(PoolMovement.kind_allocation.pluck(:amount)).to contain_exactly(400, 1_000, 150)
        expect(bank_balance).to eq(2_900)
      end

      it "shows the envelope the edit paid for" do
        within("[data-pool-group='Checking']") do
          within("[data-pool-name='Car']") { expect(page).to have_content("$1,000.00 left") }
          within("[data-pool-name='Vacation']") { expect(page).to have_content("$150.00 left") }
          expect(page).to have_content("buffer now $1,350.00")
        end
      end
    end

    # SPEC §7.3 AT THE WRITE, not at the read. Task 5 pinned that an override above what remains
    # is clamped on the SCREEN; this is the same rule asserted against the ledger, which is where
    # it costs money. The historical shape is exact: while overrides were substituted after the
    # fill, an override of $350 against $185 of cash wrote $350 and left the account at -$165.
    #
    # $5,000 into the FIRST envelope is more than the account holds, so it takes everything and
    # the two below it get nothing — a split visibly different from the un-edited one, which is
    # what proves the figure was read at all, above a buffer that lands on zero rather than
    # -$2,100.
    context "with an override larger than the account holds" do
      before do
        fill_in "Amount for Groceries", with: "5000"
        click_on "Confirm distribution"
        await("stays in your buffer")
      end

      it "hands out what there is and no more" do
        expect(page).to have_content(
          "Distributed $2,900.00 into 1 envelope, $85.00 swept back first. $0.00 stays in your buffer."
        )
        expect(balance_of("Groceries")).to eq(2_900)
        expect(balance_of("Car")).to eq(0)
      end

      # What actually left the account is the allocations less the sweep that came back into it,
      # and it cannot exceed the $2,815 the account held.
      it "cannot drive the account below zero" do
        expect(buffer).to eq(0)
        expect(buffer).not_to be_negative
        expect(
          PoolMovement.kind_allocation.sum(:amount) - PoolMovement.kind_sweep.sum(:amount)
        ).to eq(2_815)
        expect(bank_balance).to eq(2_900)
      end
    end

    # CONFIRMING TWICE REPLACES, and this is the shape the `Σ pools` invariant is most at risk
    # from: a second confirm that ADDED to the first would hand out $2,900 again from an account
    # that no longer holds it, and every envelope would end up holding money the bank does not
    # have.
    context "when confirmed a second time" do
      before do
        click_on "Confirm distribution"
        await("Distributed $2,900.00")
        visit new_distribution_path
        await("You've already distributed this period")
        click_on "Confirm distribution"
        await("stays in your buffer")
      end

      # Amendment D: the screen said this replaces the previous split, so the sentence afterwards
      # says the same thing. "Distributed $2,900.00" here would read as a second $2,900 moving.
      it "says it replaced the split rather than adding to it" do
        expect(page).to have_content(
          "Replaced this period's split — distributed $2,900.00 into 2 envelopes, $85.00 swept back first."
        )
        expect(page).to have_no_content("Distributed $2,900.00 into")
      end

      it "leaves one split in the ledger, not two" do
        expect(PoolMovement.distributed.count).to eq(3)
        expect(PoolMovement.kind_allocation.sum(:amount)).to eq(2_900)
        expect(balance_of("Groceries")).to eq(400)
        expect(buffer).to eq(0)
        expect(bank_balance).to eq(2_900)
      end
    end
  end

  # THE COLLAPSED SCREEN'S HIDDEN `account_id`, which every other example on this page would pass
  # without: with one account the controller's fallback finds the right one whether the field is
  # there or not. Here the pay landed in Checking, so the fallback picks CHECKING — and the user
  # is looking at Ally. Delete the field and the button writes Checking's split from Ally's
  # screen, which is the shape "the moment a second paycheck arrives mid-period" names.
  describe "confirming a second account from its own screen", :aggregate_failures do
    let(:ally) { create(:pool, :account, user: user, name: "Ally") }

    before do
      envelope("Groceries", 400, priority: 1)
      deposit(2_400, on: Date.current)
      create(
        :pool_budget,
        :per_paycheck_rate,
        amount: 100,
        pool: create(:pool, :budget_pool, user: user, account: ally, name: "Holiday")
      )
      create(
        :entry,
        amount: 300,
        date: Date.current,
        item: create(:item, category: create(:category, :income, user: user, pool: ally))
      )
      visit new_distribution_path(account_id: ally.id)
    end

    # The pairing: with no account named this screen opens on Checking, so the example below is
    # about the field and not about the only account there is.
    it "opens on the account the pay landed in when none is named" do
      visit new_distribution_path
      expect(page).to have_css("h1", text: "Checking")
      expect(page).to have_no_css("h1", text: "Ally")
    end

    it "writes the split for the account on screen, not the default one" do
      expect(page).to have_css("h1", text: "Ally")
      click_on "Confirm distribution"

      expect(page).to have_content("Distributed $100.00 into 1 envelope. $200.00 stays in your buffer.")
      expect(balance_of("Holiday")).to eq(100)
      expect(balance_of("Groceries")).to eq(0)
      expect(Pool.find(checking.id).calculator.balance).to eq(2_400)
    end
  end

  # An account that cannot fund anything still has a button, and pressing it must say so rather
  # than claim a split. $100 in against $400 out leaves the account $300 down, so every row
  # clamps to zero and no movement is written at all.
  describe "an account with nothing to give", :aggregate_failures do
    before do
      envelope("Quarterly Taxes", 200, priority: 1)
      deposit(100, on: Date.current)
      spend(400, on: Date.current)
      visit new_distribution_path
    end

    # The pairing: the button is offered on a screen that has nothing to hand out, which is what
    # makes the sentence below a refusal rather than a missing control.
    it "offers the button over an account with nothing in it" do
      expect(page).to have_css("h2", text: "Nothing to distribute")
      expect(page).to have_button("Confirm distribution")
    end

    it "says nothing could be funded and leaves the ledger empty" do
      click_on "Confirm distribution"
      expect(page).to have_content("Nothing could be funded. -$300.00 stays in your buffer.")
      expect(page).to have_no_content("Distributed $")
      expect(PoolMovement.count).to eq(0)
      expect(balance_of("Quarterly Taxes")).to eq(0)
      expect(buffer).to eq(-300)
      expect(bank_balance).to eq(-300)
    end
  end

  private

  # A SYNCHRONISATION POINT, NOT AN EXPECTATION. A hook that performs two round trips has to
  # wait for the first to land before starting the second, and Capybara's predicates are what
  # block until it does. It raises rather than returning false because a hook that carried on
  # regardless would move the failure into an example that had nothing to do with it — the
  # assertions themselves all live in examples, which is what RSpec/ExpectInHook is about.
  def await(content)
    return if page.has_content?(content)

    raise "expected the page to show #{content.inspect} before the next step"
  end

  # The account's unallocated cash, read through the app's own definition of a balance and
  # through a FRESHLY BUILT calculator: PoolCalculator memoises, so one held across the confirm
  # answers from before the write.
  def buffer = Pool.find(checking.id).calculator.balance

  # WHAT THE BANK WOULD SAY: the account's own cash plus every envelope inside it. Compared
  # against the literal deposits the fixture planted, never against a sum of its own parts —
  # `Pool#total` IS that sum, so the two agree after any write whatsoever.
  def bank_balance = Pool.find(checking.id).total

  def balance_of(name) = user.pools.find_by!(name: name).calculator.balance

  def envelope(name, rate, funded: nil, priority: 0)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    create(:pool_budget, :per_paycheck_rate, pool: pool, amount: rate)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: funded, date: Date.current - 14) if funded
    pool
  end

  def deposit(amount, on:)
    category = create(:category, :income, user: user, pool: checking)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  def spend(amount, on:)
    category = create(:category, :expense, user: user, pool: checking)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end
end
