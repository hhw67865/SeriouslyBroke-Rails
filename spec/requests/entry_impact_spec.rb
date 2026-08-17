# frozen_string_literal: true

require "rails_helper"

# `GET /entries/impact` — the §6 card's fragment, and THE ONE THING BETWEEN IT AND A CROSS-USER READ.
#
# The endpoint takes two ids off the query string and prints a POOL BALANCE from them. Both are
# scoped through `current_user`, and that scoping is asserted here rather than in the system suite
# because a browser can only ever send ids the page put in front of it — the request layer is where
# a stranger's id is actually reachable, and where a dropped scope looks exactly like a missing
# record.
#
# EVERY FIGURE IS A PLANTED LITERAL and each scope is pinned in BOTH directions: the owner's id
# beside the stranger's, on the same request shape, so an example cannot pass by finding nothing.
RSpec.describe "Entry impact", type: :request do
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.current) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:groceries_pool) { create(:pool, :budget_pool, user: user, account: checking, name: "Groceries") }
  let(:groceries) { create(:category, user: user, name: "Groceries", category_type: :expense, pool: groceries_pool) }

  # $240 funded, $300 a period claimed.
  before do
    create(:pool_movement, from_pool: checking, to_pool: groceries_pool, amount: 240, date: Time.zone.now)
    create(:pool_budget, :per_period_rate, pool: groceries_pool, amount: 300)
    sign_in user, scope: :user
  end

  describe "the category id" do
    it "prints the owner's envelope", :aggregate_failures do
      get impact_entries_path(category_id: groceries.id, amount: "55")

      expect(response.body).to include("Groceries envelope")
      expect(response.body).to include("$240.00")
      expect(response.body).to include("$185.00")
    end

    # A STRANGER'S CATEGORY IS NOT A 404 AND NOT A CARD: `find_by` answers nil, the presenter has no
    # category, and the fragment is empty — the same answer the cleared select gets.
    it "prints nothing at all for a category belonging to somebody else", :aggregate_failures do
      other = create(:user)
      other_pool = create(:pool, :budget_pool, user: other, name: "Their Groceries")
      other_category = create(:category, user: other, name: "Their Groceries", category_type: :expense, pool: other_pool)
      create(:pool_movement, from_pool: other_pool.account, to_pool: other_pool, amount: 9_999, date: Time.zone.now)

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

    it "excludes the owner's own entry from the balance it prints", :aggregate_failures do
      get impact_entries_path(category_id: groceries.id, amount: "45", entry_id: existing.id)

      expect(groceries_pool.calculator.balance).to eq(BigDecimal("195"))
      expect(response.body).to include("$240.00")
      expect(response.body).to include("$195.00")
    end

    # A STRANGER'S ENTRY ID EXCLUDES NOTHING. The card is still rendered — the category is the
    # user's — and it must read exactly as it does with no entry id at all, which is the create
    # case's $195 → $150 and never the edit case's $240.
    #
    # WHAT THIS EXAMPLE DOES AND DOES NOT PIN, measured rather than assumed. Unscoping BOTH ids in
    # the controller (`Category.find_by` / `Entry.find_by`) fails the category example above and
    # leaves this one GREEN, because `#own_contribution` gates on `Entry#effective_pool == pool` and
    # a stranger's entry can never reach a pool this user owns. The `entry_id` scope is therefore
    # defence in depth rather than the thing that stops a leak, and the pool-identity check is what
    # actually stops it. Recorded here so nobody reads this example as proof of the scope; it pins
    # the user-visible contract, which is that a foreign entry id moves no figure.
    it "excludes nothing for an entry belonging to somebody else", :aggregate_failures do
      other = create(:user)
      theirs = create(:entry, item: create(:item, :expense, category: create(:category, user: other)), amount: 45)

      get impact_entries_path(category_id: groceries.id, amount: "45", entry_id: theirs.id)

      expect(response.body).to include("$195.00")
      expect(response.body).to include("$150.00")
      expect(response.body).not_to include("$240.00")
    end
  end
end
