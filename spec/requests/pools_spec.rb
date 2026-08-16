# frozen_string_literal: true

require "rails_helper"

# A strong-parameter list is a wire contract, and the form is only one client of it. The
# form now renders pool_type, account and priority, and system specs drive them — but these
# examples pin the contract itself, at the layer where a param silently dropped back to its
# default looks exactly like a param that was never sent, and independently of whatever
# fields the view happens to render this week.
RSpec.describe "Pools", type: :request do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }

  # `scope:` explicitly, as the system specs do: Devise's mappings are populated when the
  # routes are drawn, and routes load lazily, so inferring the scope from the record can
  # fail before the first request in the process.
  before { sign_in user, scope: :user }

  describe "POST /pools" do
    let(:envelope_params) do
      {
        pool: {
          name: "Groceries",
          pool_type: "budget",
          account_id: checking.id,
          priority: 3,
          start_date: Date.new(2026, 2, 6)
        }
      }
    end

    it "assigns the pool type, the parent account and the priority", :aggregate_failures do
      post pools_path, params: envelope_params

      groceries = user.pools.find_by(name: "Groceries")

      expect(groceries).to be_present
      expect(groceries).to be_pool_type_budget
      expect(groceries.account).to eq(checking)
      expect(groceries.priority).to eq(3)
    end
  end

  describe "PATCH /pools/:id" do
    it "moves a pool to another account" do
      other = create(:pool, :account, user: user, name: "Savings Account")
      groceries = create(:pool, :budget_pool, user: user, account: checking, name: "Groceries")

      patch pool_path(groceries), params: { pool: { account_id: other.id } }

      expect(groceries.reload.account).to eq(other)
    end
  end
end
