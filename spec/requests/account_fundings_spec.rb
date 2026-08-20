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

  # LOW-1 (fix round 2): with the funded-account guard now keyed on `awaiting_funding?` rather
  # than a second "already funded" spelling, main-from-itself is left to `PoolMovement`'s own
  # `pools_must_differ` validation — the message pinned here proves the refusal still names the
  # REAL reason (same pool on both ends) rather than the money-based "already holds money" the
  # funded-account guard uses, which would be false of a main account holding nothing.
  it "refuses funding main from itself and a foreign account", :aggregate_failures do
    post account_fundings_path,
         params: { account_funding: { account_id: main.id, amount: 10 } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must differ from the source pool")

    foreign = create(:pool, :account, user: create(:user))
    post account_fundings_path,
         params: { account_funding: { account_id: foreign.id, amount: 10 } }
    expect(response).to have_http_status(:not_found)
  end

  # AN ACCOUNT MAY BE FUNDED ONLY ONCE (fix round 1, reworded round 2 — MED-1/2/3): a double-click
  # or a resubmit before the redirect lands must not write a second movement — the guard is asked
  # again server-side, inside a lock, rather than trusted from whatever the card looked like when
  # it rendered. The message states the real rule, "already holds money", not the narrower "only
  # be funded once" round 1 shipped — the account genuinely CAN be funded again once its buffer
  # returns to zero, which round 1's wording denied.
  it "refuses to fund an account a second time", :aggregate_failures do
    post account_fundings_path, params: { account_funding: { account_id: ally.id, amount: 500 } }

    post account_fundings_path, params: { account_funding: { account_id: ally.id, amount: 300 } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("already holds money")
    expect(PoolMovement.where(to_pool: ally).count).to eq(1)
    expect(ally.calculator.balance).to eq(500)
  end

  # MED-1 (fix round 2): an envelope created before its account is ever funded is still "awaiting
  # funding" — the gate reads the buffer alone, not `pools.empty?`. This was the crafted-POST
  # repro that used to 422 an account that in fact held zero dollars; it is now the positive case.
  it "funds an account that already holds an envelope but no money", :aggregate_failures do
    create(:pool, :budget_pool, user: user, account: ally, name: "Groceries")

    post account_fundings_path, params: { account_funding: { account_id: ally.id, amount: 400 } }

    expect(response).to redirect_to(root_path)
    expect(ally.calculator.balance).to eq(400)
  end

  # I-1 (final whole-branch review): the SAME predicate guards the write, so the double-funding the
  # card used to invite is refused here too. An account funded once and then allocated to the penny
  # has a buffer of exactly $0 — the shape a distribution produces on any short period — and the
  # old buffer-only gate read that as "never funded" and let a second movement through. Planted
  # literals: $500 in, $500 into the envelope, then a $500 second attempt that must not land.
  it "refuses to fund an account whose envelopes hold all of its money", :aggregate_failures do
    vacation = create(:pool, :budget_pool, user: user, account: ally, name: "Vacation")
    post account_fundings_path, params: { account_funding: { account_id: ally.id, amount: 500 } }
    PoolMovement.create!(from_pool: ally, to_pool: vacation, amount: 500, date: Date.current, kind: :allocation)

    post account_fundings_path, params: { account_funding: { account_id: ally.id, amount: 500 } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("already holds money")
    expect(PoolMovement.where(to_pool: ally, kind: :transfer).count).to eq(1)
    expect(ally.calculator.balance).to eq(0)
    expect(ally.total).to eq(500)
  end

  # LOW-3 (fix round 2): the amount input now carries `min="0.01"`, so a zero amount is blocked
  # client-side and can only be exercised — and its retained value proven — through a direct POST.
  it "refuses a zero amount and keeps it on the card", :aggregate_failures do
    post account_fundings_path, params: { account_funding: { account_id: ally.id, amount: 0 } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must be greater than 0")
    amount_field = response.body[/<input[^>]*id="account_funding_amount"[^>]*>/]
    expect(amount_field).to include('value="0"')
  end
end
