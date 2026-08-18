# frozen_string_literal: true

require "rails_helper"

# THE DECLARATION'S PARAMETER BOUNDARY. `PATCH /budget/user` writes the signed-in user's own row,
# so ownership is never the question here — the permitted list is, and it is the whole of the
# question: `User` carries `email`, `encrypted_password`, `theme` and `default_account_id` on the
# same record as the three fields this form owns.
#
# A request spec rather than a system spec, because a browser cannot submit a field the form does
# not render. The refusal is a fact about the route.
RSpec.describe "Budget page declaration", type: :request do
  let(:user) { create(:user, theme: :light) }

  before { sign_in user, scope: :user }

  def declare(params) = patch(budget_page_user_path, params: { user: params })

  describe "the three permitted params", :aggregate_failures do
    it "writes all three and comes back to the page" do
      declare(typical_income: "2400", period_cadence: "biweekly", period_anchor_date: "2026-02-06")

      expect(response).to redirect_to(budget_page_path)
      expect(user.reload).to have_attributes(
        typical_income: BigDecimal("2400"),
        period_cadence: "biweekly",
        period_anchor_date: Date.new(2026, 2, 6)
      )
    end

    # Clearing the period back to undeclared is a legitimate move — the form offers a blank
    # option — and the income survives it, because income is untethered from the period (§3).
    it "lets the period be cleared without clearing the income" do
      user.update!(typical_income: 2_400, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6))

      declare(typical_income: "2400", period_cadence: "", period_anchor_date: "")

      expect(user.reload.period_cadence).to be_nil
      expect(user.reload.typical_income).to eq(2_400)
    end
  end

  # A FOURTH PARAM IS REFUSED — dropped by the permitted list, not written. Asserted on `theme`
  # because it is a real column with a real writer elsewhere in the app, so a widened list would
  # show up here as a value that actually changed rather than as a no-op.
  describe "a fourth param", :aggregate_failures do
    it "is not written, while the permitted three are" do
      declare(
        typical_income: "2400",
        period_cadence: "monthly",
        period_anchor_date: "2026-02-01",
        theme: "dark"
      )

      expect(user.reload.theme).to eq("light")
      expect(user.reload.typical_income).to eq(2_400)
    end

    # The pair: `email` is what a mass-assignment attack would actually reach for, and unlike
    # `theme` a changed one locks the owner out of their own account.
    it "cannot rewrite the email the session is signed in as" do
      original = user.email

      declare(typical_income: "2400", email: "attacker@example.com")

      expect(user.reload.email).to eq(original)
    end
  end

  # A CADENCE WITH NO ANCHOR yields no boundaries at all, so every divisor downstream falls back
  # to its `[count, 1].max` clamp and the app demands whole bills out of one period. `User`
  # refuses it; this pins that the refusal arrives as a 422 the page can render rather than as a
  # 500 or a silent partial write.
  describe "an invalid declaration", :aggregate_failures do
    it "renders the page again with the error and persists nothing" do
      declare(typical_income: "2400", period_cadence: "biweekly", period_anchor_date: "")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Period anchor date is required when you set a period")
      expect(user.reload.typical_income).to be_nil
      expect(user.reload.period_cadence).to be_nil
    end

    it "refuses a zero income and keeps the previous one" do
      user.update!(typical_income: 2_400)

      declare(typical_income: "0")

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.typical_income).to eq(2_400)
    end
  end

  describe "a signed-out request", :aggregate_failures do
    it "is sent to sign in rather than writing anything" do
      sign_out user

      declare(typical_income: "9999")

      expect(response).to redirect_to(new_user_session_path)
      expect(user.reload.typical_income).to be_nil
    end
  end

  # THE FILL ORDER'S OWNERSHIP BOUNDARY. `PATCH /budget/reorder` is the app's only writer for
  # `pools.priority` outside the pool form, and unlike the declaration above it takes IDS off the
  # wire — so the question here is whose pools they are and whether they are one account's.
  #
  # A request spec, because the browser can only ever submit the order the page rendered: a list
  # mixing two accounts, naming another user's pool or missing one of its own is a fact about the
  # route, and every one of them must leave `priority` exactly as it was.
  describe "the fill order" do
    let(:checking) { create(:pool, :account, user: user, name: "Checking") }
    let(:savings) { create(:pool, :account, user: user, name: "Savings") }
    let!(:rent) { envelope("Rent", priority: 0) }
    let!(:groceries) { envelope("Groceries", priority: 1) }
    let!(:gifts) { envelope("Gifts", priority: 3, account: savings) }

    def envelope(name, priority:, account: checking)
      pool = create(:pool, :budget_pool, user: user, account: account, name: name, priority: priority)
      create(:pool_budget, :per_period_rate, pool: pool, amount: 100)
      pool
    end

    def reorder(ids) = patch(budget_page_reorder_path, params: { pool_ids: ids })

    # The whole account, name by name — a count would pass on a set that had been shuffled.
    def fill_order(account = checking)
      account.child_pools.by_priority.pluck(:name, :priority)
    end

    describe "a list of one account's pools in a new order", :aggregate_failures do
      it "writes a dense 0,1,2… and comes back to the page" do
        reorder([groceries.id, rent.id])

        expect(response).to redirect_to(budget_page_path)
        expect(fill_order).to eq([["Groceries", 0], ["Rent", 1]])
      end

      # The reindex is per account and nothing else moves — the same user's other account is
      # named on the wire nowhere and must read exactly as it did.
      it "leaves the same user's other account untouched" do
        reorder([groceries.id, rent.id])

        expect(gifts.reload.priority).to eq(3)
        expect(fill_order(savings)).to eq([["Gifts", 3]])
      end
    end

    # EVERY REFUSAL, ASSERTED IN BOTH DIRECTIONS: a pinned row that did not move AND the whole
    # account's order, because a pinned row alone would pass on a rewrite that moved everything
    # else and a whole-set comparison alone reads as a count.
    describe "a list this user cannot have submitted", :aggregate_failures do
      # The bad id sits MID-LIST rather than on the end, so a guard that stopped checking after
      # the first or last element would not pass this.
      it "refuses another user's pool" do
        intruder = create(:pool, :budget_pool, name: "Theirs")

        reorder([groceries.id, intruder.id, rent.id])

        expect(response).to have_http_status(:unprocessable_content)
        expect(groceries.reload.priority).to eq(1)
        expect(fill_order).to eq([["Rent", 0], ["Groceries", 1]])
      end

      it "refuses two accounts in one order" do
        reorder([groceries.id, rent.id, gifts.id])

        expect(response).to have_http_status(:unprocessable_content)
        expect(gifts.reload.priority).to eq(3)
        expect(fill_order).to eq([["Rent", 0], ["Groceries", 1]])
      end

      # A PARTIAL LIST IS A REFUSAL, NOT A PARTIAL WRITE: Rent would keep priority 0 and
      # Groceries would be written to 0 as well, and `[priority, name]` — not the user — would
      # decide which of the two gets funded first.
      it "refuses an order missing one of the account's own pools" do
        reorder([groceries.id])

        expect(response).to have_http_status(:unprocessable_content)
        expect(groceries.reload.priority).to eq(1)
        expect(fill_order).to eq([["Rent", 0], ["Groceries", 1]])
      end

      it "refuses a duplicated id, which would silently drop a pool" do
        reorder([groceries.id, groceries.id])

        expect(response).to have_http_status(:unprocessable_content)
        expect(fill_order).to eq([["Rent", 0], ["Groceries", 1]])
      end

      # DELETED (plan 3, task 6): "refuses an account-less pool". A pool no account holds is in
      # no fill order, so an order naming one was meaningless rather than merely wrong — but
      # `Pool#account_matches_pool_type` and `CHECK ((pool_type = 0) = (account_id IS NULL))` now
      # refuse the pool itself, so the request cannot be composed. `.fill_order_account`'s
      # account-less arm is kept and now selects nothing; see `Pool::REFUSALS` and the task 6
      # report. The refusals above — a foreign id, a short list, a duplicate — cover the same
      # branch through shapes that still exist.

      it "says nothing was changed rather than failing silently" do
        reorder([groceries.id])

        expect(response.body).to include("nothing was changed")
      end

      # `Pool.apply_fill_order` writes through `update!`, so a row that was ALREADY invalid
      # before the reorder — a `start_date` a data fix left NULL — raises RecordInvalid from a
      # reindex that had nothing to do with it. That must be this route's own refusal, naming
      # the row the user has to fix, rather than an unrescued 500 on a button they were right
      # to press.
      it "refuses at 422, naming the row, when a pool in the account is already invalid" do
        rent.update_column(:start_date, nil) # rubocop:disable Rails/SkipsModelValidations -- the point

        reorder([groceries.id, rent.id])

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Rent could not be saved (start date can")
        expect(fill_order).to eq([["Rent", 0], ["Groceries", 1]])
      end
    end

    # THE TWO SEMANTICS THIS TASK INVENTED, and neither was reachable by the fixtures above:
    # every pool in them carries a rule, so a list omitting a rule-less pool and the
    # slot-preserving branch that keeps such a pool's rank were both unexercised. The demo seeds
    # are this shape — `db/seeds.rb` moves four savings pools into Checking with no rule at all —
    # and under the brief's literal guard every reorder the demo user can make was refused.
    #
    # Checking reads Rent(0, rule), Emergency(1, none), Groceries(2, rule), Vacation(3, none).
    describe "an account holding pools no rule fills", :aggregate_failures do
      let!(:emergency) { unruled("Emergency", priority: 1) }
      let!(:vacation) { unruled("Vacation", priority: 3) }

      before { groceries.update!(priority: 2) }

      def unruled(name, priority:)
        create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
      end

      # The pair to "refuses an order missing one of the account's own pools": omitting a pool a
      # rule FILLS is a refusal, omitting one no rule fills is the ordinary case.
      it "accepts a list naming only the pools a rule fills" do
        reorder([groceries.id, rent.id])

        expect(response).to redirect_to(budget_page_path)
        expect(groceries.reload.priority).to eq(0)
      end

      # THE SLOT-PRESERVING BRANCH. Emergency and Vacation are named nowhere on the wire; the two
      # that are swap with each other and everything else holds its place. Renumbering only the
      # submitted pools would leave Emergency on 1 tied with Rent on 1, and `[priority, name]` —
      # not the user — would decide which of the two Home fills first.
      it "keeps an unruled pool's rank while renumbering the account densely" do
        reorder([groceries.id, rent.id])

        expect(fill_order).to eq([["Groceries", 0], ["Emergency", 1], ["Rent", 2], ["Vacation", 3]])
        expect(emergency.reload.priority).to eq(1)
        expect(vacation.reload.priority).to eq(3)
      end
    end

    describe "a signed-out request", :aggregate_failures do
      it "is sent to sign in rather than reordering anything" do
        sign_out user

        reorder([groceries.id, rent.id])

        expect(response).to redirect_to(new_user_session_path)
        expect(fill_order).to eq([["Rent", 0], ["Groceries", 1]])
      end
    end
  end
end
