# frozen_string_literal: true

require "rails_helper"

# Ownership is the controller's job, and it is the only assertion here that no browser test can
# make: AllocationCalculator takes a `user` and an `account` and never checks that the two belong
# together, so whether another user's account can produce a proposal is decided entirely by how
# this controller looks the account up.
RSpec.describe "Distributions", type: :request do
  let(:user) { create(:user, :biweekly) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }

  # `scope:` explicitly, as the system specs do: Devise's mappings are populated when the routes
  # are drawn, and routes load lazily, so inferring the scope from the record can fail before the
  # first request in the process.
  before { sign_in user, scope: :user }

  describe "GET /distributions/new" do
    # The positive half. Without it the 404 below would still pass on a controller that 404s on
    # every request, or on a route that does not exist at all.
    it "proposes a split for an account the signed-in user owns", :aggregate_failures do
      get new_distribution_path(account_id: checking.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Checking")
    end

    # The plan's ruling: with no account named, open on the one this period's pay landed in. Both
    # directions of the same fixture — the income moves and the screen follows it — because an
    # assertion on one account alone passes on any rule that happens to pick that account.
    it "opens on the account this period's income landed in", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      deposit(2_400, into: checking)
      deposit(50, into: ally)

      get new_distribution_path

      expect(response.body).to include("Checking")
      expect(response.body).not_to include("Ally")
    end

    it "follows the income to the other account", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      deposit(50, into: checking)
      deposit(2_400, into: ally)

      get new_distribution_path

      expect(response.body).to include("Ally")
      expect(response.body).not_to include("Checking")
    end

    # No income anywhere is the ordinary shape of a brand-new user and of every user before their
    # first paycheck of the period. `max_by` promises nothing about which of several equal maxima
    # it returns, so without the index tie-break this is the example that flaps.
    it "falls back to priority order when no income has arrived", :aggregate_failures do
      create(:pool, :account, user: user, name: "Ally", priority: 5)

      get new_distribution_path

      expect(response.body).to include("Checking")
      expect(response.body).not_to include("Ally")
    end

    # The whole point. A bare `Pool.find(params[:account_id])` renders this page — another
    # person's buffer, envelope names and balances — with a 200.
    # Status only, and deliberately: the test environment's verbose exception page renders the
    # SOURCE OF THE CALLING SPEC, so `response.body` contains the stranger's account name
    # whatever the controller does. Measured — the assertion was written and it failed against a
    # correct 404. A body assertion here would have been a test of the error page, not of the
    # lookup, and the 200-plus-name example above is what pins that the page can render a name
    # at all.
    it "refuses another user's account" do
      stranger = create(:pool, :account, user: create(:user), name: "Someone Elses Bank")

      get new_distribution_path(account_id: stranger.id)

      expect(response).to have_http_status(:not_found)
    end

    # An envelope's id is a perfectly valid pool id belonging to the right user. Filled by
    # AllocationCalculator it has no child pools to fund and its own balance stands in as a
    # buffer, so the page would render real figures about a thing that is not an account.
    it "refuses one of the user's own pools that is not an account" do
      groceries = create(:pool, :budget_pool, user: user, account: checking, name: "Groceries")

      get new_distribution_path(account_id: groceries.id)

      expect(response).to have_http_status(:not_found)
    end

    # A user with no account at all has nothing to distribute FROM, and the calculator would
    # raise on the nil rather than say so.
    it "sends a user with no account back home with a reason", :aggregate_failures do
      checking.destroy!

      get new_distribution_path

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Set up an account before distributing.")
    end
  end

  # THE OVERRIDE PARAMS, and specifically the shapes only a hand-built URL produces. This screen
  # is a GET anyone can link to, `overrides` is an open hash keyed by pool id, and both of the
  # shapes below are 500s on the obvious implementation — `"1".permit!` is a NoMethodError and
  # `["1"].to_d` is another. Nothing a browser submits can reach either, which is exactly why no
  # system example can cover them.
  # $300 of income against a $400 ask, so the proposal is short and the waterfall renders its
  # boxes — which is what makes `value="300.00"` a reading of the row the override was meant to
  # change, rather than of a summary line that would move for other reasons too.
  describe "GET /distributions/new with overrides", :aggregate_failures do
    let!(:groceries) { create(:pool, :budget_pool, user: user, account: checking, name: "Groceries") }

    before do
      create(:pool_budget, :per_paycheck_rate, pool: groceries, amount: 400)
      create(
        :entry,
        item: create(:item, category: create(:category, :income, user: user, pool: checking)),
        amount: 300,
        date: Date.current
      )
    end

    # The positive half: a well-formed override is applied, so the three refusals below are
    # refusals of bad input rather than of every override.
    it "applies a well-formed override" do
      get new_distribution_path(account_id: checking.id, overrides: { groceries.id => "120" })

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="120.00"')
    end

    it "ignores a scalar where a hash of overrides was expected" do
      get new_distribution_path(account_id: checking.id, overrides: "1")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="300.00"')
    end

    it "ignores an override whose value is not a scalar" do
      get new_distribution_path(account_id: checking.id, overrides: { groceries.id => ["1"] })

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="300.00"')
    end

    # An id that names no row on this account has no line to edit — the same rule
    # AllocationCommitter#amount_for states, reached here through a pool that belongs to
    # somebody else entirely.
    it "ignores an override naming a pool the account does not hold" do
      stranger = create(:pool, :budget_pool, user: create(:user), name: "Not Yours")

      get new_distribution_path(account_id: checking.id, overrides: { stranger.id => "5" })

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="300.00"')
    end
  end

  def deposit(amount, into:)
    category = create(:category, :income, user: user, pool: into)
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end
end
