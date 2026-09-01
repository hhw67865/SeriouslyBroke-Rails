# frozen_string_literal: true

require "rails_helper"

# §7a. `Budget.for_user` is the app's one answer to which rules a user owns, and these examples pin
# the lookup at the layer where it lives: a scoped find is BOTH a reach and a refusal, and a scope
# that returns everything passes every "it found it" assertion ever written.
#
# WHAT THIS FILE LOST IN PLAN 3, TASK 3, AND WHY IT IS NOT A GAP. Half of it was the category-mode
# half of each pair — a cap reachable by `edit`, a `budget[category_id]` write ownership-scoped on
# the way in, a `PATCH` re-parenting a cap onto another category, a `DELETE` returning to that
# category's page. Every one of those pinned the behaviour this task deletes: `category_id` is no
# longer a permitted parameter, `belongs_to :category` is gone from the model, and `#owner_path`'s
# category branch with it. The examples are deleted WITH the behaviour rather than rewritten
# against a shape the app refuses, and the ownership question they asked is asked in full by the
# `pool_id` pair that survives — the same question, of the owner that remains.
#
# A request spec rather than a system spec because the form does not offer the pool; the route is
# the whole interface under test.
RSpec.describe "Budgets", type: :request do
  let(:user) { create(:user) }
  let(:pool) do
    create(:pool, :budget_pool, user: user, account: create(:pool, :account, user: user), name: "Groceries")
  end

  let(:stranger) { create(:user) }
  let(:stranger_pool) do
    create(:pool, :budget_pool, user: stranger, account: create(:pool, :account, user: stranger))
  end

  let!(:pool_rule) { create(:budget, :rate, pool: pool, amount: 200) }

  # `scope:` explicitly, as the other request specs do: Devise's mappings are populated when
  # the routes are drawn, and routes load lazily.
  before { sign_in user, scope: :user }

  describe "GET /budgets/:id/edit" do
    it "reaches the user's own rule" do
      get edit_budget_path(pool_rule)

      expect(response).to have_http_status(:ok)
    end

    # `show_exceptions = :rescuable` in the test environment, so RecordNotFound arrives as
    # the 404 a real request would get rather than as a raised exception. The status is what
    # the user meets, so the status is what is asserted.
    it "refuses another user's rule" do
      foreign = create(:budget, :rate, pool: stranger_pool)

      get edit_budget_path(foreign)

      expect(response).to have_http_status(:not_found)
    end
  end

  # THE OTHER HALF OF §7a: a scoped READ beside an unscoped WRITE is not ownership, it is ownership
  # on the way in only. `budget[pool_id]` is a wire parameter, and `Budget` itself cannot object to
  # a foreign pool — it validates that the pool is not an account and that the shape is legal,
  # never whose it is.
  #
  # Where the line sits, and it is deliberate: the controller answers WHOSE (a stranger's id is a
  # 404, the same answer #set_budget gives), and the model answers WHAT SHAPE (a user's own account
  # gets the form error it already had, not a 404). Scoping the lookup to `.budget_pools` would
  # make the controller a second reader of a validation that already exists, and would turn a
  # legible form error into a vanished record.
  describe "POST /budgets" do
    it "writes a rule on the user's own pool", :aggregate_failures do
      own = create(:pool, :budget_pool, user: user, account: pool.account, name: "Dining Out")

      expect { post budgets_path, params: { budget: { amount: "40.00", pool_id: own.id, basis: "monthly", interval_months: 1 } } }
        .to change(Budget, :count).by(1)
      expect(response).to redirect_to(budget_page_path)
      expect(own.budgets.reload.sole.amount).to eq(40)
    end

    # AMENDMENT B, TRIPPED ON PURPOSE. This slot and its PATCH twin used to pin `budget[pool_id]`
    # as INERT, and they were correct while the parameter was unpermitted — that was the whole
    # point of writing them. The Budget page's edit form submits a rule's own pool back, so the
    # permitted list was widened, and at that moment "whose pool is this" became the question.
    it "refuses a stranger's pool and writes nothing", :aggregate_failures do
      expect { post budgets_path, params: { budget: { amount: "40.00", pool_id: stranger_pool.id } } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:not_found)
      expect(stranger_pool.budgets.reload).to be_empty
    end

    # The line drawn from the other side: this pool is the user's OWN, so the controller must let
    # it through and `Budget` must answer. A `.budget_pools` in the lookup would 404 a record the
    # user can see on their own screen.
    it "answers the user's own account with a 422, not a 404", :aggregate_failures do
      own_account = create(:pool, :account, user: user)

      expect { post budgets_path, params: { budget: { amount: "40.00", pool_id: own_account.id } } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    # A rule with no owner at all — the state a bare `/budgets/new` submits, now that the form
    # offers no owner control. `Budget#must_belong_to_a_pool` answers with a legible 422 on
    # `:base`, which is where the form renders it.
    it "answers a rule with no pool at all with a 422", :aggregate_failures do
      expect { post budgets_path, params: { budget: { amount: "40.00" } } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    # `category_id` IS NO LONGER PERMITTED BY THIS CONTROLLER, and the refusal is silent by design:
    # an unpermitted key is dropped, so the request is exactly the owner-less one above.
    #
    # THE SCHEMA HALF OF THIS PIN IS WITHDRAWN (two-ledger spec §3, Task 2). It read
    # `Budget.column_names` — "there is no such column to carry one" — which was true between
    # `DropCapEraBudgetColumns` and Task 1's migration, and Task 1 re-added the column as the
    # OWNER a rule will have after Task 8. The half that is still the point is unchanged and is
    # what this asserts: the wire cannot set it. Task 7 gives the category lane a controller of its
    # own, and it will pin the same key going the other way.
    it "ignores a category_id entirely and writes no rule", :aggregate_failures do
      own_category = create(:category, :expense, user: user)

      expect { post budgets_path, params: { budget: { amount: "40.00", category_id: own_category.id } } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(own_category.reload.budgets).to be_empty
    end
  end

  # The write, not just the read: "it 302s to the Budget page" and "the amount moved" are two
  # different facts and both are asserted.
  describe "PATCH /budgets/:id" do
    # THE BUDGET PAGE, NOT THE POOL PAGE. The pool page was a floor while nothing else could
    # render a rule; §8's page is where every rule now lives and is the page the Edit link was
    # clicked from.
    it "updates a rule and returns to the Budget page", :aggregate_failures do
      patch budget_path(pool_rule), params: { budget: { amount: "275.00" } }

      expect(response).to redirect_to(budget_page_path)
      expect(pool_rule.reload.amount).to eq(275)
    end

    it "refuses another user's rule and leaves it alone", :aggregate_failures do
      foreign = create(:budget, :rate, pool: stranger_pool, amount: 90)

      patch budget_path(foreign), params: { budget: { amount: "999.00" } }

      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.amount).to eq(90)
    end

    # RE-PARENTING, which is the update-shaped version of the same hole: the rule is mine and
    # #set_budget finds it, so the refusal has to come from the assignment rather than the lookup.
    # Nothing in `Budget` objects — a stranger's envelope is an envelope — so the rule would move
    # onto their page and render there. The reach direction is asserted too, or "it refuses a
    # stranger's pool" would pass against a parameter that was silently dropped.
    it "re-parents onto another of the user's own pools", :aggregate_failures do
      own_pool = create(:pool, :budget_pool, user: user, account: pool.account, name: "Dining Out")

      patch budget_path(pool_rule), params: { budget: { pool_id: own_pool.id } }

      expect(response).to redirect_to(budget_page_path)
      expect(pool_rule.reload.pool).to eq(own_pool)
    end

    it "refuses to re-parent onto a stranger's pool and leaves the rule alone", :aggregate_failures do
      patch budget_path(pool_rule), params: { budget: { pool_id: stranger_pool.id } }

      expect(response).to have_http_status(:not_found)
      expect(pool_rule.reload.pool).to eq(pool)
    end
  end

  describe "DELETE /budgets/:id" do
    it "deletes a rule and returns to the Budget page", :aggregate_failures do
      expect { delete budget_path(pool_rule) }.to change(Budget, :count).by(-1)
      expect(response).to redirect_to(budget_page_path)
      expect(Budget.exists?(pool_rule.id)).to be false
    end

    it "refuses to delete another user's rule", :aggregate_failures do
      foreign = create(:budget, :rate, pool: stranger_pool)

      delete budget_path(foreign)

      expect(response).to have_http_status(:not_found)
      expect(Budget.exists?(foreign.id)).to be true
    end
  end
end
