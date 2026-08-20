# frozen_string_literal: true

require "rails_helper"

# ONBOARDING STEP 2 (main-account spec §5): each non-main account is funded with its real
# balance by ONE movement from main — mirroring the transfers that really happened.
RSpec.describe "AccountFundings", type: :request do
  let(:user) { create(:user) }
  let(:main) { create(:pool, :account, user: user, name: "Main") }
  let(:ally) { create(:pool, :account, user: user, name: "Ally") }

  before do
    user.update!(default_account: main)
    sign_in user, scope: :user
  end

  it "moves the entered balance from main to the account", :aggregate_failures do
    post account_fundings_path,
         params: { account_funding: { account_id: ally.id, amount: 1200.50 } }

    movement = PoolMovement.order(:created_at).last
    expect(movement.from_pool).to eq(main)
    expect(movement.to_pool).to eq(ally)
    expect(movement.amount).to eq(1200.50)
    expect(movement).to be_kind_transfer
    expect(response).to redirect_to(root_path)
  end

  it "refuses funding main from itself and a foreign account", :aggregate_failures do
    post account_fundings_path,
         params: { account_funding: { account_id: main.id, amount: 10 } }
    expect(response).to have_http_status(:unprocessable_content)

    foreign = create(:pool, :account, user: create(:user))
    post account_fundings_path,
         params: { account_funding: { account_id: foreign.id, amount: 10 } }
    expect(response).to have_http_status(:not_found)
  end

  # AN ACCOUNT MAY BE FUNDED ONLY ONCE (fix round 1): a double-click or a resubmit before the
  # redirect lands must not write a second movement — the guard is asked again server-side,
  # inside a lock, rather than trusted from whatever the card looked like when it rendered.
  it "refuses to fund an account a second time", :aggregate_failures do
    post account_fundings_path, params: { account_funding: { account_id: ally.id, amount: 500 } }

    post account_fundings_path, params: { account_funding: { account_id: ally.id, amount: 300 } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(PoolMovement.where(to_pool: ally).count).to eq(1)
    expect(ally.calculator.balance).to eq(500)
  end
end
