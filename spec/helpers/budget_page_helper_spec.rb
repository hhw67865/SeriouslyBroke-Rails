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

    # ** THE $0 ARM IS A GUARD AND ITS ROW CANNOT BE SAVED ANY MORE (two-shapes spec §2/§7). ** Zero
    # was legal on exactly one shape — the dateless target fed by hand — and the sticker printed
    # "$0.00 / period" for it beside a real built-up figure, which reads as a rule somebody set wrong
    # rather than a rule that was never about a rate. `Budget` validates `amount > 0` on every shape
    # now, so the rule is built UNSAVED here: the helper branches on the amount alone and the sticker
    # is still what this example asserts.
    it "says a $0 rule is fed by hand" do
      goal = build(:category, :expense, :funded)

      expect(helper.budget_rule_amount(build(:budget, :per_period_rate, category: goal, amount: 0)))
        .to eq("fed by hand")
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

    # ** THE BUILD-UP CLAUSE IS DELETED WITH THE COLUMNS IT READ (two-shapes spec §7), AND SO ARE ITS
    # FOUR EXAMPLES. ** They pinned "per period, builds up", "per period, builds up toward $1,200.00",
    # the monthly twin of the first, and the agreement between the clause and `Budget#claim_shape`
    # over every saved shape. All of them are about `budgets.carries_over` and `budgets.target_amount`,
    # which `TwoShapes` drops: there is ONE dateless shape now — the allowance that resets — and what
    # a fund is building toward is its own AMOUNT with a DATE beside it, which `#budget_rule_amount`
    # and the row's due date already print.
    #
    # WHAT IS LEFT IS THE CADENCE WORDS, exactly as they read before the clause was added — so every
    # figure a resetting rule printed is unchanged, and the two examples above are the whole of it.

    # THE DATED ARM, so "no clause" is asserted rather than assumed of the one shape that accrues.
    it "says once for a one-off and every N months for a repeating bill", :aggregate_failures do
      expect(helper.budget_rule_basis_phrase(rule(:by_date, amount: 5_000))).to eq("once")
      expect(helper.budget_rule_basis_phrase(rule(:recurring, amount: 600))).to eq("every 6 months")
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

    # THE DATED ARM'S HINT, which is the second thing the sentence can say. The build-up clause it
    # used to carry ("builds up toward $1,200.00") is deleted with the columns — see
    # `#budget_rule_basis_phrase` above.
    it "names the unit for a one-off too" do
      expect(helper.budget_amount_hint(rule(:by_date, amount: 5_000)))
        .to eq("What this rule asks for once.")
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
