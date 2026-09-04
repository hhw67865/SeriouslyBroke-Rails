# frozen_string_literal: true

require "rails_helper"

# §7a. `Budget.for_user` is the app's one answer to which rules a user owns, and these examples pin
# the lookup at the layer where it lives: a scoped find is BOTH a reach and a refusal, and a scope
# that returns everything passes every "it found it" assertion ever written.
#
# THE OWNER IS A CATEGORY (two-ledger spec §3), AND THE PAIRS BELOW ARE THE POOL PAIRS RE-ASKED OF
# IT. `budget[pool_id]` is no longer a permitted parameter and `budget[category_id]` is — the same
# question ("whose owner is this?") of the owner that holds the money. What changed in these
# examples is only which column the ownership question is asked about; every branch they covered
# — a reach, a stranger's id, a shape refusal, an owner-less save, a re-parent both ways — is
# asked again below.
#
# A request spec rather than a system spec for the pairs a browser cannot compose: a stranger's id,
# and an unpermitted key. The picker itself is covered in spec/system/budgets/form_spec.rb.
RSpec.describe "Budgets", type: :request do
  let(:user) { create(:user) }
  let(:groceries) { create(:category, :expense, :funded, user: user, name: "Groceries") }

  let(:stranger) { create(:user) }
  let(:stranger_category) { create(:category, :expense, :funded, user: stranger, name: "Their Rent") }

  let!(:rule) { create(:budget, :rate, category: groceries, amount: 200) }

  # `scope:` explicitly, as the other request specs do: Devise's mappings are populated when
  # the routes are drawn, and routes load lazily.
  before { sign_in user, scope: :user }

  describe "GET /budgets/:id/edit" do
    it "reaches the user's own rule" do
      get edit_budget_path(rule)

      expect(response).to have_http_status(:ok)
    end

    # `show_exceptions = :rescuable` in the test environment, so RecordNotFound arrives as
    # the 404 a real request would get rather than as a raised exception. The status is what
    # the user meets, so the status is what is asserted.
    it "refuses another user's rule" do
      foreign = create(:budget, :rate, category: stranger_category)

      get edit_budget_path(foreign)

      expect(response).to have_http_status(:not_found)
    end

    # ** THE PREFILL ON THIS PATH IS THE AMOUNT AND NOTHING ELSE (fix round 1 — M1). ** A drift
    # suggestion is the only thing that links here with a payload and the only thing it has to say
    # is a figure it measured; the rest of the rule is already on the row. Merging the whole query
    # string over `RuleForm.from` handed a GET the power to re-word an existing rule, and both of
    # these were live.
    it "takes a drift suggestion's amount" do
      get edit_budget_path(rule, budget: { amount: "45.00" })

      expect(response.body).to include('value="45.00"')
    end

    # SCENARIO A: the read-only box rendered the OTHER category's name and the hidden field carried
    # it, so the form said the rule belonged somewhere it did not and Save moved it there.
    it "ignores a category in the query string", :aggregate_failures do
      own = create(:category, :expense, :funded, user: user, name: "Dining Out")

      get edit_budget_path(rule, budget: { category_id: own.id })

      expect(response.body).to include("Groceries")
      expect(response.body).not_to include("Dining Out")
      expect(rule.reload.category).to eq(groceries)
    end

    # SCENARIO B: a schedule in the query string re-rendered a dated bill as a per-period rule with
    # the date still sitting in a now-hidden input — `toggle()` early-returns when the state already
    # matches — so Save was refused for a due date on a control that was not on screen. The rule
    # opens on the schedule the ROW carries, whatever the URL says.
    it "ignores a schedule in the query string", :aggregate_failures do
      bill = create(:budget, :recurring, category: groceries, amount: 800, item: create(:item, category: groceries))

      get edit_budget_path(bill, budget: { schedule: "per_period" })

      expect(input_tag("budget_schedule_every_n")).to include('checked="checked"')
      expect(input_tag("budget_schedule_per_period")).not_to include('checked="checked"')
    end

    # THE HIDDEN OWNER IS GONE WITH THE PERMITTED KEY: a persisted rule keeps its category because
    # the ROW has one, and the field's only real effect was to make a re-parent a legal PATCH.
    it "submits no category field at all" do
      get edit_budget_path(rule)

      expect(response.body).not_to include('name="budget[category_id]"')
    end
  end

  # ** WHAT A BROWSER WITH NO JAVASCRIPT IS SERVED. ** A request spec IS that browser: the reveals
  # are an enhancement, the `<noscript>` rule in the partial forces every hidden block visible, and
  # the server has to answer for whatever such a form submits.
  describe "GET /budgets/:id/edit — without JavaScript", :aggregate_failures do
    # ** THE "UNSPENT MONEY" RADIOS ARE DISABLED ON A DATED SCHEDULE, AND SAY WHY (fix round 1 —
    # L2). ** They were merely HIDDEN, which with no JavaScript means visible and live — so a user
    # could choose "Builds up" on a dated bill and `RuleForm` dropped it in silence, because
    # `Budget#build_up_must_be_valid` refuses `carries_over` beside an anchor and the form forces
    # `resets` there rather than arguing. A disabled control submits nothing and states its reason,
    # which is the honest version of the same refusal.
    it "disables the unspent radios on a dated bill and states the reason" do
      bill = create(:budget, :recurring, category: groceries, amount: 800, item: create(:item, category: groceries))

      get edit_budget_path(bill)

      expect(response.body).to include("A dated bill never carries money over.")
      expect(input_tag("budget_unspent_builds")).to include('disabled="disabled"')
      expect(input_tag("budget_unspent_resets")).to include('disabled="disabled"')
      expect(input_tag("budget_target_amount")).to include('disabled="disabled"')
    end

    # THE OTHER DIRECTION, or "it disables them" would pass against a form that disabled them always.
    it "leaves them live on a dateless rule" do
      get edit_budget_path(rule)

      expect(response.body).not_to include("A dated bill never carries money over.")
      expect(input_tag("budget_unspent_builds")).not_to include('disabled="disabled"')
      expect(input_tag("budget_target_amount")).not_to include('disabled="disabled"')
    end
  end

  # ** THE "PAYS" SELECT RENDERS EVERY ITEM THE USER OWNS, AND IT COSTS ONE STATEMENT TO DO IT. **
  # That is the price of filtering in the browser rather than re-fetching (and of degrading without
  # JavaScript at all), and it is only acceptable while it stays flat: a select that grew a query per
  # category would look exactly the same on the page. `User#items` is `has_many through: :categories`
  # so `categories` is already in the join — the explicit `.joins(:category)` this used to carry was
  # a second join on the same table, and nothing but a count would have said so.
  describe "GET /budgets/new — the Pays select" do
    def item_statements
      statements = []
      recorder = lambda do |_name, _start, _finish, _id, payload|
        statements << payload[:sql] unless ["SCHEMA", "TRANSACTION"].include?(payload[:name])
      end
      ActiveSupport::Notifications.subscribed(recorder, "sql.active_record") { get new_budget_path }
      statements.count { |sql| sql.include?(%("items")) }
    end

    # STRICT EQUALITY, and the absolute figure beside it: equality alone would be satisfied by a page
    # that read the items zero times, which is what a select rendered from an empty relation does.
    def stock_two_more_categories
      2.times do |index|
        category = create(:category, :expense, :funded, user: user, name: "Cat #{index}")
        4.times { |slot| create(:item, category: category, name: "Item #{index}-#{slot}") }
      end
    end

    it "reads the items once, whatever the size of the account", :aggregate_failures do
      create(:item, category: groceries, name: "Milk")
      one_category = item_statements

      stock_two_more_categories
      three_categories = item_statements

      expect([user.categories.count, user.items.count]).to eq([3, 9])
      expect(three_categories).to eq(one_category)
      expect(one_category).to eq(1)
    end
  end

  # ** THE WIRE CARRIES THE USER'S WORDS SINCE RULES-OWN-THE-BUDGET §4. ** `basis` is no longer a
  # permitted parameter; `schedule` (`per_period` / `monthly` / `every_n` / `once`) and `unspent`
  # (`resets` / `builds`) are, and `RuleForm` turns them into the columns. Every payload below is
  # therefore spelled as a person would answer the form, and the ASSERTIONS are on the columns —
  # which is the only way a request spec can tell the mapping from a mapping that agrees with itself.
  #
  # The words a bare form submits, so each example states only the fields it is about.
  def rule_words(**overrides)
    { amount: "40.00", rule_type: "usage", schedule: "per_period", unspent: "resets" }.merge(overrides)
  end

  # ONE RENDERED `<input>`, BY ID. Rails writes an input's attributes in its own order and moves them
  # between versions, so `include?(%(id="x" checked="checked"))` pins the ORDER as much as the state
  # — it broke first time out on `disabled` landing before `name`. Find the tag, then ask it.
  def input_tag(id) = response.body[/<input[^>]*id="#{id}"[^>]*>/].to_s

  # THE OTHER HALF OF §7a: a scoped READ beside an unscoped WRITE is not ownership, it is ownership
  # on the way in only. `budget[category_id]` is a wire parameter, and `Budget` itself cannot object
  # to a foreign category — it validates that the shape is legal and that the item belongs to the
  # category, never whose it is.
  #
  # Where the line sits, and it is deliberate: the controller answers WHOSE (a stranger's id is a
  # 404, the same answer #set_budget gives), and the model answers WHAT SHAPE. Scoping the lookup to
  # `.expenses` would make the controller a second reader of a rule the model states, and would turn
  # a legible form error into a vanished record.
  describe "POST /budgets" do
    it "writes a rule on the user's own category", :aggregate_failures do
      own = create(:category, :expense, :funded, user: user, name: "Dining Out")

      expect { post budgets_path, params: { budget: rule_words(category_id: own.id, schedule: "monthly") } }
        .to change(Budget, :count).by(1)
      expect(response).to redirect_to(budget_page_path)
      expect(own.budgets.reload.sole.amount).to eq(40)
    end

    # ** ONE EXAMPLE PER ROW OF §2.1, THROUGH THE FULL STACK. ** The unit pins are in
    # `spec/services/rule_form_spec.rb`; these are here because a permitted-parameter list is the
    # other half of the mapping, and a field dropped from `BUDGET_FIELDS` is a control that silently
    # writes nothing.
    {
      "a per-period rate" => [
        { schedule: "per_period", unspent: "resets", amount: "400.00" },
        { basis: "per_period", interval_months: nil, anchor_date: nil, carries_over: false, target_amount: nil }
      ],
      "an uncapped fund" => [
        { schedule: "per_period", unspent: "builds", target_amount: "", amount: "300.00" },
        { basis: "per_period", interval_months: nil, anchor_date: nil, carries_over: true, target_amount: nil }
      ],
      "a goal with a target" => [
        { schedule: "per_period", unspent: "builds", target_amount: "5000", amount: "200.00" },
        { basis: "per_period", interval_months: nil, anchor_date: nil, carries_over: true, target_amount: 5_000 }
      ],
      "a goal fed by hand" => [
        { schedule: "per_period", unspent: "builds", target_amount: "5000", amount: "0" },
        { basis: "per_period", interval_months: nil, anchor_date: nil, carries_over: true, target_amount: 5_000 }
      ],
      "a monthly rate" => [
        { schedule: "monthly", unspent: "resets", amount: "260.00" },
        { basis: "monthly", interval_months: 1, anchor_date: nil, carries_over: false, target_amount: nil }
      ],
      "a bill every 6 months" => [
        { schedule: "every_n", interval_months: "6", anchor_date: "2026-12-01", amount: "600.00" },
        {
          basis: "monthly",
          interval_months: 6,
          anchor_date: Date.new(2026, 12, 1),
          carries_over: false,
          target_amount: nil
        }
      ],
      "a one-time bill" => [
        { schedule: "once", anchor_date: "2026-12-01", amount: "600.00" },
        {
          basis: "monthly",
          interval_months: nil,
          anchor_date: Date.new(2026, 12, 1),
          carries_over: false,
          target_amount: nil
        }
      ]
    }.each do |name, (submitted, columns)|
      it "writes #{name}", :aggregate_failures do
        own = create(:category, :expense, :funded, user: user, name: "Dining Out")

        post budgets_path, params: { budget: rule_words(category_id: own.id, **submitted) }

        expect(response).to redirect_to(budget_page_path)
        expect(own.budgets.reload.sole.slice(*columns.keys)).to eq(columns.stringify_keys)
      end
    end

    # EVERY RULE HAS A TYPE (§3), and the give-way order is built on it — so the radio is required
    # and a submission with none is refused rather than defaulted.
    it "refuses a rule with no type", :aggregate_failures do
      own = create(:category, :expense, :funded, user: user, name: "Dining Out")

      expect { post budgets_path, params: { budget: rule_words(category_id: own.id, rule_type: "") } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("can&#39;t be blank")
    end

    it "writes the type the form chose", :aggregate_failures do
      own = create(:category, :expense, :funded, user: user, name: "Dining Out")

      post budgets_path, params: { budget: rule_words(category_id: own.id, rule_type: "choice") }

      expect(own.budgets.reload.sole).to be_choice
    end

    # ** A CONTRADICTION IS REFUSED, NOT LAUNDERED (§4). ** `per period` writes no anchor, so this
    # payload could have been saved by dropping the date on the floor — and a bill whose due date
    # vanished on the way in is a rule that silently is not the one the user described. The message
    # lands under "How often", which is the control that decided against the date.
    it "refuses a per-period rule carrying a due date, under How often", :aggregate_failures do
      own = create(:category, :expense, :funded, user: user, name: "Dining Out")

      expect { post budgets_path, params: { budget: rule_words(category_id: own.id, anchor_date: "2026-12-01") } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("How often does not take a due date")
    end

    # `basis` IS NOT A PERMITTED PARAMETER ANY MORE. Silent, as an unpermitted key always is: the
    # request is exactly the one above it, and the shape comes from `schedule` alone — so a client
    # written against the old wire cannot set a basis behind the form's back.
    it "ignores a basis on the wire and takes the schedule's own", :aggregate_failures do
      own = create(:category, :expense, :funded, user: user, name: "Dining Out")

      post budgets_path, params: { budget: rule_words(category_id: own.id, basis: "monthly") }

      expect(response).to redirect_to(budget_page_path)
      expect(own.budgets.reload.sole.basis).to eq("per_period")
    end

    # AMENDMENT B, TRIPPED ON PURPOSE. This slot and its PATCH twin used to pin the OWNER parameter
    # as INERT, and they were correct while it was unpermitted — that was the whole point of writing
    # them. The Budget page's form submits a rule's own owner back, so the permitted list was
    # widened, and at that moment "whose is this" became the question.
    it "refuses a stranger's category and writes nothing", :aggregate_failures do
      expect { post budgets_path, params: { budget: rule_words(category_id: stranger_category.id) } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:not_found)
      expect(stranger_category.budgets.reload).to be_empty
    end

    # The line drawn from the other side, and this is the pool era's "answers the user's own account
    # with a 422, not a 404" re-asked of the owner that replaced it. An INCOME category is the user's
    # OWN, so the controller must let it through and the MODEL must answer — and it does, from an
    # unexpected direction: `BudgetProposal` stamps `funded_since` on the way in, and
    # `Category#only_expenses_hold_money` refuses that on an income category (§2: income lands in
    # available and is allocated out of it). The refusal is carried onto the rule's `:base`, which is
    # where the form prints it.
    #
    # Scoping the lookup to `.expenses` would turn this into a 404 — the user's own record
    # vanishing — where the model gives a sentence they can act on. The form does not OFFER an
    # income category (`categories.expenses` in the picker); that is the affordance, not the
    # boundary.
    it "answers the user's own income category with a 422, not a 404", :aggregate_failures do
      income = create(:category, :income, user: user)

      expect { post budgets_path, params: { budget: rule_words(category_id: income.id) } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("only expense categories hold money")
      expect(income.reload.funded_since).to be_nil
    end

    # A rule with no owner at all — the state a bare `/budgets/new` submits when nothing is chosen.
    # `Budget#must_have_an_owner` answers with a legible 422 on `:base`, which is where the form
    # renders it, and the sentence names the CATEGORY because that is the control the form offers.
    it "answers a rule with no owner at all with a 422", :aggregate_failures do
      expect { post budgets_path, params: { budget: rule_words } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("must belong to a category")
    end

    # `pool_id` IS NEITHER PERMITTED NOR A COLUMN (two-ledger spec §3/§5). The refusal is silent by
    # design: an unpermitted key is dropped, so the request is exactly the owner-less one above.
    # Kept after the drop because the payload is what a tampered POST would actually send — a client
    # written against the pool era — and the answer must be a 422 rather than an UnknownAttribute
    # 500.
    # ** ONE CATEGORY, ONE CATCH-ALL RULE, ON THE WIRE (two-ledger spec §3; computed-claims ruling of
    # 2026-09-03). ** `groceries` already carries the file's `let!(:rule)` — an item-less $200 rate —
    # so a second rule naming no item is the shape whose claim would double-count the category's own
    # spending. The model answers on `:base`, which is where `budgets/_form` prints it, and the
    # controller turns that into the same 422 every other shape refusal gets.
    it "refuses a second rule covering the whole of one category", :aggregate_failures do
      expect { post budgets_path, params: { budget: rule_words(category_id: groceries.id) } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("already has a rule covering all of its spending")
    end

    # THE OTHER DIRECTION, on the same category and through the same POST: a rule that names an ITEM
    # has a lane of its own and is written.
    it "writes a second rule on the same category when it names an item", :aggregate_failures do
      phone = create(:item, category: groceries, name: "Phone")

      expect do
        post budgets_path, params: { budget: rule_words(category_id: groceries.id, item_id: phone.id) }
      end.to change(Budget, :count).by(1)
      expect(response).to redirect_to(budget_page_path)
    end

    it "ignores a pool_id entirely and writes no rule", :aggregate_failures do
      expect { post budgets_path, params: { budget: rule_words(pool_id: SecureRandom.uuid) } }
        .not_to change(Budget, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # The write, not just the read: "it 302s to the Budget page" and "the amount moved" are two
  # different facts and both are asserted.
  describe "PATCH /budgets/:id" do
    it "updates a rule and returns to the Budget page", :aggregate_failures do
      patch budget_path(rule), params: { budget: { amount: "275.00" } }

      expect(response).to redirect_to(budget_page_path)
      expect(rule.reload.amount).to eq(275)
    end

    it "refuses another user's rule and leaves it alone", :aggregate_failures do
      foreign = create(:budget, :rate, category: stranger_category, amount: 90)

      patch budget_path(foreign), params: { budget: { amount: "999.00" } }

      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.amount).to eq(90)
    end

    # ** RE-PARENTING IS NOT A THING THIS ACTION DOES ANY MORE (fix round 1 — M1). ** It WAS: the
    # key was permitted and merely ownership-scoped, so a PATCH could move a rule between the user's
    # own categories — an act no control on §4's form can ask for (the category is read-only on an
    # edit) and one the page that LISTS rules should own, since that page is what groups them by
    # category. `BudgetsController#update_params` drops the key outright, which is the only spelling
    # of "not writable" that a hand-made request also obeys.
    #
    # THESE THREE EXAMPLES ARE THE OLD PAIR PLUS ITS INCOME TWIN, FLIPPED RATHER THAN DELETED. Each
    # pinned a branch of a re-parent that could still be attempted; what changed is the answer, and
    # the answer has to be pinned or the key could quietly come back.
    it "leaves the category alone when a PATCH carries another of the user's own", :aggregate_failures do
      own = create(:category, :expense, :funded, user: user, name: "Dining Out")

      patch budget_path(rule), params: { budget: rule_words(category_id: own.id) }

      expect(response).to redirect_to(budget_page_path)
      expect(rule.reload.category).to eq(groceries)
      expect(own.budgets.reload).to be_empty
    end

    it "leaves the category alone when a PATCH carries a stranger's", :aggregate_failures do
      patch budget_path(rule), params: { budget: rule_words(category_id: stranger_category.id) }

      expect(response).to redirect_to(budget_page_path)
      expect(rule.reload.category).to eq(groceries)
      expect(stranger_category.budgets.reload).to be_empty
    end

    # THE INCOME ARM, WHICH USED TO BE A 422 FROM `Budget#category_must_be_an_expense`. `#update`
    # wrote straight through `BudgetProposal`'s guard, so this re-parent once SAVED CLEAN — the rule
    # counted into `Budget.steady_need` and was unfillable forever, since `Category.in_fill_order` is
    # holders and an income category can never be one. It is answered a layer earlier now: the key
    # never reaches the record, so there is nothing for the validation to refuse. The validation
    # stays where it is, for a category the user later switches to income.
    it "leaves the category alone when a PATCH carries the user's own income category", :aggregate_failures do
      income = create(:category, :income, user: user)

      patch budget_path(rule), params: { budget: rule_words(category_id: income.id) }

      expect(response).to redirect_to(budget_page_path)
      expect(rule.reload.category).to eq(groceries)
      expect(income.budgets.reload).to be_empty
    end

    # ** A SHAPE CHANGE ON AN EXISTING RULE IS LEGAL (§4), AND THE CLAIM SIMPLY RE-RUNS. ** The
    # "the schedule itself is already set on this rule" form is gone: a rate rule becoming a
    # building one is a decision the user is now allowed to make, and because the claim is COMPUTED
    # the walk re-runs from the rule's accrual start under the new shape with nothing migrated.
    # `Budget#claim_shape` is the one door onto that reading, and it is what is asserted — the three
    # columns beside it are what the form actually wrote.
    it "turns a rate rule into a building one and the claim reads the new shape", :aggregate_failures do
      patch budget_path(rule),
            params: { budget: rule_words(schedule: "per_period", unspent: "builds", target_amount: "5000", amount: "200") }

      expect(response).to redirect_to(budget_page_path)
      expect(rule.reload.carries_over).to be true
      expect(rule.target_amount).to eq(5_000)
      expect(rule.claim_shape).to eq(:building)
    end

    # THE OTHER DIRECTION, because a target left behind on a rule whose money now resets is a figure
    # no formula reads sitting on a row that looks like progress.
    it "turns a building rule back into a rate rule and drops the target", :aggregate_failures do
      fund = create(:budget, :capped, category: create(:category, :expense, :funded, user: user), amount: 200)

      patch budget_path(fund), params: { budget: rule_words(unspent: "resets", amount: "200") }

      expect(response).to redirect_to(budget_page_path)
      expect(fund.reload.carries_over).to be false
      expect(fund.target_amount).to be_nil
      expect(fund.claim_shape).to eq(:rate)
    end

    # A PARTIAL PATCH KEEPS THE SHAPE IT DID NOT MENTION. `RuleForm` reads `per_period` when nothing
    # says otherwise — right for a blank form, catastrophic for a request naming only an amount —
    # so `#update` merges the submission over the rule's OWN words. §4's form submits every control
    # on every save, so this changes nothing about what a user's submission does.
    it "leaves a dated bill's schedule alone when only the amount is sent", :aggregate_failures do
      bill = create(:budget, :recurring, category: create(:category, :expense, :funded, user: user), amount: 800)

      patch budget_path(bill), params: { budget: { amount: "900" } }

      expect(response).to redirect_to(budget_page_path)
      expect(bill.reload.amount).to eq(900)
      expect(bill.interval_months).to eq(6)
      expect(bill.anchor_date).to eq(Date.new(2026, 6, 1))
    end

    # THE SAME CONTRADICTION AS THE POST, ON THE UPDATE PATH: a due date that the chosen schedule
    # does not take is refused under "How often" rather than dropped on the way in.
    it "refuses a per-period rule carrying a due date, under How often", :aggregate_failures do
      patch budget_path(rule), params: { budget: rule_words(schedule: "per_period", anchor_date: "2026-12-01") }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("How often does not take a due date")
      expect(rule.reload.anchor_date).to be_nil
    end
  end

  describe "DELETE /budgets/:id" do
    it "deletes a rule and returns to the Budget page", :aggregate_failures do
      expect { delete budget_path(rule) }.to change(Budget, :count).by(-1)
      expect(response).to redirect_to(budget_page_path)
      expect(Budget.exists?(rule.id)).to be false
    end

    it "refuses to delete another user's rule", :aggregate_failures do
      foreign = create(:budget, :rate, category: stranger_category)

      delete budget_path(foreign)

      expect(response).to have_http_status(:not_found)
      expect(Budget.exists?(foreign.id)).to be true
    end
  end
end
