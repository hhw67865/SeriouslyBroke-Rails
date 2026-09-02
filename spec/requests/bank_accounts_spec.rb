# frozen_string_literal: true

require "rails_helper"

# The wire contract of the Home add-account door: `bank_account[name]` is the ONLY writable
# attribute, and the pool type is a server fact. Pinned here rather than in a system spec —
# no user submits a crafted param through Chrome, and this layer can see the status codes.
RSpec.describe "BankAccounts", type: :request do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before { sign_in user, scope: :user }

  describe "POST /bank_accounts" do
    it "creates an account pool from the name alone", :aggregate_failures do
      post bank_accounts_path, params: { bank_account: { name: "Ally Savings" } }

      pool = user.pools.find_by(name: "Ally Savings")
      expect(pool).to be_pool_type_account
      expect(response).to redirect_to(root_path)
    end

    # ONE CRAFTED POST, ASKED TWICE. Every attribute a Pool carries that a caller could want is on
    # it at once, because a permit list is only proven by the params it drops TOGETHER — a request
    # that smuggled one of these would smuggle the rest. The two examples below split what the
    # dropping protects, not the request: the first is about what the pool IS and where it sits,
    # the second about the two figures the budget reads off it.
    def post_crafted
      post bank_accounts_path,
           params: {
             bank_account: {
               name: "Sneaky",
               pool_type: "savings",
               account_id: checking.id,
               priority: 9,
               target_amount: 500
             }
           }

      user.pools.find_by(name: "Sneaky")
    end

    it "keeps the pool's type and its containment the server's own", :aggregate_failures do
      sneaky = post_crafted

      expect(sneaky).to be_pool_type_account
      expect(sneaky.account_id).to be_nil
    end

    it "drops the ordering and the target a param could carry", :aggregate_failures do
      sneaky = post_crafted

      expect(sneaky.priority).to eq(0)
      expect(sneaky.target_amount).to be_nil
    end

    it "answers 422 with nothing written when the name is refused", :aggregate_failures do
      post bank_accounts_path, params: { bank_account: { name: checking.name.downcase } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.pools.count).to eq(1)
    end

    it "makes the first account the main account, and only the first", :aggregate_failures do
      user.update!(default_account: nil)
      post bank_accounts_path, params: { bank_account: { name: "First" } }
      expect(user.reload.default_account.name).to eq("First")

      post bank_accounts_path, params: { bank_account: { name: "Second" } }
      expect(user.reload.default_account.name).to eq("First")
    end
  end

  # ── THE RENAME AND DELETE DOORS, ARRIVED FROM `spec/requests/pools_spec.rb` (Task 7).
  #
  # That file is deleted with the route it pinned. Its two examples described the pool form's own
  # contract — "assigns the pool type, the parent account and the priority" on POST /pools, and
  # "moves a pool to another account" on PATCH — and neither describes anything that still exists:
  # there is one kind of pool now, it sits inside nothing, and `priority` moved onto the category.
  # What survives is that an account can be renamed and deleted, which is the half of the pool
  # edit screen this resource absorbed.
  describe "PATCH /bank_accounts/:id" do
    def patch_crafted
      other = create(:pool, :account, user: user, name: "Ally")

      patch bank_account_path(checking),
            params: {
              bank_account: {
                name: "Checking",
                pool_type: "savings",
                account_id: other.id,
                priority: 9,
                target_amount: 500
              }
            }
    end

    it "renames the account", :aggregate_failures do
      patch bank_account_path(checking), params: { bank_account: { name: "Everyday Checking" } }

      expect(checking.reload.name).to eq("Everyday Checking")
      expect(response).to redirect_to(root_path)
    end

    # THE SAME CRAFTED PAYLOAD AS THE CREATE DOOR ABOVE, ON THE OTHER VERB. A permit list narrowed
    # for `create` and forgotten for `update` is the ordinary way this contract comes apart, and
    # `pool_type` is the one that matters: a "bank account" talked into `savings` would then fail
    # the database's `pools_account_matches_pool_type` CHECK on its next save, and its required
    # target would never have been asked for.
    it "keeps everything but the name the server's own", :aggregate_failures do
      patch_crafted

      checking.reload
      expect(checking).to be_pool_type_account
      expect(checking.account_id).to be_nil
      expect([checking.priority, checking.target_amount]).to eq([0, nil])
    end

    it "answers 422 with nothing written when the name is refused", :aggregate_failures do
      patch bank_account_path(checking), params: { bank_account: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(checking.reload.name).to eq("Checking")
    end

    # THE SCOPE IS `current_user.pools.accounts`, AND BOTH HALVES ARE PINNED. A stranger's id is
    # the ordinary 404; a NON-ACCOUNT pool of the user's own is the half the `.accounts` clause
    # adds, and it is what keeps a route named `bank_accounts` from being the app's last general
    # pool editor.
    it "404s on another user's account", :aggregate_failures do
      stranger = create(:pool, :account, user: create(:user), name: "Theirs")

      patch bank_account_path(stranger), params: { bank_account: { name: "Mine" } }

      expect(response).to have_http_status(:not_found)
      expect(stranger.reload.name).to eq("Theirs")
    end

    it "404s on a pool of this user's that is not an account", :aggregate_failures do
      envelope = create(:pool, :budget_pool, user: user, account: checking, name: "Groceries")

      patch bank_account_path(envelope), params: { bank_account: { name: "Renamed" } }

      expect(response).to have_http_status(:not_found)
      expect(envelope.reload.name).to eq("Groceries")
    end
  end

  describe "DELETE /bank_accounts/:id" do
    it "deletes the account", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")

      delete bank_account_path(ally)

      expect(user.pools.find_by(name: "Ally")).to be_nil
      expect(response).to redirect_to(root_path)
    end

    # THE REFUSAL IS REPORTED, NOT SWALLOWED. `Pool has_many :categories, dependent:
    # :restrict_with_error` halts the callback chain and writes a sentence onto `:base` rather
    # than raising, so a controller that ignored `#destroy`'s return value would redirect with
    # "deleted." over a row still sitting in the database.
    #
    # THE MAIN ACCOUNT IS THE ONE UNDER TEST, and it has to be: `Category#pool_must_be_reachable`
    # lets a category point only at the user's default account, so it is the only account a
    # category can still be blocking.
    it "refuses while a category still points at it, and says so", :aggregate_failures do
      create(:category, :expense, user: user, name: "Groceries", pool: checking)

      delete bank_account_path(checking)

      expect(user.pools.find_by(name: "Checking")).to be_present
      expect(flash[:alert]).to be_present
    end
  end
end
