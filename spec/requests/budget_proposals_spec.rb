# frozen_string_literal: true

require "rails_helper"

# §8'S ACCEPT FLOW: one form, one POST, one transaction.
#
# WHAT THE FLOW LOST (two-ledger spec §3/§5). It used to arrive with an ENVELOPE HALF beside the
# rule — a pool to find-or-create, an account to fund it from, and a category to RE-POINT at it —
# and this file was mostly the ownership questions those three ids asked. There is no envelope: the
# category holds the money, `budget[category_id]` is the rule's owner and is pinned in
# spec/requests/budgets_spec.rb like any other owner parameter, and the whole `envelope[...]`
# surface is deleted. TEN EXAMPLES GO WITH IT — a stranger's account, the user's own non-account
# pool, a blank account, a submitted `pool_type`, a blank `envelope[category_id]`, the stale
# creation half, the join-by-name pair, the savings-goal refusal and the `budget[pool_id]` reuse —
# because each named a branch of a cascade that no longer exists.
#
# WHAT IT KEPT IS THE PART THAT WAS ALWAYS THE POINT: accepting is more than one write, and a
# half-done acceptance is the worst outcome available. The second write is now the `funded_since`
# stamp — the date the category starts holding its own money (§4) — and the mutation check below
# pins that a refused rule leaves it unwritten.
#
# A REQUEST SPEC because these are answers to REQUESTS THE UI CANNOT MAKE: a stranger's item id, an
# item of the user's own in the wrong category, and a rule refused after the stamp. The browser
# path is covered in spec/system/budget_page/suggestions_spec.rb.
RSpec.describe "Budget proposals", type: :request do
  let(:user) { create(:user) }
  let(:stranger) { create(:user) }
  # HOLDING NOTHING YET, which is the state a proposing suggestion is about: `funded_since` is nil,
  # so the category's spending drains available and accepting is what starts it holding.
  let(:utilities) { create(:category, :expense, user: user, name: "Utilities") }
  let(:phone) { create(:item, category: utilities, name: "Phone") }

  # `scope:` explicitly, as the other request specs do: Devise's mappings are populated when the
  # routes are drawn, and routes load lazily.
  #
  # THE FIXTURES ARE FORCED HERE, and that is not tidiness: `phone` is created lazily by the first
  # reference to it, which is inside `#accept` — so inside the `expect { }` block, where the
  # category it mints would be counted as something this request created.
  before do
    phone
    sign_in user, scope: :user
  end

  describe "POST /budgets accepting a proposal", :aggregate_failures do
    # THE REACH DIRECTION FOR BOTH WRITES AT ONCE. Without it, every "it refuses" example below
    # would pass just as well against a flow that silently wrote nothing at all.
    it "stamps funded_since on the category and writes the rule" do
      expect { accept }.to change(Budget, :count).by(1)

      expect(utilities.reload.funded_since).to eq(Date.current)
      expect(utilities.budgets.sole.item).to eq(phone)
      expect(response).to redirect_to(budget_page_path)
    end

    # THE STAMP IS "WHEN IT STARTED", NOT "WHEN IT WAS LAST TOUCHED" — the state the SECOND rule in
    # a category is in, and the one place a re-stamp would quietly move money. Pushing the start
    # date forward to today would hand the category's own recent spending back to available on the
    # strength of a rule the user was adding to it.
    it "leaves an earlier funded_since alone when a second rule arrives" do
      utilities.update!(funded_since: Date.current - 90.days)
      internet = create(:item, category: utilities, name: "Internet")

      accept(item_id: internet.id, amount: "65.00")

      expect(utilities.reload.funded_since).to eq(Date.current - 90.days)
      expect(utilities.budgets.count).to eq(1)
    end

    # §7a'S CLASS, AND THE SHARPEST OF ITS APPEARANCES: a stranger's item id would write a funding
    # rule against THEIR spending, which this user's page would then read back through
    # BudgetCalculator as their own bill being paid or unpaid.
    it "refuses a stranger's item and writes nothing" do
      foreign_item = create(:item, category: create(:category, :expense, user: stranger))

      expect { accept(item_id: foreign_item.id) }.not_to change(Budget, :count)
      expect(response).to have_http_status(:not_found)
      expect(utilities.reload.funded_since).to be_nil
    end

    # The line, from the other side: this item is the user's OWN, so the controller must let it
    # through and `Budget#item_must_belong_to_category` must answer. Scoping the lookup any harder
    # would turn a legible form error into a record that vanished.
    it "answers the user's own item in another category with a 422, not a 404" do
      elsewhere = create(:item, category: create(:category, :expense, user: user, name: "Travel"))

      expect { accept(item_id: elsewhere.id) }.not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    # THE MUTATION CHECK ON THE TRANSACTION, and it is the whole reason `BudgetProposal` is still a
    # class. The stamp succeeds and the RULE fails, which is the only ordering in which a partial
    # write is possible — and a `funded_since` with no rule is the worse half: it silently moves
    # every future entry in that category off available and onto the category's own holdings, for a
    # rule the user never got.
    it "writes no funded_since when the rule itself is refused" do
      expect { accept(amount: "0") }.not_to change(Budget, :count)
      expect(utilities.reload.funded_since).to be_nil
      expect(response).to have_http_status(:unprocessable_content)
    end

    # TWO BILLS IN ONE CATEGORY ARE TWO RULES ON ONE OWNER — the case that needed a whole reuse
    # cascade in the pool era (an envelope to find-or-create, by id and then by name) and needs
    # nothing at all now. It is asserted because it was the flow's most load-bearing requirement,
    # not because anything special happens.
    it "adds a second rule to the same category" do
      accept
      internet = create(:item, category: utilities, name: "Internet")

      expect { accept(item_id: internet.id, amount: "65.00") }.to change(Budget, :count).by(1)
      expect(utilities.reload.budgets.map { |rule| rule.item.name }).to contain_exactly("Phone", "Internet")
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

    it "refuses a stranger's category id" do
      foreign = create(:category, :expense, user: stranger)

      get new_budget_path, params: { budget: { amount: "10", category_id: foreign.id } }

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

  # ONE ACCEPTANCE, as the suggestion panel sends it: a dated bill's whole shape in one `budget`
  # hash, the owner included. The `envelope:` half the panel used to send beside it is gone, and
  # with it the keyword-splitting `#accept(budget:, envelope:)` this helper needed to keep the two
  # apart.
  def accept(**overrides)
    post budgets_path,
         params: {
           budget: {
             amount: "85.00",
             basis: "monthly",
             interval_months: 1,
             anchor_date: Date.current + 1.month,
             item_id: phone.id,
             category_id: utilities.id
           }.merge(overrides)
         }
  end
end
