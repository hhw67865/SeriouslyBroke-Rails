# frozen_string_literal: true

require "rails_helper"

# §7a. `User has_many :budgets, through: :categories` reaches category-mode rules only, so
# `current_user.budgets.find` answered 404 for every pool-mode rule — which is every rule the
# Budget page manages. These examples pin the lookup at the layer where it lives: a scoped
# find is BOTH a reach and a refusal, and a scope that returns everything passes every
# "it found it" assertion ever written.
#
# A request spec rather than a system spec because there is no UI yet that links to a
# pool-mode rule's form; the route is the whole interface under test.
RSpec.describe "Budgets", type: :request do
  let(:user) { create(:user) }
  let(:pool) do
    create(:pool, :budget_pool, user: user, account: create(:pool, :account, user: user), name: "Groceries")
  end
  let(:category) { create(:category, :expense, user: user) }

  let(:stranger) { create(:user) }
  let(:stranger_pool) do
    create(:pool, :budget_pool, user: stranger, account: create(:pool, :account, user: stranger))
  end

  let!(:pool_rule) { create(:budget, :rate, pool: pool, category: nil, amount: 200) }
  let!(:category_rule) { create(:budget, category: category, amount: 150) }

  # `scope:` explicitly, as the other request specs do: Devise's mappings are populated when
  # the routes are drawn, and routes load lazily.
  before { sign_in user, scope: :user }

  describe "GET /budgets/:id/edit" do
    it "reaches a pool-mode rule" do
      get edit_budget_path(pool_rule)

      expect(response).to have_http_status(:ok)
    end

    it "still reaches a category-mode rule" do
      get edit_budget_path(category_rule)

      expect(response).to have_http_status(:ok)
    end

    # `show_exceptions = :rescuable` in the test environment, so RecordNotFound arrives as
    # the 404 a real request would get rather than as a raised exception. The status is what
    # the user meets, so the status is what is asserted.
    it "refuses another user's pool-mode rule" do
      foreign = create(:budget, :rate, pool: stranger_pool, category: nil)

      get edit_budget_path(foreign)

      expect(response).to have_http_status(:not_found)
    end

    it "refuses another user's category-mode rule" do
      foreign = create(:budget, category: create(:category, :expense, user: stranger))

      get edit_budget_path(foreign)

      expect(response).to have_http_status(:not_found)
    end
  end

  # The write, not just the read. A widened reader that lands on `category_path(nil)` raises
  # AFTER the row has already changed, so "it 302s to the pool" and "the amount moved" are
  # two different facts and both are asserted.
  describe "PATCH /budgets/:id" do
    it "updates a pool-mode rule and returns to its pool", :aggregate_failures do
      patch budget_path(pool_rule), params: { budget: { amount: "275.00" } }

      expect(response).to redirect_to(pool_path(pool))
      expect(pool_rule.reload.amount).to eq(275)
    end

    it "updates a category-mode rule and returns to its category", :aggregate_failures do
      patch budget_path(category_rule), params: { budget: { amount: "175.00" } }

      expect(response).to redirect_to(category_path(category))
      expect(category_rule.reload.amount).to eq(175)
    end

    it "refuses another user's pool-mode rule and leaves it alone", :aggregate_failures do
      foreign = create(:budget, :rate, pool: stranger_pool, category: nil, amount: 90)

      patch budget_path(foreign), params: { budget: { amount: "999.00" } }

      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.amount).to eq(90)
    end
  end

  describe "DELETE /budgets/:id" do
    it "deletes a pool-mode rule and returns to its pool", :aggregate_failures do
      expect { delete budget_path(pool_rule) }.to change(Budget, :count).by(-1)
      expect(response).to redirect_to(pool_path(pool))
    end

    it "refuses to delete another user's pool-mode rule", :aggregate_failures do
      foreign = create(:budget, :rate, pool: stranger_pool, category: nil)

      delete budget_path(foreign)

      expect(response).to have_http_status(:not_found)
      expect(Budget.exists?(foreign.id)).to be true
    end
  end
end
