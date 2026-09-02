# frozen_string_literal: true

require "rails_helper"

# The source list: which parties the money can come from, and what a row that cannot make the move
# says instead (spec §5).
#
# THE PORT OF `spec/system/account_movements/new/sources_spec.rb`. One assertion could not come across —
# "an envelope in a second account is not offered" — because nothing crosses anything on the purpose
# ledger (two-ledger spec §2). Its place is taken by AVAILABLE, which is offered and is the one
# source that is not a category at all.
#
# `Capybara.exact` is unset, so `have_content("$300.00")` also matches "$1,300.00" and matches the
# sidebar. Every figure below is scoped to the row that owns it.
RSpec.describe "Allocations New Sources", type: :system do
  include_context "with categories to reallocate between"

  # THE STATE BEFORE ANY AMOUNT IS TYPED. Without it every assertion in these files would also pass
  # on a screen that had already moved the money, or that had quietly dropped half its rows.
  describe "before an amount is entered", :aggregate_failures do
    before { visit new_allocation_path(to_category_id: dentist.id) }

    # EVERY HOLDER AND THE ROOT, and the destination is not among them: it is the other end of the
    # move. Both directions on one screen, so this cannot pass on a list that simply failed to
    # render.
    it "offers every holder category and the root, and not the destination" do
      expect(page).to have_css("[data-source='Available']")
      expect(page).to have_css("[data-source='Car']")
      expect(page).to have_css("[data-source='Cushion']")
      expect(page).to have_no_css("[data-source='Dentist']")
    end

    # AVAILABLE HAS NO STATUS AND NO RULES, which is what makes it the root rather than a category:
    # its whole holding is free, and there is no row vocabulary to print beside it.
    it "offers the root with everything in it free and no status of its own" do
      within("[data-source-reason='Available']") do
        expect(page).to have_content("$810.00 in it · $810.00 of it free")
      end
    end

    # Nothing to state yet, and both halves matter: the sources are on screen, so the absence of the
    # two sentences is a decision rather than an empty page.
    it "states no damage and no gain until there is a move to describe" do
      expect(page).to have_no_css("#reallocation-gain")
      expect(page).to have_no_css("[data-damage]")
      expect(page).to have_css("[data-source]", minimum: 5)
    end

    # MONEY BY TYPE ON THE SHARPEST SHAPE. Dentist has no allocation and no entry at all, so every
    # one of HoldingCalculator#balance's terms is over an empty set and returns the Integer literal 0
    # — the exact shape this branch has leaked Integer-for-BigDecimal from repeatedly. `eq(0)` cannot
    # tell them apart, so it is asserted by type, on the emptiest category on the screen.
    #
    # The screen assertion is not decoration: it anchors the ledger reading to the page the example
    # claims to be about, and without it this is the shape that wedges the driver (see the shared
    # context).
    it "reports an empty category's holding as BigDecimal rather than Integer" do
      expect(page).to have_select("Envelope", selected: "Dentist")
      expect(holding_of("Dentist")).to eq(0)
      expect(holding_of("Dentist")).to be_a(BigDecimal)
    end
  end

  # "SHOWN BUT DISABLED, WITH THE REASON". Both directions on one screen, and the enabled half is
  # what makes the disabled half mean something: a row that had simply vanished would satisfy every
  # negative assertion here.
  describe "a source that cannot make the move", :aggregate_failures do
    before { visit new_allocation_path(to_category_id: dentist.id, amount: 300) }

    it "disables it and says how little is in it" do
      expect(page).to have_css("[data-source='Gas'] input[type=radio][disabled]")
      within("[data-source-reason='Gas']") do
        expect(page).to have_content("Can't make this move — only $40.00 in it")
      end
    end

    # The other reason, which is a different sentence because it sends the user somewhere else: the
    # category is thin because a dated bill is already holding what is in it.
    it "names the bill that is holding the money" do
      within("[data-source-reason='Rent']") do
        expect(page).to have_content("only $100.00 in it")
        expect(page).to have_content("its Rent Bill rule is due")
        expect(page).to have_content("is holding $100.00")
      end
    end

    # The paired positive: a source that CAN make the move is enabled, states what it holds and what
    # of that is free, and carries no refusal.
    it "leaves an affordable source enabled and says what it holds" do
      expect(page).to have_css("[data-source='Car'] input[type=radio]:not([disabled])")
      within("[data-source-reason='Car']") do
        expect(page).to have_content("$1,000.00 in it · $200.00 of it free")
        expect(page).to have_no_content("Can't make this move")
      end
    end
  end
end
