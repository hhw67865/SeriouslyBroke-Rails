# frozen_string_literal: true

require "rails_helper"

# ONE SUBMISSION FROM THE ADJUST PANEL, TURNED INTO ONE DATED ROW OR INTO THE SENTENCE REFUSING IT
# (computed-claims spec §3.3).
#
# ** MOST OF THIS CLASS IS PINNED WHERE A USER MEETS IT. ** `spec/requests/adjustments_spec.rb` owns
# the five doors, the span refusal, the skip's amount and its date, because those are facts about a
# WIRE and the owner's zone only a request can set up. What is here is the two things no request can
# reach:
#
#   * a rule whose walk has not opened yet. `AdjustmentsController` passes `today: Date.current` and
#     `budgets.created_at` cannot be in the future of it, so the empty span exists only for a caller
#     that injects its own `today:` — which is what this class's signature offers and what §7's
#     migration will be;
#   * the ORDER inside `#initialize`, which is invisible from outside unless the row it builds is
#     asked what the calculator saw.
RSpec.describe AdjustmentForm, type: :model do
  # MONTHLY, ANCHORED ON THE FIRST, so a period is a calendar month and every literal below is
  # arithmetic done by hand. No clock is travelled: `today:` is injected on every construction, as
  # `claim_calculator_spec` injects it, because the whole subject is a walk over a calendar.
  let(:user) { create(:user, period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 1)) }
  let(:goal) do
    create(:category, :expense, user: user, name: "Vacation", funded_since: Date.new(2026, 1, 1))
  end

  # A $150-a-period rule BORN AUG 1 BUILDING TOWARD $1,200: the walk visits August (planning
  # `min($150, $1,200)` = $150) and September (planning `min($150, $1,050)` = $150), so this period
  # accrues $150 and a skip is worth −$150.
  #
  # ** IT HAS TO BE A RULE THAT WALKS, AND THE FIGURE IS ON THE RULE (rules-own-the-budget §2.1). **
  # A rate rule's `#periods` is the CURRENT period and nothing else, so its span can never be empty
  # and the refusal below has no shape to fire on; `carries_over` is what opens the walk now, where a
  # `target_amount` on the CATEGORY used to.
  let(:rule) do
    create(:budget, :capped, category: goal, amount: 150, target_amount: 1_200, created_at: Time.utc(2026, 8, 1, 9, 0))
  end

  def form(params, today:) = described_class.new(rule: rule, params: params, name: "Vacation", today: today)

  # ** A RULE WHOSE WALK HAS NOT OPENED REFUSES EVERY DATE, IN ITS OWN WORDS (fix round 2, NEW-4). **
  # `#countable_span` is empty there, and the fallback it replaced — `#window_start`'s
  # `|| current_period.first`, which `ClaimLedger` needs and a span does not — would have offered
  # "pick a date between Sep 1 and Sep 3" for a rule that counts nothing dated anywhere. A remedy
  # for a refusal no date can lift is worse than no remedy: the user tries every day it names.
  #
  # THE RULE IS BORN IN A LATER PERIOD AND NOT MERELY ON A LATER DAY, which is the walk's own
  # arithmetic: `#walk_periods` opens at the period CONTAINING the accrual start, so a rule written
  # on Sep 10 still walks September when asked about Sep 3 (§3.2's "a period's accrual counts in
  # full the day the period opens"). October is the first period whose OPEN is after this `today`.
  describe "a rule that has not started counting" do
    let(:rule) do
      create(:budget, :capped, category: goal, amount: 150, target_amount: 1_200, created_at: Time.utc(2026, 10, 1, 9, 0))
    end

    it "refuses, naming the rule rather than a span it could be met inside", :aggregate_failures do
      built = form({ amount: "100", date: "2026-09-02" }, today: Date.new(2026, 9, 3))

      expect(built.save).to be(false)
      expect(built.error_sentence).to eq("Vacation hasn't started counting yet, so there's nothing to adjust.")
      expect(built.error_sentence).not_to include("pick a date between")
      expect(rule.adjustments.count).to eq(0)
    end

    # THE OTHER SIDE OF THE SAME BOUNDARY, on the same record: once the walk opens, the identical
    # submission lands. A class that simply refused this rule forever would pass the half above.
    it "accepts the same submission once the walk has opened", :aggregate_failures do
      built = form({ amount: "100", date: "2026-10-02" }, today: Date.new(2026, 10, 3))

      expect(built.save).to be(true)
      expect(rule.adjustments.sole.local_day).to eq(Date.new(2026, 10, 2))
    end
  end

  # ** THE FIGURE THE SKIP IS COMPUTED FROM DOES NOT COUNT THE SKIP (fix round 2, NEW-6b). **
  # `rule.adjustments.new` APPENDS an unsaved row to the association and
  # `ClaimCalculator#query_adjustments` is `rule.adjustments.map`, so the row this class builds is
  # inside the collection the calculator sums. `#initialize` reads the figures into locals BEFORE it
  # builds the row, so the calculator's `@adjustment_rows` memo is taken while the collection is
  # still only what the database holds.
  #
  # ** MEASURED, AND THE HONEST READING IS NARROWER THAN THAT. ** Reordering the two statements does
  # NOT change this example's answer today: a row built before its amount is known carries `nil`,
  # and `nil.to_d` is `0` (bigdecimal/util), so the pending row sums as nothing and the memo is the
  # same either way. The explicit order is what stops that accident from becoming load-bearing —
  # any future spelling that knows the amount before the row is appended (a caller that assigns it,
  # a lazily built calculator) reads its own $150 back as $0 and writes the zero `Adjustment`
  # refuses. What this example pins is the invariant itself, in both halves: the row IS in the
  # collection, and the figure the amount came from is still the $150 the rule had without it.
  describe "a skip's arithmetic against its own pending row" do
    it "computes minus the accrual the rule had before the row existed", :aggregate_failures do
      built = form({ skip: "1" }, today: Date.new(2026, 9, 3))

      expect(built.adjustment).not_to be_persisted
      expect(rule.adjustments).to include(built.adjustment)
      expect(built.calculator.accrued_this_period).to eq(150)
      expect(built.adjustment.amount).to eq(-150)
    end
  end
end
