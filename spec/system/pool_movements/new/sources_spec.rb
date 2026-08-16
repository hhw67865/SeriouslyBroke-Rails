# frozen_string_literal: true

require "rails_helper"

# Task 7, the source list: which pools the money can come from, and what a row that cannot make
# the move says instead (spec §5, amendment D).
#
# `Capybara.exact` is unset, so `have_content("$300.00")` also matches "$1,300.00" and matches the
# sidebar. Every figure below is scoped to the row that owns it.
RSpec.describe "Pool Movements New Sources", type: :system do
  include_context "with a Checking account to reallocate in"

  # THE STATE BEFORE ANY AMOUNT IS TYPED. Without it every assertion in these files would also pass
  # on a screen that had already moved the money, or that had quietly dropped half its rows.
  describe "before an amount is entered", :aggregate_failures do
    before { visit new_pool_movement_path(to_pool_id: dentist.id) }

    # SAME-ACCOUNT ONLY (spec §5), asserted in both directions on one screen: Checking's own
    # envelopes are offered, and an envelope in a second account is not — which is not the same as
    # a screen that simply failed to render its list.
    it "offers this account's pools and no others" do
      expect(page).to have_css("[data-source='Car']")
      expect(page).to have_css("[data-source='Checking']")
      expect(page).to have_css("[data-source='Cushion']")
      expect(page).to have_no_css("[data-source='Holiday']")
      expect(page).to have_no_css("[data-source='Dentist']")
    end

    # Nothing to state yet, and both halves matter: the sources are on screen, so the absence of
    # the two sentences is a decision rather than an empty page.
    it "states no damage and no gain until there is a move to describe" do
      expect(page).to have_no_css("#reallocation-gain")
      expect(page).to have_no_css("[data-damage]")
      expect(page).to have_css("[data-source]", minimum: 5)
    end

    # AMENDMENT G ON THE SHARP SHAPE. Dentist has no movement and no entry at all, so every one of
    # PoolCalculator#balance's five `sum(:amount)` terms is over an empty set and returns the
    # Integer literal 0 — the exact shape this branch has leaked Integer-for-BigDecimal from six
    # times. `eq(0)` cannot tell them apart, so it is asserted by type, on the emptiest pool on the
    # screen and beside the figure it is supposed to be.
    #
    # The screen assertion is not decoration: it anchors the ledger reading to the page the example
    # claims to be about, and without it this was the only body in these four files that touched
    # Capybara not at all. That shape reliably wedged the driver here — `spec/support/capybara.rb`
    # quits it after every example, and a body that finishes before the `before` block's `visit`
    # has settled leaves the quit racing it. Four of the six examples in this file failed on every
    # run with `InvalidSessionIdError` and zero assertion failures; adding this line fixed it.
    it "reports an empty envelope's balance as BigDecimal rather than Integer" do
      expect(page).to have_select("Envelope", selected: "Dentist")
      expect(balance_of("Dentist")).to eq(0)
      expect(balance_of("Dentist")).to be_a(BigDecimal)
    end
  end

  # "SHOWN BUT DISABLED, WITH THE REASON" (amendment D). Both directions on one screen, and the
  # enabled half is what makes the disabled half mean something: a row that had simply vanished
  # would satisfy every negative assertion here.
  describe "a source that cannot make the move", :aggregate_failures do
    before { visit new_pool_movement_path(to_pool_id: dentist.id, amount: 300) }

    it "disables it and says how little is in it" do
      expect(page).to have_css("[data-source='Gas'] input[type=radio][disabled]")
      within("[data-source-reason='Gas']") do
        expect(page).to have_content("Can't make this move — only $40.00 in it")
      end
    end

    # The other reason, which is a different sentence because it sends the user somewhere else:
    # the envelope is thin because a dated bill is already holding what is in it.
    it "names the bill that is holding the money" do
      within("[data-source-reason='Rent']") do
        expect(page).to have_content("only $100.00 in it")
        expect(page).to have_content("its Rent Bill rule is due")
        expect(page).to have_content("is holding $100.00")
      end
    end

    # The paired positive: a source that CAN make the move is enabled, states what it holds and
    # what of that is free, and carries no refusal.
    it "leaves an affordable source enabled and says what it holds" do
      expect(page).to have_css("[data-source='Car'] input[type=radio]:not([disabled])")
      within("[data-source-reason='Car']") do
        expect(page).to have_content("$1,000.00 in it · $200.00 of it free")
        expect(page).to have_no_content("Can't make this move")
      end
    end
  end
end
