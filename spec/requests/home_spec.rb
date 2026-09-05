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
    AccountMovement.create!(from_pool: checking, to_pool: ally, amount: 500, date: Date.current, kind: :transfer)

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
    income = create(:category, :income, user: user, name: "Pay")
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

  # ** "TODAY" ON HOME IS THE OWNER'S CALENDAR DAY, NOT UTC'S (fix round 2 — LOW-1). **
  #
  # `ClaimCalculator#overdue?` is `next_due_on < today` and nothing else (fix round 1 — MED-1), so
  # WHICH day `today` is now decides, on its own, whether a bill's row says `overdue · was Sep 2` or
  # says nothing at all. A UTC evening is already tomorrow in Tokyo and still yesterday in Los
  # Angeles, and the two owners below are frozen at instants nine hours apart that straddle Sep 2 —
  # the one place a wrong reader is visible rather than merely wrong.
  #
  # THESE ARE REQUEST EXAMPLES BECAUSE THE ZONE IS A REQUEST FACT TWICE OVER: `HomeController` picks
  # the day, and `ApplicationController`'s `around_action :use_user_timezone` is what a presenter
  # built outside a request does not get. Only a real `get root_path` exercises both.
  #
  # NO LAZY `Date.current` IN THE FIXTURE. Every date here is a literal computed by hand from the
  # frozen instant, and the rule is created INSIDE the example (under `travel_to`) because
  # `ClaimCalculator#rule_born_on` re-zones `budgets.created_at` and would otherwise open the walk
  # on a day the clock has not reached.
  describe "the day a claim is read against", :aggregate_failures do
    include ActiveSupport::Testing::TimeHelpers

    # Sep 2, anchored monthly: the occurrence is unpaid, so `#next_due_on` is Sep 2 for both owners
    # and only `today` differs between them.
    let(:due) { Date.new(2026, 9, 2) }
    let(:user) do
      create(:user, timezone: zone, period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 1))
    end

    before { travel_to now }

    def plant_overdue_bill
      income = create(:category, :income, user: user, name: "Pay")
      create(:entry, item: create(:item, category: income), amount: 2_000, date: Time.utc(2026, 8, 1, 12, 0, 0))
      utilities = create(
        :category, :expense, user: user, name: "Utilities", priority: 1, funded_since: Date.new(2026, 1, 1)
      )
      create(:budget, category: utilities, amount: 1_200, interval_months: 1, anchor_date: due)
    end

    # 22:00 UTC on Sep 2 is 07:00 on Sep 3 in Tokyo. The owner's day has turned; the bill is a day
    # past. Reading UTC's date here would keep the strip silent for the nine hours the user most
    # needs it.
    context "with an owner whose day has already turned" do
      let(:zone) { "Asia/Tokyo" }
      let(:now) { Time.utc(2026, 9, 2, 22, 0, 0) }

      it "calls a bill due yesterday overdue" do
        plant_overdue_bill

        get root_path

        expect(response.body).to include("overdue · was Sep 2")
        expect(response.body).not_to include("next due Sep 2")
      end
    end

    # THE OTHER DIRECTION, WHICH IS THE ONE THAT CRIES WOLF. 02:00 UTC on Sep 3 is 19:00 on Sep 2 in
    # Los Angeles: the owner's day IS the due day, and a bill due today is a thing to do rather than
    # a thing missed (`#overdue?` is strict). Reading UTC's date would call it overdue while the
    # user's own calendar still says Sep 2.
    context "with an owner whose day has not turned yet" do
      let(:zone) { "America/Los_Angeles" }
      let(:now) { Time.utc(2026, 9, 3, 2, 0, 0) }

      # ** THE ROW'S COPY CHANGED WITH THE BLOCKS AND THE ASSERTION FOLLOWS IT (two-shapes §3). **
      # This read `next due Sep 2` — `HomeHelper#claim_schedule`, which Home no longer renders. A
      # block row says the date and the STATE (`#when_words`), so the same fact about the same bill
      # is now `Sep 2 · ready`: the day has not passed on this owner's calendar and the money is
      # there. It is a sharper pin than the old one, which could not tell a funded bill from an
      # empty one.
      it "leaves a bill due today out of the strip" do
        plant_overdue_bill

        get root_path

        expect(response.body).to include("Sep 2 · ready")
        expect(response.body).not_to include("overdue")
      end
    end
  end
end
