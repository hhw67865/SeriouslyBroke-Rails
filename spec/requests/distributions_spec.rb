# frozen_string_literal: true

require "rails_helper"

# WHAT NO BROWSER TEST CAN REACH: the override params' malformed shapes, and the write path's
# ownership.
#
# NINE EXAMPLES WERE DELETED WITH THE CONCEPT THEY TESTED (two-ledger Task 4). The purpose ledger has
# ONE root (spec §2), so a distribution is not scoped to an account and this controller no longer
# takes an `account_id` at all — `#distribution_account`, `#default_account` and
# `#fallback_account_by_income` are gone with it. Named, so nobody looks for them later:
#
#   "opens on main when more of this period's income landed there"
#   "opens on main even when a transfer carried more money to another account"
#   "falls back to priority order when the user has no main account and no income has arrived"
#       — all three asserted WHICH account the screen opens on. There is no choice to make.
#   "refuses another user's account" (GET and POST)
#   "refuses one of the user's own pools that is not an account" (GET and POST)
#       — all four defended a `Pool.find(params[:account_id])` that no longer exists. The ownership
#         they protected is now structural rather than checked: `AllocationCalculator.new(user:)`
#         takes no id from the request, so there is nothing to scope. "proposes only the signed-in
#         user's own categories" below is what asserts that in the direction that is still testable.
#   "sends a user with no account back home with a reason" (GET and POST)
#       — distributing needs no account. A user with no holder categories now gets the screen with
#         nothing on it to distribute into, which is a true page rather than a redirect.
RSpec.describe "Distributions", type: :request do
  let(:user) { create(:user, :biweekly) }
  # rubocop:disable RSpec/LetSetup -- THE POT HAS TO EXIST, and nothing here reads it: income
  # lands in a category and `Category#income_must_land_in_an_account` says that category may
  # only point at the user's MAIN account, so a user with no account cannot be paid at all. It
  # is setup for the physical side of a fixture whose every assertion is on the purpose side.
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  # rubocop:enable RSpec/LetSetup

  # `scope:` explicitly, as the system specs do: Devise's mappings are populated when the routes are
  # drawn, and routes load lazily, so inferring the scope from the record can fail before the first
  # request in the process.
  before { sign_in user, scope: :user }

  describe "GET /distributions/new" do
    # The positive half. Without it every refusal below would still pass on a route that does not
    # exist at all.
    it "proposes a split for the signed-in user", :aggregate_failures do
      groceries = holder("Groceries")
      rate(groceries, 400)
      deposit(300)

      get new_distribution_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Groceries")
      # The paired negative for the failed-confirm banner below: it belongs to #create alone, and a
      # screen nobody has confirmed carries no errors at all.
      expect(response.body).not_to include("This split wasn't written")
    end

    # WHAT THE FOUR DELETED `account_id` REFUSALS WERE PROTECTING, asserted in the one direction that
    # survives: the proposal is built from `current_user` and reads `user.categories`, so a stranger's
    # category cannot appear on it however the request is shaped. Both halves — mine is there, theirs
    # is not — because "theirs is absent" alone passes on a screen that renders nothing.
    it "proposes only the signed-in user's own categories", :aggregate_failures do
      rate(holder("Groceries"), 400)
      stranger = create(:category, :expense, :funded, user: create(:user), name: "Not Yours")
      create(:budget, :per_period_rate, category: stranger, amount: 400)
      deposit(300)

      get new_distribution_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Groceries")
      expect(response.body).not_to include("Not Yours")
    end

    # A user with nothing to distribute into gets the screen, not a redirect: there is no account to
    # be missing any more, so the old "Set up an account before distributing." bounce has nothing to
    # test for.
    it "renders an empty proposal for a user with no holder categories", :aggregate_failures do
      get new_distribution_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nothing is asking for money this period")
    end
  end

  # THE OVERRIDE PARAMS, and specifically the shapes only a hand-built URL produces. This screen is a
  # GET anyone can link to, `overrides` is an open hash keyed by category id, and both of the shapes
  # below are 500s on the obvious implementation — `"1".permit!` is a NoMethodError and `["1"].to_d`
  # is another. Nothing a browser submits can reach either, which is exactly why no system example
  # can cover them.
  #
  # $300 of income against a $400 ask, so the proposal is short and the waterfall renders its box —
  # which is what makes the placeholder a reading of the row the override was meant to change, rather
  # than of a summary line that would move for other reasons too.
  #
  # An untouched box is EMPTY and carries the proposal as its placeholder; an overridden one carries
  # the figure as its value. That is what tells the two apart below.
  describe "GET /distributions/new with overrides", :aggregate_failures do
    let!(:groceries) { holder("Groceries") }

    before do
      rate(groceries, 400)
      deposit(300)
    end

    # The positive half: a well-formed override is applied, so the three refusals below are refusals
    # of bad input rather than of every override.
    it "applies a well-formed override" do
      get new_distribution_path(overrides: { groceries.id => "120" })

      expect(response).to have_http_status(:ok)
      expect(override_field(groceries)).to include('value="120.00"')
    end

    # THE APP'S OWN UI PRODUCED THIS SHAPE, which is why the guard below is not merely defensive. The
    # month scrubber re-emits every query parameter as `hidden_field key, value: value`, and a hash
    # written into one scalar box arrives as its own #to_s. This asserts the scrubber's side: the
    # nested param is dropped rather than flattened, so a month arrow clicked mid-edit carries no
    # override at all — which is also the right behaviour, since a different month is a different
    # period whose proposal has different rows.
    it "does not carry overrides through the month scrubber" do
      get new_distribution_path(overrides: { groceries.id => "120" })

      scrubber = response.body[%r{<form[^>]*>.*?name="month".*?</form>}m]
      expect(scrubber).to be_present
      expect(scrubber).not_to include("overrides")
    end

    it "ignores a scalar where a hash of overrides was expected" do
      get new_distribution_path(overrides: "1")

      expect(response).to have_http_status(:ok)
      expect(override_field(groceries)).to include('placeholder="300.00"')
      expect(override_field(groceries)).not_to include("value=")
    end

    it "ignores an override whose value is not a scalar" do
      get new_distribution_path(overrides: { groceries.id => ["1"] })

      expect(response).to have_http_status(:ok)
      expect(override_field(groceries)).to include('placeholder="300.00"')
      expect(override_field(groceries)).not_to include("value=")
    end

    # An id that names no row has no line to edit — the same rule AllocationCalculator#fill states,
    # reached here through a category that belongs to somebody else entirely.
    it "ignores an override naming a category the user does not hold" do
      stranger = create(:category, :expense, :funded, user: create(:user), name: "Not Yours")

      get new_distribution_path(overrides: { stranger.id => "5" })

      expect(response).to have_http_status(:ok)
      expect(override_field(groceries)).to include('placeholder="300.00"')
      expect(override_field(groceries)).not_to include("value=")
    end
  end

  # CONFIRMING. What lives here that no browser test can reach is a negative override — the
  # waterfall's boxes carry `min="0"`, so Chrome refuses to submit one and the only way to the
  # validation behind it is a request built by hand. Which is exactly the shape that matters: the
  # client guard is a convenience, and the refusal has to live at the write.
  describe "POST /distributions", :aggregate_failures do
    let!(:groceries) { holder("Groceries") }

    before do
      rate(groceries, 400)
      deposit(1_000)
    end

    # The positive half. Without it every refusal below would also pass on an action that refused
    # everything, or on a route that does not exist.
    it "writes the split for the signed-in user" do
      post distributions_path

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("Distributed $400.00 into 1 envelope. $600.00 stays available.")
      expect(Allocation.kind_allocation.pluck(:amount)).to eq([400])
    end

    # THE OWNERSHIP THE DELETED `account_id` REFUSALS CARRIED, on the path where it costs money: the
    # write is built from `current_user` alone, so a stranger's category cannot be funded out of this
    # user's confirm and this user's confirm cannot touch a stranger's ledger.
    it "writes nothing into another user's categories" do
      stranger = create(:category, :expense, :funded, user: create(:user), name: "Theirs")
      create(:budget, :per_period_rate, category: stranger, amount: 400)

      post distributions_path

      expect(Allocation.kind_allocation.pluck(:to_category_id)).to eq([groceries.id])
      expect(Allocation.where(to_category: stranger)).to be_empty
    end

    # A NEGATIVE OVERRIDE IS CARRIED THROUGH TO THE WRITE RATHER THAN FLOORED — kept alive by
    # AllocationCalculator#row_for — so it fails Allocation's `amount > 0` loudly instead of vanishing
    # from a split it was meant to change. The re-render says so and the ledger is untouched: an
    # error message with a half-written ledger behind it is the worst outcome available on this
    # screen.
    it "re-renders with the error and writes nothing" do
      post distributions_path(overrides: { groceries.id => "-50" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Groceries: Amount must be greater than 0")
      expect(response.body).to include("This split wasn't written")
      # The box comes back holding what they typed, which is what makes re-rendering the right answer
      # rather than a redirect: the row that was refused is on screen beside the reason.
      expect(override_field(groceries)).to include('value="-50.00"')
      expect(Allocation.count).to eq(0)
    end

    # THE GUARD THE COMMITTER'S TRANSACTION NAMES. The deletion of the previous split is inside that
    # transaction, and that transaction is `requires_new: true` — hoist either and a failing re-run
    # destroys a good split, writes nothing in its place and still reports a failure. The rows are
    # compared BY ID, so a deletion followed by an identical rewrite could not pass this either.
    it "leaves the previous split intact when a re-run fails" do
      post distributions_path
      written = Allocation.order(:id).pluck(:id, :amount)

      post distributions_path(overrides: { groceries.id => "-50" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(Allocation.order(:id).pluck(:id, :amount)).to eq(written)
      expect(written.map(&:last)).to eq([400])
    end

    # The other direction of the replacement: a re-run that SUCCEEDS replaces its own split rather
    # than adding to it, and says so. Paired with the first example's "Distributed …", which is the
    # same sentence on a period that had never been distributed.
    it "says it replaced the previous split when a re-run succeeds" do
      post distributions_path
      post distributions_path

      expect(flash[:notice]).to eq(
        "Replaced this period's split — distributed $400.00 into 1 envelope. $600.00 stays available."
      )
      expect(Allocation.kind_allocation.pluck(:amount)).to eq([400])
    end
  end

  # The one box, isolated from the rest of the page: the layout carries other `value=` inputs, so a
  # body-wide negative would be about the sidebar rather than about the override.
  def override_field(category)
    response.body[/<input[^>]*id="override-#{category.id}"[^>]*>/]
  end

  def holder(name) = create(:category, :expense, :funded, user: user, name: name)

  def rate(category, amount) = create(:budget, :per_period_rate, category: category, amount: amount)

  def deposit(amount)
    category = create(:category, :income, user: user)
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.current)
  end
end
