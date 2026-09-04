# frozen_string_literal: true

require "rails_helper"

RSpec.describe HomeHelper, type: :helper do
  # ** `#pool_status_label`, `#pool_state_label` AND `#saving_label` ARE DELETED WITH THEIR TWELVE
  # EXAMPLES (computed-claims spec §6), AND SO IS THE `status` DOUBLE THEY ALL SHARED. ** They pinned
  # the row vocabulary of the UI design spec §4.4 — all seven `HoldingStatus` states (`overdrawn`,
  # `overdue`, `won't make it`, `behind`, `saving`, `left to spend`, `on track`), the `· last period`
  # suffix on each of them, and the `— you changed a rule here after distributing` clause gated on
  # `:behind`.
  #
  # NONE OF IT SURVIVES, AND IT IS THE MODEL RATHER THAN THE COPY THAT KILLED IT. Every one of those
  # sentences is a reading of money MOVED into a category and of what the next distribution would do
  # to it: `left to spend` is a balance awaiting a sweep, `· last period` is which period that
  # balance belongs to, `behind` is a shortfall a transfer could catch up, and the clause names an
  # edit made after a split. Nothing moves on the purpose side (§5), there is no split, and
  # `HoldingStatus`, `DistributionClock` and the partial that threaded them are all deleted.
  #
  # WHAT REPLACED THEM, AND WHERE: the claim vocabulary at the foot of this file. `#claim_figure`
  # (`spent of rate` / `built up of target`), `#claim_schedule` (`next due Mar 1 · $200.00 per
  # period`) and `#claim_trouble_label` (`over by $30.00` / `overdue · was Mar 1`) are §3.4's three
  # sentences, and the last of them carries the ONE state that survived the change of readers with
  # its wording intact — see its own example, which says so.

  # What an expanded row calls each rule. An item names itself; an item-less rule used to
  # render the literal word "Rule", which on screen reads as missing data rather than as
  # information. The row already prints the amount and the date on the other side, so what is
  # missing from the line is the rule's SHAPE — how often it comes round.
  describe "#pool_rule_label" do
    it "uses the item's name when the rule has one" do
      budget = build(:budget, item: build(:item, name: "Electric Bill"), anchor_date: Date.new(2026, 3, 1))

      expect(helper.pool_rule_label(budget)).to eq("Electric Bill")
    end

    it "names a monthly rule by its cadence" do
      budget = build(:budget, interval_months: 1, anchor_date: Date.new(2026, 3, 1))

      expect(helper.pool_rule_label(budget)).to eq("Monthly")
    end

    it "names a multi-month rule by its interval" do
      budget = build(:budget, interval_months: 6, anchor_date: Date.new(2026, 3, 1))

      expect(helper.pool_rule_label(budget)).to eq("Every 6 months")
    end

    it "names a rule that never rolls a one-off" do
      budget = build(:budget, :one_time, anchor_date: Date.new(2026, 3, 1))

      expect(helper.pool_rule_label(budget)).to eq("One-off")
    end

    # A per-period rule carries no anchor, so no expanded row can reach it today — but it is
    # the one shape whose blank interval does NOT mean "never rolls", and reading it as a
    # one-off would be silently wrong the day something asks.
    it "names a per-period rule by its cadence, not as a one-off" do
      budget = build(:budget, :per_period_rate)

      expect(helper.pool_rule_label(budget)).to eq("Per period")
    end
  end

  # ── `#pool_problem_label` IS DELETED (answers-first Task 2) and its four examples with it: "defaults
  # to the plain status label", "carries the closed-period suffix the categories band prints", "stays
  # silent about a period that has not closed" and "carries both suffixes together". (Its orphan arm
  # had already gone in two-ledger Task 6, taking four more.)
  #
  # THE PROPERTY IT PINNED IS NOT LOST — IT BECAME MOOT. The method forced `period_closed:` off the
  # status so that Home's attention band could not omit a suffix the categories band printed inches
  # below. There are no suffixes and no status: §3.4's row is one figure per rule, read off the rule
  # itself, and there is nothing for a caller to thread or to forget.

  # ** `#period_row_clause` AND ITS SEVEN EXAMPLES ARE DELETED (computed-claims Task 3), AND THE
  # CLAIM VOCABULARY BELOW REPLACES THEM. ** Every one of them read a `HoldingStatus`, whose states
  # describe money that had been MOVED into a category — `$90.00 left`, `saving`, `on track`,
  # `· last period`, `— you changed a rule here after distributing`. Nothing moves (spec §5), so
  # there is no balance to be left, no swept period to belong to and no distribution to have edited a
  # rule after. What a claim can be is: under its rate, over it, or accruing toward a date.
  #
  # THE STATUS VOCABULARY ITSELF IS NOW DELETED TOO (Task 4) — the categories, distribute and
  # reallocation screens were the last to speak it, and the first two of those were converted to the
  # claim vocabulary while the third was deleted outright. See the head of this file.

  # ── THE CLAIM VOCABULARY (computed-claims §3.4). One double per shape, for the reason the `status`
  # double above exists: these three methods read a handful of questions off a line and a real
  # `ClaimLine` would drag a category, a rule and a period walk in to answer them.
  describe "the claim vocabulary" do
    # `over_by:` DEFAULTS TO THE PRE-CLAMP DIFFERENCE THIS DOUBLE'S OWN MEMBERS DESCRIBE, which is
    # `ClaimCalculator#over_by` (`spent − accrued`) — the figure the line now CARRIES rather than one
    # the helper subtracts (fix wave — LOW-2). Stated here so a caller that passes a matching pair
    # gets the matching label without a third keyword.
    def rate_line(spent:, accrued:, over: false)
      instance_double(
        HomePresenter::ClaimLine,
        rate?: true,
        spent: spent,
        accrued: accrued,
        over?: over,
        over_by: spent.to_d - accrued.to_d,
        overdue?: false,
        next_due_on: nil
      )
    end

    # `overdue:` IS THE TENSE OF THE DATE (fix round 1 — MED-1), and it is the LINE's own answer
    # rather than a comparison the helper makes: `ClaimCalculator#overdue?` is exactly
    # `next_due_on < today`, and `today` is the one thing a view has no business holding.
    # `over?` IS HARD-FALSE HERE and is not a parameter: an accruing rule that has been overspent is
    # the `:over` trouble, whose label reads `spent − accrued` off a RATE line's members — so no
    # example in this group has ever passed one, and a sixth keyword would be a knob with no caller.
    def accruing_line(built_up:, target:, per_period:, next_due_on: nil, overdue: false)
      instance_double(
        HomePresenter::ClaimLine,
        rate?: false,
        built_up: built_up,
        target: target,
        per_period: per_period,
        next_due_on: next_due_on,
        over?: false,
        over_by: 0.to_d,
        overdue?: overdue,
        spent: 0.to_d,
        accrued: 0.to_d
      )
    end

    describe "#claim_figure" do
      # §3.4: a rate rule says what it SPENT of its rate. The denominator is the ACCRUED figure —
      # `rate + Σ this period's deltas` — because that is what `#over?` compares against, so the
      # colour and the fraction cannot describe different arithmetic.
      it "says spent of rate on a rate rule" do
        expect(helper.claim_figure(rate_line(spent: 310, accrued: 400))).to eq("$310.00 of $400.00")
      end

      # ** THE NOUN IS NOT THE CALLER'S TO CHOOSE. ** A row printing "spent" over a fund's running
      # total would be the money screen's oldest lie, that savings are money to spend.
      it "says built up of target on an accruing rule" do
        line = accruing_line(built_up: 450, target: 1_200, per_period: 200)

        expect(helper.claim_figure(line)).to eq("$450.00 built up of $1,200.00")
      end
    end

    describe "#claim_schedule" do
      # §3.4's second half, on the shape that has one.
      it "names the next due date and the per-period share" do
        line = accruing_line(built_up: 450, target: 1_200, per_period: 200, next_due_on: Date.new(2026, 3, 1))

        expect(helper.claim_schedule(line)).to eq("next due Mar 1 · $200.00 per period")
      end

      # A DATELESS TARGET HAS NO DUE DATE, and the clause is the half that is true rather than a
      # sentence with a gap in it.
      it "drops the date on a rule that has none" do
        expect(helper.claim_schedule(accruing_line(built_up: 650, target: 2_400, per_period: 150)))
          .to eq("$150.00 per period")
      end

      # A FULL FUND ACCRUES NOTHING MORE, so "$0.00 per period" would be a line reporting nothing.
      # THE DATE SURVIVES ALONE — the clause is not nil here, which is what the method's own comment
      # used to claim (fix round 1 — MED-2).
      it "drops the share on a fund that is already full" do
        line = accruing_line(built_up: 1_200, target: 1_200, per_period: 0, next_due_on: Date.new(2026, 3, 1))

        expect(helper.claim_schedule(line)).to eq("next due Mar 1")
      end

      # ** A DATE THAT HAS GONE BY IS NOT "NEXT" (fix round 1 — MED-1). ** A $600 bill due Aug 15,
      # fully built up and never paid, kept its occurrence anchored where it was (§3.2) and the row
      # printed `next due Aug 15` on Sep 3 — a past date under a word that promises a future one. The
      # tense comes off `#overdue?`, which IS `next_due_on < today`, so the row and the trouble strip
      # cannot disagree about which side of today a date is on.
      it "puts a date that has passed in the past tense" do
        line = accruing_line(built_up: 600, target: 600, per_period: 0, next_due_on: Date.new(2026, 8, 15), overdue: true)

        expect(helper.claim_schedule(line)).to eq("was due Aug 15")
      end

      # BOTH TENSES CARRY THE SHARE, so the fund still saving toward a date it has already missed
      # reads as one sentence rather than losing half of it to the tense.
      it "keeps the per-period share beside a date that has passed" do
        line = accruing_line(built_up: 400, target: 600, per_period: 200, next_due_on: Date.new(2026, 8, 15), overdue: true)

        expect(helper.claim_schedule(line)).to eq("was due Aug 15 · $200.00 per period")
      end

      # A RATE RULE HAS NEITHER — use-it-or-lose-it accrues toward nothing and is due on no day — so
      # the view renders no element at all.
      it "is nil for a rate rule" do
        expect(helper.claim_schedule(rate_line(spent: 310, accrued: 400))).to be_nil
      end
    end

    describe "#claim_trouble_label" do
      # ** THE EXCESS, NOT THE CLAIM. ** §3.1 clamps an overspent claim to zero, so a figure taken
      # from the claim would print "over by $0.00" on every overspend. `ClaimCalculator#over_by` is
      # the pre-clamp difference, which is the money that came straight out of what is free — and it
      # is the CALCULATOR's subtraction since the fix wave (LOW-2), carried on the line, rather than
      # one this helper and `EntryImpactPresenter#pre_clamp_claim` each spelled for themselves.
      it "names the excess on a rule spent past its rate" do
        expect(helper.claim_trouble_label(rate_line(spent: 180, accrued: 150, over: true)))
          .to eq("over by $30.00")
      end

      # ** THE ONE STATE THAT SURVIVES THE CHANGE OF READERS UNCHANGED IN MEANING: ** a date has
      # passed and the money is not there. The deleted `#pool_state_label`'s own wording, character
      # for character, which is why this example is the last thing in this file that a reader of the
      # old vocabulary would recognise.
      it "dates an overdue occurrence" do
        line = accruing_line(built_up: 400, target: 600, per_period: 0, next_due_on: Date.new(2026, 3, 1))

        expect(helper.claim_trouble_label(line)).to eq("overdue · was Mar 1")
      end
    end
  end
end
