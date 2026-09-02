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

    movement = AccountMovement.order(:created_at).last
    expect(movement.from_pool).to eq(main)
    expect(movement.to_pool).to eq(ally)
    expect(movement.amount).to eq(1200.50)
    expect(movement).to be_kind_transfer
    expect(response).to redirect_to(root_path)
  end

  # LOW-1 (fix round 2): with the funded-account guard now keyed on `awaiting_funding?` rather
  # than a second "already funded" spelling, main-from-itself is left to `AccountMovement`'s own
  # `pools_must_differ` validation — the message pinned here proves the refusal still names the
  # REAL reason (same pool on both ends) rather than the money-based "already holds money" the
  # funded-account guard uses, which would be false of a main account holding nothing.
  it "refuses funding main from itself and a foreign account", :aggregate_failures do
    post account_fundings_path,
         params: { account_funding: { account_id: main.id, amount: 10 } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must differ from the source account")

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
    expect(AccountMovement.where(to_pool: ally).count).to eq(1)
    expect(ally.balance).to eq(500)
  end

  # TWO EXAMPLES ARE DELETED HERE WITH THE SHAPE THEY PLANTED (two-ledger spec §5, Task 8):
  # "funds an account that already holds an envelope but no money" (MED-1) and "refuses to fund an
  # account whose envelopes hold all of its money" (I-1). Both turned on an ENVELOPE INSIDE an
  # account — the first proved the gate read the buffer rather than `pools.empty?`, the second that
  # an account emptied into its own envelopes still counts as funded. Nothing sits inside an account
  # now, so neither fixture can be built and neither distinction exists: `#awaiting_funding?` reads
  # the account's balance, full stop, and "refuses to fund an account a second time" above is the
  # whole of what it can get wrong.

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
