# frozen_string_literal: true

require "rails_helper"

# §8'S ACCEPT FLOW: one form, one POST, one transaction (task-7 amendment A).
# `BudgetsController#create` finds-or-creates the envelope, re-points the category at it and
# writes the rule — so `budget_params` grew four columns (`basis`, `interval_months`,
# `anchor_date`, `item_id`) and the request grew an envelope half, and every one of those five new
# wire parameters is a fresh ownership question.
#
# A REQUEST SPEC because these are answers to REQUESTS THE UI CANNOT MAKE: a stranger's item id, a
# stale creation half from a page loaded before the first acceptance, a `pool_type` the form does
# not render. The browser path is covered in spec/system/budget_page/suggestions_spec.rb.
#
# Its own file rather than another block in budgets_spec.rb: this flow needs three fixtures of its
# own and that file already carries seven.
RSpec.describe "Budget proposals", type: :request do
  let(:user) { create(:user) }
  let(:stranger) { create(:user) }
  let(:account) { create(:pool, :account, user: user, name: "Checking") }
  let(:utilities) { create(:category, :expense, user: user, name: "Utilities") }
  let(:phone) { create(:item, category: utilities, name: "Phone") }

  # `scope:` explicitly, as the other request specs do: Devise's mappings are populated when the
  # routes are drawn, and routes load lazily.
  #
  # THE FIXTURES ARE FORCED HERE, and that is not tidiness: `account` is created lazily by the
  # first reference to it, which is inside `#accept` — so inside the `expect { }` block, where it
  # would be counted as a Pool this request created. Every "writes nothing" example below would
  # then fail against a flow that wrote nothing at all.
  before do
    account
    phone
    sign_in user, scope: :user
  end

  describe "POST /budgets with an envelope half", :aggregate_failures do
    # THE REACH DIRECTION FOR ALL THREE WRITES AT ONCE. Without it, every "it refuses" example
    # below would pass just as well against a flow that silently wrote nothing at all.
    it "creates the envelope, re-points the category and writes the rule" do
      expect { accept }.to change(Budget, :count).by(1)

      envelope = user.pools.find_by(name: "Utilities")
      expect(envelope.pool_type).to eq("budget")
      expect(envelope.account).to eq(account)
      expect(utilities.reload.pool).to eq(envelope)
      expect(envelope.budgets.sole.item).to eq(phone)
      expect(response).to redirect_to(budget_page_path)
    end

    # THE CAP THE RE-POINT DESTROYS, in the direction where it IS destroyed.
    # `Category#destroy_budget_if_pool_linked` fires on the re-point because a category cannot hold
    # both a cap and a pool — so a successful acceptance deletes a rule the user wrote, which is
    # what the panel's cap sentence promises out loud. Net `Budget.count` is unchanged (one cap
    # out, one rule in) and that is exactly why the record is named rather than counted.
    it "replaces the category's cap with the new rule" do
      cap = create(:budget, category: utilities, amount: 300)

      expect { accept }.to not_change(Budget, :count)
      expect(Budget.exists?(cap.id)).to be false
      expect(utilities.reload.pool.budgets.sole.item).to eq(phone)
    end

    # §7a'S CLASS, THIRD APPEARANCE, AND THE SHARPEST OF THE THREE: a stranger's item id would
    # write a funding rule against THEIR spending, which this user's page would then read back
    # through BudgetCalculator as their own bill being paid or unpaid.
    it "refuses a stranger's item and writes nothing" do
      foreign_item = create(:item, category: create(:category, :expense, user: stranger))

      expect { accept(budget: { item_id: foreign_item.id }) }.not_to change(Budget, :count)
      expect(response).to have_http_status(:not_found)
      expect(utilities.reload.pool).to be_nil
    end

    # The line, from the other side: this item is the user's OWN, so the controller must let it
    # through and `Budget#item_must_belong_to_pool` must answer. Scoping the lookup any harder
    # would turn a legible form error into a record that vanished.
    it "answers the user's own item in another category with a 422, not a 404" do
      elsewhere = create(:item, category: create(:category, :expense, user: user, name: "Travel"))

      expect { accept(budget: { item_id: elsewhere.id }) }.not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a stranger's category in the envelope half and writes nothing" do
      foreign = create(:category, :expense, user: stranger)

      expect { accept(envelope: { category_id: foreign.id }) }.not_to change(Pool, :count)
      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.pool).to be_nil
    end

    it "refuses a stranger's account in the envelope half and writes nothing" do
      foreign_account = create(:pool, :account, user: stranger)

      expect { accept(envelope: { account_id: foreign_account.id }) }.not_to change(Pool, :count)
      expect(response).to have_http_status(:not_found)
      expect(utilities.reload.pool).to be_nil
    end

    # Ownership here, shape in the model: this pool IS the user's, it is simply not an account,
    # so `Pool#account_matches_pool_type` answers with a 422 the form can print rather than a 404
    # that makes the user's own record disappear.
    it "answers the user's own non-account pool with a 422, not a 404" do
      own_envelope = create(:pool, :budget_pool, user: user, account: account, name: "Groceries")

      expect { accept(envelope: { account_id: own_envelope.id }) }.not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(utilities.reload.pool).to be_nil
    end

    # A USER WHO HAS NOMINATED NO ACCOUNT is asked rather than written blank: the engine reads
    # `users.default_account_id`, which is nullable, and a budget pool with no account can be
    # funded by no distribution at all.
    it "refuses an envelope with no account and writes nothing" do
      expect { accept(envelope: { account_id: "" }) }.not_to change(Pool, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(utilities.reload.pool).to be_nil
    end

    # THE MUTATION CHECK ON THE TRANSACTION. The pool and the re-point both succeed and the RULE
    # fails, which is the only ordering in which a partial write is possible — and all three are
    # pinned, because a pool with no rule is an envelope nothing ever fills and a re-pointed
    # category with neither silently moves every entry in it into a stranger of an envelope.
    it "writes no pool, no re-point and no rule when the rule itself is refused" do
      expect { accept(budget: { amount: "0" }) }.to not_change(Pool, :count).and not_change(Budget, :count)
      expect(utilities.reload.pool).to be_nil
      expect(response).to have_http_status(:unprocessable_content)
    end

    # THE FOURTH ROW THE ROLLBACK HAS TO RESTORE, and counting cannot see it. The re-point runs
    # `Category#destroy_budget_if_pool_linked` on a `before_validation`, so the cap's DELETE is
    # issued INSIDE the savepoint — but `not_change(Budget, :count)` passes just as happily if the
    # cap were deleted and the rule created, which is a user losing a rule they wrote to a request
    # that failed. The example above deliberately has no cap, so this is the one that tests it,
    # and it names the RECORD rather than a total.
    it "leaves the category's cap standing when the rule is refused" do
      cap = create(:budget, category: utilities, amount: 300)

      expect { accept(budget: { amount: "0" }) }.to not_change(Budget, :count)
      expect(utilities.reload.budget).to eq(cap)
      expect(utilities.pool).to be_nil
    end

    # `pool_type` IS NOT A WIRE PARAMETER. An envelope is a budget pool by definition, and taking
    # the type from the form would let this path hang a funding rule on a brand-new savings goal.
    it "ignores a submitted pool_type" do
      accept(envelope: { pool_type: "savings" })

      expect(user.pools.find_by(name: "Utilities").pool_type).to eq("budget")
    end

    # An envelope half with no category has nothing to re-point, so it is not an envelope half at
    # all — and the rule then has no owner, which `Budget#exactly_one_owner` says legibly.
    it "treats a blank category id as no envelope half" do
      expect { accept(envelope: { category_id: "" }) }.to not_change(Pool, :count).and not_change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # THE MOST LOAD-BEARING CASE ON THIS FLOW, ANSWERED SERVER-SIDE. Several bills in one category
  # share ONE envelope, because `Budget#item_must_belong_to_pool` requires the rule's item to sit
  # in a category pointing at the rule's pool and a category points at exactly one pool.
  describe "a second bill in the same category", :aggregate_failures do
    # The engine's payload switches to `pool_id` reuse by itself once the category is pool-covered
    # — but a page loaded BEFORE the first acceptance still carries the creation half on every one
    # of that category's suggestions. That stale request must ADD to the envelope the first
    # acceptance made, not make a second one and re-point the category away from the first.
    it "reuses the category's envelope when a stale creation half arrives" do
      accept
      internet = create(:item, category: utilities, name: "Internet")

      expect { accept(budget: { amount: "65.00", item_id: internet.id }) }.not_to change(Pool, :count)
      expect(user.pools.where(name: "Utilities").count).to eq(1)
      expect(utilities.reload.pool.budgets.count).to eq(2)
    end

    # REUSE BY NAME, and it is the demo seeds' own shape rather than a hypothetical: the engine
    # names a proposed envelope after the CATEGORY, and a user whose "Utilities" envelope already
    # exists beside an un-pointed "Utilities" category had all three of its bills refused by
    # `Pool`'s name uniqueness. An envelope already called this IS this envelope.
    it "joins an envelope that already carries the proposed name" do
      existing = create(:pool, :budget_pool, user: user, account: account, name: "Utilities")

      expect { accept }.to not_change(Pool, :count).and change(Budget, :count).by(1)
      expect(utilities.reload.pool).to eq(existing)
      expect(existing.budgets.sole.item).to eq(phone)
    end

    # NARROWED TO ENVELOPES. A savings goal by the same name is a different kind of thing, and
    # hanging a monthly bill on someone's holiday fund silently is worse than the uniqueness error
    # — which the user answers by renaming, in the field the form puts right there.
    it "refuses rather than reusing a savings goal of the same name" do
      create(:pool, :savings_pool, user: user, account: account, name: "Utilities")

      expect { accept }.to not_change(Pool, :count).and not_change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(utilities.reload.pool).to be_nil
    end

    # The ordinary reuse payload — `budget[pool_id]` and no envelope half at all — takes the plain
    # `budget.save` path and must land in the same envelope.
    it "adds a rule to an envelope the payload names by id" do
      accept
      internet = create(:item, category: utilities, name: "Internet")
      envelope = utilities.reload.pool

      post budgets_path, params: { budget: bill(amount: "65.00", item_id: internet.id, pool_id: envelope.id) }

      expect(envelope.budgets.count).to eq(2)
    end
  end

  # The READ-shaped half of the same leak: a stranger's item id in the prefill query string would
  # render THEIR item's name on this user's form.
  describe "GET /budgets/new with a prefill" do
    it "refuses a stranger's item id" do
      foreign_item = create(:item, category: create(:category, :expense, user: stranger))

      get new_budget_path, params: { budget: { amount: "10", item_id: foreign_item.id } }

      expect(response).to have_http_status(:not_found)
    end

    # `params.expect` raises ParameterMissing on a bare `/budgets/new`, which is how this form is
    # ordinarily reached — so the absence of the key must be an empty prefill and not a 400.
    it "still renders the plain form with no prefill at all" do
      get new_budget_path

      expect(response).to have_http_status(:ok)
    end
  end

  private

  # A dated-bill proposal's budget half, as the suggestion panel sends it.
  def bill(**overrides)
    {
      amount: "85.00",
      basis: "monthly",
      interval_months: 1,
      anchor_date: Date.current + 1.month,
      item_id: phone.id
    }.merge(overrides)
  end

  # One acceptance. BOTH HALVES ARE NAMED KEYWORDS, deliberately: with a trailing `**rest` a bare
  # `accept(amount: "0")` is parsed as keywords and lands in the ENVELOPE half, which is how the
  # mutation check below first passed against a request that had written all three rows.
  def accept(budget: {}, envelope: {})
    post budgets_path,
         params: {
           budget: bill(**budget),
           envelope: { name: "Utilities", account_id: account.id, category_id: utilities.id }.merge(envelope)
         }
  end
end
