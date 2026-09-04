# frozen_string_literal: true

require "rails_helper"

# THE CATEGORY FORM'S WIRE CONTRACT, AFTER `pool_id` LEFT IT (two-ledger spec §3–§5, Task 7).
#
# WHAT THIS FILE USED TO BE. Every example here was §7a's widened-parameter class asked of
# `category[pool_id]`: plan 3 made a pool REQUIRED on every category, which turned that param into
# the ordinary payload of every create and update, and a scoped READ beside an unscoped WRITE would
# have put this user's whole spending history into a STRANGER's pool balance —
# `PoolBalanceLedger::ENTRY_POOL_ID` joined on pool id with no user filter. The controller answered
# it with a `current_user.pools.find`, and this file pinned the 404-vs-422 line that lookup drew.
#
# THE PARAM IS GONE, SO THE HAZARD CLASS IS TOO. Nothing reads `categories.pool_id` any more, the
# form offers no picker, and `category_params` permits no foreign id of any kind — the three
# attributes that replaced it (`target_amount`, `priority`, `funded_since`) are plain columns of
# the record itself, so there is no "whose is this" question for a request to get wrong. The six
# examples that pinned the pool lookup are DELETED, each named in the task report; what stands in
# their place is the contract of the three that arrived.
#
# STILL A REQUEST SPEC, for the reason the old one was: these are answers to requests the UI does
# not make. The form never submits a `pool_id`, and a param dropped silently back to its default
# looks exactly like a param that was never sent — which only this layer can tell apart.
RSpec.describe "Categories", type: :request do
  let(:user) { create(:user) }
  # rubocop:disable RSpec/LetSetup -- nothing NAMES this account and every example needs it:
  # the `:account` trait's `after(:create)` is what makes the user's first account their MAIN
  # one, and the pot is where every entry below lands.
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  # rubocop:enable RSpec/LetSetup

  # `scope:` explicitly, as the other request specs do: Devise's mappings are populated when the
  # routes are drawn, and routes load lazily.
  before { sign_in user, scope: :user }

  describe "POST /categories" do
    def create_category(attributes)
      post categories_path, params: { category: { name: "Vacation", category_type: "expense" }.merge(attributes) }
    end

    # THE REACH DIRECTION, first. Without it every refusal below would pass just as well against a
    # controller that wrote nothing at all.
    it "writes the three holding columns", :aggregate_failures do
      expect { create_category(target_amount: 2_400, priority: 3, funded_since: "2026-02-06") }
        .to change(Category, :count).by(1)

      category = user.categories.find_by(name: "Vacation")
      expect([category.target_amount, category.priority]).to eq([2_400, 3])
      expect(category.funded_since).to eq(Date.new(2026, 2, 6))
      expect(response).to redirect_to(categories_path(type: "expense"))
    end

    # ** `pool_id` IS NEITHER PERMITTED NOR A COLUMN (Task 8). ** It was the IDOR the deleted
    # `current_user.pools.find` lookup existed to refuse; the column is gone, so the payload is what
    # a client written against the pool era would still send and the answer must be an ordinary
    # write rather than an UnknownAttribute 500.
    it "drops a pool a crafted param names" do
      create_category(pool_id: SecureRandom.uuid)

      expect(response).to redirect_to(categories_path(type: "expense"))
    end

    # THE MODEL'S OWN LINE, WHICH IS THE ONE THAT SURVIVES. `Category#holding_columns_are_sane`
    # refuses a target on a category that cannot hold money, and a shape refusal is a 422 — the
    # same division the deleted pool examples drew between "whose" (404) and "what shape" (422).
    it "answers a target on an income category with a 422", :aggregate_failures do
      expect { create_category(category_type: "income", target_amount: 2_400) }
        .not_to change(Category, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    # A CATEGORY THAT HOLDS NOTHING IS THE HONEST DEFAULT (§4): its spending drains available until
    # it gets a rule or an allocation. Blank is not a refusal.
    it "accepts all three blank", :aggregate_failures do
      expect { create_category(target_amount: "", funded_since: "") }.to change(Category, :count).by(1)

      category = user.categories.find_by(name: "Vacation")
      expect(category).not_to be_holder
      expect(category.target_amount).to be_nil
    end
  end

  # ** THE INDEX'S CLAIM AGGREGATES ARE BATCHED (fix round 1, MED-3 — re-homed on claims). **
  #
  # Each card prints what its category's money is, and it used to build a `HoldingCalculator` per
  # card to do it — N categories, N sets of grouped aggregates, on the one screen that renders every
  # category a user owns. The reader changed with the model (computed-claims spec §6) and the hazard
  # did not: `Category#claim` is the unbatched door and costs a spending query and an adjustment
  # query PER RULE. `CategoriesController#claim_ledger` builds ONE `ClaimLedger` for the page, which
  # is what Home and the Budget page already do.
  #
  # ** THE `adjustments` STATEMENTS ARE THE PROBE, NOT THE TOTAL, and the choice of table is the
  # whole design of this example. ** A claim is read out of two lanes — the dated deltas and the
  # draining entries — and `entries` is hopeless as a probe here, because every card ALSO asks
  # `CategoryCalculator` what it spent this period and lists its top items. Those are per-card
  # questions about per-card data, they grow with the row count for a reason this pin does not
  # touch, and counting them would make the assertion fail on a page that batches its claims
  # perfectly. `adjustments` is read by NOTHING else on this screen, so it isolates exactly the
  # reader under test: one grouped statement from the ledger, or one per rule from a per-card
  # calculator.
  #
  # EVERY CATEGORY CARRIES A RULE, which is not decoration. A claim comes from a rule (§3.3), so a
  # holder with none asks the ledger nothing at all — five ruleless categories would cost zero
  # statements, the equality below would hold trivially, and the example would pass against a page
  # that had gone back to a calculator per card.
  #
  # THE FIGURE ITSELF IS ASSERTED AS `eq(1)` rather than only as an equality: one grouped statement
  # is what "batched" means here, and a page that stopped reading claims altogether would satisfy a
  # bare equality while printing nothing about anybody's money.
  #
  # A request spec because the count is a fact about a rendered PAGE, and the null cache store this
  # environment configures means every card really renders.
  describe "GET /categories — claim aggregates" do
    def adjustment_statements
      statements = []
      recorder = lambda do |_name, _start, _finish, _id, payload|
        statements << payload[:sql] unless ["SCHEMA", "TRANSACTION"].include?(payload[:name])
      end
      ActiveSupport::Notifications.subscribed(recorder, "sql.active_record") do
        get categories_path(type: "expense")
      end
      statements.count { |sql| sql.include?(%("adjustments")) }
    end

    def holders(*names)
      names.each do |name|
        category = create(:category, :expense, :funded, user: user, name: name)
        create(:budget, :per_period_rate, category: category, amount: 100)
      end
      # A warm request first: the FIRST render of a template compiles it and loads its own rows, and
      # a compile counted on one side of the comparison and not the other is noise the assertion
      # cannot tell from a regression.
      get categories_path(type: "expense")
    end

    it "asks the same number of times for one rule as for five", :aggregate_failures do
      holders("Groceries")
      one = adjustment_statements

      holders("Rent", "Transit", "Utilities", "Vacation")
      five = adjustment_statements

      expect(user.categories.count(&:holder?)).to eq(5)
      expect(five).to eq(one)
      expect(five).to eq(1)
    end
  end

  # ** THE SHOW PAGE HAD NO PIN AT ALL, AND IT WAS THE ONE ACTION THAT BUILT ITS OWN LEDGER (fix
  # wave — LOW-1). ** `CategoriesController#claim_ledger` is a `helper_method` and its comment says
  # in as many words that it exists "so the SHOW action and the card partial can reach the same
  # reader without a second construction path" — but `#show` handed `CategoryBudgetPresenter` no
  # `claims:`, so the card built a `ClaimLedger` of its own and the promise was false. Nothing on
  # the index could catch it: the index passes its ledger in.
  #
  # THE PROBE IS THE INDEX'S, for the index's reasons — `adjustments` is read by nothing else on
  # this screen, so it isolates the claim reader from the per-card spending queries. §3.4 gives a
  # LINE PER RULE, so N here is rules on ONE category rather than categories: a card that walked
  # back to `Budget#claim_calculator` per line would cost one statement per rule.
  #
  # ** WHAT THIS PIN DOES NOT CATCH, SAID PLAINLY: the threading itself. ** Measured both ways — with
  # `claims:` handed in and with it left nil — this page costs the same 1 and 1, because nothing else
  # on the show template asks the `claim_ledger` helper, so the card's own ledger was the ONLY one
  # built and it batches exactly as well. The defect LOW-1 names is a second construction path rather
  # than a live cost: the day a partial on this page reads the helper (as `_category_card` does on
  # the index), an unthreaded card would make the second ledger and the `budgets` figure below would
  # go to 2. That is what the second arm is here for, and it is the honest reach of it.
  describe "GET /categories/:id — claim aggregates" do
    def adjustment_statements(category)
      statements = []
      recorder = lambda do |_name, _start, _finish, _id, payload|
        statements << payload[:sql] unless ["SCHEMA", "TRANSACTION"].include?(payload[:name])
      end
      ActiveSupport::Notifications.subscribed(recorder, "sql.active_record") { get category_path(category) }
      [
        statements.count { |sql| sql.include?(%("adjustments")) },
        statements.count { |sql| sql.start_with?(%(SELECT "budgets")) }
      ]
    end

    # ONE CATCH-ALL RULE AND `count − 1` ITEM-BACKED ONES: a category may hold only one item-less
    # rule (`Budget#category_may_hold_one_item_less_rule`), and the item lane is a second grouped
    # statement in the ledger, so both lanes are live at every size and the comparison is not
    # measuring a lane appearing.
    def rules_on(category, count)
      create(:budget, :per_period_rate, category: category, amount: 100)
      (count - 1).times do |index|
        item = create(:item, category: category, name: "Lane #{index}")
        create(:budget, :per_period_rate, category: category, amount: 50, item: item)
      end
      get category_path(category) # a warm request: the first render compiles the template.
    end

    it "asks the same number of times for one rule as for five", :aggregate_failures do
      one_rule = create(:category, :expense, :funded, user: user, name: "Groceries")
      five_rules = create(:category, :expense, :funded, user: user, name: "Pet Care")
      rules_on(one_rule, 1)
      rules_on(five_rules, 5)

      expect(adjustment_statements(five_rules)).to eq(adjustment_statements(one_rule))
      expect(adjustment_statements(five_rules)).to eq([1, 1])
    end
  end

  describe "PATCH /categories/:id" do
    let!(:category) do
      create(:category, :expense, :funded, user: user, name: "Groceries", target_amount: 500)
    end

    # ** CLEARING `funded_since` STOPS THE CATEGORY HOLDING MONEY (§4). ** A blank has to reach the
    # column as NULL rather than being skipped as "unchanged": the whole affordance the form
    # promises is that a user can take a category back out of the fill order, and a permit list
    # that ignored the blank would leave the checkbox and the data disagreeing.
    it "clears the funding start when the field is submitted blank", :aggregate_failures do
      patch category_path(category), params: { category: { funded_since: "" } }

      expect(response).to redirect_to(categories_path(type: "expense"))
      expect(category.reload.funded_since).to be_nil
      expect(category).not_to be_holder
    end

    it "clears the target the same way" do
      patch category_path(category), params: { category: { target_amount: "" } }

      expect(category.reload.target_amount).to be_nil
    end

    # THE UPDATE-SHAPED HOLE, and it was the sharper of the two on the pool lookup: the category is
    # mine and `#set_category` finds it, so a refusal has to come from the assignment rather than
    # from the lookup. There is nothing left to refuse — the param is simply not permitted.
    #
    # `name` RIDES ALONG, and it is not padding: `params.expect` raises ParameterMissing when NONE
    # of the listed keys is present, so a payload of `pool_id` alone is a 400 rather than a write
    # this example could inspect. The realistic crafted request is a real form submission with one
    # extra field, which is what this sends.
    it "drops a pool a crafted param names on update", :aggregate_failures do
      patch category_path(category), params: { category: { name: "Groceries", pool_id: SecureRandom.uuid } }

      expect(response).to redirect_to(categories_path(type: "expense"))
      expect(category.reload.name).to eq("Groceries")
    end
  end
end
