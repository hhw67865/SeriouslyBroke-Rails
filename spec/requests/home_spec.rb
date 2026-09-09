# frozen_string_literal: true

require "rails_helper"

# ** THE ONE ONBOARDING GATE, ASKED THROUGH A REAL RESPONSE (account-openings spec §3). **
# `HomePresenter#awaiting_opening?` decides whether an account gets a row in the "Your accounts" card
# or a finished card behind the accounts line, and it is a SERVER decision the response body pins
# directly — which is why these are request examples and not system ones.
#
# ** THE HIGH-1 GUARD SURVIVES ITS OWN CARD. ** `users.default_account_id` nullifies when the main
# account is deleted (`on_delete: :nullify`), and onboarding step 2's card used to read
# `main_account.name` unconditionally — a user left with no main account 500'd on Home with no door
# back in. The card is deleted; the state it 500'd on is still reachable, so the first example below
# is the same guard on the screen that replaced it.
RSpec.describe "Home", type: :request do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let!(:ally) { create(:pool, :account, user: user, name: "Ally") }

  before { sign_in user, scope: :user }

  def opened!(account, balance)
    AccountOpening.new(user, account, balance: balance).save
  end

  it "renders, with the add-account door, when there is no main account", :aggregate_failures do
    user.update!(default_account: nil)

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(checking.name, ally.name)
    expect(response.body).to include("Add an account")
  end

  # ── DELETED WITH ONBOARDING STEPS 2 AND 3 (account-openings spec §3), their successors named
  # beside them:
  #
  #   "offers the funding card on an account nothing has moved money into" and "offers no funding
  #   card once a movement has funded the account" — both pinned MED-1's ruling that MONEY was the
  #   funding card's only signal. Money is no longer any signal at all: $0.00 is a real answer to
  #   "what's in it right now", and an account that holds nothing is asked exactly like one that
  #   holds thousands. The two examples below are the successor pair, keyed on the record instead.
  #
  #   "renders the opening-balance card only under main's own section" and "…once the latch closes"
  #   — the one-time main correction and the category-existence latch behind it. There is no latch:
  #   every account answers the same question and can answer it again through **Edit balance**
  #   (`spec/system/home/openings_spec.rb` is where that door is pinned).
  it "offers a row for an account that has not said what it holds", :aggregate_failures do
    get root_path

    expect(user.reload.default_account).to eq(checking)
    expect(response.body).to include("What&#39;s in it right now")
    expect(response.body).to include("data-account-row=\"Ally\"")
    expect(response.body).to include("data-account-row=\"Checking\"")
  end

  # THE ROW GOES AND THE CARD ARRIVES: an account that has answered is behind the accounts line with
  # its own **Edit balance** door, which is the same form asked a second time.
  it "offers a card with Edit balance once the account has answered", :aggregate_failures do
    opened!(checking, "300")
    opened!(ally, "500")

    get root_path

    expect(response.body).not_to include("data-account-row=\"Ally\"")
    expect(response.body).to include("data-edit-balance=\"Ally\"")
    expect(response.body).to include("Edit balance")
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
