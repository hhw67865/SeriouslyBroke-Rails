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

  # ** `#budget_rule_amount` AND ITS SIX EXAMPLES ARE DELETED (two-shapes spec §4). ** It printed the
  # STICKER — what the rule declares, `$1,200.00 every 6 months` — beside the claim's own figure on
  # `budget_page/_rule_row`, and the row's header argued that the repetition was deliberate. On a
  # dated rule it was the target said twice inside one sentence, and the rules table that replaced
  # the row has a column for the schedule alone: `HomeHelper#shape_words` says `bill · every 6
  # months` without saying the money again, and Edit is one click away for the declaration itself.
  #
  # WHAT THE SIX EXAMPLES PINNED AND WHERE IT LIVES NOW: the four "amount and what it is per" cases
  # are `#budget_rule_basis`' own words, still asserted through `#budget_rule_basis_phrase` below
  # and rendered by the dead-rule suggestion and the rule form's hint; the $0 pair pinned an arm no
  # `Budget` can reach since `amount > 0` was validated on every shape, and nothing renders it.

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

    # ** THE `unit:` OVERRIDE AND ITS EXAMPLE ARE DELETED (fix round 1's ruling). ** It existed for
    # exactly one row: a `monthly`-no-anchor rule read back as "Every period" with its MONTHLY figure
    # still in the box, so the record's own phrase would have called a month's money a period's.
    # `RuleForm.from` DIVIDES that figure now — the box is per-period money on every path — so the
    # record's phrase is the true one everywhere and there is no unit left to override.
    # `#budget_monthly_conversion_note` below is what names the ROW's unit.
  end

  # ** THE NOTE BESIDE THAT ROW'S AMOUNT (fix round 1's ruling). ** §5 rules the `monthly`-no-anchor
  # shape converts on save, and the fix round settled that what the conversion preserves is the
  # MONEY: the box opens at `Budget#steady_ask` and saving writes that. So the sentence is an
  # EXPLANATION rather than a warning — why the figure is not the one the user remembers typing, and
  # that the cost is unchanged. It used to read "saving it as every period would make it $260.00 a
  # period — change the amount if you mean that", which asked a reader to defend themselves against
  # their own form.
  describe "#budget_monthly_conversion_note" do
    def form_for(budget) = RuleForm.new(build(:user, :biweekly), RuleForm.from(budget), budget: budget)

    it "names the row's own figure and says the cost is kept" do
      note = helper.budget_monthly_conversion_note(form_for(build(:budget, :rate, amount: 260)))

      expect(note).to eq(
        "This rule was $260.00 a month — shown here as what it costs each period on your " \
        "biweekly grid. Saving keeps that cost."
      )
    end

    # THE OTHER DIRECTION, so the note is never a fixture of the page: every other shape says
    # nothing at all.
    it "says nothing on a rule whose words describe its own columns", :aggregate_failures do
      expect(helper.budget_monthly_conversion_note(form_for(build(:budget, :per_period_rate, amount: 400)))).to be_nil
      expect(helper.budget_monthly_conversion_note(form_for(build(:budget, :by_date, amount: 5_000)))).to be_nil
    end
  end

  # ---------------------------------------------------------------------------------------------
  # §5's preview card — the rule said back
  # ---------------------------------------------------------------------------------------------
  #
  # ** A REAL `RulePreview` OVER A REAL RULE, never a double. ** Every sentence below branches on a
  # shape that `ClaimCalculator` reads off columns `Budget`'s own validations decide are legal, and a
  # double is free to claim a shape the model would refuse — which is how a card comes to print a
  # sentence about a rule that cannot exist.
  describe "the preview sentences" do
    let(:user) { create(:user, :biweekly) }
    let(:groceries) { create(:category, :expense, :funded, user: user, name: "Groceries") }

    def preview_of(**columns)
      budget = Budget.new(category: groceries, **columns)
      RulePreview.new(RuleForm.new(user, RuleForm.from(budget), budget: budget), user: user)
    end

    # §5's own copy target, and the bold half is the RULE — who gets how much, how often. The due
    # date of a repeating rule trails it, because "every 2 months" is the rule and "next due Oct 3"
    # is where the cycle happens to stand today.
    it "says a repeating dated rule back with its interval and its next occurrence" do
      water = build(:item, category: groceries, name: "Water")
      preview = preview_of(amount: 48.20, basis: :monthly, interval_months: 2, anchor_date: Date.current + 1.month, rule_type: :bill, item: water)

      expect(helper.rule_preview_sentence(preview)).to eq(
        "<strong>Water gets $48.20 every 2 months</strong>, next due " \
        "#{(Date.current + 1.month).strftime("%b %-d, %Y")}."
      )
    end

    # THE OTHER TWO SHAPES. A one-off's date is INSIDE the bold — the day IS the rule there — and a
    # rate rule has no day at all.
    it "says the other two shapes back", :aggregate_failures do
      rate = preview_of(amount: 400, basis: :per_period, rule_type: :usage)
      goal = preview_of(amount: 5_000, basis: :monthly, anchor_date: Date.new(2027, 6, 1), rule_type: :choice)

      expect(helper.rule_preview_sentence(rate)).to eq("<strong>Groceries gets $400.00 every period</strong>.")
      expect(helper.rule_preview_sentence(goal)).to eq("<strong>Groceries gets $5,000.00 by Jun 1, 2027</strong>.")
    end

    # WHAT BECOMES OF THE MONEY — the one sentence that separates §2's two shapes, and the question
    # the deleted "Unspent money" radio used to make the user answer.
    it "says what becomes of the money, per shape", :aggregate_failures do
      rate = preview_of(amount: 400, basis: :per_period, rule_type: :usage)
      goal = preview_of(amount: 5_000, basis: :monthly, anchor_date: Date.new(2027, 6, 1), rule_type: :choice)

      expect(helper.rule_preview_holding_sentence(rate)).to start_with("Whatever's unspent resets on ")
      expect(helper.rule_preview_holding_sentence(goal))
        .to eq("Each period sets aside its share so the money is there on the day.")
    end

    # ** WHERE THE RULE SITS IN THE GIVE-WAY ORDER, WHICH IS WHAT THE TYPE IS FOR (§3). ** All three,
    # because the sentence is the only place on the form that says what choosing one COSTS.
    it "says which end of the give-way order each type is", :aggregate_failures do
      expect(helper.rule_preview_type_sentence(preview_of(amount: 90, basis: :per_period, rule_type: :bill)))
        .to eq("It's a bill, so it's the last thing to give way.")
      expect(helper.rule_preview_type_sentence(preview_of(amount: 90, basis: :per_period, rule_type: :usage)))
        .to eq("It's usage, so it gives way after your choices and before your bills.")
      expect(helper.rule_preview_type_sentence(preview_of(amount: 90, basis: :per_period, rule_type: :choice)))
        .to eq("It's a choice, so it's the first thing to give way.")
    end

    # ** THE TWO UNITS, FOR THE ONE ROW WHOSE WORDS DO NOT DESCRIBE ITS OWN COLUMNS (§5's ruling;
    # this task's carry). ** $260 a month is $120.00 a period on a fortnightly grid, and the second
    # figure is `Budget#steady_ask`'s — the app's one normaliser — rather than a division written
    # here. Nil on every other rule, so the line is never a fixture of the card.
    # THE MONTHLY HALF IS THE ROW'S (carried on the flag) AND THE PER-PERIOD HALF IS THE BOX'S, which
    # after the read-back's division is `Budget#steady_ask` — so the card names the two figures a
    # user has to be able to reconcile, and neither is derived from the other here.
    it "states both units for a monthly rule read back as every period", :aggregate_failures do
      monthly = create(:budget, :rate, category: groceries, amount: 260, rule_type: :usage)
      preview = RulePreview.new(RuleForm.new(user, RuleForm.from(monthly), budget: monthly), user: user)

      expect(helper.rule_preview_units(preview)).to eq("$260.00 a month · $120.00 a period on your biweekly grid")
      expect(helper.rule_preview_units(preview_of(amount: 400, basis: :per_period, rule_type: :usage))).to be_nil
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
