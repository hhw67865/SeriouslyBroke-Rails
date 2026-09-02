# frozen_string_literal: true

require "rails_helper"

# `GET /entries/impact` — the §6 card's fragment, and THE ONE THING BETWEEN IT AND A CROSS-USER READ.
#
# The endpoint takes two ids off the query string and prints a CATEGORY'S HOLDING from them. Both are
# scoped through `current_user`, and that scoping is asserted here rather than in the system suite
# because a browser can only ever send ids the page put in front of it — the request layer is where
# a stranger's id is actually reachable, and where a dropped scope looks exactly like a missing
# record.
#
# EVERY FIGURE IS A PLANTED LITERAL and each scope is pinned in BOTH directions: the owner's id
# beside the stranger's, on the same request shape, so an example cannot pass by finding nothing.
RSpec.describe "Entry impact", type: :request do
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }
  # NO ACCOUNT LET (Task 6): nothing on this endpoint reads one. Income is what needs a main account
  # and this fixture writes none; the `:category` factory mints one of its own for the lane column
  # that Task 8 drops.
  let(:groceries) do
    create(:category, :expense, user: user, name: "Groceries", funded_since: 30.days.ago.to_date)
  end

  # $240 allocated in, $300 a period claimed. The funding is an `Allocation` — money moving out of
  # AVAILABLE and into the category (two-ledger spec §2) — where it used to be a movement into an
  # envelope sitting inside Checking.
  before do
    create(:allocation, kind: :allocation, to_category: groceries, amount: 240, date: Time.zone.now)
    create(:budget, :per_period_rate, category: groceries, amount: 300)
    sign_in user, scope: :user
  end

  describe "the category id" do
    it "prints the owner's category", :aggregate_failures do
      get impact_entries_path(category_id: groceries.id, amount: "55")

      expect(response.body).to include("Groceries envelope")
      expect(response.body).to include("$240.00")
      expect(response.body).to include("$185.00")
    end

    # A STRANGER'S CATEGORY IS NOT A 404 AND NOT A CARD: `find_by` answers nil, the presenter has no
    # category, and the fragment is empty — the same answer the cleared select gets.
    it "prints nothing at all for a category belonging to somebody else", :aggregate_failures do
      other = create(:user)
      other_category = create(:category, :expense, :funded, user: other, name: "Their Groceries")
      create(:allocation, kind: :allocation, to_category: other_category, amount: 9_999, date: Time.zone.now)

      get impact_entries_path(category_id: other_category.id, amount: "55")

      expect(response).to have_http_status(:ok)
      expect(response.body.strip).to be_empty
      expect(response.body).not_to include("Their Groceries")
      expect(response.body).not_to include("9,999")
    end
  end

  describe "the entry id" do
    # $45 already logged, so the ledger holds $195 and the card must hold $240 — see
    # EntryImpactPresenter#own_contribution.
    let!(:existing) do
      create(:entry, item: create(:item, category: groceries), amount: 45, date: Date.current)
    end

    it "excludes the owner's own entry from the holding it prints", :aggregate_failures do
      get impact_entries_path(category_id: groceries.id, amount: "45", entry_id: existing.id)

      expect(groceries.holding_calculator.balance).to eq(BigDecimal("195"))
      expect(response.body).to include("$240.00")
      expect(response.body).to include("$195.00")
    end

    # A STRANGER'S ENTRY ID EXCLUDES NOTHING. The card is still rendered — the category is the
    # user's — and it must read exactly as it does with no entry id at all, which is the create
    # case's $195 → $150 and never the edit case's $240.
    #
    # WHAT THIS EXAMPLE DOES AND DOES NOT PIN, and the measurement survives the conversion with the
    # reader renamed. Unscoping BOTH ids in the controller (`Category.find_by` / `Entry.find_by`)
    # fails the category example above and leaves this one GREEN, because `#own_contribution` gates
    # on the entry's own `item.category_id` matching the category the card is describing, and a
    # stranger's entry names a stranger's category. The `entry_id` scope is therefore defence in
    # depth rather than the thing that stops a leak. Recorded here so nobody reads this example as
    # proof of the scope; it pins the user-visible contract, which is that a foreign entry id moves
    # no figure.
    it "excludes nothing for an entry belonging to somebody else", :aggregate_failures do
      other = create(:user)
      theirs = create(:entry, item: create(:item, :expense, category: create(:category, user: other)), amount: 45)

      get impact_entries_path(category_id: groceries.id, amount: "45", entry_id: theirs.id)

      expect(response.body).to include("$195.00")
      expect(response.body).to include("$150.00")
      expect(response.body).not_to include("$240.00")
    end
  end

  # THE CARD ANSWERS THE SAME QUESTION THE LEDGER DOES, ON THE SAME DATE (§4's re-anchored
  # start-date rule).
  #
  # This is the divergence the start-date rule opened and the one the card cannot survive: the
  # ledger sends an entry dated before its category's `funded_since` to AVAILABLE, while a card that
  # asked only "is this a holder" would name the category, print its holding, and offer a "left"
  # figure for money that was never going to come out of it. `EntryImpactPresenter#holding` asks
  # `Category#counts_spending_on?` — the app's one Ruby mirror of `CategoryLedger::ENTRY_CATEGORY_ID`
  # — with the day the ENTRY is about.
  #
  # ASSERTED THROUGH THE FRAGMENT rather than on the presenter, because the whole failure is that
  # the two halves of the screen disagree, and only a rendered card shows which one the user reads.
  # `data-impact-card` is the partial's own switch: "unbudgeted" is the honest card, "envelope" is
  # the figures card. Both directions on one fixture — the SAME category, one entry either side of
  # the funding date — so an example cannot pass by a card that never renders figures at all.
  describe "the start-date rule" do
    before { groceries.update!(funded_since: Date.current) }

    it "shows the honest card for an entry that predates the funding date", :aggregate_failures do
      old = create(:entry, item: create(:item, category: groceries), amount: 45, date: 30.days.ago)

      get impact_entries_path(category_id: groceries.id, amount: "10", entry_id: old.id)

      expect(response.body).to include('data-impact-card="unbudgeted"')
      expect(response.body).to include("Not holding money yet")
      expect(response.body).not_to include("Groceries envelope")
    end

    it "still shows the figures for an entry on the funding date itself", :aggregate_failures do
      today = create(:entry, item: create(:item, category: groceries), amount: 45, date: Date.current)

      get impact_entries_path(category_id: groceries.id, amount: "10", entry_id: today.id)

      expect(response.body).to include('data-impact-card="envelope"')
      expect(response.body).to include("Groceries envelope")
      expect(response.body).not_to include("Not holding money yet")
    end
  end
end
