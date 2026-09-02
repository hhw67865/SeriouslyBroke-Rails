# frozen_string_literal: true

require "rails_helper"

# THE WRITE: moving money by hand when life happens — one allocation, from, to, amount, on the
# purpose ledger.
#
# THE PORT OF `spec/system/account_movements/move_spec.rb`. One refusal could not come across —
# "refuses a source in another account" — because `must_not_cross_accounts` dies with the concept
# (two-ledger spec §2: an allocation moves intention, not location). The floor at the write survives
# it, ported to `Allocation#source_must_hold_it`, and is the example below it.
#
# THE INVARIANT IS `available + Σ holdings == income − expenses`, and a hand move cannot change it:
# the money stays inside the user's own purpose ledger. Every total below is pinned against the
# LITERAL $3,000 deposit the fixture planted rather than against a sum of the app's own parts.
#
# `Capybara.exact` is unset, so `have_content("$300.00")` also matches "$1,300.00" and matches the
# sidebar. Every figure below is scoped to the row or the sentence that owns it.
RSpec.describe "Allocations Move", type: :system do
  include_context "with categories to reallocate between"

  describe "moving the money", :aggregate_failures do
    before do
      visit new_allocation_path(to_category_id: dentist.id, from_category_id: car.id, amount: 300)
      click_on "Move the money"
      await("Moved $300.00")
    end

    it "lands on Home and says what it did, from the ledger" do
      expect(page).to have_content("Moved $300.00 from Car to Dentist. Car $700.00 · Dentist $300.00")
      expect(page).to have_css("h1", text: "Home")
    end

    # ONE ROW, AND A `transfer` — the column default, which is exactly what keeps it out of
    # `Allocation.distributed`.
    it "writes one transfer and nothing a distribution owns" do
      moved = Allocation.where(from_category: car, to_category: dentist)
      expect(moved.count).to eq(1)
      expect(moved.first).to be_kind_transfer
      expect(moved.first.amount).to eq(300)
      expect(Allocation.distributed.count).to eq(0)
    end

    # The two holdings move by exactly the amount, in opposite directions, and the root does not move
    # at all — pinned against the fixture's own $3,000 deposit.
    it "moves the money between the two categories and creates none" do
      expect(holding_of("Car")).to eq(700)
      expect(holding_of("Dentist")).to eq(300)
      expect(available).to eq(810)
      expect(purpose_total).to eq(3_000)
    end

    # THE PREVIEW WAS TRUE. The left side was computed before the write through HoldingProjection's
    # `pending:`; the right side is read out of the database afterwards. Two independent routes to the
    # same figures, which is the whole point of building the damage statement out of the same readers
    # the ledger will produce.
    #
    # READ OFF THE FLASH rather than off Home's own rows: Home renders the POOL ledger until Task 6,
    # so a hand move on the purpose ledger does not touch anything it prints. The sentence in the
    # flash is built from `CategoryLedger` after the write, which is the reading this example is
    # about — see the port note in this file's header.
    it "leaves the categories exactly where the screen said it would" do
      expect(page).to have_content("Car $700.00 · Dentist $300.00")
      expect([holding_of("Car"), holding_of("Dentist")]).to eq([700, 300])
    end

    # MONEY BY TYPE. It is BigDecimal from a `money` column and `eq(300)` passes for the Integer just
    # as happily, so no figure above can tell the two apart.
    #
    # The post-write side is the WEAKER half and is named as such: every category here now has an
    # allocation whose amount comes back from Postgres as a BigDecimal. `available` is the one that
    # earns its place — it is a Ruby-side subtraction of four sums, which is its own chance to leak.
    # The genuinely empty shape is asserted on Dentist in new/sources_spec.rb, before money reaches it.
    #
    # The screen assertion anchors the ledger reading to the page it is about, and it is also what
    # keeps this body from touching Capybara not at all — the shape that wedges the driver (see the
    # shared context).
    it "reports money as BigDecimal rather than Integer" do
      expect(page).to have_css("h1", text: "Home")
      expect(holding_of("Car")).to be_a(BigDecimal)
      expect(available).to be_a(BigDecimal)
      expect(Allocation.where(from_category: car, to_category: dentist).sole.amount).to be_a(BigDecimal)
    end
  end

  # A HAND MOVE BACK TO THE ROOT — a savings withdrawal (spec §3), and the direction the pool era
  # spelled as "an envelope back to its account's buffer". It is one row with a NULL destination, and
  # that NULL is what AVAILABLE is.
  describe "moving money back to available", :aggregate_failures do
    before do
      visit new_allocation_path(
        to_category_id: ReallocationPresenter::ROOT.id, from_category_id: pool_free_source.id, amount: 200
      )
      click_on "Move the money"
      await("Moved $200.00")
    end

    def pool_free_source = category("Cushion")

    it "writes one row with the root on the null side" do
      expect(page).to have_content("Moved $200.00 from Cushion to Available. Cushion $300.00 · Available $1,010.00")
      row = Allocation.where(from_category: category("Cushion")).sole
      expect([row.to_category, row.kind]).to eq([nil, "transfer"])
      expect([holding_of("Cushion"), available]).to eq([300, 1_010])
      expect(purpose_total).to eq(3_000)
    end
  end

  # A redistribution replaces the period's own rows and must leave a hand move alone: a user who
  # moves $50 between categories and then redistributes still has their $50 move.
  #
  # THE MOVE IS RENT → AVAILABLE, and the direction is deliberate: it lands squarely inside the
  # period, on the root every distributed row also touches, so `distributed` is the ONLY thing
  # sparing it — which is the fact this example is about. Written category → category it would be
  # spared by nothing in particular and would pass with `kind: :allocation` forced on.
  describe "surviving a redistribution", :aggregate_failures do
    let(:distributed_before) { Allocation.distributed.pluck(:id) }
    let(:transfer) { Allocation.where(from_category: category("Rent"), to_category: nil).sole }

    before do
      distribute
      distributed_before
      visit new_allocation_path(
        to_category_id: ReallocationPresenter::ROOT.id, from_category_id: category("Rent").id, amount: 100
      )
      click_on "Move the money"
      await("Moved $100.00")
      transfer
      distribute
    end

    it "replaces the distribution's own rows" do
      expect(distributed_before).not_to be_empty
      expect(Allocation.distributed.pluck(:id)).not_to include(*distributed_before)
      expect(Allocation.distributed).to be_any
    end

    it "leaves the hand move untouched" do
      expect(Allocation.where(id: transfer.id)).to exist
      expect(transfer.reload).to be_kind_transfer
      expect(purpose_total).to eq(3_000)
    end
  end

  # NOTHING IS WRITTEN AND THE SCREEN SAYS WHY. Three refusals, each reaching the server by a
  # different route, and each paired against the move that does succeed above.
  #
  # THE PAGE ASSERTION COMES FIRST IN EVERY ONE OF THEM, and that ordering is the whole of their
  # reliability. `click_on` returns as soon as the click is dispatched, so reading the database
  # straight after it can measure the ledger before the request has landed and pass on a move that
  # was about to be written. A Capybara predicate blocks until the response is on screen; only then
  # is the ledger a settled thing to read.
  describe "refusals", :aggregate_failures do
    it "refuses a blank amount and writes nothing" do
      visit new_allocation_path(to_category_id: dentist.id, from_category_id: car.id)
      click_on "Move the money"

      expect(page).to have_css("#reallocation-errors", text: "Nothing moved")
      expect(page).to have_content("Amount can't be blank")
      expect(Allocation.where(to_category: dentist)).not_to exist
    end

    # The browser's own refusal of a zero, before anything is submitted: a zero move is not an event
    # and the box says so rather than the server having to. `have_current_path` is the synchronising
    # half here — there is no response to wait for, so what has to be shown is that no request was
    # made at all.
    it "refuses a zero amount in the box" do
      visit new_allocation_path(to_category_id: dentist.id, from_category_id: car.id)
      fill_in "How much", with: "0"
      click_on "Move the money"

      expect(page).to have_css("input#move-amount:invalid")
      expect(page).to have_current_path(%r{/allocations/new})
      expect(Allocation.where(to_category: dentist)).not_to exist
    end

    # A MISSING SIDE IS NOT THE ROOT, and both ends are asserted because the leak is symmetrical.
    # `nil` and `ROOT` are the same NULL column, so a POST naming one end and leaving the other blank
    # wrote a well-formed move the user never asked for — MEASURED: a source and no destination saved
    # `Cushion → available` for $300 and reported it as a success. AVAILABLE is nameable, by the
    # explicit `"available"` string the select and the radios both submit, and the example above
    # ("moving money back to available") is the paired positive that keeps this from reading as a
    # refusal of the root itself.
    it "refuses a move with no destination and writes nothing" do
      visit new_allocation_path(from_category_id: car.id, amount: 300)
      click_on "Move the money"

      expect(page).to have_css("#reallocation-errors", text: "Nothing moved")
      expect(page).to have_content("Envelope can't be blank")
      expect(Allocation.where(from_category: car)).not_to exist
      expect(holding_of("Car")).to eq(1_000)
    end

    it "refuses a move with no source and writes nothing" do
      visit new_allocation_path(to_category_id: dentist.id, amount: 300)
      click_on "Move the money"

      expect(page).to have_css("#reallocation-errors", text: "Nothing moved")
      expect(page).to have_content("Source can't be blank")
      expect(Allocation.where(to_category: dentist)).not_to exist
      expect(available).to eq(810)
    end

    # THE AFFORDABILITY FLOOR AT THE WRITE, which without `Allocation#source_must_hold_it` would live
    # only in the view. A disabled radio is a rendering: a tab opened while Gas held more, or a
    # hand-edited `from_category_id`, would have written the move and left Gas overspent by $260.
    # Both directions in one session: the same screen, the same amount, one source refused and one
    # taken.
    it "refuses a source that does not hold the amount, and takes one that does" do
      visit new_allocation_path(to_category_id: dentist.id, from_category_id: car.id, amount: 300)
      submit_with_source(category("Gas"))
      expect(page).to have_content("Amount is more than Gas holds — it has $40.00")
      expect(holding_of("Gas")).to eq(40)

      find_by_id("from-#{car.id}").click
      click_on "Move the money"
      expect(page).to have_content("Moved $300.00 from Car to Dentist")
      expect(holding_of("Car")).to eq(700)
    end
  end

  # ** ALLOCATING INTO A CATEGORY STARTS IT HOLDING (§4, final fix wave I-1). ** The spec's own
  # sentence is "the date it first got a rule OR AN ALLOCATION", and only the rule path
  # (`BudgetProposal`) ever wrote the date. This screen's destination select is built from HOLDERS, so
  # the gap was not reachable by clicking — but `AllocationsController#party_from` resolves against
  # `current_user.categories`, not against holders, so a crafted POST wrote money INTO a category with
  # a NULL `funded_since`: money every reader in the app calls absent, in a category no picker offers
  # to move it back out of.
  #
  # REACHED THE ONLY WAY IT CAN BE — the real form with the destination option appended and selected,
  # which is the same door `submit_with_destination` opens for a stranger's category below. What
  # separates the two is ownership: this one IS the user's, so it is stamped and taken rather than
  # refused.
  describe "moving money into a category that is not holding yet", :aggregate_failures do
    let!(:misc) { create(:category, :expense, user: user, name: "Misc", priority: 8) }

    before do
      visit new_allocation_path(to_category_id: dentist.id, from_category_id: car.id, amount: 300)
      submit_with_destination(misc)
      await("Moved $300.00")
    end

    it "stamps the funding start and reports the money as held" do
      expect(page).to have_content("Moved $300.00 from Car to Misc. Car $700.00 · Misc $300.00")
      expect(misc.reload.funded_since).to eq(Date.current)
      expect(misc).to be_holder
      expect(holding_of("Misc")).to eq(300)
    end

    # THE MONEY IS REACHABLE AGAIN, which is the whole point of the stamp rather than a second
    # consequence of it: a holder is in `Category.in_fill_order` and in every population the
    # reallocation screen builds its radios from, so the $300 has a door back out.
    it "puts the category in the fill order and on the screen that moves money out", :aggregate_failures do
      expect(user.categories.in_fill_order).to include(misc)

      visit new_allocation_path(to_category_id: dentist.id)
      expect(page).to have_css("#from-#{misc.id}")
    end

    # §2 IS UNMOVED. A hand move cannot change the partition, and stamping a date does not either —
    # it changes which side of it the money is counted on, and there was no spending here to move.
    it "leaves the partition exactly where it was" do
      expect(page).to have_css("h1", text: "Home")
      expect(purpose_total).to eq(3_000)
    end
  end

  # THE OTHER DIRECTION: a destination that is ALREADY holding keeps its own start date. Re-stamping
  # to today would push the date forward and hand the category's own recent spending back to
  # available, which is the failure `Category#start_holding`'s no-op arm exists to prevent — and this
  # is the ordinary path, taken by every move the screen itself offers.
  describe "moving money into a category that is already holding", :aggregate_failures do
    it "leaves the funding start exactly where it was" do
      started_on = dentist.funded_since
      visit new_allocation_path(to_category_id: dentist.id, from_category_id: car.id, amount: 300)
      click_on "Move the money"

      expect(page).to have_content("Moved $300.00 from Car to Dentist")
      expect(started_on).to be < Date.current
      expect(dentist.reload.funded_since).to eq(started_on)
    end
  end

  # A stranger's category can be neither end. Both ends, both verbs, and each paired with the request
  # that does work.
  describe "another user's categories", :aggregate_failures do
    let(:stranger_category) { create(:category, :expense, :funded, name: "Someone Else's") }

    it "does not open on one as the destination" do
      visit new_allocation_path(to_category_id: stranger_category.id)
      expect(page).to have_content("We couldn't find that envelope")
      expect(page).to have_no_content("Where it comes from")
      visit new_allocation_path(to_category_id: dentist.id)
      expect(page).to have_content("Where it comes from")
    end

    # THE FOURTH CORNER of a 2x2 the other three examples cover between them: a stranger's category
    # as the DESTINATION of a POST. `require_own_categories` guards both keys on both verbs through
    # ONE lookup, and an unasserted corner is how a guard comes to be written for one key only.
    it "does not move money into one" do
      visit new_allocation_path(to_category_id: dentist.id, from_category_id: car.id, amount: 300)
      submit_with_destination(stranger_category)

      expect(page).to have_content("We couldn't find that envelope")
      expect(Allocation.where(to_category: stranger_category)).not_to exist
      expect(holding_of("Car")).to eq(1_000)
    end

    # Page first, ledger second — see the refusals block for why every one of these is ordered that
    # way.
    it "does not move money out of one" do
      visit new_allocation_path(to_category_id: dentist.id, from_category_id: car.id, amount: 300)
      submit_with_source(stranger_category)

      expect(page).to have_content("We couldn't find that envelope")
      expect(Allocation.where(to_category: dentist)).not_to exist
      expect(holding_of("Dentist")).to eq(0)
    end
  end
end
