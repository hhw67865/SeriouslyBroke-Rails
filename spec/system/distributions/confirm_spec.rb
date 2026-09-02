# frozen_string_literal: true

require "rails_helper"

# The button that actually splits the paycheck, and the loop it closes — distribute, land on Home,
# and find the ledger holding what the sentence said.
#
# THE INVARIANT IS `available + Σ holdings == income − expenses` (two-ledger spec §2), and every
# example below reads it out of the database AFTER the write, never off the proposal — a proposal
# agreeing with itself was true before this task existed. The totals here are pinned against the
# LITERAL deposits the fixture planted, and every part is pinned against its own literal beside them.
#
# THREE EXAMPLES WERE WITHDRAWN AND ONE GROUP DELETED (two-ledger Task 4), each named where it stood:
#   * the three that read the funded envelopes back off HOME's own rows. Home renders the POOL ledger
#     until Task 6, and a distribution no longer writes it — so those rows are correct and unchanged
#     and say nothing about the split. Their claim survives as the ledger assertion beside each of
#     them, which is where it was always sharper; Task 6 restores the screen half on categories.
#   * "confirming a second account from its own screen", whole. There is one root per user (§2), so
#     there is no second screen, no hidden `account_id`, and no default to confirm the wrong one from.
#
# `Capybara.exact` is unset, so `have_content("$400.00")` also matches "$1,400.00" and matches
# whatever the sidebar prints. Every figure below is scoped to the row or the sentence that owns it.
RSpec.describe "Distribution Confirm", type: :system do
  # Biweekly, anchored today: this period is today..+13, and money allocated a fortnight ago belongs
  # to a period that has closed — which is what makes Groceries' leftover sweepable.
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }
  # The pot, for income to land in: `Category#income_must_land_in_an_account` says an income category
  # may only point at the user's main account. No figure below is read off it.
  # rubocop:disable RSpec/LetSetup -- THE POT HAS TO EXIST, and nothing here reads it: income
  # lands in a category and `Category#income_must_land_in_an_account` says that category may
  # only point at the user's MAIN account, so a user with no account cannot be paid at all. It
  # is setup for the physical side of a fixture whose every assertion is on the purpose side.
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  # rubocop:enable RSpec/LetSetup

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
      expect(Allocation.count).to eq(0)
      expect(holding_of("Groceries")).to eq(0)
      expect(holding_of("Car")).to eq(0)
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

      # WITHDRAWN: "shows the envelopes funded" read `$400.00 left` and `buffer now $500.00` off
      # Home's own rows. Home renders POOLS until Task 6 and a distribution writes CATEGORIES, so
      # those rows would be correct, unchanged, and about a different ledger. The ledger half below
      # is what that example was really asserting.
      it "writes one allocation per funded category" do
        expect(Allocation.distributed.count).to eq(2)
        expect(Allocation.kind_allocation.sum(:amount)).to eq(1_900)
        expect(holding_of("Groceries")).to eq(400)
        expect(holding_of("Car")).to eq(1_500)
      end

      # $2,400 went in, $1,900 was handed out, $500 is left. The left-hand figure is the fixture's
      # deposit; the right-hand one is available read back after the write.
      it "drops the buffer by exactly the allocated total" do
        expect(buffer).to eq(500)
        expect(2_400 - buffer).to eq(Allocation.kind_allocation.sum(:amount))
      end

      # THE INVARIANT. $2,400 is the paycheck the fixture planted and nothing else has entered this
      # user's life, so that is what both partitions hold before and after. The allocations moved it
      # between the root and the categories; none of them made any.
      it "creates no money" do
        expect(purpose_total).to eq(2_400)
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
      within("[data-category-name='Car']") { expect(page).to have_content("$2,500.00 of $2,600.00") }
      within("[data-category-name='Vacation']") { expect(page).to have_content("$0.00 of $150.00") }
      # `distributed`, not every allocation: the fixture's own funding of Groceries a fortnight ago
      # is a `transfer`, and it is what makes this category sweepable in the first place.
      expect(Allocation.distributed.count).to eq(0)
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

      # WITHDRAWN with its Home rows: "shows the swept envelope topped up and the starved one empty"
      # read `$400.00 left` / `$0.00 left` off Home, which is still the pool ledger. Its three
      # figures are the three below, read out of the ledger the confirm actually wrote.
      #
      # Three rows: the sweep out of Groceries and two allocations. $85 left Groceries and $400 came
      # back, so the category holds its full rate rather than $485. Vacation's $0.00 row is not a
      # row at all — `Allocation` refuses a zero amount, and one starved category must not roll the
      # whole split back.
      it "writes the sweep as an allocation of its own" do
        expect(Allocation.kind_sweep.pluck(:amount)).to eq([85])
        expect(Allocation.kind_allocation.pluck(:amount)).to contain_exactly(400, 2_500)
        expect(holding_of("Groceries")).to eq(400)
        expect(holding_of("Vacation")).to eq(0)
      end

      # WITH A SWEEP THE SUBTRACTION NEEDS ITS SECOND TERM: available fell $2,815, not $2,900,
      # because $85 came back to the root on its way out to the categories.
      it "drops the buffer by the allocations less the sweep" do
        expect(buffer).to eq(0)
        expect(2_815 - buffer).to eq(
          Allocation.kind_allocation.sum(:amount) - Allocation.kind_sweep.sum(:amount)
        )
      end

      # $500 + $2,400 of pay, and not a cent of it created or destroyed by three allocations.
      it "creates no money" do
        expect(purpose_total).to eq(2_900)
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
      within("[data-category-name='Vacation']") { expect(page).to have_content("$150.00") }
      expect(Allocation.distributed.count).to eq(0)
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

      # WITHDRAWN with its Home rows: "shows the envelope the edit paid for" read `$1,000.00 left`
      # and `$150.00 left` off Home. The two holdings and the buffer below are the same three
      # figures, read out of the ledger.
      it "writes the figure in the box, and the cascade it caused" do
        expect(page).to have_content(
          "Distributed $1,550.00 into 3 envelopes, $85.00 swept back first. $1,350.00 stays in your buffer."
        )
        expect(Allocation.kind_allocation.pluck(:amount)).to contain_exactly(400, 1_000, 150)
        expect([holding_of("Car"), holding_of("Vacation"), buffer]).to eq([1_000, 150, 1_350])
        expect(purpose_total).to eq(2_900)
      end
    end

    # SPEC §7.3 AT THE WRITE, not at the read. Task 5 pinned that an override above what remains
    # is clamped on the SCREEN; this is the same rule asserted against the ledger, which is where
    # it costs money. The historical shape is exact: while overrides were substituted after the
    # fill, an override of $350 against $185 of cash wrote $350 and left the account at -$165.
    #
    # $5,000 into the FIRST category is more than there is, so it takes everything and the two below
    # it get nothing — a split visibly different from the un-edited one, which is what proves the
    # figure was read at all, above a buffer that lands on zero rather than -$2,100.
    context "with an override larger than the buffer holds" do
      before do
        fill_in "Amount for Groceries", with: "5000"
        click_on "Confirm distribution"
        await("stays in your buffer")
      end

      it "hands out what there is and no more" do
        expect(page).to have_content(
          "Distributed $2,900.00 into 1 envelope, $85.00 swept back first. $0.00 stays in your buffer."
        )
        expect(holding_of("Groceries")).to eq(2_900)
        expect(holding_of("Car")).to eq(0)
      end

      # What actually left the root is the allocations less the sweep that came back into it, and it
      # cannot exceed the $2,815 that was there.
      it "cannot drive the buffer below zero" do
        expect(buffer).to eq(0)
        expect(buffer).not_to be_negative
        expect(
          Allocation.kind_allocation.sum(:amount) - Allocation.kind_sweep.sum(:amount)
        ).to eq(2_815)
        expect(purpose_total).to eq(2_900)
      end
    end

    # CONFIRMING TWICE REPLACES, and this is the shape the §2 invariant is most at risk from: a
    # second confirm that ADDED to the first would hand out $2,900 again from a root that no longer
    # holds it, and every category would end up holding money that never came in.
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
        expect(Allocation.distributed.count).to eq(3)
        expect(Allocation.kind_allocation.sum(:amount)).to eq(2_900)
        expect(holding_of("Groceries")).to eq(400)
        expect(buffer).to eq(0)
        expect(purpose_total).to eq(2_900)
      end
    end
  end

  # A root that cannot fund anything still has a button, and pressing it must say so rather than
  # claim a split. $100 in against $400 out leaves the buffer $300 down, so every row clamps to zero
  # and no allocation is written at all.
  describe "a buffer with nothing to give", :aggregate_failures do
    before do
      envelope("Quarterly Taxes", 200, priority: 1)
      deposit(100, on: Date.current)
      spend(400, on: Date.current)
      visit new_distribution_path
    end

    # The pairing: the button is offered on a screen that has nothing to hand out, which is what
    # makes the sentence below a refusal rather than a missing control.
    it "offers the button over a buffer with nothing in it" do
      expect(page).to have_css("h2", text: "Nothing to distribute")
      expect(page).to have_button("Confirm distribution")
    end

    it "says nothing could be funded and leaves the ledger empty" do
      click_on "Confirm distribution"
      expect(page).to have_content("Nothing could be funded. -$300.00 stays in your buffer.")
      expect(page).to have_no_content("Distributed $")
      expect(Allocation.count).to eq(0)
      expect(holding_of("Quarterly Taxes")).to eq(0)
      expect(buffer).to eq(-300)
      expect(purpose_total).to eq(-300)
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

  # A FRESH ledger every time: `CategoryLedger` is a snapshot memoised at first read, so one held
  # across the confirm answers from before the write.
  def ledger = CategoryLedger.new(user.categories.expenses.to_a, user: user)

  # MONEY WITH NO JOB YET — the purpose ledger's root, which is what "buffer" names on this screen.
  def buffer = ledger.available

  # THE §2 PARTITION: available plus every holding. Compared against the literal deposits the fixture
  # planted, never against a sum of its own parts.
  def purpose_total
    categories = user.categories.expenses.to_a
    snapshot = CategoryLedger.new(categories, user: user)

    snapshot.available + categories.sum(0.to_d) { |category| snapshot.holding_of(category) }
  end

  def holding_of(name) = user.categories.find_by!(name: name).holding_calculator.balance

  def envelope(name, rate, funded: nil, priority: 0)
    category = create(:category, :expense, :funded, user: user, name: name, priority: priority)
    create(:budget, :per_period_rate, pool: nil, category: category, amount: rate)
    create(:allocation, to_category: category, amount: funded, date: Date.current - 14) if funded
    category
  end

  def deposit(amount, on:)
    category = create(:category, :income, user: user)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # Spending by a category that holds none of its own money, so it drains AVAILABLE (§4).
  def spend(amount, on:)
    category = create(:category, :expense, user: user)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end
end
