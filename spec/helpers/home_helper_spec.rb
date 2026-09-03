# frozen_string_literal: true

require "rails_helper"

RSpec.describe HomeHelper, type: :helper do
  # `needs_attention?` is answered from HoldingStatus's own constant rather than a hand-set
  # flag, so a double can never claim a combination the real object cannot produce.
  #
  # `period_closed?` is on the double because #period_row_clause READS it off the status rather than
  # taking it as a keyword — that is the fix, not an accident of the double: a keyword gave a caller
  # the option of omitting it, and Home's attention band took that option.
  def status(state, amount: 0, due_on: nil, target: nil, period_closed: false)
    instance_double(
      HoldingStatus,
      state: state,
      amount: amount,
      due_on: due_on,
      target: target,
      period_closed?: period_closed,
      needs_attention?: HoldingStatus::ATTENTION_STATES.include?(state)
    )
  end

  # The row vocabulary of the UI design spec §4.4. Home's system specs reach two of these
  # six states; the rest are exercised here so a wording or formatting change cannot slip
  # through, and so Task 7's pool rows inherit tested copy.
  describe "#pool_status_label" do
    it "names the amount already spent when overdrawn" do
      expect(helper.pool_status_label(status(:overdrawn, amount: 50))).to eq("overdrawn $50.00")
    end

    it "names the date that passed when overdue" do
      label = helper.pool_status_label(status(:overdue, amount: 600, due_on: Date.new(2026, 3, 1)))

      expect(label).to eq("overdue · was Mar 1")
    end

    it "names the unreachable date when it won't make it" do
      label = helper.pool_status_label(status(:wont_make_it, amount: 300, due_on: Date.new(2026, 2, 14)))

      expect(label).to eq("won't make it · Feb 14")
    end

    # How much EXTRA is owed, not the gap to target — the two differ and the spec is explicit.
    it "names the catch-up amount when behind" do
      expect(helper.pool_status_label(status(:behind, amount: 385))).to eq("behind $385.00")
    end

    # The only state that renders a spendable number, because a rate envelope is the only
    # kind where the balance genuinely is spendable (principle 2).
    it "names what is left to spend on a rate envelope" do
      expect(helper.pool_status_label(status(:left_to_spend, amount: 240))).to eq("$240.00 left")
    end

    # The seventh state. Both forms read as accumulation; neither reads as money to spend,
    # which is the whole reason it exists (principle 2).
    it "names progress toward a target when saving" do
      expect(helper.pool_status_label(status(:saving, amount: 424, target: 2_400)))
        .to eq("$424.00 of $2,400.00")
    end

    it "names what has been put away when a savings pool has no target" do
      expect(helper.pool_status_label(status(:saving, amount: 424, target: 0))).to eq("$424.00 saved")
    end

    # The word this state was carved out to avoid, asserted directly: a substring check on
    # "$424.00" alone would pass against the label it replaced.
    it "never says a savings balance is left to spend", :aggregate_failures do
      expect(helper.pool_status_label(status(:saving, amount: 424, target: 2_400))).not_to include("left")
      expect(helper.pool_status_label(status(:saving, amount: 424, target: 0))).not_to include("left")
    end

    it "stays quiet on track" do
      expect(helper.pool_status_label(status(:on_track, amount: 1_000))).to eq("$1,000.00 · on track")
    end

    # Single-digit days unpadded: the locale's :short format renders "Mar 01", which is not
    # the vocabulary the spec writes and not how any other date in this app is formatted.
    it "does not zero-pad a single-digit day" do
      label = helper.pool_status_label(status(:overdue, amount: 10, due_on: Date.new(2026, 3, 5)))

      expect(label).to eq("overdue · was Mar 5")
    end

    # Plan 2b decision 1: the closed-period marker is a SUFFIX on the real balance, never a
    # replacement for it. The $60 is physically in the envelope until a distribution moves it,
    # and `Σ pools == your bank balance` is the invariant the whole app rests on — so the
    # figure has to survive the marker. Asserted as full equality, because a `have_content`
    # on the suffix alone would pass against a label that had dropped the amount.
    it "marks a closed period without touching the amount" do
      label = helper.pool_status_label(status(:left_to_spend, amount: 60), period_closed: true)

      expect(label).to eq("$60.00 left · last period")
    end

    # The default, and the direction that keeps the marker meaning something: an ordinary row
    # must not carry it. Same state and same amount as above, so the flag is the only variable.
    it "says nothing about a period that has not closed" do
      expect(helper.pool_status_label(status(:left_to_spend, amount: 60))).to eq("$60.00 left")
    end

    # A closed period is a fact about the money, not about how the pool is doing, so it does
    # not displace the state's own wording — an overdrawn envelope whose period ended is both
    # at once. This is the pair that would fail if the suffix were folded into one branch.
    it "marks a closed period on a state that is already in trouble" do
      label = helper.pool_status_label(status(:overdrawn, amount: 80), period_closed: true)

      expect(label).to eq("overdrawn $80.00 · last period")
    end
  end

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
  # THE PROPERTY IT PINNED IS NOT LOST — IT BECAME STRUCTURAL. The method forced `period_closed:` off
  # the status so that Home's attention band could not omit the suffix the categories band printed
  # inches below. The trouble strip that replaced that band renders `shared/_holding_status`, which
  # threads BOTH suffixes off ONE `HomePresenter::Row`: a caller chooses which OBJECT to pass, not
  # which suffixes, and an object missing an answer raises at render. The two suffixes' own wording
  # is pinned above, on `#pool_status_label`, which is where it always lived. Seven examples replace
  # the four.

  # ** `#period_row_clause` AND ITS SEVEN EXAMPLES ARE DELETED (computed-claims Task 3), AND THE
  # CLAIM VOCABULARY BELOW REPLACES THEM. ** Every one of them read a `HoldingStatus`, whose states
  # describe money that had been MOVED into a category — `$90.00 left`, `saving`, `on track`,
  # `· last period`, `— you changed a rule here after distributing`. Nothing moves (spec §5), so
  # there is no balance to be left, no swept period to belong to and no distribution to have edited a
  # rule after. What a claim can be is: under its rate, over it, or accruing toward a date.
  #
  # THE STATUS VOCABULARY ITSELF IS NOT DELETED — the categories, distribute and reallocation screens
  # still speak it, and `#pool_status_label`'s own examples above are untouched. Home simply stopped.

  # ── THE CLAIM VOCABULARY (computed-claims §3.4). One double per shape, for the reason the `status`
  # double above exists: these three methods read a handful of questions off a line and a real
  # `ClaimLine` would drag a category, a rule and a period walk in to answer them.
  describe "the claim vocabulary" do
    def rate_line(spent:, accrued:, over: false)
      instance_double(
        HomePresenter::ClaimLine,
        rate?: true,
        spent: spent,
        accrued: accrued,
        over?: over,
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
      # from the claim would print "over by $0.00" on every overspend. `spent − accrued` is the
      # pre-clamp difference, which is the money that came straight out of what is free.
      it "names the excess on a rule spent past its rate" do
        expect(helper.claim_trouble_label(rate_line(spent: 180, accrued: 150, over: true)))
          .to eq("over by $30.00")
      end

      # THE ONE STATE THAT SURVIVES THE CHANGE OF READERS UNCHANGED IN MEANING: a date has passed and
      # the money is not there. `pool_state_label`'s own wording, kept.
      it "dates an overdue occurrence" do
        line = accruing_line(built_up: 400, target: 600, per_period: 0, next_due_on: Date.new(2026, 3, 1))

        expect(helper.claim_trouble_label(line)).to eq("overdue · was Mar 1")
      end
    end
  end
end
