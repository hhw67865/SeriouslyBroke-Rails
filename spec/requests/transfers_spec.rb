# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Transfers" do
  let(:user) { create(:user) }
  let!(:main) { create(:account, user: user, name: "Checking", opening_balance: 1_000) }
  let!(:savings) { create(:account, user: user, name: "Savings", opening_balance: 100) }

  before { sign_in user, scope: :user }

  it "moves money and redirects with a notice", :aggregate_failures do
    post transfers_path, params: { transfer: { from_account_id: main.id, to_account_id: savings.id, amount: "40.00", date: Date.current } }

    expect(response).to redirect_to(savings_path)
    follow_redirect!
    expect(response.body).to include("Transferred $40.00 from Checking to Savings.")
    expect(Transfer.count).to eq(1)
  end

  it "redirects to Home when the form carried return: home", :aggregate_failures do
    post transfers_path, params: { transfer: { from_account_id: main.id, to_account_id: savings.id, amount: "40.00", date: Date.current }, return: "home" }

    expect(response).to redirect_to(root_path)
    expect(Transfer.count).to eq(1)
  end

  it "re-renders the savings page at 422 on a refusal", :aggregate_failures do
    post transfers_path, params: { transfer: { from_account_id: main.id, to_account_id: main.id, amount: "40.00", date: Date.current } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("must differ from the source account")
    expect(Transfer.count).to eq(0)
  end

  it "re-renders Home at 422 on a refusal when the form carried return: home", :aggregate_failures do
    post transfers_path, params: { transfer: { from_account_id: main.id, to_account_id: main.id, amount: "40.00", date: Date.current }, return: "home" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("data-tiles")
    expect(Transfer.count).to eq(0)
  end

  it "deletes a transfer and returns to Savings", :aggregate_failures do
    transfer = create(:transfer, from_account: main, to_account: savings, amount: 40, date: Date.current)

    delete transfer_path(transfer)

    expect(response).to redirect_to(savings_path)
    expect(Transfer.exists?(transfer.id)).to be(false)
  end

  it "deletes a transfer and returns to Activity when the form carried return: activity", :aggregate_failures do
    transfer = create(:transfer, from_account: main, to_account: savings, amount: 40, date: Date.current)

    delete transfer_path(transfer, return: "activity")

    expect(response).to redirect_to(activity_path)
    follow_redirect!
    expect(response.body).to include("Removed the transfer of $40.00 from Checking to Savings.")
  end

  it "never deletes another user's transfer" do
    foreign_transfer = create(:transfer)

    delete transfer_path(foreign_transfer)

    expect(response).to have_http_status(:not_found)
  end
end
