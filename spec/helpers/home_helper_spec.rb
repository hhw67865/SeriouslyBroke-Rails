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
    #
    # ** `capped?` AND `building?` HAVE LEFT THE DOUBLE WITH THE READERS THEY STOOD FOR (two-shapes
    # spec §7). ** There was one accruing shape without a date — the fund whose money carried over —
    # and `#capped?` said whether it named a ceiling at all; both were derived from the other keywords
    # here precisely because no `Budget` could hold the combinations they could state independently.
    # There is ONE accruing shape now, it always has a date and it always has a figure, so the double
    # states what the line carries and nothing more.
    #
    # `next_due_on:` IS STILL DEFAULTED, because a settled one-off answers nil to it — see "renders no
    # clause for a rule that is settled".
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

      # ** THE "built up alone" ARM IS DELETED WITH THE SHAPE (two-shapes spec §7). ** It was the
      # uncapped fund, whose `ClaimCalculator#target` was NIL — an un-gated sentence printed
      # `$450.00 built up of `, a dangling preposition over an empty figure — and there is no such
      # shape: every accruing rule has a day and a figure, so both halves of the "of" are always
      # there.
    end

    describe "#claim_schedule" do
      # §3.4's second half, on the shape that has one.
      it "names the next due date and the per-period share" do
        line = accruing_line(built_up: 450, target: 1_200, per_period: 200, next_due_on: Date.new(2026, 3, 1))

        expect(helper.claim_schedule(line)).to eq("next due Mar 1 · $200.00 per period")
      end

      # ** `#building_schedule` AND ITS THREE EXAMPLES ARE DELETED (two-shapes spec §7). ** A building
      # rule had no date at all, so its whole clause was `+$150.00 per period` — money added every
      # period for as long as the rule lived — and the leading PLUS was what told it from a dated
      # rule's `$200.00 per period`, a share of a bill that stops when the bill is whole. A goal names
      # a day now and takes the dated clause like every other accruing rule, which says the same thing
      # with the deadline the share is derived from.
      #
      # THE ARM THOSE EXAMPLES ALSO COVERED — a rule accruing nothing more — survives as the settled
      # one-off below, which is the only way `#next_due_on` and `#per_period` are now both empty.
      it "renders no clause for a rule that is settled" do
        expect(helper.claim_schedule(accruing_line(built_up: 0, target: 600, per_period: 0))).to be_nil
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

  # ── ** THE BLOCK ROW'S VOCABULARY (two-shapes spec §3). ** ─────────────────────────────────────
  #
  # Home's category blocks say a rule in three phrases — what SHAPE it is, what it HAS, and WHEN —
  # and these are the one spelling of each, which Task 3's Budget rows and Task 4's preview will
  # call. Doubles for the reason the group above uses them: a real `ClaimLine` drags a category, a
  # rule and a period walk in to answer four questions.
  #
  # ** `#claim_figure` AND `#claim_schedule` ARE NOT DELETED, WHICH THE BRIEF ASKED FOR. ** Both are
  # still rendered by `budget_page/_rule_row.html.erb` and `categories/…/_holdings_card.html.erb`,
  # and both of those screens are out of this task's scope — the Budget page is Task 3's and the
  # categories page is out of scope for the whole plan (spec §8). Their examples above therefore
  # stay, and the sentences genuinely differ: `#figure_words` says `$450.00 of $1,200.00` where
  # `#claim_figure` says `$450.00 built up of $1,200.00`, which is pinned in both directions below.
  describe "the block row's vocabulary" do
    # `rule:` IS A DOUBLE OF THE RECORD'S OWN CLASSIFIER (`Budget#cadence`) rather than a set of
    # columns, because that is what the helper reads: the classification is the model's and only the
    # WORDS are this screen's. A cascade over `basis`/`interval_months`/`anchor_date` here would be
    # a fifth reading of one shape.
    def rule_double(cadence:, bill: false, interval_months: nil, item: nil)
      instance_double(Budget, cadence: cadence, bill?: bill, interval_months: interval_months, item: item)
    end

    def block_line(**overrides)
      defaults = {
        rule: rule_double(cadence: :per_period),
        stripe_type: :usage,
        rate?: true,
        filled: 310.to_d,
        denominator: 400.to_d,
        target: 0.to_d,
        per_period: 0.to_d,
        next_due_on: nil,
        resets_on: nil,
        overdue?: false,
        short?: false,
        fund_short?: false,
        fund_gap: 0.to_d,
        bar_state: :normal
      }

      instance_double(HomePresenter::ClaimLine, **defaults, **overrides)
    end

    describe "#shape_words" do
      it "says a rate rule is a period's allowance" do
        expect(helper.shape_words(block_line)).to eq("usage · a period")
      end

      # THE MONTHLY-BASIS RULE WITH NO DATE — "$260 every month", reachable only from a suggestion
      # (spec §5) and therefore never offered by the form. It is a RATE shape (no anchor) with a
      # monthly cadence, so a reader that branched on `#rate?` before asking the cadence would call
      # it "a period" and quietly restate its schedule as something the user never wrote.
      it "keeps a monthly rule monthly even though it accrues like a rate" do
        line = block_line(rule: rule_double(cadence: :monthly, bill: true, interval_months: 1), stripe_type: :bill)

        expect(helper.shape_words(line)).to eq("bill · every month")
      end

      it "names a repeating rule by its interval" do
        line = block_line(rule: rule_double(cadence: :every_n, bill: true, interval_months: 12), stripe_type: :bill)

        expect(helper.shape_words(line)).to eq("bill · every 12 months")
      end

      # ** THE ONE-OFF SPLITS ON ITS TYPE, AND BOTH DIRECTIONS ARE PINNED. ** A bill is a thing to
      # PAY on a day; anything else with a day is a figure being SAVED toward, and the figure is what
      # the row is about — so it is in the phrase, with its year, because a goal's horizon is
      # routinely years out and "Jun 1" alone would read as this June.
      it "says a goal as a figure and a day" do
        line = block_line(
          rule: rule_double(cadence: :one_off),
          stripe_type: :choice,
          rate?: false,
          target: 5_000.to_d,
          next_due_on: Date.new(2027, 6, 1)
        )

        expect(helper.shape_words(line)).to eq("choice · $5,000.00 by Jun 1, 2027")
      end

      it "says a one-time bill as a day it happens once" do
        line = block_line(
          rule: rule_double(cadence: :one_off, bill: true),
          stripe_type: :bill,
          rate?: false,
          target: 600.to_d,
          next_due_on: Date.new(2026, 12, 1)
        )

        expect(helper.shape_words(line)).to eq("bill · once, Dec 1")
      end
    end

    describe "#figure_words" do
      # ONE SENTENCE FOR BOTH SHAPES, off `#filled` and `#denominator` — the pair that makes them
      # one. The caller does not choose the noun, because a row printing "spent" over a target's
      # running total would be the money screen's oldest lie.
      it "says what a rate rule has spent of its rate" do
        expect(helper.figure_words(block_line)).to eq("$310.00 of $400.00")
      end

      it "says what a dated rule has of what it needs", :aggregate_failures do
        line = block_line(rate?: false, filled: 80.to_d, denominator: 120.to_d)

        expect(helper.figure_words(line)).to eq("$80.00 of $120.00")
        # ** AND IT DOES NOT SAY "built up". ** That is `#claim_figure`'s wording, which two other
        # screens still render; this section's rows are a column of figures and the four extra words
        # on every dated row were the widest thing in it.
        expect(helper.figure_words(line)).not_to include("built up")
      end
    end

    describe "#when_words" do
      # USE-IT-OR-LOSE-IT IS RESET AT THE BOUNDARY (§3.1), so what a rate row has to say about time
      # is the day it starts again — `ClaimLine#resets_on`, which is the period's own close plus one.
      it "says the day a rate rule starts again" do
        expect(helper.when_words(block_line(resets_on: Date.new(2026, 10, 1)))).to eq("resets Oct 1")
      end

      # NO PERIOD, NO RESET DAY: the row says one clause fewer rather than naming a boundary nobody
      # declared, which is `HomePresenter#period_range`'s refusal arriving on the row.
      it "says nothing about a rate rule with no period declared" do
        expect(helper.when_words(block_line)).to be_nil
      end

      # THE MONEY IS THERE FOR THE DAY.
      it "calls a dated rule with its money ready" do
        line = block_line(rate?: false, next_due_on: Date.new(2026, 9, 17))

        expect(helper.when_words(line)).to eq("Sep 17 · ready")
      end

      # THE MONEY IS NOT THERE AND THE DAY IS INSIDE THIS PERIOD — `ClaimLine#short?`, the pair the
      # runway's red tick fires on, said in words so a colour is not the only thing carrying it.
      it "names the gap on a rule that is short" do
        line = block_line(
          rate?: false,
          next_due_on: Date.new(2026, 9, 20),
          short?: true,
          fund_short?: true,
          fund_gap: 40.to_d
        )

        expect(helper.when_words(line)).to eq("Sep 20 · $40.00 short")
      end

      # STILL ACCRUING: a day further out than this period, and what this period is putting toward
      # it. The PLUS is what tells a contribution from a total.
      it "says what a rule still saving is putting in" do
        line = block_line(
          rate?: false, next_due_on: Date.new(2027, 4, 2), fund_short?: true, per_period: 41.67.to_d
        )

        expect(helper.when_words(line)).to eq("Apr 2 · +$41.67")
      end

      # ** A SETTLED ONE-OFF ASKS FOR NOTHING MORE, so the share drops rather than printing
      # `+$0.00`. ** `ClaimCalculator#planned_for` returns zero for a one-time bill whose money has
      # been spent, and a rule advertising a contribution it is not making is worse than a bare date.
      it "drops the share where the rule is asking for nothing" do
        line = block_line(rate?: false, next_due_on: Date.new(2026, 12, 1), fund_short?: true)

        expect(helper.when_words(line)).to eq("Dec 1")
      end

      # A DATE GONE BY WITH THE MONEY MISSING, in `#claim_trouble_label`'s exact wording — the strip
      # above and the row below print one string about one rule, which is why it is not respelled.
      it "puts a date already gone in the past tense" do
        line = block_line(rate?: false, next_due_on: Date.new(2026, 8, 15), overdue?: true)

        expect(helper.when_words(line)).to eq("overdue · was Aug 15")
      end
    end

    # ── THE PACE, SAID ONCE FOR THE RUNWAY AND THE SHORTFALL STRIP ───────────────────────────────
    describe "#pace_words" do
      it "says what a day may cost while free is above zero" do
        pace = HomePresenter::Pace.new(amount: 32.81.to_d, fine: true)

        expect(helper.pace_words(pace)).to eq("$32.81 a day is fine for the rest of the period.")
      end

      # THE SHORTFALL STRIP'S OWN SENTENCE, character for character: it is the only arm that strip
      # ever renders, and it read it out of its own view until this task.
      it "says what a day must come down by while free is under" do
        pace = HomePresenter::Pace.new(amount: 210.80.to_d, fine: false)

        expect(helper.pace_words(pace))
          .to eq("Spending $210.80 a day less for the rest of this period lands it at zero.")
      end

      it "is nil before a period is declared" do
        expect(helper.pace_words(nil)).to be_nil
      end
    end

    # ── THE COLOURS, WHICH ARE TABLES AND NOT CASCADES ──────────────────────────────────────────
    #
    # `fetch` FOR `Budget::TYPE_RANK`'S OWN REASON: a fourth rule type added to the enum without a
    # colour would render a row with no stripe at all, which is invisible until somebody notices a
    # blank column. Every arm is pinned so the tables cannot rot silently.
    describe "the type and bar palettes" do
      it "gives each rule type its own stripe and text colour", :aggregate_failures do
        stripes = [:bill, :usage, :choice].index_with { |type| helper.stripe_fill(block_line(stripe_type: type)) }
        words = [:bill, :usage, :choice].index_with { |type| helper.type_text_class(block_line(stripe_type: type)) }

        expect(stripes).to eq(bill: "bg-brand-darker", usage: "bg-dusty-teal", choice: "bg-terracotta")
        expect(words).to eq(
          bill: "text-brand-dark", usage: "text-dusty-teal-dark", choice: "text-terracotta-dark"
        )
      end

      # GREEN WHEN IT HAS ARRIVED, RED WHEN IT IS OVER OR SHORT, OLIVE WHILE IT IS STILL FILLING
      # (§3). The state is the ROW's (`ClaimLine#bar_state`) and this is only its palette.
      it "paints a bar by the state the row is in" do
        fills = [:full, :over, :short, :normal].index_with { |state| helper.bar_fill(block_line(bar_state: state)) }

        expect(fills).to eq(
          full: "bg-status-success",
          over: "bg-status-danger",
          short: "bg-status-danger",
          normal: "bg-brand-dark"
        )
      end
    end
  end
end
