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
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }

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

    # ** `pool_id` IS NOT MERELY UNUSED, IT IS UNWRITABLE. ** The column still exists for the
    # length of this branch (`Category belongs_to :pool, optional: true`), so a param naming it
    # would be assigned if it were permitted — including a STRANGER's, which is the exact IDOR the
    # deleted lookup existed to refuse. Pinned as an absence so the permit list cannot quietly
    # regain it before Task 8 drops the column.
    it "drops a pool a crafted param names", :aggregate_failures do
      stranger_account = create(:pool, :account, user: create(:user), name: "Their Checking")

      create_category(pool_id: stranger_account.id)

      expect(response).to redirect_to(categories_path(type: "expense"))
      expect(user.categories.find_by(name: "Vacation").pool).to be_nil
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
      stranger_account = create(:pool, :account, user: create(:user), name: "Their Checking")

      patch category_path(category), params: { category: { name: "Groceries", pool_id: stranger_account.id } }

      expect(response).to redirect_to(categories_path(type: "expense"))
      expect(category.reload.pool).to eq(checking)
    end
  end
end
