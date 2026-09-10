# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Accounts" do
  let(:user) { create(:user) }

  # `scope:` explicitly: routes are loaded lazily, so Devise's mappings are still empty
  # when this runs and it has nothing to infer the scope from.
  before { sign_in user, scope: :user }

  it "opens an account with its balance and makes the first one main", :aggregate_failures do
    post accounts_path, params: { account: { name: "Checking", balance: "250.00" } }

    expect(response).to redirect_to(root_path)
    account = user.reload.main_account
    expect(account.name).to eq("Checking")
    expect(account.balance).to eq(250)
  end

  it "re-renders home with the refusal", :aggregate_failures do
    create(:account, user: user, name: "Checking")

    post accounts_path, params: { account: { name: "checking", balance: "" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("has already been taken")
  end

  it "renames and corrects a balance", :aggregate_failures do
    account = create(:account, user: user, name: "Old", opening_balance: 10)

    patch account_path(account), params: { account: { name: "New", balance: "99.5" } }

    expect(response).to redirect_to(root_path)
    expect(account.reload).to have_attributes(name: "New", opening_balance: 99.5)
  end

  # The rename and the balance are one act: a refused figure must not leave the new name behind.
  it "keeps the old name when the balance is refused", :aggregate_failures do
    account = create(:account, user: user, name: "Old", opening_balance: 10)

    patch account_path(account), params: { account: { name: "New", balance: "abc" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("is not a number")
    expect(account.reload).to have_attributes(name: "Old", opening_balance: 10)
  end

  it "deletes a non-main account and refuses main", :aggregate_failures do
    main = create(:account, user: user)
    other = create(:account, user: user)

    delete account_path(other)
    expect(Account.exists?(other.id)).to be(false)

    delete account_path(main)
    expect(Account.exists?(main.id)).to be(true)
    expect(flash[:alert]).to include("main account")
  end

  # 404 rather than a raise: this app's test environment rescues, so the refusal is the response.
  it "never touches another user's account", :aggregate_failures do
    other = create(:account)

    delete account_path(other)

    expect(response).to have_http_status(:not_found)
    expect(Account.exists?(other.id)).to be(true)
  end
end
