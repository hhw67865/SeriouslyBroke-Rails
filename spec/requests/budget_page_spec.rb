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

  # ** THE TWO THINGS THE URL SAYS ABOUT ONE RENDER (two-shapes spec §4). ** Neither is trusted with
  # anything: `open` is compared as a string against the ids the page itself rendered, and `declare`
  # is a presence read. A request spec because both are facts about the ROUTE — the page's own
  # behaviour is `system/budget_page/open_spec.rb`'s.
  describe "GET /budget", :aggregate_failures do
    def holder(name, priority: 1)
      create(:category, :expense, :funded, user: user, name: name, priority: priority).tap do |category|
        create(:budget, :per_period_rate, category: category, amount: 400)
      end
    end

    # ** `?open=` OPENS THAT CATEGORY'S PANEL AND ONLY THAT ONE. ** The closed panels are RENDERED
    # and `hidden` (§4 asks for expand with no round trip), so the assertion is on the attribute
    # rather than on the presence of the markup: a check for the panel's own hook would pass on
    # every row on the page.
    it "opens the category the parameter names, and only that one" do
      groceries = holder("Groceries")
      holder("Rent", priority: 2)

      get budget_page_path(open: groceries.id)

      expect(response.body).to include(%(data-category-id="#{groceries.id}"))
      expect(response.body.scan(/data-app--budget-page--category-list-target="panel"[^>]*/).count { |tag| tag.include?("hidden") })
        .to eq(1)
    end

    # NOTHING OPEN WITHOUT THE PARAMETER — the memory is the viewer's browser's, not the server's,
    # so a bare load opens nothing and `category_list_controller` restores what it restores.
    it "opens nothing at all without the parameter" do
      holder("Groceries")
      holder("Rent", priority: 2)

      get budget_page_path

      expect(response.body.scan(/data-app--budget-page--category-list-target="panel"[^>]*/).count { |tag| tag.include?("hidden") })
        .to eq(2)
    end

    # AN ID THAT IS NOT THIS USER'S SIMPLY MATCHES NO ROW. The page never looks the parameter up —
    # it compares it against the ids it rendered — so a stranger's category is not a 404 and not a
    # leak, it is a page with nothing open.
    it "opens nothing for an id that is not this user's" do
      holder("Groceries")
      stranger = create(:category, :expense, :funded, user: create(:user), name: "Theirs")

      get budget_page_path(open: stranger.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Theirs")
    end

    # ** THE DECLARATION FORM IS BEHIND "change" (§4), where it used to be permanently open under a
    # paragraph of prose. ** Both directions, because a form that never rendered would pass the
    # first half alone.
    it "reveals the declaration form only when asked for it" do
      get budget_page_path

      expect(response.body).not_to include("data-declaration")

      get budget_page_path(declare: 1)

      expect(response.body).to include("data-declaration")
      expect(response.body).to include("Save period and income")
    end
  end

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

  # ** `scale` IS ON THE WIRE, SO THE GUARD HAS TO BE AT THE WRITE (fix round LOW-1). ** The offer
  # is only made for a cadence that is really MOVING — a FIRST cadence is not a change, because
  # until the user names a period their per-period amounts are denominated in the 12-a-year
  # FALLBACK, an assumption the app made rather than anything they said. `CadenceChange#offered?`
  # says so, but `#offered?` gates the QUESTION; a `scale=1` typed by hand never passes through it.
  #
  # Unguarded, this request scales $400 by 12/26 against that fallback and writes $184.62 — the
  # user's only rule rewritten to 46 cents in the dollar by a parameter the page never rendered.
  # The cadence itself still saves, because there was never anything wrong with the declaration.
  describe "a scale answer to a question that was never asked", :aggregate_failures do
    # `scale` RIDES BESIDE `user[...]`, not inside it — the confirm's two buttons are
    # `name="scale"` on the same form, so this is the shape a real answer arrives in.
    def answer_scale(params) = patch(budget_page_user_path, params: { user: params, scale: "1" })

    def holding_category = create(:category, :expense, :funded, user: user, name: "Groceries")

    # A GOAL FED ONLY BY HAND: `carries_over` and a `target_amount` ON THE RULE are what make
    # `Budget#set_aside_only?` true and the amount-0 rule legal at the model (rules-own-the-budget
    # spec §2.1 row 4). The category names nothing — it is a name with a priority now.
    def goal_category
      create(:category, :expense, :funded, user: user, name: "Someday")
    end

    # THE EMERGENCY FUND (§2.2): a per-period rule whose unspent money BUILDS UP. Its amount is
    # denominated per period exactly as a rate rule's is, so a cadence change means the same thing
    # for it and it scales.
    def fund_category
      create(:category, :expense, :funded, user: user, name: "Emergency")
    end

    # A RULE THE CADENCE CANNOT CHANGE THE MEANING OF: "$1,200 every 6 months, next due Dec 1" names
    # an OCCURRENCE, and the catch-up formula re-plans it on whatever grid exists.
    def dated_bill
      create(:budget, amount: 1_200, interval_months: 6, anchor_date: Date.new(2026, 12, 1), category: holding_category)
    end

    # ** AND THE FLASH SAYS ONLY WHAT WAS WRITTEN (fix round 2, NEW-1). ** The sentence used to
    # branch on the PARAMETER rather than on what `#apply` did, so this same request — the cadence
    # saved, not one amount touched — told the user "your per-period amounts were scaled to it".
    # A flash claiming a rewrite that did not happen is worse than no flash: the user has no reason
    # to check, and the rules they would have checked are the ones the sentence is about.
    it "saves the first cadence, leaves every amount alone, and does not claim a scaling", :aggregate_failures do
      rule = create(:budget, :per_period_rate, amount: 400, category: holding_category)

      answer_scale(period_cadence: "biweekly", period_anchor_date: "2026-02-06")

      expect(response).to redirect_to(budget_page_path)
      expect(user.reload.period_cadence).to eq("biweekly")
      expect(rule.reload.amount).to eq(400)
      expect(flash[:notice]).to eq("Your period and income are saved — every figure below is re-derived.")
    end

    # THE SECOND UNTRUE CASE, and it is a REAL cadence change: monthly to biweekly on a user whose
    # only rule is a dated bill. `#offered?` is false because there is nothing denominated in
    # periods to scale — the confirm was never rendered and there was nothing for it to list — so
    # `#apply` scales nothing and the sentence must not say it did.
    it "says nothing about scaling on a real change with no per-period rule", :aggregate_failures do
      user.update!(period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 1))
      bill = dated_bill

      answer_scale(period_cadence: "biweekly", period_anchor_date: "2026-02-06")

      expect(user.reload.period_cadence).to eq("biweekly")
      expect(bill.reload.amount).to eq(1_200)
      expect(flash[:notice]).to eq("Your period and income are saved — every figure below is re-derived.")
    end

    # THE TRUE CASE, on the same route and with the same parameter, so the two sentences are pinned
    # against each other rather than one of them alone: a real change with a per-period rule to
    # scale writes $400 × 12 ÷ 26 = $184.62 and says so.
    it "says the amounts were scaled where they actually were", :aggregate_failures do
      user.update!(period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 1))
      rule = create(:budget, :per_period_rate, amount: 400, category: holding_category)

      answer_scale(period_cadence: "biweekly", period_anchor_date: "2026-02-06")

      expect(rule.reload.amount).to eq(BigDecimal("184.62"))
      expect(flash[:notice]).to eq(
        "Your period is saved and your per-period amounts were scaled to it — every figure below is re-derived."
      )
    end

    # ** THE THREE "$0 GOAL RULE" AND "BUILDING RULE" EXAMPLES WERE DELETED WITH THEIR SHAPES
    # (two-shapes spec §2/§7), AND ONE OF THEM COMES BACK (§12). ** They pinned that a hand-fed goal
    # (`amount: 0`) was neither scaled nor offered — `CadenceChange::SMALLEST_RATE` had floored
    # `0 × 12/26` at $0.01, a standing contribution the owner never declared — and that a per-period
    # rule which CARRIED ITS MONEY OVER scaled like any other, because what the amount is
    # denominated in is the whole question.
    #
    # The zero row still cannot be written (`Budget` validates `amount > 0` on every shape), and the
    # goal that carries its money toward a DATE is `:one_off`, already excluded. But §12 restores an
    # allowance that keeps what it doesn't spend, whose `#cadence` is `:per_period` — so the second
    # example's sentence is true again and it is asserted below rather than left to the classifier.

    # ** A FUND SCALES LIKE ANY OTHER PER-PERIOD RULE (§12), AND THE REASON IS THE ONE
    # `CadenceChange` STATES: what the amount is DENOMINATED IN. ** "$510 a period, keeps" means
    # $13,260 a year on a fortnightly grid and $6,120 on a monthly one, exactly as a resetting $510
    # would — the keeping changes what the rule is worth after the boundary, not what it asks of a
    # period. `Budget#steady_ask` hands `Budget.steady_need` its amount verbatim either way, so a
    # fund left behind by a cadence change would be a claim in the wrong unit on every screen.
    #
    # $510 × 12 ÷ 26 = **$235.38**, and the rate rule beside it is scaled in the same request so a
    # fix that simply stopped scaling could not pass.
    it "scales a fund exactly as it scales the rate rule beside it", :aggregate_failures do
      user.update!(period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 1))
      fund = create(:budget, :keeps_unspent, amount: 510, category: fund_category)
      rate = create(:budget, :per_period_rate, amount: 400, category: holding_category)

      answer_scale(period_cadence: "biweekly", period_anchor_date: "2026-02-06")

      expect(fund.reload.amount).to eq(BigDecimal("235.38"))
      expect(fund).to be_keeps_unspent
      expect(rate.reload.amount).to eq(BigDecimal("184.62"))
    end

    # ** A DATED RULE IS NOT SCALED AND IS NOT OFFERED, which is the surviving half of the pair. **
    # "$5,000 by Jun 1, 2027" names an OCCURRENCE rather than a period and the catch-up formula
    # re-plans it on whatever grid exists, so a ratio applied to it would be applied twice. Both
    # directions in one request: the $400 rate rule beside it IS scaled, so a fix that simply stopped
    # scaling would fail here too.
    it "leaves a goal alone while scaling the rate rule beside it", :aggregate_failures do
      user.update!(period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 1))
      rate = create(:budget, :per_period_rate, amount: 400, category: holding_category)
      goal = create(:budget, :by_date, amount: 5_000, category: goal_category)

      answer_scale(period_cadence: "biweekly", period_anchor_date: "2026-02-06")

      expect(rate.reload.amount).to eq(BigDecimal("184.62"))
      expect(goal.reload.amount).to eq(5_000)
    end

    # THE OFFER ITSELF, on the screen that makes it (`BudgetPageController#offer_scaling` renders
    # `show` at 422 rather than redirecting): the goal is not a line and the rate rule is. Asserted
    # on the rendered page rather than on `CadenceChange#lines`, because "offered" and "not offered"
    # are facts about what the user is shown — and the panel names an item-less rule by its CATEGORY.
    it "lists the rate rule on the confirm it offers and not the goal", :aggregate_failures do
      user.update!(period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 1))
      create(:budget, :per_period_rate, amount: 400, category: holding_category)
      create(:budget, :by_date, amount: 5_000, category: goal_category)

      patch(budget_page_user_path, params: { user: { period_cadence: "biweekly", period_anchor_date: "2026-02-06" } })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('data-cadence-line="Groceries"')
      expect(response.body).not_to include('data-cadence-line="Someday"')
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
  # `categories.priority` outside the category form, and unlike the declaration above it takes IDS
  # off the wire — so the question here is whose categories they are.
  #
  # ONE LIST, WHERE THERE WERE BANDS (two-ledger spec §2). The wire carried `pool_ids[]` for one
  # ACCOUNT, because priority was only compared inside an account; `AllocationCalculator` fills
  # every holder off one root now, so the whole page is one order. TWO EXAMPLES ARE DELETED WITH
  # THE BANDS — "leaves the same user's other account untouched" and "refuses two accounts in one
  # order" — because neither names a shape a request can be composed in: there is no second list
  # for a reorder to leak into and no account to mix.
  #
  # A request spec, because the browser can only ever submit the order the page rendered: a list
  # naming another user's category or missing one of its own is a fact about the route, and every
  # one of them must leave `priority` exactly as it was.
  describe "the fill order" do
    let!(:rent) { holder("Rent", priority: 0) }
    let!(:groceries) { holder("Groceries", priority: 1) }

    # A CATEGORY THAT HOLDS MONEY AND CARRIES A RULE — the two conditions `Category.apply_fill_order`
    # refuses a list that is not exactly the set of.
    def holder(name, priority:)
      category = create(:category, :expense, :funded, user: user, name: name, priority: priority)
      create(:budget, :per_period_rate, category: category, amount: 100)
      category
    end

    def reorder(ids) = patch(budget_page_reorder_path, params: { category_ids: ids })

    # The whole holder set, name by name — a count would pass on a set that had been shuffled.
    def fill_order = user.categories.in_fill_order.pluck(:name, :priority)

    describe "a list of the user's categories in a new order", :aggregate_failures do
      it "writes a dense 0,1,2… and comes back to the page" do
        reorder([groceries.id, rent.id])

        expect(response).to redirect_to(budget_page_path)
        expect(fill_order).to eq([["Groceries", 0], ["Rent", 1]])
      end
    end

    # EVERY REFUSAL, ASSERTED IN BOTH DIRECTIONS: a pinned row that did not move AND the whole
    # order, because a pinned row alone would pass on a rewrite that moved everything else and a
    # whole-set comparison alone reads as a count.
    describe "a list this user cannot have submitted", :aggregate_failures do
      # The bad id sits MID-LIST rather than on the end, so a guard that stopped checking after
      # the first or last element would not pass this.
      it "refuses another user's category" do
        intruder = create(:category, :expense, :funded, name: "Theirs")

        reorder([groceries.id, intruder.id, rent.id])

        expect(response).to have_http_status(:unprocessable_content)
        expect(groceries.reload.priority).to eq(1)
        expect(fill_order).to eq([["Rent", 0], ["Groceries", 1]])
      end

      # A PARTIAL LIST IS A REFUSAL, NOT A PARTIAL WRITE: Rent would keep priority 0 and
      # Groceries would be written to 0 as well, and `[priority, name]` — not the user — would
      # decide which of the two gets funded first.
      it "refuses an order missing one of the user's own rule-carrying categories" do
        reorder([groceries.id])

        expect(response).to have_http_status(:unprocessable_content)
        expect(groceries.reload.priority).to eq(1)
        expect(fill_order).to eq([["Rent", 0], ["Groceries", 1]])
      end

      it "refuses a duplicated id, which would silently drop a category" do
        reorder([groceries.id, groceries.id])

        expect(response).to have_http_status(:unprocessable_content)
        expect(fill_order).to eq([["Rent", 0], ["Groceries", 1]])
      end

      it "says nothing was changed rather than failing silently" do
        reorder([groceries.id])

        expect(response.body).to include("nothing was changed")
      end

      # `Category.apply_fill_order` writes through `update!`, so a row that was ALREADY invalid
      # before the reorder — a `funded_since` in the future that a data fix left behind — raises
      # RecordInvalid from a reindex that had nothing to do with it. That must be this route's own
      # refusal, naming the row the user has to fix, rather than an unrescued 500 on a button they
      # were right to press.
      #
      # ** IT WAS A `target_amount` OF ZERO until §6's migration dropped `categories.target_amount`
      # and took `#target_is_a_goal` with it, AND THE COLUMN THAT REPLACES IT MATTERS. ** A negative
      # `priority` is the obvious substitute and it is the wrong one: the reindex OVERWRITES
      # `priority`, so the row saves clean and there is nothing left to refuse — measured, this
      # example passed a 302. `funded_since` is a column the reorder does not touch, which is what
      # makes it the same class of already-broken row the deleted fixture was.
      it "refuses at 422, naming the row, when a category is already invalid" do
        rent.update_column(:funded_since, Date.current + 1.month) # rubocop:disable Rails/SkipsModelValidations -- the point

        reorder([groceries.id, rent.id])

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Rent could not be saved (funded since can&#39;t be in the future")
        expect(fill_order).to eq([["Rent", 0], ["Groceries", 1]])
      end
    end

    # THE TWO SEMANTICS THE POOL ERA INVENTED, RE-ANCHORED. Every category in the fixtures above
    # carries a rule, so a list omitting a rule-less HOLDER and the slot-preserving branch that
    # keeps such a holder's rank were both unexercised. A savings goal is exactly this shape — it
    # holds money and is in the waterfall, and no rule fills it — so under a literal
    # "submit the whole fill order" guard every reorder a user with a goal can make was refused.
    #
    # The user reads Rent(0, rule), Emergency(1, goal), Groceries(2, rule), Vacation(3, goal).
    describe "holders no rule fills", :aggregate_failures do
      let!(:emergency) { goal("Emergency", priority: 1) }
      let!(:vacation) { goal("Vacation", priority: 3) }

      before { groceries.update!(priority: 2) }

      def goal(name, priority:)
        create(:category, :expense, :funded, user: user, name: name, priority: priority)
      end

      # The pair to "refuses an order missing one of the user's own rule-carrying categories":
      # omitting a category a rule FILLS is a refusal, omitting one no rule fills is the ordinary
      # case.
      it "accepts a list naming only the categories a rule fills" do
        reorder([groceries.id, rent.id])

        expect(response).to redirect_to(budget_page_path)
        expect(groceries.reload.priority).to eq(0)
      end

      # THE SLOT-PRESERVING BRANCH. Emergency and Vacation are named nowhere on the wire; the two
      # that are swap with each other and everything else holds its place. Renumbering only the
      # submitted categories would leave Emergency on 1 tied with Rent on 1, and `[priority, name]`
      # — not the user — would decide which of the two the waterfall fills first.
      it "keeps a rule-less holder's rank while renumbering the fill order densely" do
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
