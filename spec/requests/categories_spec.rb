# frozen_string_literal: true

require "rails_helper"

# §7a'S WIDENED-PARAMETER CLASS, ASKED OF `category[pool_id]`.
#
# Plan 3 decision 3 made a pool REQUIRED on every category, which turned `pool_id` from a corner of
# this form that nothing routinely wrote into the ordinary payload of every create and every update.
# A scoped READ beside an unscoped WRITE is ownership on the way in only, and the consequence here
# is the app's central invariant rather than one screen's chrome:
# `PoolBalanceLedger::ENTRY_POOL_ID` resolves an entry through
# `COALESCE(entries.pool_id, categories.pool_id)` and joins on pool id with no user filter, so a
# stranger's pool id puts this user's whole spending history into that user's balance and breaks
# `Σ pools == your bank balance` for both of them.
#
# A REQUEST SPEC because these are answers to requests the UI cannot make: the form's picker only
# ever renders `current_user.pools`, so a foreign id can only arrive by tampering — which is exactly
# the case a form-driven system spec cannot reach.
#
# EVERY EXAMPLE IS A PAIR. A controller that 404s everything passes every "it refuses" assertion
# ever written, and the 404-vs-422 line is the one every ownership fix on this branch has drawn:
# WHOSE is the controller's question and answers 404; WHAT SHAPE is the model's and answers 422.
RSpec.describe "Categories", type: :request do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let!(:groceries) { create(:pool, :budget_pool, user: user, account: checking, name: "Groceries") }

  let(:stranger) { create(:user) }
  let!(:stranger_account) { create(:pool, :account, user: stranger, name: "Their Checking") }

  # `scope:` explicitly, as the other request specs do: Devise's mappings are populated when the
  # routes are drawn, and routes load lazily.
  before { sign_in user, scope: :user }

  describe "POST /categories" do
    def create_category(pool_id:, type: "expense", name: "Groceries Spending")
      post categories_path, params: { category: { name: name, category_type: type, pool_id: pool_id } }
    end

    # THE REACH DIRECTION, first. Without it every refusal below would pass just as well against a
    # controller that wrote nothing at all.
    it "writes the user's own pool onto the category", :aggregate_failures do
      expect { create_category(pool_id: groceries.id) }.to change(Category, :count).by(1)

      expect(user.categories.find_by(name: "Groceries Spending").pool).to eq(groceries)
      expect(response).to redirect_to(categories_path(type: "expense"))
    end

    it "refuses a stranger's pool and writes nothing", :aggregate_failures do
      expect { create_category(pool_id: stranger_account.id) }.not_to change(Category, :count)

      expect(response).to have_http_status(:not_found)
      expect(stranger.categories.reload).to be_empty
    end

    # THE OTHER SIDE OF THE SAME LINE: this pool is the user's OWN, so the controller must let it
    # through and the MODEL must answer. Scoping the lookup to `.accounts` here would 404 a record
    # the user can see in their own picker.
    it "answers the user's own budget pool on an income category with a 422, not a 404", :aggregate_failures do
      expect { create_category(pool_id: groceries.id, type: "income", name: "Salary") }
        .not_to change(Category, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    # The required `belongs_to :pool` answers a blank, and it must not be mistaken for a stranger's
    # id: a 404 on an empty picker would tell the user their own form had vanished.
    it "answers a blank pool with a 422, not a 404", :aggregate_failures do
      expect { create_category(pool_id: "") }.not_to change(Category, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /categories/:id" do
    let!(:category) { create(:category, :expense, user: user, name: "Groceries Spending", pool: checking) }

    it "re-points onto another of the user's own pools", :aggregate_failures do
      patch category_path(category), params: { category: { pool_id: groceries.id } }

      expect(response).to redirect_to(categories_path(type: "expense"))
      expect(category.reload.pool).to eq(groceries)
    end

    # THE UPDATE-SHAPED HOLE, and it is the sharper of the two: the category is mine and
    # `#set_category` finds it, so the refusal has to come from the assignment rather than from the
    # lookup. Nothing in `Category` objects — a stranger's account is an account — so this user's
    # entire spending history would have moved into that user's balance.
    it "refuses to re-point onto a stranger's pool and leaves the category alone", :aggregate_failures do
      patch category_path(category), params: { category: { pool_id: stranger_account.id } }

      expect(response).to have_http_status(:not_found)
      expect(category.reload.pool).to eq(checking)
    end
  end
end
