# frozen_string_literal: true

require "rails_helper"

# Task 7, the damage statement: what a move costs the source, and what it buys the destination —
# stated before a cent has moved (spec §5).
#
# Every per-period figure below is a REAL RECOMPUTATION of PoolCalculator#required with the balance
# this move would leave, never the amount divided by something. The two are only equal when one
# period remains, and on this plan the subtraction printed `$206.43` where the truth was `$194.17`.
RSpec.describe "Pool Movements New Damage", type: :system do
  include_context "with a Checking account to reallocate in"

  describe "moving $300 into Dentist", :aggregate_failures do
    before { visit new_pool_movement_path(to_pool_id: dentist.id, amount: 300) }

    # SPEC §5'S OWN LINE, rebuilt: `Car $1,340 → $1,122 — Maintenance slips to $494/$800`. The
    # per-period figure is $100 of shortfall over the 5 period boundaries between today and the due
    # date — NOT $300 divided by anything, which is what makes $20.00 rather than $60.00 right.
    it "names the rule that slips and what the envelope will ask for" do
      within("[data-damage='Car']") do
        expect(page).to have_content("$1,000.00 → $700.00")
        expect(page).to have_content("its Maintenance rule slips to $700.00 of $800.00")
        expect(page).to have_content("asks $20.00 a period instead of $0.00")
      end
    end

    # THE OPPOSITE DIRECTION, on the same screen. A savings goal with no rules holds nothing back,
    # so the move takes only free money: nothing slips and nothing asks for more, and the line
    # says so by not saying it (spec §5: state the consequence only when there is one).
    it "says nothing about a rule or a period when neither moves" do
      within("[data-damage='Cushion']") do
        expect(page).to have_content("$500.00 → $200.00")
        expect(page).to have_no_content("slips to")
        expect(page).to have_no_content("a period instead of")
      end
    end

    # The red case, in the state the app already has for it rather than a new one. Taking $300 of
    # Insurance's $400 leaves $300 owed on a bill with no period boundary left before it is due.
    it "says when the move leaves the source unable to make its date" do
      within("[data-damage='Insurance']") do
        expect(page).to have_content("its Premium rule slips to $100.00 of $400.00")
        expect(page).to have_content("becomes won't make it")
      end
    end

    # THE AMBER MIDDLE STATE — the branch this task's correction created, and the one the view's
    # own comment calls the whole point of the screen: a move inside `free_amount` costs nothing
    # and is stated in grey, a move that reaches PAST it into money a rule was holding is amber,
    # and one that pushes the envelope into a new state is red. Three colours, mutually exclusive.
    #
    # `Candidate#promised?` was asserted in NEITHER direction until this example: mutating it to a
    # bare `false` passed all twenty-five. The two negatives below are what make it bite — without
    # them a version that painted everything grey, or everything amber, would still pass.
    it "colours a move by whether it takes money a rule was holding" do
      expect(page).to have_css("[data-damage='Cushion'].text-gray-500")
      expect(page).to have_css("[data-damage='Car'].text-status-warning")
      expect(page).to have_css("[data-damage='Insurance'].text-status-danger")
      expect(page).to have_no_css("[data-damage='Car'].text-gray-500")
      expect(page).to have_no_css("[data-damage='Cushion'].text-status-warning")
    end

    # WHAT THE COST BUYS, and the destination's own row vocabulary on both sides of the move.
    it "states what the destination gains" do
      within("#reallocation-gain") do
        expect(page).to have_content("Dentist $0.00 → $300.00")
        expect(page).to have_content("won't make it")
        expect(page).to have_content("becomes $300.00 · on track")
      end
    end
  end

  # WHY `net_of_sweep:` IS ON BOTH RECOMPUTATIONS. Coffee's rate period closed a fortnight ago, so
  # the next distribution takes its whole leftover back and tops the envelope up to its full rate
  # either way — taking $100 out of it costs NOTHING per period. Read through a plain calculator the
  # row would say "asks $50.00 a period instead of $0.00", a cost the very next distribution erases.
  # The rule's allocation still slips, and that is true and worth saying.
  describe "moving $100 out of an envelope whose period has closed", :aggregate_failures do
    before { visit new_pool_movement_path(to_pool_id: dentist.id, amount: 100) }

    it "says nothing about a period when the leftover was going to be swept anyway" do
      within("[data-source='Coffee']") { expect(page).to have_content("$150.00 left · last period") }
      within("[data-damage='Coffee']") do
        expect(page).to have_content("$150.00 → $50.00")
        expect(page).to have_content("its Per period rule slips to $50.00 of $100.00")
        expect(page).to have_no_content("a period instead of")
      end
    end
  end
end
