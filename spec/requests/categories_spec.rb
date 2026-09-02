# frozen_string_literal: true

require "rails_helper"

# THE CATEGORY FORM'S WIRE CONTRACT, AFTER `pool_id` LEFT IT (two-ledger spec §3–§5, Task 7).
#
# WHAT THIS FILE USED TO BE. Every example here was §7a's widened-parameter class asked of
# `category[pool_id]`: plan 3 made a pool REQUIRED on every category, which turned that param into
# the ordinary payload of every create and update, and a scoped READ beside an unscoped WRITE would
# have put this user's whole spending history into a STRANGER's pool balance —
# `PoolBalanceLedger::ENTRY_POOL_ID` joined on pool id with no user filter. The controller answered
# it with a `current_user.pools.find`, and this file pinned the 404-vs-422 line that lookup drew.
#
# THE PARAM IS GONE, SO THE HAZARD CLASS IS TOO. Nothing reads `categories.pool_id` any more, the
# form offers no picker, and `category_params` permits no foreign id of any kind — the three
# attributes that replaced it (`target_amount`, `priority`, `funded_since`) are plain columns of
# the record itself, so there is no "whose is this" question for a request to get wrong. The six
# examples that pinned the pool lookup are DELETED, each named in the task report; what stands in
# their place is the contract of the three that arrived.
#
# STILL A REQUEST SPEC, for the reason the old one was: these are answers to requests the UI does
# not make. The form never submits a `pool_id`, and a param dropped silently back to its default
# looks exactly like a param that was never sent — which only this layer can tell apart.
RSpec.describe "Categories", type: :request do
  let(:user) { create(:user) }
  # rubocop:disable RSpec/LetSetup -- nothing NAMES this account and every example needs it:
  # the `:account` trait's `after(:create)` is what makes the user's first account their MAIN
  # one, and the pot is where every entry below lands.
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  # rubocop:enable RSpec/LetSetup

  # `scope:` explicitly, as the other request specs do: Devise's mappings are populated when the
  # routes are drawn, and routes load lazily.
  before { sign_in user, scope: :user }

  describe "POST /categories" do
    def create_category(attributes)
      post categories_path, params: { category: { name: "Vacation", category_type: "expense" }.merge(attributes) }
    end

    # THE REACH DIRECTION, first. Without it every refusal below would pass just as well against a
    # controller that wrote nothing at all.
    it "writes the three holding columns", :aggregate_failures do
      expect { create_category(target_amount: 2_400, priority: 3, funded_since: "2026-02-06") }
        .to change(Category, :count).by(1)

      category = user.categories.find_by(name: "Vacation")
      expect([category.target_amount, category.priority]).to eq([2_400, 3])
      expect(category.funded_since).to eq(Date.new(2026, 2, 6))
      expect(response).to redirect_to(categories_path(type: "expense"))
    end

    # ** `pool_id` IS NEITHER PERMITTED NOR A COLUMN (Task 8). ** It was the IDOR the deleted
    # `current_user.pools.find` lookup existed to refuse; the column is gone, so the payload is what
    # a client written against the pool era would still send and the answer must be an ordinary
    # write rather than an UnknownAttribute 500.
    it "drops a pool a crafted param names" do
      create_category(pool_id: SecureRandom.uuid)

      expect(response).to redirect_to(categories_path(type: "expense"))
    end

    # THE MODEL'S OWN LINE, WHICH IS THE ONE THAT SURVIVES. `Category#holding_columns_are_sane`
    # refuses a target on a category that cannot hold money, and a shape refusal is a 422 — the
    # same division the deleted pool examples drew between "whose" (404) and "what shape" (422).
    it "answers a target on an income category with a 422", :aggregate_failures do
      expect { create_category(category_type: "income", target_amount: 2_400) }
        .not_to change(Category, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    # A CATEGORY THAT HOLDS NOTHING IS THE HONEST DEFAULT (§4): its spending drains available until
    # it gets a rule or an allocation. Blank is not a refusal.
    it "accepts all three blank", :aggregate_failures do
      expect { create_category(target_amount: "", funded_since: "") }.to change(Category, :count).by(1)

      category = user.categories.find_by(name: "Vacation")
      expect(category).not_to be_holder
      expect(category.target_amount).to be_nil
    end
  end

  # ** THE INDEX'S HOLDING AGGREGATES ARE BATCHED (fix round 1, MED-3). **
  #
  # Each card prints what its category holds, and it built a `HoldingCalculator` per card to do it —
  # N categories, N sets of grouped aggregates, on the one screen that renders every category a user
  # owns. `CategoriesController#holding_terms` builds ONE `CategoryLedger` over the holders and
  # threads `#terms_for` into each calculator, which is what Home, the Budget page and
  # `AllocationCalculator` already do.
  #
  # THE ALLOCATION STATEMENTS ARE THE PROBE, not the total. A category's HOLDING is allocations in,
  # allocations out and the spending it counts; the allocation halves are read by nothing else on
  # this page, so counting statements against that table isolates exactly the reader under test.
  # The total keeps growing with the row count for a reason this fix does not touch: every card also
  # asks `CategoryCalculator` what it SPENT this period and lists its top items, which are per-card
  # questions about per-card data.
  #
  # MEASURED, BOTH WAYS, at the browser-facing layer rather than by reasoning about the source.
  # Before: 2 allocation statements for one holder and 10 for five (two per card). After: 3 and 3 —
  # the ledger's own fixed grouped queries. One holder costs ONE statement more than it used to,
  # which is the honest price of the constant and is why the assertion is an EQUALITY between the
  # two counts rather than a ceiling on either.
  #
  # A request spec because the count is a fact about a rendered PAGE, and the null cache store this
  # environment configures means every card really renders.
  describe "GET /categories — holding aggregates" do
    def allocation_statements
      statements = []
      recorder = lambda do |_name, _start, _finish, _id, payload|
        statements << payload[:sql] unless ["SCHEMA", "TRANSACTION"].include?(payload[:name])
      end
      ActiveSupport::Notifications.subscribed(recorder, "sql.active_record") do
        get categories_path(type: "expense")
      end
      statements.count { |sql| sql.include?(%("allocations")) }
    end

    def holders(*names)
      names.each { |name| create(:category, :expense, :funded, user: user, name: name) }
      # A warm request first: the FIRST render of a template compiles it and loads its own rows, and
      # a compile counted on one side of the comparison and not the other is noise the assertion
      # cannot tell from a regression.
      get categories_path(type: "expense")
    end

    it "asks the same number of times for one holder as for five", :aggregate_failures do
      holders("Groceries")
      one = allocation_statements

      holders("Rent", "Transit", "Utilities", "Vacation")
      five = allocation_statements

      expect(user.categories.count(&:holder?)).to eq(5)
      expect(five).to eq(one)
      # The figure itself, so a future change that batches by accident — or stops reading
      # allocations at all — is not silently green.
      expect(five).to eq(3)
    end
  end

  describe "PATCH /categories/:id" do
    let!(:category) do
      create(:category, :expense, :funded, user: user, name: "Groceries", target_amount: 500)
    end

    # ** CLEARING `funded_since` STOPS THE CATEGORY HOLDING MONEY (§4). ** A blank has to reach the
    # column as NULL rather than being skipped as "unchanged": the whole affordance the form
    # promises is that a user can take a category back out of the fill order, and a permit list
    # that ignored the blank would leave the checkbox and the data disagreeing.
    it "clears the funding start when the field is submitted blank", :aggregate_failures do
      patch category_path(category), params: { category: { funded_since: "" } }

      expect(response).to redirect_to(categories_path(type: "expense"))
      expect(category.reload.funded_since).to be_nil
      expect(category).not_to be_holder
    end

    it "clears the target the same way" do
      patch category_path(category), params: { category: { target_amount: "" } }

      expect(category.reload.target_amount).to be_nil
    end

    # THE UPDATE-SHAPED HOLE, and it was the sharper of the two on the pool lookup: the category is
    # mine and `#set_category` finds it, so a refusal has to come from the assignment rather than
    # from the lookup. There is nothing left to refuse — the param is simply not permitted.
    #
    # `name` RIDES ALONG, and it is not padding: `params.expect` raises ParameterMissing when NONE
    # of the listed keys is present, so a payload of `pool_id` alone is a 400 rather than a write
    # this example could inspect. The realistic crafted request is a real form submission with one
    # extra field, which is what this sends.
    it "drops a pool a crafted param names on update", :aggregate_failures do
      patch category_path(category), params: { category: { name: "Groceries", pool_id: SecureRandom.uuid } }

      expect(response).to redirect_to(categories_path(type: "expense"))
      expect(category.reload.name).to eq("Groceries")
    end
  end
end
