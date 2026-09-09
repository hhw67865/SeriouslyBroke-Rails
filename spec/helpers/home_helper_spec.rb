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
        ClaimLine,
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
        ClaimLine,
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

    # ** `#claim_figure` AND `#claim_schedule` ARE DELETED, AND SO ARE THEIR TEN EXAMPLES (this
    # task's carry (b)). ** They were the SECOND spelling of a row's figure and a row's date:
    # `$450.00 built up of $1,200.00` against `#figure_words`' `$450.00 of $1,200.00`, and `next due
    # Mar 1 · $200.00 per period` against `#when_words`' `Mar 1 · +$200.00`. Task 2 kept them alive
    # by ruling because their two readers — the Budget page's rule row and the categories holdings
    # card — were outside its scope and named this task as the fold; both are converted in this
    # commit and both now print what Home prints.
    #
    # WHAT EACH DELETED EXAMPLE ASSERTED, AND WHERE IT LIVES NOW — nothing is unpinned by the fold:
    #
    #   spent of rate / built up of target        → `#figure_words`, below, both shapes
    #   the "built up alone" uncapped arm         → deleted with the shape (two-shapes §7), already
    #   next due + the per-period share           → `#when_words`, `Mar 1 · +$200.00`
    #   a settled rule renders no clause          → `#when_words` says `paid <date>` instead, below
    #   a full fund drops the share               → `#when_words` says `Mar 1 · ready`
    #   a past date reads `was due`               → `#when_words`' overdue arm, unchanged wording
    #   a rate rule has no clause                 → `#when_words` answers the RESET day or nil

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
  # ** THESE THREE ARE NOW THE WHOLE VOCABULARY, ON EVERY SCREEN THAT SAYS A RULE. ** Home's blocks,
  # the Budget page's open panel and the categories holdings card render exactly `#shape_words` /
  # `#figure_words` / `#when_words` over exactly one row type (`ClaimLine`), so a sentence about a
  # rule cannot differ between two screens a click apart — which it did, for one plan, and which is
  # what the deletion above closes.
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
        # ** THE THIRD SHAPE'S PREDICATE, DEFAULTED TO "not a fund" (two-shapes §12). ** All three
        # sentences below read it — `#shape_words` appends ", keeps", `#figure_words` drops the "of"
        # and `#when_words` says what it adds — so it is on the double for `#rate?`'s own reason: it
        # is the LINE's answer, off `ClaimCalculator#shape`, and not something a helper derives.
        fund?: false,
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
        bar_state: :normal,
        # ** THE TWO MEMBERS THIS TASK'S CARRY (a) ADDED, DEFAULTED TO "not a paid one-off". ** They
        # are on the double rather than derived because they are the LINE's answers:
        # `ClaimCalculator#settled?` is the app's one reading of a bill being finished, and
        # `#settled_on` is the day its spending reached the target.
        paid?: false,
        paid_on: nil
      }

      instance_double(ClaimLine, **defaults, **overrides)
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

      # ** NIL-SAFE ON THE DATE, ON BOTH ONE-OFF ARMS (this task's carry (a)). ** `once` and
      # `$5,000.00` are true sentences about a rule with no anchor; `undefined method 'strftime' for
      # nil` is a 500. Both arms, because a guard on one of two branches is a guard nobody can rely
      # on.
      it "drops the day rather than raising where a one-off has no date", :aggregate_failures do
        bill = block_line(rule: rule_double(cadence: :one_off, bill: true), stripe_type: :bill, rate?: false)
        goal = block_line(
          rule: rule_double(cadence: :one_off), stripe_type: :choice, rate?: false, target: 5_000.to_d
        )

        expect(helper.shape_words(bill)).to eq("bill · once")
        expect(helper.shape_words(goal)).to eq("choice · $5,000.00")
      end

      # ** §12: `usage · a period, keeps`. ** The cadence and then one word — a fund is a per-period
      # rule in every other sentence the app says about it, so the suffix is what distinguishes it
      # rather than a fourth cadence.
      it "says a fund is a period's allowance that keeps" do
        line = block_line(rate?: false, fund?: true, denominator: nil)

        expect(helper.shape_words(line)).to eq("usage · a period, keeps")
      end

      # AND THE SUFFIX RIDES ON WHATEVER CADENCE THE RULE HAS. A `monthly`-basis fund is not a shape
      # the form can write, but it is a legal row, and the words for it have to name both facts
      # rather than choose between them.
      it "keeps a monthly fund's own cadence in front of the suffix" do
        line = block_line(
          rule: rule_double(cadence: :monthly, interval_months: 1), rate?: false, fund?: true, denominator: nil
        )

        expect(helper.shape_words(line)).to eq("usage · every month, keeps")
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

      # ** AND A FUND HAS NO "of" AT ALL (§12), which is the one row that DOES say "built up". ** It
      # is aiming at nothing — `ClaimCalculator#target` is nil for this shape — so there is no second
      # figure to be a fraction of, and the noun is what stops a bare `$806.00` in a column of
      # spending figures from reading as spending.
      it "says what a fund has built up, with nothing to be a fraction of", :aggregate_failures do
        line = block_line(rate?: false, fund?: true, filled: 806.to_d, denominator: nil)

        expect(helper.figure_words(line)).to eq("built up $806.00")
        expect(helper.figure_words(line)).not_to include(" of ")
      end
    end

    # ** THE TROUBLE STRIP'S OVERSPEND SENTENCE, BOTH SHAPES (fix round — MED). ** The view wrote
    # `<spent> spent of <accrued>` itself, and `accrued` is THIS PERIOD's accrual — right for an
    # allowance that resets and nonsense for a fund, which is spent against what it HAD. Both arms
    # here, because the rate arm is the string the view used to hold and must not have moved.
    describe "#claim_over_detail" do
      it "measures a rate rule's spending against this period's accrual" do
        line = block_line(spent: 110.to_d, accrued: 100.to_d)

        expect(helper.claim_over_detail(line)).to eq("$110.00 spent of $100.00")
      end

      # A $60-a-period fund holding $806 and spent $900: `$900.00 spent of $60.00` was the sentence
      # before, beside a header reading `over by $34.00` — two figures that cannot both be about one
      # rule. The second figure is what the fund HAD, and the sentence says which it is.
      it "measures a fund's spending against what it had built up" do
        line = block_line(rate?: false, fund?: true, denominator: nil, spent: 900.to_d, built_up: 806.to_d)

        expect(helper.claim_over_detail(line)).to eq("$900.00 spent, $806.00 built up")
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

      # ** A FUND SAYS WHAT IT ADDS, BECAUSE IT HAS NO DAY AND NO BOUNDARY (§12). ** It is not
      # "ready" (there is nothing to be ready for) and it does not "reset" (that is the shape it is
      # the opposite of), so the only true clause left is the standing contribution — with its unit
      # spelled out, because there is no date beside it to say what a period is.
      it "says what a fund adds every period" do
        line = block_line(rate?: false, fund?: true, denominator: nil, per_period: 510.to_d)

        expect(helper.when_words(line)).to eq("+$510.00 a period")
      end

      # AND NOTHING WHERE THE SHARE IS NOT POSITIVE, on the dated arm's own rule: a `+$0.00` clause
      # would advertise a contribution the rule is not making.
      it "says nothing about a fund contributing nothing" do
        line = block_line(rate?: false, fund?: true, denominator: nil, per_period: 0.to_d)

        expect(helper.when_words(line)).to be_nil
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

      # ── ** THE PAID ONE-OFF (this task's carry (a)) ** ────────────────────────────────────────
      #
      # A one-time bill's occurrence NEVER rolls — there is no interval to roll onto — so before its
      # date a paid rule read `Sep 20 · $600.00 short` and after it `overdue · was Sep 20`: the two
      # worst sentences this vocabulary has, about a bill that had been paid. The arm is FIRST,
      # because nothing else the row could say about such a rule is true any more.
      #
      # BOTH DIRECTIONS ON ONE FIXTURE: the same members with `paid?` false read the old, wrong
      # sentence, so an arm that never fired would fail the second half.
      it "says a paid one-off is paid, with the day it was paid on", :aggregate_failures do
        members = {
          rate?: false, next_due_on: Date.new(2026, 9, 20), short?: true, fund_short?: true, fund_gap: 600.to_d
        }

        expect(helper.when_words(block_line(**members, paid?: true, paid_on: Date.new(2026, 9, 14))))
          .to eq("paid Sep 14")
        expect(helper.when_words(block_line(**members))).to eq("Sep 20 · $600.00 short")
      end

      # THE DAY IS THE SETTLING ENTRY'S AND IT IS FREE (`ClaimCalculator#settled_on` walks rows the
      # claim has already summed) — but the arm degrades rather than raising if it is ever nil, and
      # "paid" alone is still the true half of the sentence.
      it "says a bare paid where the settling day cannot be named" do
        line = block_line(rate?: false, next_due_on: Date.new(2026, 9, 20), paid?: true)

        expect(helper.when_words(line)).to eq("paid")
      end

      # ** NIL-SAFE ON THE DATE (this task's carry (a)). ** No `Budget` reaches these words without
      # an anchor, so this is a guard rather than a branch the data takes — and it is worth having
      # because three screens now render these words over rows built by three presenters, and the
      # one that raised would be a 500 on a money screen rather than a clause missing from a row.
      # BOTH HALVES: the clause survives the missing date on its own, and where there is no clause
      # either the row renders no element at all rather than an empty one.
      it "drops the date rather than raising where a dated rule has none", :aggregate_failures do
        expect(helper.when_words(block_line(rate?: false))).to eq("ready")
        expect(helper.when_words(block_line(rate?: false, fund_short?: true))).to be_nil
      end
    end

    # ── ** THE RUNWAY TICK'S OWN WORDS, SAID ONCE FOR TWO PLACES ON ONE PANEL ** ─────────────────
    #
    # The runway prints these beside the dot at full width AND down in the pace block whenever a
    # label is suppressed or the screen is narrow, so the two spellings of one screen cannot come to
    # disagree about whether a bill is ready. A `RunwayTick` is a `Data`, so the fixture is the real
    # thing rather than a double — a double would let the state and the gap drift apart, which is the
    # one relationship these two arms are about.
    #
    # NO DATE IN THE WORDS, and that is the panel's ruling rather than an omission: a tick's PLACE on
    # the ruler is its day, which is the thing the deleted list could not say. `#when_words` still
    # carries the date, for the rows in "This period" that have no ruler to sit on.
    describe "#runway_tick_words" do
      def runway_tick(state:, gap: 0.to_d)
        HomePresenter::RunwayTick.new(
          line: nil, day_index: 11, percent: 79, label: "Electric", amount: 120.to_d, state: state, gap: gap
        )
      end

      # THE MONEY IS THERE FOR THE DAY: the name, and the one word that says so.
      it "calls a tick whose money is there ready" do
        expect(helper.runway_tick_words(runway_tick(state: :ready))).to eq("Electric · ready")
      end

      # THE MONEY IS NOT THERE, AND THE GAP IS NAMED — `ClaimLine#fund_gap`, the same figure the
      # trouble strip prints about the same rule. "Short" without an amount is a fact nobody can act
      # on, which is why the arm carries the figure rather than the adjective alone.
      it "names the gap on a tick that is short" do
        expect(helper.runway_tick_words(runway_tick(state: :short, gap: 40.to_d))).to eq("Electric · $40.00 short")
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
