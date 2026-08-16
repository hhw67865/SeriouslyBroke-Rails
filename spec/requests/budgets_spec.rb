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

  # THE OTHER HALF OF §7a: a scoped READ beside an unscoped WRITE is not ownership, it is
  # ownership on the way in only. `budget[category_id]` is a wire parameter, and `Budget`
  # itself cannot object to a foreign category — it validates that the category is an expense
  # and pool-free, never whose it is.
  #
  # Where the line sits, and it is deliberate: the controller answers WHOSE (a stranger's id
  # is a 404, the same answer #set_budget gives), and the model answers WHAT SHAPE (a user's
  # own income category gets the form error it already had, not a 404). Stacking
  # `.expenses.budgetable` onto the lookup would make the controller a second reader of two
  # validations that already exist, and would turn a legible form error into a vanished record.
  describe "POST /budgets" do
    it "writes a rule on the user's own category", :aggregate_failures do
      own = create(:category, :expense, user: user)

      expect { post budgets_path, params: { budget: { amount: "40.00", category_id: own.id } } }
        .to change(Budget, :count).by(1)
      expect(response).to redirect_to(category_path(own))
      expect(own.reload.budget.amount).to eq(40)
    end

    it "refuses a stranger's category and writes nothing", :aggregate_failures do
      foreign_category = create(:category, :expense, user: stranger)

      expect { post budgets_path, params: { budget: { amount: "40.00", category_id: foreign_category.id } } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:not_found)
      expect(foreign_category.reload.budget).to be_nil
    end

    # The line, asserted from the other side: this is the user's OWN category, so the
    # controller must not hide it. `Budget#category_must_be_expense` answers instead, and the
    # 422 is the whole distinction — a `.expenses` in the lookup would make this a 404 and
    # send the user's own category down the same drain as a stranger's.
    it "answers the user's own income category with a 422, not a 404", :aggregate_failures do
      own_income = create(:category, :income, user: user)

      expect { post budgets_path, params: { budget: { amount: "40.00", category_id: own_income.id } } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    # AMENDMENT B, TRIPPED ON PURPOSE. This slot and its PATCH twin used to pin `budget[pool_id]`
    # as INERT, and they were correct while the parameter was unpermitted — that was the whole
    # point of writing them. The Budget page's edit form submits a pool-mode rule's own pool back,
    # so the permitted list is widened, and at that moment "whose pool is this" becomes exactly
    # the question `category_id` already had to answer. The inert pair is gone because the fact it
    # asserted stopped being true; these are its both-direction replacements.
    it "refuses a stranger's pool and writes nothing", :aggregate_failures do
      expect { post budgets_path, params: { budget: { amount: "40.00", pool_id: stranger_pool.id } } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:not_found)
      expect(stranger_pool.budgets.reload).to be_empty
    end

    # The same line as the income-category example above, drawn on the other owner: this pool is
    # the user's OWN, so the controller must let it through and `Budget` must answer. A
    # `.budget_pools` in the lookup would 404 a record the user can see on their own screen.
    it "answers the user's own account with a 422, not a 404", :aggregate_failures do
      own_account = create(:pool, :account, user: user)

      expect { post budgets_path, params: { budget: { amount: "40.00", pool_id: own_account.id } } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # The write, not just the read. A widened reader that lands on `category_path(nil)` raises
  # AFTER the row has already changed, so "it 302s to the pool" and "the amount moved" are
  # two different facts and both are asserted.
  describe "PATCH /budgets/:id" do
    # THE BUDGET PAGE, NOT THE POOL PAGE. The pool page was a floor while nothing else could
    # render a pool-mode rule; §8's page is where every rule now lives and is the page the Edit
    # link was clicked from.
    it "updates a pool-mode rule and returns to the Budget page", :aggregate_failures do
      patch budget_path(pool_rule), params: { budget: { amount: "275.00" } }

      expect(response).to redirect_to(budget_page_path)
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

    # RE-PARENTING, which is the update-shaped version of the same hole: the rule is mine and
    # #set_budget finds it, so the refusal has to come from the assignment rather than the
    # lookup. Nothing in `Budget` objects — a stranger's expense category is an expense
    # category — so the rule would move onto their page and render there.
    it "re-parents onto another of the user's own categories", :aggregate_failures do
      own = create(:category, :expense, user: user)

      patch budget_path(category_rule), params: { budget: { category_id: own.id } }

      expect(response).to redirect_to(category_path(own))
      expect(category_rule.reload.category).to eq(own)
    end

    it "refuses to re-parent onto a stranger's category and leaves the rule alone", :aggregate_failures do
      foreign_category = create(:category, :expense, user: stranger)

      patch budget_path(category_rule), params: { budget: { category_id: foreign_category.id } }

      expect(response).to have_http_status(:not_found)
      expect(category_rule.reload.category).to eq(category)
    end

    # The pool-mode half of the re-parenting pair above, and the reach direction for `pool_id`:
    # the assignment has to actually happen, or "it refuses a stranger's pool" would pass against
    # a parameter that was silently dropped.
    it "re-parents a pool-mode rule onto another of the user's own pools", :aggregate_failures do
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
    it "deletes a pool-mode rule and returns to the Budget page", :aggregate_failures do
      expect { delete budget_path(pool_rule) }.to change(Budget, :count).by(-1)
      expect(response).to redirect_to(budget_page_path)
    end

    # The category-mode branch of #owner_path had NO passing twin anywhere before this: no view
    # links to it and no system spec reaches it, so the only executed proof that destroy works
    # at all was the pool-mode example above — which exercises the other branch.
    it "deletes a category-mode rule and returns to its category", :aggregate_failures do
      expect { delete budget_path(category_rule) }.to change(Budget, :count).by(-1)
      expect(response).to redirect_to(category_path(category))
      expect(Budget.exists?(category_rule.id)).to be false
    end

    it "refuses to delete another user's pool-mode rule", :aggregate_failures do
      foreign = create(:budget, :rate, pool: stranger_pool, category: nil)

      delete budget_path(foreign)

      expect(response).to have_http_status(:not_found)
      expect(Budget.exists?(foreign.id)).to be true
    end
  end
end
