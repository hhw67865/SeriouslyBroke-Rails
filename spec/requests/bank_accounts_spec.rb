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
end
