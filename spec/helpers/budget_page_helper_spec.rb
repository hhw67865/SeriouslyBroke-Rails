# frozen_string_literal: true

require "rails_helper"

RSpec.describe BudgetPageHelper, type: :helper do
  # Real Budget records rather than doubles: every branch below reads a combination of `basis`,
  # `interval_months` and `anchor_date` that Budget's own validations decide is legal, and a
  # double is free to claim a shape the model would refuse.
  def rule(*traits, **attrs) = build(:budget, *traits, **attrs)

  describe "#budget_rule_name" do
    it "names the item it pays" do
      budget = rule(category: build(:category, :expense, :funded), item: build(:item, name: "Rent Bill"))

      expect(helper.budget_rule_name(budget)).to eq("Rent Bill")
    end

    it "falls back to the category for an item-less rule" do
      budget = rule(category: build(:category, :expense, :funded, name: "Groceries"))

      expect(helper.budget_rule_name(budget)).to eq("Groceries")
    end

    # THE POOL ARM AND ITS EXAMPLE ARE DELETED WITH `budgets.pool_id` (two-ledger spec §5,
    # Task 8). It read "falls back to the pool for a rule written before the cutover"; there is one
    # owner lane now and the category arm above is it.
  end

  # THE FIGURE AND WHAT IT IS A FIGURE PER. $600 a period and $600 every six months are the same
  # digits and a twelvefold difference in what the user owes.
  describe "#budget_rule_amount" do
    it "says a rate rule's period" do
      expect(helper.budget_rule_amount(rule(:per_period_rate, category: build(:category, :expense, :funded), amount: 400))).to eq("$400.00 / period")
    end

    it "says a recurring rule's interval" do
      budget = rule(category: build(:category, :expense, :funded), amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))

      expect(helper.budget_rule_amount(budget)).to eq("$600.00 every 6 months")
    end

    it "says a monthly rule is monthly" do
      expect(helper.budget_rule_amount(rule(:rate, category: build(:category, :expense, :funded), amount: 120))).to eq("$120.00 a month")
    end

    it "says a one-off rule happens once" do
      expect(helper.budget_rule_amount(rule(:one_time, category: build(:category, :expense, :funded), amount: 300))).to eq("$300.00 once")
    end

    # ** THE MINTED GOAL RULE, WHICH HAS NO RATE TO STATE (fix wave — LOW-4). ** Zero is legal on
    # exactly one shape — a dateless target rule (`Budget#set_aside_only?`, spec §10.1 ruling 3) —
    # and Task 4's migration minted one for every goal in the database that lacked a rule. The
    # sticker printed "$0.00 / period" for those, beside a real built-up figure on the same row,
    # which reads as a rule somebody set wrong rather than a rule that was never about a rate.
    #
    # ** THE TARGET IS THE RULE'S (rules-own-the-budget spec §2.1 row 4). ** The fixture put it on
    # the CATEGORY, because that was the only shape the model let the amount be zero on; Task 4
    # dropped `categories.target_amount` and `#set_aside_only?` reads all three columns off the rule,
    # so `:hand_fed` is that same shape said on the record that owns it. THE HELPER READS NEITHER —
    # it branches on the amount alone — which is why the sticker is what this example asserts.
    it "says a $0 goal rule is fed by hand" do
      goal = build(:category, :expense, :funded)

      expect(helper.budget_rule_amount(rule(:hand_fed, category: goal))).to eq("fed by hand")
    end

    # THE OTHER DIRECTION, one penny apart: a rule that names ANY rate states it, so the gate cannot
    # be satisfied by a helper that stopped printing figures.
    it "still states a rate of a single cent" do
      goal = build(:category, :expense, :funded)

      expect(helper.budget_rule_amount(rule(:per_period_rate, category: goal, amount: 0.01))).to eq("$0.01 / period")
    end
  end

  # ** THE SAME FACT IN A SENTENCE, AND IT NOW SAYS WHAT BECOMES OF THE MONEY (rules-own-the-budget
  # spec §2.1). ** The cadence alone was the whole story while every dateless rule reset at the
  # boundary; a rule may now BUILD UP, and "$300.00 per period" says exactly the same words about a
  # fund that keeps every unspent penny as about a grocery budget that keeps none.
  describe "#budget_rule_basis_phrase" do
    # THE RESETTING ARMS ARE UNTOUCHED, which is the direction that keeps every figure already
    # pinned on the drift accept form ("Currently $150.00 per period", "Currently $260.00 a month").
    it "says per period for a rate rule" do
      expect(helper.budget_rule_basis_phrase(rule(:per_period_rate, amount: 400))).to eq("per period")
    end

    it "says a month for a monthly rate rule" do
      expect(helper.budget_rule_basis_phrase(rule(:rate, amount: 260))).to eq("a month")
    end

    # §2.1 row 2 — the fund that grows without limit. There is no figure to name, so it names none
    # rather than printing an empty one.
    it "says a per-period fund builds up" do
      expect(helper.budget_rule_basis_phrase(rule(:building, amount: 300))).to eq("per period, builds up")
    end

    # §2.1 row 3 — the goal. "builds up" and "builds up toward $1,200.00" are different promises:
    # the first grows for as long as the rule lives, the second stops.
    it "names the figure a capped fund is building toward" do
      expect(helper.budget_rule_basis_phrase(rule(:capped, amount: 200))).to eq("per period, builds up toward $1,200.00")
    end

    it "says the same of a monthly rule that builds up" do
      budget = rule(basis: :monthly, interval_months: 1, carries_over: true, amount: 260)

      expect(helper.budget_rule_basis_phrase(budget)).to eq("a month, builds up")
    end

    # SAVED, on one category: a per-period rate, a monthly rate, a capped fund and a dated bill —
    # every shape `Budget#shape_must_be_valid` permits. The fund is the item-LESS rule because
    # `Budget#category_may_hold_one_item_less_rule` allows exactly one and a building rule with an
    # item is not the category's own lane; the other three take a lane apiece.
    def every_saved_shape
      category = create(:category, :expense, :funded)
      lane = ->(name) { create(:item, category: category, name: name) }
      [
        create(:budget, :per_period_rate, category: category, amount: 400, item: lane["Bread"]),
        create(:budget, :rate, category: category, amount: 260, item: lane["Milk"]),
        create(:budget, :capped, category: category, amount: 200),
        create(
          :budget,
          category: category,
          amount: 600,
          interval_months: 6,
          anchor_date: Date.new(2026, 3, 1),
          item: lane["Insurance"]
        )
      ]
    end

    # ** THE HELPER READS THE RAW COLUMNS AND THIS IS WHAT STOPS THE TWO SPELLINGS DRIFTING (fix
    # wave — LOW-3). ** `Budget#claim_shape` is the app's one door onto §3's three formulas, and the
    # helper deliberately does not use it: `budgets/_form.html.erb` calls the helper with
    # `RuleForm#budget`, a `Budget.new` with no category on the new-rule path, and `#claim_shape`
    # builds a calculator whose `today:` falls back to `Date.current` there — the ambient clock
    # inside a form hint, on a record whose owner has not been chosen yet.
    #
    # SO THE AGREEMENT IS PINNED INSTEAD, over every SAVED shape (`Budget#shape_must_be_valid`
    # refuses the one pair — an anchor beside `carries_over` — that could make the two disagree, so
    # these four are all there are). The clause the helper adds is exactly `:building`:
    #
    #   per-period rate → :rate     → no clause
    #   monthly rate    → :rate     → no clause
    #   capped fund     → :building → "builds up toward $1,200.00"
    #   dated bill      → :dated    → no clause (the anchor wins, §3.2)
    it "adds the build-up clause exactly where the rule's claim shape is :building", :aggregate_failures do
      saved = every_saved_shape

      saved.each do |budget|
        clause = helper.budget_rule_basis_phrase(budget).include?("builds up")

        expect(clause).to eq(budget.claim_shape == :building), "#{budget.claim_shape} said #{clause}"
      end
      expect(saved.map(&:claim_shape)).to eq([:rate, :rate, :building, :dated])
    end
  end

  # ** THE HINT'S SECOND CLAUSE IS GONE WITH THE FORM IT DESCRIBED (spec §7). ** It read "— the
  # schedule itself is already set on this rule", which was true of exactly one form: the edit form
  # that refused to re-offer a rule's shape. §4's form offers every control on both paths, so the
  # sentence would now point away from a radio the user is looking straight at.
  describe "#budget_amount_hint" do
    it "names the unit and nothing about where the schedule lives" do
      expect(helper.budget_amount_hint(rule(:per_period_rate, amount: 400)))
        .to eq("What this rule asks for per period.")
    end

    it "carries the build-up into the hint" do
      expect(helper.budget_amount_hint(rule(:capped, amount: 200)))
        .to eq("What this rule asks for per period, builds up toward $1,200.00.")
    end
  end

  # ** `#pool_balance_clause` AND ITS TWO EXAMPLES ARE DELETED (computed-claims spec §6). ** They
  # asserted, over all seven `HoldingStatus` states, that a group said its BALANCE exactly once:
  # the clause `· holds $250.00` printed for the three states whose label named a bill's shortfall
  # instead, and stayed silent for the four whose label was the balance already. Every one of those
  # states is a reading of money MOVED into a category, and nothing moves on the purpose side any
  # more (§5) — `HoldingStatus` is deleted, and so is the helper that read it.
  #
  # WHAT REPLACED THE SENTENCE, and where it is pinned: §3.4's row prints ONE figure per rule,
  # named — `spent of rate` for an envelope, `built up of target` for a fund — so there is no
  # second clause to fill in a figure the first one left out. `HomeHelper#claim_figure` is that
  # reader and `spec/helpers/home_helper_spec.rb` pins it; the row is pinned on the page in
  # `spec/system/budget_page/rules_spec.rb`.

  # `#budget_rule_reason` AND ITS ONE SURVIVING EXAMPLE ARE DELETED (two-ledger spec §5, Task 5).
  # It gave an account-less pool Home's own wording, which was the last reason a rule could be
  # outside the fill order; a rule belongs to a category and every category is in the waterfall, so
  # `BudgetPagePresenter::Rule` no longer carries a `reason` for the helper to word.
end
