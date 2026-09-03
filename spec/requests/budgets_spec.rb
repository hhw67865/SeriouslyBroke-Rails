# frozen_string_literal: true

require "rails_helper"

# §7a. `Budget.for_user` is the app's one answer to which rules a user owns, and these examples pin
# the lookup at the layer where it lives: a scoped find is BOTH a reach and a refusal, and a scope
# that returns everything passes every "it found it" assertion ever written.
#
# THE OWNER IS A CATEGORY (two-ledger spec §3), AND THE PAIRS BELOW ARE THE POOL PAIRS RE-ASKED OF
# IT. `budget[pool_id]` is no longer a permitted parameter and `budget[category_id]` is — the same
# question ("whose owner is this?") of the owner that holds the money. What changed in these
# examples is only which column the ownership question is asked about; every branch they covered
# — a reach, a stranger's id, a shape refusal, an owner-less save, a re-parent both ways — is
# asked again below.
#
# A request spec rather than a system spec for the pairs a browser cannot compose: a stranger's id,
# and an unpermitted key. The picker itself is covered in spec/system/budgets/form_spec.rb.
RSpec.describe "Budgets", type: :request do
  let(:user) { create(:user) }
  let(:groceries) { create(:category, :expense, :funded, user: user, name: "Groceries") }

  let(:stranger) { create(:user) }
  let(:stranger_category) { create(:category, :expense, :funded, user: stranger, name: "Their Rent") }

  let!(:rule) { create(:budget, :rate, category: groceries, amount: 200) }

  # `scope:` explicitly, as the other request specs do: Devise's mappings are populated when
  # the routes are drawn, and routes load lazily.
  before { sign_in user, scope: :user }

  describe "GET /budgets/:id/edit" do
    it "reaches the user's own rule" do
      get edit_budget_path(rule)

      expect(response).to have_http_status(:ok)
    end

    # `show_exceptions = :rescuable` in the test environment, so RecordNotFound arrives as
    # the 404 a real request would get rather than as a raised exception. The status is what
    # the user meets, so the status is what is asserted.
    it "refuses another user's rule" do
      foreign = create(:budget, :rate, category: stranger_category)

      get edit_budget_path(foreign)

      expect(response).to have_http_status(:not_found)
    end
  end

  # THE OTHER HALF OF §7a: a scoped READ beside an unscoped WRITE is not ownership, it is ownership
  # on the way in only. `budget[category_id]` is a wire parameter, and `Budget` itself cannot object
  # to a foreign category — it validates that the shape is legal and that the item belongs to the
  # category, never whose it is.
  #
  # Where the line sits, and it is deliberate: the controller answers WHOSE (a stranger's id is a
  # 404, the same answer #set_budget gives), and the model answers WHAT SHAPE. Scoping the lookup to
  # `.expenses` would make the controller a second reader of a rule the model states, and would turn
  # a legible form error into a vanished record.
  describe "POST /budgets" do
    it "writes a rule on the user's own category", :aggregate_failures do
      own = create(:category, :expense, :funded, user: user, name: "Dining Out")

      expect { post budgets_path, params: { budget: { amount: "40.00", category_id: own.id, basis: "monthly", interval_months: 1 } } }
        .to change(Budget, :count).by(1)
      expect(response).to redirect_to(budget_page_path)
      expect(own.budgets.reload.sole.amount).to eq(40)
    end

    # AMENDMENT B, TRIPPED ON PURPOSE. This slot and its PATCH twin used to pin the OWNER parameter
    # as INERT, and they were correct while it was unpermitted — that was the whole point of writing
    # them. The Budget page's form submits a rule's own owner back, so the permitted list was
    # widened, and at that moment "whose is this" became the question.
    it "refuses a stranger's category and writes nothing", :aggregate_failures do
      expect { post budgets_path, params: { budget: { amount: "40.00", category_id: stranger_category.id } } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:not_found)
      expect(stranger_category.budgets.reload).to be_empty
    end

    # The line drawn from the other side, and this is the pool era's "answers the user's own account
    # with a 422, not a 404" re-asked of the owner that replaced it. An INCOME category is the user's
    # OWN, so the controller must let it through and the MODEL must answer — and it does, from an
    # unexpected direction: `BudgetProposal` stamps `funded_since` on the way in, and
    # `Category#only_expenses_hold_money` refuses that on an income category (§2: income lands in
    # available and is allocated out of it). The refusal is carried onto the rule's `:base`, which is
    # where the form prints it.
    #
    # Scoping the lookup to `.expenses` would turn this into a 404 — the user's own record
    # vanishing — where the model gives a sentence they can act on. The form does not OFFER an
    # income category (`categories.expenses` in the picker); that is the affordance, not the
    # boundary.
    it "answers the user's own income category with a 422, not a 404", :aggregate_failures do
      income = create(:category, :income, user: user)

      expect { post budgets_path, params: { budget: { amount: "40.00", category_id: income.id, basis: "per_period" } } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("only expense categories hold money")
      expect(income.reload.funded_since).to be_nil
    end

    # A rule with no owner at all — the state a bare `/budgets/new` submits when nothing is chosen.
    # `Budget#must_have_an_owner` answers with a legible 422 on `:base`, which is where the form
    # renders it, and the sentence names the CATEGORY because that is the control the form offers.
    it "answers a rule with no owner at all with a 422", :aggregate_failures do
      expect { post budgets_path, params: { budget: { amount: "40.00" } } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("must belong to a category")
    end

    # `pool_id` IS NEITHER PERMITTED NOR A COLUMN (two-ledger spec §3/§5). The refusal is silent by
    # design: an unpermitted key is dropped, so the request is exactly the owner-less one above.
    # Kept after the drop because the payload is what a tampered POST would actually send — a client
    # written against the pool era — and the answer must be a 422 rather than an UnknownAttribute
    # 500.
    # ** ONE CATEGORY, ONE CATCH-ALL RULE, ON THE WIRE (two-ledger spec §3; computed-claims ruling of
    # 2026-09-03). ** `groceries` already carries the file's `let!(:rule)` — an item-less $200 rate —
    # so a second rule naming no item is the shape whose claim would double-count the category's own
    # spending. The model answers on `:base`, which is where `budgets/_form` prints it, and the
    # controller turns that into the same 422 every other shape refusal gets.
    it "refuses a second rule covering the whole of one category", :aggregate_failures do
      expect { post budgets_path, params: { budget: { amount: "40.00", category_id: groceries.id, basis: "per_period" } } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("already has a rule covering all of its spending")
    end

    # THE OTHER DIRECTION, on the same category and through the same POST: a rule that names an ITEM
    # has a lane of its own and is written.
    it "writes a second rule on the same category when it names an item", :aggregate_failures do
      phone = create(:item, category: groceries, name: "Phone")

      expect do
        post budgets_path,
             params: { budget: { amount: "40.00", category_id: groceries.id, basis: "per_period", item_id: phone.id } }
      end.to change(Budget, :count).by(1)
      expect(response).to redirect_to(budget_page_path)
    end

    it "ignores a pool_id entirely and writes no rule", :aggregate_failures do
      expect { post budgets_path, params: { budget: { amount: "40.00", pool_id: SecureRandom.uuid } } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # The write, not just the read: "it 302s to the Budget page" and "the amount moved" are two
  # different facts and both are asserted.
  describe "PATCH /budgets/:id" do
    it "updates a rule and returns to the Budget page", :aggregate_failures do
      patch budget_path(rule), params: { budget: { amount: "275.00" } }

      expect(response).to redirect_to(budget_page_path)
      expect(rule.reload.amount).to eq(275)
    end

    it "refuses another user's rule and leaves it alone", :aggregate_failures do
      foreign = create(:budget, :rate, category: stranger_category, amount: 90)

      patch budget_path(foreign), params: { budget: { amount: "999.00" } }

      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.amount).to eq(90)
    end

    # RE-PARENTING, which is the update-shaped version of the same hole: the rule is mine and
    # #set_budget finds it, so the refusal has to come from the assignment rather than the lookup.
    # Nothing in `Budget` objects — a stranger's category is a category — so the rule would move
    # onto their page and render there. The reach direction is asserted too, or "it refuses a
    # stranger's category" would pass against a parameter that was silently dropped.
    it "re-parents onto another of the user's own categories", :aggregate_failures do
      own = create(:category, :expense, :funded, user: user, name: "Dining Out")

      patch budget_path(rule), params: { budget: { category_id: own.id } }

      expect(response).to redirect_to(budget_page_path)
      expect(rule.reload.category).to eq(own)
    end

    it "refuses to re-parent onto a stranger's category and leaves the rule alone", :aggregate_failures do
      patch budget_path(rule), params: { budget: { category_id: stranger_category.id } }

      expect(response).to have_http_status(:not_found)
      expect(rule.reload.category).to eq(groceries)
    end

    # THE PATH `BudgetProposal` DOES NOT GUARD (fix round 1). `#create` goes through the proposal,
    # whose `funded_since` stamp `Category#only_expenses_hold_money` refuses on an income category —
    # `#update` writes straight through, so this re-parent SAVED CLEAN. The rule then counted into
    # `Budget.steady_need` and was unfillable forever, because `Category.in_fill_order` is holders
    # and an income category can never be one.
    #
    # A 422 AND NOT A 404: the category is the user's OWN, so ownership is not the objection — the
    # model's is, and `Budget#category_must_be_an_expense` says it where the form can print it.
    it "refuses to re-parent onto the user's own income category", :aggregate_failures do
      income = create(:category, :income, user: user)

      patch budget_path(rule), params: { budget: { category_id: income.id } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("must be an expense category")
      expect(rule.reload.category).to eq(groceries)
      expect(income.budgets.reload).to be_empty
    end
  end

  describe "DELETE /budgets/:id" do
    it "deletes a rule and returns to the Budget page", :aggregate_failures do
      expect { delete budget_path(rule) }.to change(Budget, :count).by(-1)
      expect(response).to redirect_to(budget_page_path)
      expect(Budget.exists?(rule.id)).to be false
    end

    it "refuses to delete another user's rule", :aggregate_failures do
      foreign = create(:budget, :rate, category: stranger_category)

      delete budget_path(foreign)

      expect(response).to have_http_status(:not_found)
      expect(Budget.exists?(foreign.id)).to be true
    end
  end
end
