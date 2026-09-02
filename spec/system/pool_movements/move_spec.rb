# frozen_string_literal: true

require "rails_helper"

# Task 7, THE WRITE: moving money between two envelopes when life happens — one movement, from, to,
# amount, inside one account.
#
# THE INVARIANT IS `Σ pools == your bank balance`, and a reallocation cannot change it: the money
# stays in the account, so the bank holds exactly what it held. Every total below is pinned against
# the LITERAL $3,000 deposit the fixture planted rather than against a sum of the app's own parts —
# `Pool#total` IS that sum, so summing the parts against it is `x == x` and passes after any write
# whatsoever.
#
# `Capybara.exact` is unset, so `have_content("$300.00")` also matches "$1,300.00" and matches the
# sidebar. Every figure below is scoped to the row or the sentence that owns it.
RSpec.describe "Pool Movements Move", type: :system do
  include_context "with a Checking account to reallocate in"

  describe "moving the money", :aggregate_failures do
    before do
      visit new_pool_movement_path(to_pool_id: dentist.id, from_pool_id: car.id, amount: 300)
      click_on "Move the money"
      await("Moved $300.00")
    end

    it "lands on Home and says what it did, from the ledger" do
      expect(page).to have_content("Moved $300.00 from Car to Dentist. Car $700.00 · Dentist $300.00")
      expect(page).to have_css("h1", text: "Home")
    end

    # ONE ROW, AND A `transfer` — the column default, which is exactly what keeps it out of
    # `PoolMovement.distributed`.
    it "writes one transfer and nothing a distribution owns" do
      moved = PoolMovement.where(from_pool: car, to_pool: dentist)
      expect(moved.count).to eq(1)
      expect(moved.first).to be_kind_transfer
      expect(moved.first.amount).to eq(300)
      expect(PoolMovement.distributed.count).to eq(0)
    end

    # The two balances move by exactly the amount, in opposite directions, and the bank does not
    # move at all — pinned against the fixture's own $3,000 deposit.
    it "moves the money between the two pools and creates none" do
      expect(balance_of("Car")).to eq(700)
      expect(balance_of("Dentist")).to eq(300)
      expect(balance_of("Checking")).to eq(810)
      expect(bank_balance).to eq(3_000)
    end

    # THE PREVIEW WAS TRUE. The left side was computed before the write through PoolCalculator's
    # `pending:`; the right side is read out of the database afterwards. Two independent routes to
    # the same figures, which is the whole point of building the damage statement out of the same
    # readers the ledger will produce.
    it "leaves the envelopes exactly where the screen said it would" do
      expect(balance_of("Car")).to eq(700)
      within("[data-pool-name='Car']") { expect(page).to have_content("$700.00") }
      within("[data-pool-name='Dentist']") { expect(page).to have_content("$300.00") }
    end

    # AMENDMENT G, ASSERTED BY TYPE. Money is BigDecimal from a `money` column and `eq(300)` passes
    # for the Integer just as happily, so no figure above can tell the two apart.
    #
    # The post-write side is the WEAKER half and is named as such: every pool here now has a
    # movement whose amount comes back from Postgres as a BigDecimal, so these read as BigDecimal
    # almost by construction. `bank_balance` is the one that earns its place — `Pool#total` runs a
    # second, Ruby-side sum over the account's children, which is its own chance to leak. The
    # genuinely empty shape is asserted on Dentist in new/sources_spec.rb, before money reaches it.
    #
    # The screen assertion anchors the ledger reading to the page it is about, and it is also what
    # keeps this body from touching Capybara not at all — the shape that wedged the driver in
    # new/sources_spec.rb (see spec/support/reallocation_context.rb). Safe here only by accident:
    # this describe's `before` ends in an `await`, which settles the page where a bare `visit` does
    # not.
    it "reports money as BigDecimal rather than Integer" do
      expect(page).to have_css("h1", text: "Home")
      expect(balance_of("Car")).to be_a(BigDecimal)
      expect(bank_balance).to be_a(BigDecimal)
      expect(PoolMovement.where(from_pool: car, to_pool: dentist).sole.amount).to be_a(BigDecimal)
    end
  end

  # ── "SURVIVING A REDISTRIBUTION" MOVED TO `spec/system/allocations/move_spec.rb` (two-ledger
  # Task 4). Amendment A is about a hand move outliving the replacement of a period's split, and a
  # distribution writes `allocations` now — so the two examples that lived here compared a
  # `pool_movements` transfer against a replacement that cannot see its table at all, which is a
  # true statement about nothing. The claim is asserted at full strength on the purpose ledger,
  # where both rows are the same kind of row again.

  # NOTHING IS WRITTEN AND THE SCREEN SAYS WHY. Four refusals, each reaching the server by a
  # different route, and each paired against the move that does succeed above.
  #
  # THE PAGE ASSERTION COMES FIRST IN EVERY ONE OF THEM, and that ordering is the whole of their
  # reliability. `click_on` returns as soon as the click is dispatched, so reading the database
  # straight after it — which `expect { click }.not_to change(PoolMovement, :count)` does — can
  # measure the ledger before the request has landed and pass on a move that was about to be
  # written. A Capybara predicate blocks until the response is on screen; only then is the ledger
  # a settled thing to read.
  describe "refusals", :aggregate_failures do
    it "refuses a blank amount and writes nothing" do
      visit new_pool_movement_path(to_pool_id: dentist.id, from_pool_id: car.id)
      click_on "Move the money"

      expect(page).to have_css("#reallocation-errors", text: "Nothing moved")
      expect(page).to have_content("Amount can't be blank")
      expect(PoolMovement.where(to_pool: dentist)).not_to exist
    end

    # The browser's own refusal of a zero, before anything is submitted: a zero move is not an
    # event (amendment E) and the box says so rather than the server having to. `have_current_path`
    # is the synchronising half here — there is no response to wait for, so what has to be shown is
    # that no request was made at all.
    it "refuses a zero amount in the box" do
      visit new_pool_movement_path(to_pool_id: dentist.id, from_pool_id: car.id)
      fill_in "How much", with: "0"
      click_on "Move the money"

      expect(page).to have_css("input#move-amount:invalid")
      expect(page).to have_current_path(%r{/pool_movements/new})
      expect(PoolMovement.where(to_pool: dentist)).not_to exist
    end

    # SPEC §5 AT THE WRITE. The source list never offers Holiday, so this reaches `create` the only
    # way it can — a hand-edited field — and is refused by PoolMovement's own #crosses_accounts?.
    it "refuses a source in another account" do
      visit new_pool_movement_path(to_pool_id: dentist.id, from_pool_id: car.id, amount: 300)
      submit_with_source(pool("Holiday"))

      expect(page).to have_content("must be in the same account")
      expect(PoolMovement.where(to_pool: dentist)).not_to exist
      expect(balance_of("Dentist")).to eq(0)
    end

    # THE AFFORDABILITY FLOOR AT THE WRITE, which until this round lived only in the view. A
    # disabled radio is a rendering: a tab opened while Gas held more, or a hand-edited
    # `from_pool_id`, would have written the move and left Gas overdrawn by $260 — measured, by
    # deleting the validation and watching the flash read "Gas -$260.00". Both directions in one
    # session: the same screen, the same amount, one source refused and one taken.
    it "refuses a source that does not hold the amount, and takes one that does" do
      visit new_pool_movement_path(to_pool_id: dentist.id, from_pool_id: car.id, amount: 300)
      submit_with_source(pool("Gas"))
      expect(page).to have_content("Amount is more than Gas holds — it has $40.00")
      expect(balance_of("Gas")).to eq(40)

      find_by_id("from-#{car.id}").click
      click_on "Move the money"
      expect(page).to have_content("Moved $300.00 from Car to Dentist")
      expect(balance_of("Car")).to eq(700)
    end
  end

  # AMENDMENT B: a stranger's pool can be neither end. Both ends, both verbs, and each paired with
  # the request that does work.
  describe "another user's pools", :aggregate_failures do
    let(:stranger_pool) { create(:pool, :budget_pool, name: "Someone Else's") }

    it "does not open on one as the destination" do
      visit new_pool_movement_path(to_pool_id: stranger_pool.id)
      expect(page).to have_content("We couldn't find that envelope")
      expect(page).to have_no_content("Where it comes from")
      visit new_pool_movement_path(to_pool_id: dentist.id)
      expect(page).to have_content("Where it comes from")
    end

    # Page first, ledger second — see the refusals block for why every one of these is ordered
    # that way.
    it "does not move money out of one" do
      visit new_pool_movement_path(to_pool_id: dentist.id, from_pool_id: car.id, amount: 300)
      submit_with_source(stranger_pool)

      expect(page).to have_content("We couldn't find that envelope")
      expect(PoolMovement.where(to_pool: dentist)).not_to exist
      expect(balance_of("Dentist")).to eq(0)
    end
  end
end
