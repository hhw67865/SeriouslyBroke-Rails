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
      # The paired negative for the failed-confirm banner below: it belongs to #create alone, and
      # a screen nobody has confirmed carries no errors at all.
      expect(response.body).not_to include("This split wasn't written")
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
  # box — which is what makes the placeholder a reading of the row the override was meant to
  # change, rather than of a summary line that would move for other reasons too.
  #
  # An untouched box is EMPTY and carries the proposal as its placeholder; an overridden one
  # carries the figure as its value. That is what tells the two apart below.
  describe "GET /distributions/new with overrides", :aggregate_failures do
    let!(:groceries) { create(:pool, :budget_pool, user: user, account: checking, name: "Groceries") }

    before do
      create(:pool_budget, :per_period_rate, pool: groceries, amount: 400)
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
      expect(override_field(groceries)).to include('value="120.00"')
    end

    # THE APP'S OWN UI PRODUCED THIS SHAPE, which is why the guard below is not merely defensive.
    # The month scrubber re-emits every query parameter as `hidden_field key, value: value`, and a
    # hash written into one scalar box arrives as its own #to_s. This asserts the scrubber's side:
    # the nested param is dropped rather than flattened, so a month arrow clicked mid-edit carries
    # no override at all — which is also the right behaviour, since a different month is a
    # different period whose proposal has different rows.
    it "does not carry overrides through the month scrubber" do
      get new_distribution_path(account_id: checking.id, overrides: { groceries.id => "120" })

      scrubber = response.body[%r{<form[^>]*>.*?name="month".*?</form>}m]
      expect(scrubber).to be_present
      expect(scrubber).not_to include("overrides")
    end

    it "ignores a scalar where a hash of overrides was expected" do
      get new_distribution_path(account_id: checking.id, overrides: "1")

      expect(response).to have_http_status(:ok)
      expect(override_field(groceries)).to include('placeholder="300.00"')
      expect(override_field(groceries)).not_to include("value=")
    end

    it "ignores an override whose value is not a scalar" do
      get new_distribution_path(account_id: checking.id, overrides: { groceries.id => ["1"] })

      expect(response).to have_http_status(:ok)
      expect(override_field(groceries)).to include('placeholder="300.00"')
      expect(override_field(groceries)).not_to include("value=")
    end

    # An id that names no row on this account has no line to edit — the same rule
    # AllocationCalculator#fill states, reached here through a pool that belongs to
    # somebody else entirely.
    it "ignores an override naming a pool the account does not hold" do
      stranger = create(:pool, :budget_pool, user: create(:user), name: "Not Yours")

      get new_distribution_path(account_id: checking.id, overrides: { stranger.id => "5" })

      expect(response).to have_http_status(:ok)
      expect(override_field(groceries)).to include('placeholder="300.00"')
      expect(override_field(groceries)).not_to include("value=")
    end
  end

  # CONFIRMING. Two things live here that no browser test can reach: the ownership of a WRITE
  # path (amendment E), and a negative override — the waterfall's boxes carry `min="0"`, so
  # Chrome refuses to submit one and the only way to the validation behind it is a request built
  # by hand. Which is exactly the shape that matters: the client guard is a convenience, and the
  # refusal has to live at the write.
  describe "POST /distributions", :aggregate_failures do
    let!(:groceries) { create(:pool, :budget_pool, user: user, account: checking, name: "Groceries") }

    before do
      create(:pool_budget, :per_period_rate, pool: groceries, amount: 400)
      deposit(1_000, into: checking)
    end

    # The positive half. Without it every refusal below would also pass on an action that
    # refused everything, or on a route that does not exist.
    it "writes the split for an account the signed-in user owns" do
      post distributions_path(account_id: checking.id)

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("Distributed $400.00 into 1 envelope. $600.00 stays in your buffer.")
      expect(PoolMovement.kind_allocation.pluck(:amount)).to eq([400])
    end

    # The whole point, and it is worth more here than on the GET: that one renders another
    # person's balances, this one would MOVE THEIR MONEY. Both halves asserted — the 404, and
    # the ledger that stayed empty behind it.
    it "refuses another user's account" do
      stranger = create(:pool, :account, user: create(:user), name: "Someone Elses Bank")
      create(:pool, :budget_pool, user: stranger.user, account: stranger, name: "Their Rent")

      post distributions_path(account_id: stranger.id)

      expect(response).to have_http_status(:not_found)
      expect(PoolMovement.count).to eq(0)
    end

    # An envelope's id is a valid pool id belonging to the right user. Filled by
    # AllocationCalculator it has no child pools to fund and its own balance stands in as a
    # buffer, so the write would be about a thing that is not an account.
    it "refuses one of the user's own pools that is not an account" do
      post distributions_path(account_id: groceries.id)

      expect(response).to have_http_status(:not_found)
      expect(PoolMovement.count).to eq(0)
    end

    it "sends a user with no account back home with a reason" do
      # The categories go first, and that is plan 3 task 6's rule showing through the fixture: an
      # account refuses to be destroyed while any category still points at it (`has_many
      # :categories, dependent: :restrict_with_error`), and this describe's `#deposit` gave
      # Checking an income category.
      user.categories.destroy_all
      groceries.destroy!
      checking.destroy!

      post distributions_path

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Set up an account before distributing.")
    end

    # A NEGATIVE OVERRIDE IS CARRIED THROUGH TO THE WRITE RATHER THAN FLOORED — Task 3's ruling,
    # kept alive by AllocationCalculator#row_for — so it fails PoolMovement's `amount > 0`
    # loudly instead of vanishing from a split it was meant to change. The re-render says so and
    # the ledger is untouched: an error message with a half-written ledger behind it is the worst
    # outcome available on this screen.
    it "re-renders with the error and writes nothing" do
      post distributions_path(account_id: checking.id, overrides: { groceries.id => "-50" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Groceries: Amount must be greater than 0")
      expect(response.body).to include("This split wasn't written")
      # The box comes back holding what they typed, which is what makes re-rendering the right
      # answer rather than a redirect: the row that was refused is on screen beside the reason.
      expect(override_field(groceries)).to include('value="-50.00"')
      expect(PoolMovement.count).to eq(0)
    end

    # AMENDMENT B, AND THE GUARD IT NAMES. The deletion of the previous split is inside the
    # committer's transaction, and that transaction is `requires_new: true` — hoist either and a
    # failing re-run destroys a good split, writes nothing in its place and still reports a
    # failure. The rows are compared BY ID, so a deletion followed by an identical rewrite could
    # not pass this either.
    it "leaves the previous split intact when a re-run fails" do
      post distributions_path(account_id: checking.id)
      written = PoolMovement.order(:id).pluck(:id, :amount)

      post distributions_path(account_id: checking.id, overrides: { groceries.id => "-50" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(PoolMovement.order(:id).pluck(:id, :amount)).to eq(written)
      expect(written.map(&:last)).to eq([400])
    end

    # The other direction of the replacement: a re-run that SUCCEEDS replaces its own split
    # rather than adding to it, and says so. Paired with the first example's "Distributed …",
    # which is the same sentence on a period that had never been distributed.
    it "says it replaced the previous split when a re-run succeeds" do
      post distributions_path(account_id: checking.id)
      post distributions_path(account_id: checking.id)

      expect(flash[:notice]).to eq(
        "Replaced this period's split — distributed $400.00 into 1 envelope. $600.00 stays in your buffer."
      )
      expect(PoolMovement.kind_allocation.pluck(:amount)).to eq([400])
    end
  end

  # The one box, isolated from the rest of the page: the layout carries other `value=` inputs,
  # so a body-wide negative would be about the sidebar rather than about the override.
  def override_field(pool)
    response.body[/<input[^>]*id="override-#{pool.id}"[^>]*>/]
  end

  def deposit(amount, into:)
    category = create(:category, :income, user: user, pool: into)
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end
end
