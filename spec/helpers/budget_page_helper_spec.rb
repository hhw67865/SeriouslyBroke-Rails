# frozen_string_literal: true

require "rails_helper"

RSpec.describe BudgetPageHelper, type: :helper do
  # Real Rule records rather than doubles: every branch below reads a combination of
  # `anchor_date`, `interval_months` and `keeps_unspent` that Rule's own validations decide is
  # legal, and a double is free to claim a shape the model would refuse.
  def rule(*traits, **attributes) = build(:rule, *traits, **attributes)

  describe "#rule_name" do
    it "names the item it pays" do
      expect(helper.rule_name(rule(item: build(:item, name: "Rent Bill")))).to eq("Rent Bill")
    end

    it "falls back to the category for an item-less rule" do
      expect(helper.rule_name(rule(category: build(:category, name: "Groceries")))).to eq("Groceries")
    end
  end

  describe "#rule_basis_phrase" do
    it "says per period for a rate rule" do
      expect(helper.rule_basis_phrase(rule(:rate, amount: 400))).to eq("per period")
    end

    it "says once for a one-off and every N months for a repeating bill", :aggregate_failures do
      expect(helper.rule_basis_phrase(rule(:by_date, amount: 5_000))).to eq("once")
      expect(helper.rule_basis_phrase(rule(:rolling, amount: 600))).to eq("every 6 months")
    end
  end

  describe "#rule_amount_hint" do
    it "names the unit the amount is in", :aggregate_failures do
      expect(helper.rule_amount_hint(rule(:rate, amount: 400))).to eq("What this rule asks for per period.")
      expect(helper.rule_amount_hint(rule(:by_date, amount: 5_000))).to eq("What this rule asks for once.")
    end
  end

  describe "#interval_label" do
    it "says a bare interval in months", :aggregate_failures do
      expect(helper.interval_label(1)).to eq("every month")
      expect(helper.interval_label(6)).to eq("every 6 months")
    end
  end

  # A real RulePreview over a real rule, never a double: every sentence branches on a shape
  # ClaimCalculator reads off columns Rule's validations decide are legal.
  describe "the preview sentences" do
    let(:user) { create(:user, :biweekly) }
    let(:due) { user.today + 1.month }
    let(:water) do
      preview_of(
        amount: 48.20,
        interval_months: 2,
        anchor_date: due,
        rule_type: :bill,
        item: create(:item, category: groceries, name: "Water")
      )
    end
    let(:rate) { preview_of(amount: 400, rule_type: :usage) }
    let(:goal) { preview_of(amount: 5_000, anchor_date: Date.new(2027, 6, 1), rule_type: :choice) }
    let(:groceries) { create(:category, user: user, name: "Groceries") }

    def preview_of(**columns)
      written = Rule.new(category: groceries, **columns)
      RulePreview.new(RuleForm.new(user, RuleForm.from(written), rule: written), user: user)
    end

    # The bold half is the RULE — who gets how much, how often. A repeating rule's due date trails
    # it, because "every 2 months" is the rule and "next due Oct 3" is where the cycle stands today.
    it "says a repeating dated rule back with its interval and its next occurrence" do
      expect(helper.rule_preview_sentence(water)).to eq(
        "<strong>Water gets $48.20 every 2 months</strong>, next due #{due.strftime("%b %-d, %Y")}."
      )
    end

    # A one-off's date is INSIDE the bold — the day IS the rule there — and a rate rule has no day.
    it "says the other two shapes back", :aggregate_failures do
      expect(helper.rule_preview_sentence(rate)).to eq("<strong>Groceries gets $400.00 every period</strong>.")
      expect(helper.rule_preview_sentence(goal)).to eq("<strong>Groceries gets $5,000.00 by Jun 1, 2027</strong>.")
    end

    it "says what becomes of the money, per shape", :aggregate_failures do
      expect(helper.rule_preview_holding_sentence(rate)).to start_with("Whatever's unspent resets on ")
      expect(helper.rule_preview_holding_sentence(goal))
        .to eq("Each period sets aside its share so the money is there on the day.")
      expect(helper.rule_preview_holding_sentence(preview_of(amount: 60, keeps_unspent: true, rule_type: :usage)))
        .to eq("It builds up with no limit.")
    end

    # All three, because the sentence is the only place on the form that says what choosing a type
    # COSTS.
    it "says which end of the give-way order each type is", :aggregate_failures do
      expect(helper.rule_preview_type_sentence(preview_of(amount: 90, rule_type: :bill)))
        .to eq("It's a bill, so it's the last thing to give way.")
      expect(helper.rule_preview_type_sentence(preview_of(amount: 90, rule_type: :usage)))
        .to eq("It's usage, so it gives way after your choices and before your bills.")
      expect(helper.rule_preview_type_sentence(preview_of(amount: 90, rule_type: :choice)))
        .to eq("It's a choice, so it's the first thing to give way.")
    end

    # A half-filled form is not a refusal: the card lists the blanks and builds no calculator.
    it "lists what is missing instead of pricing a rule that has no shape", :aggregate_failures do
      blank = preview_of(rule_type: nil)

      expect(blank).not_to be_ready
      expect(blank.missing).to eq(["Fill in an amount.", "Choose what kind of rule this is."])
    end
  end
end
