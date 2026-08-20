# frozen_string_literal: true

require "rails_helper"

# HIGH-1 (fix round 2, main-account spec §5): `users.default_account_id` nullifies when the
# main account is deleted (`add_foreign_key :users, :pools, column: :default_account_id,
# on_delete: :nullify`), and the fund-account card used to read `main_account.name`
# unconditionally — a user left with no main account 500'd on Home with no door back in.
# `HomePresenter#awaiting_funding?` now requires a main account before it offers the card to
# anyone at all, which is what this pins: a request-spec status code, because Capybara's
# Selenium driver cannot see one.
RSpec.describe "Home", type: :request do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let!(:ally) { create(:pool, :account, user: user, name: "Ally") }

  before { sign_in user, scope: :user }

  it "renders with no funding card, and the add-account door, when there is no main account", :aggregate_failures do
    user.update!(default_account: nil)

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(checking.name, ally.name)
    expect(response.body).not_to include("Real balance today")
    expect(response.body).to include("Add a bank account")
  end

  # ONBOARDING STEP 3'S RENDER GATE (main-account spec §5, fix round 1 — MED-1): three request
  # examples for `HomePresenter#awaiting_opening_balance?`, mirroring this file's own precedent —
  # a status/body assertion rather than a system spec, because the gate is a server decision the
  # response body can pin directly. `checking` is main here (the `:account` trait's own
  # after(:create) makes the first account a fixture mints for a user their default_account).
  #
  # "real balance today", LOWERCASE r: the opening-balance card's own label is "Main's real
  # balance today", while `_fund_account`'s label is the capitalised "Real balance today" — the
  # ally card renders in these examples too (an empty, non-main account is always awaiting
  # funding), and `String#include?` is case-sensitive, so the lowercase substring names this
  # card alone without colliding with its sibling.
  it "renders the opening-balance card only under main's own section", :aggregate_failures do
    get root_path

    expect(response.body).to include("real balance today")
    expect(response.body).to include("Set #{checking.name}")
    expect(response.body).not_to include("Set #{ally.name}")
  end

  it "no longer renders the opening-balance card once the latch closes", :aggregate_failures do
    income = create(:category, :income, user: user, pool: checking, name: "Pay")
    create(:entry, item: create(:item, category: income), amount: 300, date: Date.current)
    post opening_balance_path, params: { opening_balance: { actual: 1000 } }

    get root_path

    expect(response.body).not_to include("real balance today")
    expect(response.body).not_to include("Set #{checking.name}")
  end

  it "renders no opening-balance card when there is no main account", :aggregate_failures do
    user.update!(default_account: nil)

    get root_path

    expect(response.body).not_to include("real balance today")
    expect(response.body).not_to include("Set #{checking.name}")
  end
end
