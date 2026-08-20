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

  # I-1 (final whole-branch review, main-account spec §5): the card's gate is the account's FAMILY
  # total, not its buffer. `AllocationCommitter` calls a waterfall that leaves an account's buffer
  # at exactly $0 "the ordinary shape of a short period", so a funded account whose envelopes hold
  # every dollar it has used to get the card back — asking a user who had already funded it to
  # "match your bank statement" a second time, which puts BOTH accounts wrong against their banks
  # by whatever they typed. Planted literals: $500 funded in, $500 allocated out, buffer $0,
  # total $500. The two balance assertions are what make the third one about the right shape.
  it "offers no funding card on an account whose envelopes hold all of its money", :aggregate_failures do
    vacation = create(:pool, :budget_pool, user: user, account: ally, name: "Vacation")
    PoolMovement.create!(from_pool: checking, to_pool: ally, amount: 500, date: Date.current, kind: :transfer)
    PoolMovement.create!(from_pool: ally, to_pool: vacation, amount: 500, date: Date.current, kind: :allocation)

    get root_path

    expect(ally.calculator.balance).to eq(0)
    expect(ally.total).to eq(500)
    expect(response.body).not_to include("Real balance today")
  end

  # THE OTHER DIRECTION OF THE SAME GATE (MED-1, unmoved by I-1): an EMPTY envelope is not money,
  # so an account holding one and nothing else still totals zero and still gets the card. Pinned
  # here beside its opposite so a future tightening cannot close one without noticing the other.
  it "still offers the card on an account holding only an empty envelope", :aggregate_failures do
    create(:pool, :budget_pool, user: user, account: ally, name: "Vacation")

    get root_path

    expect(ally.total).to eq(0)
    expect(response.body).to include("Real balance today")
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
