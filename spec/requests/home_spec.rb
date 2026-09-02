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

  # ── DELETED (Task 6): "offers no funding card on an account whose envelopes hold all of its
  # money". It pinned the I-1 ruling — the card's gate was the account's FAMILY total (`Pool#total`,
  # unallocated cash plus every envelope inside it) rather than its bare buffer, because a
  # distribution that drained an account's buffer to exactly $0 brought the card back under a fully
  # funded account. Nothing is housed inside an account under the two-ledger model: a category holds
  # its own money and lives nowhere (spec §2), so the buffer and the family total are one figure,
  # `AccountLedger#balance_of`, and there is no shape in which they can disagree. The fixture the
  # example planted — an envelope inside Ally holding every dollar Ally has — cannot exist.
  #
  # MED-1'S OWN DIRECTION IS WHAT SURVIVES, re-asked below on the two shapes that are left: an
  # account nothing has moved into gets the card, and one a movement has funded does not. Money is
  # still the only signal.
  it "offers the funding card on an account nothing has moved money into", :aggregate_failures do
    get root_path

    expect(user.reload.default_account).to eq(checking)
    expect(AccountLedger.new(user).balance_of(ally)).to eq(0)
    expect(response.body).to include("Real balance today")
  end

  it "offers no funding card once a movement has funded the account", :aggregate_failures do
    PoolMovement.create!(from_pool: checking, to_pool: ally, amount: 500, date: Date.current, kind: :transfer)

    get root_path

    expect(AccountLedger.new(user).balance_of(ally)).to eq(500)
    expect(response.body).not_to include("Real balance today")
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
