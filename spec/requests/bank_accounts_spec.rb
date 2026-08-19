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

    it "drops every crafted attribute a param could carry", :aggregate_failures do
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

      sneaky = user.pools.find_by(name: "Sneaky")
      expect(sneaky).to be_pool_type_account
      expect(sneaky.account_id).to be_nil
      expect(sneaky.priority).to eq(0)
      expect(sneaky.target_amount).to be_nil
    end

    it "answers 422 with nothing written when the name is refused", :aggregate_failures do
      post bank_accounts_path, params: { bank_account: { name: checking.name.downcase } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.pools.count).to eq(1)
    end
  end
end
