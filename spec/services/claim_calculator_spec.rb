# frozen_string_literal: true

require "rails_helper"

# THE §3 FORMULA MATRIX (computed-claims spec §9), CASE BY CASE AND BOTH DIRECTIONS.
#
# EVERY FIGURE BELOW IS A PLANTED LITERAL, on `category_ledger_spec`'s rule: an assertion of the form
# `calc.built_up == <something derived from the calculator>` is `x == x` and would pass against a
# class walking the wrong periods. Each expectation is the arithmetic done by hand from the fixture,
# and the working is written beside it wherever the number is not obvious from one line.
#
# THE USER IS MONTHLY-ANCHORED ON THE 1st, deliberately: the periods are then the calendar months and
# the reader can hold the walk in their head. The cadence is not what the formulas are about, so it
# is varied in exactly one group ("on another cadence grid") rather than everywhere.
#
# `today:` IS ALWAYS INJECTED and no example travels the clock. `Date.current` never appears: the
# whole subject is a walk over a calendar, so a fixture whose dates move with the wall clock would
# make every literal here a different assertion each morning.
#
# ** `spec/services/budget_calculator_spec.rb` IS DELETED, AND ITS SUBJECT IS THIS FILE'S (fix wave
# — MED-3). ** `BudgetCalculator` answered "what does this rule need from the next DISTRIBUTION",
# and Task 4 deleted the distribution; the class survived on one branch of `Budget#steady_ask` with
# a due date that CONTRADICTED the one below — it had no fulfilment signal for an item-less rule, so
# it assumed every bill was paid on time and rolled the date on the calendar. The Budget page's
# structural check priced an item-less one-off anchored Aug 1 at $0.00 a period while the row an
# inch above it read `overdue · was Aug 1`. Both class and spec are gone; `#due_on`, `#periods_left`
# and `#planned_this_period` here are the only readings of a rule's schedule left in the app, and
# `budget_steady_ask_spec` pins the branch that now calls them.
RSpec.describe ClaimCalculator, type: :model do
  let(:user) { create(:user, period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 1)) }

  # THE CATEGORY HOLDS FROM JAN 1, which is the accrual start every walk below begins at (§3.2:
  # "dated rules accrue from `funded_since`, never retroactively"). The one group that varies it says
  # so in its own heading.
  let(:groceries) { create(:category, :expense, user: user, name: "Groceries", funded_since: Date.new(2026, 1, 1)) }

  # ** EVERY ACCRUING RULE BELOW IS BORN ON JAN 1 TOO, AND THE `created_at:` IS NOT BOOKKEEPING. **
  # A rule accrues from the LATER of its category's funding date and its own creation (§3.2, Henry's
  # ruling of 2026-09-03), so a fixture that says "this fund has been building since January" has to
  # say the rule existed in January — a rule created by the factory a moment ago would honestly walk
  # one period, not nine. The pair of examples that vary it are in "a rule younger than its
  # category" below.
  def born = Time.utc(2026, 1, 1, 9, 0)

  def spend(amount, on:, item: nil)
    create(:entry, item: item || create(:item, category: groceries), amount: amount, date: on)
  end

  def adjust(rule, amount, on:)
    create(:adjustment, rule: rule, amount: amount, date: on)
  end

  # A $1,200 GOAL DUE AUG 31 on a category of its OWN, born on the moment given. A category may carry
  # only one rule whose lane is the whole of it (`Budget#category_may_hold_one_item_less_rule`), so
  # two birth dates need two categories.
  #
  # ** IT WAS A $150-A-PERIOD CAPPED BUILDING RULE, AND THE HORIZON IS WHAT REPLACES THE RATE
  # (two-shapes §2). ** A stated rate with no deadline became a stated deadline with a derived share:
  # `1,200 ÷ periods left`, recomputed every period. MAR 31 2027 is eight monthly periods from Aug
  # 2026, which is the month every group below opens its walk in — so the share there is exactly the
  # $150 the old rate was and those literals are unchanged. The two groups whose walk opens in a
  # DIFFERENT month re-derive their own figures beside the example, because a catch-up share is a
  # fact about the horizon and not about the rule alone: that is the whole difference §2 introduced.
  def goal_born_on(name, moment, funded_since: Date.new(2026, 1, 1))
    goal = create(:category, :expense, user: user, name: name, funded_since: funded_since)
    create(
      :budget,
      category: goal,
      amount: 1_200,
      basis: :monthly,
      interval_months: nil,
      anchor_date: Date.new(2027, 3, 31),
      created_at: moment
    )
  end

  # ===========================================================================================
  # §3.1 — the rate rule. `claim = max(0, rate + Σ adjustments this period − spent_this_period)`
  # ===========================================================================================
  describe "a rate rule" do
    let(:rule) { create(:budget, :per_period_rate, category: groceries, amount: 400) }
    let(:today) { Date.new(2026, 9, 3) } # the period is Sep 1 – Sep 30

    def calc(on = today) = described_class.new(rule, today: on)

    it "claims its whole rate when nothing has been spent", :aggregate_failures do
      expect(calc.claim).to eq(400)
      expect(calc.spent_this_period).to eq(0)
      expect(calc).not_to be_over
    end

    it "claims what is left of the rate when some of it has been spent", :aggregate_failures do
      spend(150, on: Date.new(2026, 9, 2))

      expect(calc.claim).to eq(250)
      expect(calc.spent_this_period).to eq(150)
      expect(calc).not_to be_over
    end

    # EXACTLY SPENT IS NOT OVER, and this is the example that says so: the claim is zero on both
    # sides of the line, so `over?` is the only reader that can tell them apart.
    it "claims nothing once the rate is exactly spent", :aggregate_failures do
      spend(400, on: Date.new(2026, 9, 2))

      expect(calc.claim).to eq(0)
      expect(calc).not_to be_over
    end

    it "claims nothing and reads over when the rate is overspent", :aggregate_failures do
      spend(450, on: Date.new(2026, 9, 2))

      expect(calc.claim).to eq(0)
      expect(calc).to be_over
    end

    # USE-IT-OR-LOSE-IT (§3.1): nothing carries, in either direction. August's $400 of spending is
    # invisible in September and August's unspent $400 is not added to it.
    it "resets to the whole rate at the period boundary", :aggregate_failures do
      spend(400, on: Date.new(2026, 8, 20))

      expect(calc.claim).to eq(400)
      expect(calc.spent_this_period).to eq(0)
      expect(calc.built_up).to eq(0)
    end

    it "counts the same spending in the period it falls in", :aggregate_failures do
      spend(400, on: Date.new(2026, 8, 20))

      expect(calc(Date.new(2026, 8, 25)).claim).to eq(0)
      expect(calc(Date.new(2026, 8, 25)).spent_this_period).to eq(400)
    end

    it "has no due date and no periods to count down to it", :aggregate_failures do
      expect(calc.next_due_on).to be_nil
      expect(calc.periods_left).to be_nil
    end

    describe "with adjustments (§3.3)" do
      it "adds a positive delta dated inside the period", :aggregate_failures do
        adjust(rule, 100, on: Time.utc(2026, 9, 2, 12))
        spend(150, on: Date.new(2026, 9, 2))

        expect(calc.accrued_this_period).to eq(500)
        expect(calc.claim).to eq(350)
      end

      # A SKIP IS AN ADJUSTMENT OF −planned DATED TODAY (§3.3) — there is no second verb.
      it "is skipped whole by a delta of minus its planned accrual", :aggregate_failures do
        adjust(rule, -calc.planned_this_period, on: Time.utc(2026, 9, 3, 12))

        expect(calc.accrued_this_period).to eq(0)
        expect(calc.claim).to eq(0)
        expect(calc).not_to be_over
      end

      # ONLY ITS OWN PERIOD. The same −$400 dated in August leaves September untouched.
      it "leaves the neighbouring period alone" do
        adjust(rule, -400, on: Time.utc(2026, 8, 20, 12))

        expect(calc.claim).to eq(400)
      end

      it "takes the claim below the rate and no further than zero", :aggregate_failures do
        adjust(rule, -500, on: Time.utc(2026, 9, 2, 12))

        expect(calc.claim).to eq(0)
        expect(calc).to be_over
      end
    end

    # A MONTHLY-BASIS RATE UNDER A FORTNIGHTLY USER IS `Budget#steady_ask`'s FIGURE, and this app has
    # exactly one answer to "what does a standing rate cost a period": $260 a month is $120 a period,
    # because 26 periods a year is what biweekly means.
    describe "on another cadence grid" do
      let(:user) { create(:user, :biweekly) }
      let(:rule) { create(:budget, :rate, category: groceries, amount: 260) }

      it "states a monthly rate in the user's own periods" do
        expect(calc.planned_this_period).to eq(120)
      end
    end
  end

  # ===========================================================================================
  # §3.2 — the dated rule. The accrual walk, the catch-up formula, the cap and the fulfilment.
  # ===========================================================================================
  describe "a dated rule" do
    # $600 every six months, next due Jun 1, paid out of the Insurance item.
    let(:premium) { create(:item, category: groceries, name: "Premium") }
    let(:rule) do
      create(
        :budget,
        category: groceries,
        item: premium,
        amount: 600,
        interval_months: 6,
        anchor_date: Date.new(2026, 6, 1),
        created_at: born
      )
    end

    def calc(on) = described_class.new(rule, today: on)

    # THE WALK, PERIOD BY PERIOD. Six periods from Jan 1 to the Jun 1 due date, so the catch-up
    # formula lands on $100 a month and holds there while nothing disturbs it:
    #   Jan (600−0)/6 = 100 → 100     Apr (600−300)/3 = 100 → 400
    #   Feb (600−100)/5 = 100 → 200   May (600−400)/2 = 100 → 500
    #   Mar (600−200)/4 = 100 → 300   Jun (600−500)/1 = 100 → 600
    it "accrues one period's catch-up share at a time", :aggregate_failures do
      expect(calc(Date.new(2026, 3, 15)).built_up).to eq(300)
      expect(calc(Date.new(2026, 4, 15)).built_up).to eq(400)
    end

    it "names the share, the due date and the periods left", :aggregate_failures do
      march = calc(Date.new(2026, 3, 15))

      expect(march.planned_this_period).to eq(100)
      expect(march.next_due_on).to eq(Date.new(2026, 6, 1))
      expect(march.periods_left).to eq(4) # Mar, Apr, May and the Jun period the bill opens
    end

    # A PERIOD'S ACCRUAL COUNTS IN FULL THE DAY THE PERIOD OPENS (§3.2), which is what puts the whole
    # $600 there ON Jun 1 rather than at the end of the month the bill is due in.
    it "is whole on the day the bill's own period opens" do
      expect(calc(Date.new(2026, 6, 1)).built_up).to eq(600)
    end

    it "stops growing at the target" do
      expect(calc(Date.new(2026, 8, 15)).built_up).to eq(600)
    end

    it "asks for nothing more once it is there" do
      expect(calc(Date.new(2026, 8, 15)).planned_this_period).to eq(0)
    end

    # ** `#overdue?` IS THE DATE AND ONLY THE DATE (§3.2; fix round 1 — MED-1), AND THE `built_up <
    # target` HALF IS DELETED. ** It read "a date past AND a fund short", which silenced the ordinary
    # overdue bill: §3.2's catch-up formula floors `periods_left` at 1 for a date already past, so an
    # unpaid bill's fund fills to its target in ONE period and the WHOLE fund is the common state of a
    # date that has gone by. A $600 premium due Jun 1, fully saved and never paid, was silent on the
    # strip and its row printed `next due Jun 1` — a past date under the word "next". §3.2 is explicit:
    # "an occurrence whose money was never spent stays where it was anchored and the row reads
    # overdue". So the trigger is the unfulfilled occurrence, and the FUND STATE is what the copy
    # splits on rather than what the predicate gates on (`_trouble.html.erb`, pinned in `trouble_spec`).
    #
    # FOUR PINS: the date both sides of `today`, and — on the past side — the fund both whole and
    # short, which is the pair the old predicate collapsed.

    # ON the due date is not past it. The bill is due TODAY, which is a thing to do rather than a
    # thing missed, and a strict `<` is the whole of that distinction.
    it "is not overdue on the day the bill falls due", :aggregate_failures do
      june = calc(Date.new(2026, 6, 1))

      expect(june.next_due_on).to eq(Date.new(2026, 6, 1))
      expect(june.built_up).to eq(600)
      expect(june).not_to be_overdue
    end

    # THE DAY AFTER, WITH THE FUND WHOLE — the state the old predicate called healthy. Nothing was
    # spent, so `cycles_paid_by` stays at 0, the occurrence does not roll and Jun 1 is a date that
    # went by with the bill unpaid.
    it "is overdue the day after its date even with the fund whole", :aggregate_failures do
      second = calc(Date.new(2026, 6, 2))

      expect(second.next_due_on).to eq(Date.new(2026, 6, 1))
      expect(second.built_up).to eq(600)
      expect(second).to be_overdue
    end

    # THE SAME DATE WITH THE FUND SHORT, and the arithmetic is §3.2'S SETTLE ORDER: a $200 part
    # payment in August lands AFTER that period's accrual, so `raw = 600 − 200` leaves **$400.00**;
    # $200 is less than one whole cycle, so `cycles_paid_by` stays at 0 and the occurrence does not
    # roll. Date past, fund $200 short — and the verdict is the same one as above, because the
    # predicate no longer reads the fund.
    it "is overdue once part of the bill has been paid out of the fund", :aggregate_failures do
      spend(200, on: Date.new(2026, 8, 10), item: premium)
      august = calc(Date.new(2026, 8, 15))

      expect(august.next_due_on).to eq(Date.new(2026, 6, 1))
      expect(august.built_up).to eq(400)
      expect(august).to be_overdue
    end

    # THE OTHER SIDE OF THE DATE, WITH THE FUND SHORT — March holds $300 of $600 against a date three
    # months out. A fund that is behind is not overdue; it is saving, which is what the catch-up
    # formula is for.
    it "is not overdue while the date is still ahead and the fund is short", :aggregate_failures do
      march = calc(Date.new(2026, 3, 15))

      expect(march.next_due_on).to eq(Date.new(2026, 6, 1))
      expect(march.built_up).to eq(300)
      expect(march).not_to be_overdue
    end

    # AND A RULE WITH NO DATE AT ALL IS NEVER OVERDUE — `#next_due_on` is nil for a rate rule, and a
    # `nil < today` would raise rather than answer.
    it "is never overdue on a rule that has no due date" do
      rate_rule = create(:budget, :per_period_rate, category: create(:category, :expense, :funded, user: user), amount: 400)

      expect(described_class.new(rate_rule, today: Date.new(2026, 8, 15))).not_to be_overdue
    end

    # ** THE CATCH-UP FORMULA, RECOMPUTED EVERY PERIOD (§3.2/§3.3). ** February is skipped by a
    # −$100 delta, and the remaining four periods rise from $100 to $125 to land the target on time:
    #   Jan 100 → 100   Feb 100 − 100 → 100   Mar (600−100)/4 = 125 → 225
    #   Apr 125 → 350   May 125 → 475         Jun 125 → 600
    describe "after a period is skipped" do
      before { adjust(rule, -100, on: Time.utc(2026, 2, 10, 12)) }

      it "leaves the skipped period where it started" do
        expect(calc(Date.new(2026, 2, 20)).built_up).to eq(100)
      end

      it "raises every later period's share to recover the due date", :aggregate_failures do
        march = calc(Date.new(2026, 3, 15))

        expect(march.planned_this_period).to eq(125)
        expect(march.built_up).to eq(225)
      end

      it "still lands the whole target on the day it is due" do
        expect(calc(Date.new(2026, 6, 1)).built_up).to eq(600)
      end
    end

    # ** FULFILMENT (§3.2): an expense on the rule's ITEM drops the built-up and the cycle rolls to
    # the next due date. ** June's $600 payment takes the fund to zero and re-aims it at Dec 1, six
    # periods out, so July starts again at $100 a month.
    describe "after the bill is paid" do
      before { spend(600, on: Date.new(2026, 6, 5), item: premium) }

      it "drops the built-up by what was spent", :aggregate_failures do
        june = calc(Date.new(2026, 6, 15))

        expect(june.built_up).to eq(0)
        expect(june).not_to be_over
      end

      it "restarts the accrual toward the next due date", :aggregate_failures do
        july = calc(Date.new(2026, 7, 15))

        expect(july.next_due_on).to eq(Date.new(2026, 12, 1))
        expect(july.periods_left).to eq(6) # Jul, Aug, Sep, Oct, Nov and the Dec period
        expect(july.built_up).to eq(100)
      end

      it "is back to two periods' worth by August" do
        expect(calc(Date.new(2026, 8, 15)).built_up).to eq(200)
      end
    end

    # A PARTIAL PAYMENT DROPS THE FUND WITHOUT ROLLING THE CYCLE — $200 against a $600 bill leaves
    # $400 owed and the bill still due Jun 1, so July's overdue share is the whole remainder.
    describe "after a part payment" do
      before { spend(200, on: Date.new(2026, 6, 5), item: premium) }

      it "keeps the rest of the fund and the same due date", :aggregate_failures do
        june = calc(Date.new(2026, 6, 15))

        expect(june.built_up).to eq(400)
        expect(june.next_due_on).to eq(Date.new(2026, 6, 1))
      end

      it "asks for the whole remainder once the due date has passed", :aggregate_failures do
        july = calc(Date.new(2026, 7, 15))

        expect(july.planned_this_period).to eq(200)
        expect(july.built_up).to eq(600)
      end
    end

    # ** SPILL ON OVER-FULFILMENT (§3.2): a fulfilment larger than the claim spills into free and the
    # category shows "over". ** The $100 of overspend is NOT re-saved — the fund had $600 and never
    # had $700, so July starts from zero rather than from minus a hundred.
    describe "after the bill is overpaid" do
      before { spend(700, on: Date.new(2026, 6, 5), item: premium) }

      it "claims nothing and reads over in the period it happened", :aggregate_failures do
        june = calc(Date.new(2026, 6, 15))

        expect(june.claim).to eq(0)
        expect(june).to be_over
      end

      it "starts the next cycle from zero rather than from the overspend", :aggregate_failures do
        july = calc(Date.new(2026, 7, 15))

        expect(july.built_up).to eq(100)
        expect(july).not_to be_over
      end
    end

    # ** THE ITEM IS THE LANE FOR AN ITEM-BACKED RULE (§3.2). ** Groceries bought out of the same
    # category are not a payment of the insurance premium, and the pair is asserted both ways so the
    # filter cannot be satisfied by a rule that counts nothing at all.
    describe "the lane a fulfilment has to arrive on" do
      # ** THE PARTITION (§3.1/§3.2, ruling of 2026-09-03). ** A catch-all rule beside this
      # item-backed one: the catch-all's lane is the category MINUS the items that carry a rule of
      # their own, so paying the premium lowers the premium's fund and NOTHING else. Without the
      # partition the two lanes overlap, one payment lowers two claims, and `free` rises when a bill
      # is paid — the shape `claim_ledger_spec` prices in full.
      it "keeps an item-backed rule's spending out of the catch-all rule's lane", :aggregate_failures do
        catch_all = beside_the_premium
        spend(300, on: Date.new(2026, 9, 2), item: premium)

        expect(catch_all.spent_this_period).to eq(0)
        expect(catch_all.claim).to eq(400)
      end

      # THE OTHER DIRECTION, and it is what keeps the partition from being a filter that excludes
      # everything: an item nobody has written a rule for is the catch-all's business.
      it "still counts an entry on an item that carries no rule of its own", :aggregate_failures do
        catch_all = beside_the_premium
        spend(150, on: Date.new(2026, 9, 2), item: create(:item, category: groceries, name: "Bread"))

        expect(catch_all.spent_this_period).to eq(150)
        expect(catch_all.claim).to eq(250)
      end

      # `rule` is referenced so the premium's own dated rule exists — it is what makes the Premium
      # item a ruled one and therefore what the partition has to exclude.
      def beside_the_premium
        rule
        described_class.new(
          create(:budget, :per_period_rate, category: groceries, amount: 400),
          today: Date.new(2026, 9, 3)
        )
      end

      it "ignores spending on another item of the same category" do
        spend(600, on: Date.new(2026, 6, 5), item: create(:item, category: groceries, name: "Bread"))

        expect(calc(Date.new(2026, 6, 15)).built_up).to eq(600)
      end

      # AN ITEM-LESS DATED RULE TAKES THE CATEGORY, which is §3.2's other arm.
      it "takes the whole category when the rule names no item" do
        item_less = create(
          :budget,
          category: groceries,
          amount: 600,
          interval_months: 6,
          anchor_date: Date.new(2026, 6, 1),
          created_at: born
        )
        spend(600, on: Date.new(2026, 6, 5), item: create(:item, category: groceries, name: "Bread"))

        expect(described_class.new(item_less, today: Date.new(2026, 6, 15)).built_up).to eq(0)
      end
    end

    # ** `funded_since` IS THE ACCRUAL START, NEVER RETROACTIVE (§3.2). ** The same rule, the same
    # due date, the same day — and three months of accrual instead of four, because the category did
    # not hold money before April.
    describe "a category that only started holding in April" do
      let(:groceries) do
        create(:category, :expense, user: user, name: "Groceries", funded_since: Date.new(2026, 4, 1))
      end

      it "accrues from the funding date rather than from the anchor", :aggregate_failures do
        april = calc(Date.new(2026, 4, 15))

        expect(april.periods_left).to eq(3) # Apr, May and the Jun period
        expect(april.built_up).to eq(200) # 600 / 3, against the 400 a January start would hold
      end

      it "still lands the whole target on the day it is due" do
        expect(calc(Date.new(2026, 6, 1)).built_up).to eq(600)
      end
    end

    # ** AN ITEM-LESS BILL'S CYCLE ROLLS ON THE CATEGORY'S SPENDING, NOT ON THE CALENDAR (review of
    # 2026-09-03), and this is the divergence from `BudgetCalculator#due_date` stated as a figure. **
    # That class has no fulfilment signal for a rule with no item, so it assumes the bill was paid on
    # time and reports Dec 1 here; the computed model reads the category's own spending, finds none,
    # and says what is true — the bill is overdue and the fund is still holding the whole $600. This
    # reading is the law going forward; `BudgetCalculator` dies in Task 4.
    describe "an item-less bill nobody has paid" do
      let(:rule) do
        create(
          :budget,
          category: groceries,
          amount: 600,
          interval_months: 6,
          anchor_date: Date.new(2026, 6, 1),
          created_at: born
        )
      end

      it "stays at the occurrence it was anchored on", :aggregate_failures do
        september = calc(Date.new(2026, 9, 3))

        expect(september.next_due_on).to eq(Date.new(2026, 6, 1))
        expect(september.built_up).to eq(600)
        # AND THE ROW READS OVERDUE, which is §3.2's own sentence about this shape and what the
        # comment above has always claimed. Under the old `built_up < target` half it did not.
        expect(september).to be_overdue
      end

      # THE OTHER DIRECTION: spending on the category IS the fulfilment signal an item-less rule has,
      # so once the money goes out the cycle rolls and the fund starts again.
      it "rolls to the next occurrence once the category's own spending settles it", :aggregate_failures do
        spend(600, on: Date.new(2026, 6, 5))
        september = calc(Date.new(2026, 9, 3))

        expect(september.next_due_on).to eq(Date.new(2026, 12, 1))
        expect(september.built_up).to eq(300) # Jul, Aug, Sep at (600 − 0) / 6 a period
      end
    end

    # A ONE-TIME RULE NEVER ROLLS — it has no interval, so its due date is its anchor forever, and
    # paying it empties the fund and leaves it empty.
    describe "a one-time bill" do
      let(:rule) do
        create(
          :budget,
          category: groceries,
          item: premium,
          amount: 600,
          interval_months: nil,
          anchor_date: Date.new(2026, 6, 1),
          created_at: born
        )
      end

      it "keeps its anchor as the due date after it is settled", :aggregate_failures do
        spend(600, on: Date.new(2026, 6, 5), item: premium)
        july = calc(Date.new(2026, 7, 15))

        expect(july.next_due_on).to eq(Date.new(2026, 6, 1))
        expect(july.built_up).to eq(0)
      end

      # ── ** THE PAID ONE-OFF (two-shapes Task 3's carry (a)) ** ─────────────────────────────────
      #
      # `#settled?` HAS ALWAYS BEEN THE GATE THE WALK ASKS (`#planned_for` returns zero for a paid
      # one-time bill, or it would re-accrue its whole amount for ever against a date that never
      # moves). It is PUBLIC now because three screens have to stop calling a paid bill late: the
      # row's `when` clause, the runway's tick and the trouble strip all read a rule whose date has
      # not rolled and whose fund is empty, and every one of them read the emptiness as a shortfall.
      #
      # BOTH DIRECTIONS ON ONE FIXTURE: the same rule before and after the payment.
      it "is settled once the bill is paid and not before", :aggregate_failures do
        expect(calc(Date.new(2026, 7, 15))).not_to be_settled

        spend(600, on: Date.new(2026, 6, 5), item: premium)

        expect(calc(Date.new(2026, 7, 15))).to be_settled
      end

      # ** AND IT IS NO LONGER OVERDUE, WHICH IS THE WHOLE POINT OF THE PREDICATE BEING PUBLIC. **
      # July 15 is six weeks past a June 1 date that can never roll, so before the payment this is
      # the ordinary overdue bill and after it there is nothing left to do.
      it "stops being overdue the moment it is paid", :aggregate_failures do
        expect(calc(Date.new(2026, 7, 15))).to be_overdue

        spend(600, on: Date.new(2026, 6, 5), item: premium)

        expect(calc(Date.new(2026, 7, 15))).not_to be_overdue
      end

      # ** THE SETTLING DAY IS THE DAY THE RUNNING TOTAL REACHED THE TARGET — the date the row
      # prints as `paid Jun 20`. ** Two part payments, so the answer is the SECOND one: a reader
      # that named the first receipt would date the settlement before the money was there, and one
      # that named the last would be right only by accident on a single-payment bill.
      it "names the day the spending reached the target", :aggregate_failures do
        spend(200, on: Date.new(2026, 6, 5), item: premium)
        spend(400, on: Date.new(2026, 6, 20), item: premium)
        july = calc(Date.new(2026, 7, 15))

        expect(july).to be_settled
        expect(july.settled_on).to eq(Date.new(2026, 6, 20))
      end

      # NIL WHILE THE BILL IS UNPAID, because there is no settlement to date — an answer rather than
      # the first receipt's day, which would be this reader guessing.
      it "names no day while the bill is only part paid", :aggregate_failures do
        spend(200, on: Date.new(2026, 6, 5), item: premium)
        july = calc(Date.new(2026, 7, 15))

        expect(july).not_to be_settled
        expect(july.settled_on).to be_nil
      end
    end

    # ** A REPEATING RULE IS NEVER SETTLED, whatever has been paid into it (§3.2). ** There is
    # always a next occurrence to fund, and this is the property that keeps the paid arm above from
    # silencing an ordinary six-monthly bill: it rolls its date instead, which is the correct
    # sentence for that shape and was never the misreading.
    describe "a repeating bill that has been paid" do
      let(:rule) do
        create(
          :budget,
          category: groceries,
          item: premium,
          amount: 600,
          interval_months: 6,
          anchor_date: Date.new(2026, 6, 1),
          created_at: born
        )
      end

      it "is not settled and rolls its date instead", :aggregate_failures do
        spend(600, on: Date.new(2026, 6, 5), item: premium)
        july = calc(Date.new(2026, 7, 15))

        expect(july).not_to be_settled
        expect(july.settled_on).to be_nil
        expect(july.next_due_on).to eq(Date.new(2026, 12, 1))
      end
    end

    # A RATE RULE ANSWERS FALSE WITHOUT WALKING ANYTHING — `#one_time?` is asked first, so a
    # use-it-or-lose-it rule never reaches a question about a bill.
    describe "a rate rule asked whether it is settled" do
      let(:rule) { create(:budget, :per_period_rate, category: groceries, amount: 400, created_at: born) }

      it "is never settled and names no day", :aggregate_failures do
        march = calc(Date.new(2026, 3, 10))

        expect(march).not_to be_settled
        expect(march.settled_on).to be_nil
      end
    end
  end

  # ===========================================================================================
  # ** THE GOAL (two-shapes spec §2 row 5) — A DATED RULE WITH NO INTERVAL, AND NOTHING ELSE. **
  # $1,200 by Aug 31, from a category funded Jan 1: eight monthly periods, so §3.2's catch-up share
  # is `1,200 ÷ 8` = **$150.00** every period and stays there — the gap and the periods left fall
  # together. That is what makes "a savings goal" and "a bill" one shape: the walk is the same walk,
  # and the only thing a goal adds is a longer horizon.
  #
  # ** IT WAS A CAPPED BUILDING RULE (`carries over` + a target, §2.1 row 3), AND EVERY FIGURE BELOW
  # IS THE ONE THAT SHAPE PRODUCED. ** The rate was stated and the horizon derived; here the horizon
  # is stated and the share derived, and on this fixture they are the same $150. What DID change is
  # the recovery after a raid — see "gives money back on a negative delta" — because a deadline
  # re-plans and a standing rate does not.
  #
  # ** THREE WHOLE GROUPS WENT WITH THE SHAPE (§7), AND THEY ARE NAMED HERE RATHER THAN DELETED
  # QUIETLY: **
  #
  #   "with no rate at all" — the goal fed only by set-asides, spelled as an amount of ZERO. There is
  #     no such shape: every rule has a positive amount, and a goal with no standing contribution is
  #     a target with a date the owner has not started saving for.
  #   "an uncapped building rule" — the fund with no ceiling, whose share was its plain rate for ever
  #     and whose adjustments touched only their own period. A rule that names no day it is needed is
  #     a rule nothing can be short for; §2 retires it.
  #   "a negative adjustment on a capped building rule at its cap" / "at the cap" — the cap's own
  #     refill arithmetic (`min(rate, gap)`, never faster than the rate) and the `#capped?` pair.
  #     There is one cap now, the rule's own amount, and the recovery after a raid is the catch-up
  #     share, which the group below pins.
  # ===========================================================================================
  describe "a goal" do
    let(:vacation) do
      create(
        :category,
        :expense,
        user: user,
        name: "Vacation",
        funded_since: Date.new(2026, 1, 1)
      )
    end
    let(:rule) do
      create(
        :budget,
        category: vacation,
        amount: 1_200,
        basis: :monthly,
        interval_months: nil,
        anchor_date: Date.new(2026, 8, 31),
        created_at: born
      )
    end

    def calc(on) = described_class.new(rule, today: on)

    def withdraw(amount, on:)
      create(:entry, item: create(:item, category: vacation), amount: amount, date: on)
    end

    it "accrues its share, one period at a time" do
      expect(calc(Date.new(2026, 4, 15)).built_up).to eq(600) # four periods of $150
    end

    # ** THE HORIZON IS THE DIFFERENCE, AND IT IS THE WHOLE OF WHAT THE OLD SHAPE LACKED. ** The
    # capped building rule answered NIL to both of these — no due date, no periods to count down to
    # one — which is why a fund could be neither early nor late and Home could say nothing about when
    # it would arrive. April is the fourth of eight periods, so five remain including its own.
    it "names the share, the day it is needed and the periods left", :aggregate_failures do
      april = calc(Date.new(2026, 4, 15))

      expect(april.next_due_on).to eq(Date.new(2026, 8, 31))
      expect(april.periods_left).to eq(5)
      expect(april.planned_this_period).to eq(150)
    end

    # THE CEILING IS THE RULE'S OWN AMOUNT, and the ninth period asks for nothing: eight periods of
    # $150 reach $1,200 exactly.
    it "stops at the figure the rule names", :aggregate_failures do
      september = calc(Date.new(2026, 9, 15))

      expect(september.built_up).to eq(1_200)
      expect(september.planned_this_period).to eq(0)
    end

    it "takes a set-aside on top of its share" do
      adjust(rule, 500, on: Time.utc(2026, 2, 10, 12))

      expect(calc(Date.new(2026, 2, 20)).built_up).to eq(800) # 150 + 150 + 500
    end

    # THE CEILING HOLDS AGAINST A SET-ASIDE TOO, which is the one way an accrual can arrive above the
    # target at all: the catch-up share is itself bounded by the gap, so without this example nothing
    # would exercise the `min` in `#accrued_in`.
    it "does not build past the target on a set-aside that overshoots it" do
      adjust(rule, 2_000, on: Time.utc(2026, 2, 10, 12))

      expect(calc(Date.new(2026, 2, 20)).built_up).to eq(1_200)
    end

    # ** A RAID IS A NEGATIVE DELTA, AND THE DEADLINE IS WHAT DECIDES THE RECOVERY (two-shapes §2). **
    # March: 150 + 150 + 150 − 200 = $250. APRIL RECOVERS FASTER THAN THE OLD RATE, and that is the
    # change of shape rather than a change of arithmetic: the gap is $950 with five periods left
    # (Apr … Aug), so the share is **$190.00** and the fund reaches $440 — where a standing rate
    # rebuilt at $150 to $400 and would still have been $200 short on the day. A deadline re-plans.
    it "gives money back on a negative delta, and re-plans to make the date", :aggregate_failures do
      adjust(rule, -200, on: Time.utc(2026, 3, 10, 12))

      expect(calc(Date.new(2026, 3, 20)).built_up).to eq(250)
      expect(calc(Date.new(2026, 4, 20)).planned_this_period).to eq(190)
      expect(calc(Date.new(2026, 4, 20)).built_up).to eq(440)
    end

    it "drops by what is spent out of the goal" do
      withdraw(300, on: Date.new(2026, 3, 10))

      expect(calc(Date.new(2026, 3, 20)).built_up).to eq(150) # 450 accrued, 300 taken
    end
  end

  # ===========================================================================================
  # ** THE SHAPE TABLE (two-shapes spec §2), ROW BY ROW. ** Five ways a user can write a rule and the
  # TWO formulas they map onto, read off ONE column of the rule's own. `#shape` and `#target` are
  # asserted together on each row because they are one classification: the shape says which formula,
  # and `#target` is the ceiling that formula runs against — a row that got one right and the other
  # wrong would be a walk running the right arithmetic against the wrong bound.
  #
  # ** IT WAS SEVEN ROWS, THREE FORMULAS AND `#capped?` BESIDE THEM (§2.1). ** Two rows were the
  # building shape (a fund with a ceiling and one without) and `#capped?` existed because the second
  # had no ceiling at all — `#target` was NIL there, and every reader of it had to ask a second
  # question first. Both are retired: a dated rule's target is its own amount and a rate rule's is
  # zero, so `#target` is always a figure and there is nothing left for a third predicate to say.
  #
  # ONE CATEGORY PER ROW, because `Budget#category_may_hold_one_item_less_rule` allows a category
  # exactly one rule whose lane is the whole of it.
  # ===========================================================================================
  describe "#shape and #target across §2" do
    def rule_for(name, *traits, **attrs)
      owner = create(:category, :expense, user: user, name: name, funded_since: Date.new(2026, 1, 1))
      create(:budget, *traits, category: owner, created_at: born, **attrs)
    end

    def calc(rule) = described_class.new(rule, today: Date.new(2026, 9, 3))

    # ROW 1 — $400 every period. The allowance that resets with the paycheck. `#target` is ZERO
    # rather than nil: a rate rule accrues toward nothing, and zero is what the walk's siblings have
    # always read there.
    it "calls a per-period rule a rate rule", :aggregate_failures do
      rule = rule_for("Groceries", :per_period_rate, amount: 400)

      expect(calc(rule).shape).to eq(:rate)
      expect(calc(rule)).to be_rate
      expect(calc(rule).target).to eq(0)
    end

    # ROW 2 — $260 every month, no due date. The same formula on a different unit: `Budget#steady_ask`
    # is what divides the month over the user's grid, and the SHAPE is untouched by the basis. The
    # form does not offer this row (§5's ruling) and `SuggestionEngine` still writes it, which is why
    # the classification has to keep answering for it.
    it "calls an anchorless monthly rule a rate rule too", :aggregate_failures do
      rule = rule_for("Power", :rate, amount: 260)

      expect(calc(rule).shape).to eq(:rate)
      expect(calc(rule).target).to eq(0)
    end

    # ROW 3 — $600 by Dec 1, once. The one-time bill: a date and no interval.
    it "calls an anchored rule with no interval dated, aiming at its own amount", :aggregate_failures do
      rule = rule_for("Registration", amount: 600, interval_months: nil, anchor_date: Date.new(2026, 12, 1))

      expect(calc(rule).shape).to eq(:dated)
      expect(calc(rule)).to be_dated
      expect(calc(rule).target).to eq(600)
    end

    # ROW 4 — $600 by Dec 1, every 6 months. The interval is what rolls the occurrence on payment; it
    # changes neither the shape nor the target.
    it "calls an anchored interval rule dated as well", :aggregate_failures do
      rule = rule_for("Insurance", amount: 600, interval_months: 6, anchor_date: Date.new(2026, 12, 1))

      expect(calc(rule).shape).to eq(:dated)
      expect(calc(rule).target).to eq(600)
    end

    # ** ROW 5 — $5,000 by Jun 1, 2027: A GOAL, AND IT IS ROW 3 WITH A LONGER HORIZON. ** This is the
    # whole of what §2 changed. The same columns, the same formula, the same target — "the goal" is a
    # word for a dated rule whose date is far away, not a shape the model has to know about.
    it "calls a goal the same dated shape as a one-off bill", :aggregate_failures do
      goal = rule_for("Vacation", :by_date, amount: 5_000)
      bill = rule_for("Registration", amount: 5_000, interval_months: nil, anchor_date: Date.new(2026, 12, 1))

      expect(calc(goal).shape).to eq(calc(bill).shape)
      expect(calc(goal).shape).to eq(:dated)
      expect(calc(goal).target).to eq(5_000)
    end

    # ** THE THIRD SHAPE CANNOT BE BUILT, WHICH IS THE SHARPEST FORM THE RETIREMENT CAN TAKE (§7). **
    # `:building`, `:capped` and `:hand_fed` are deleted from the factory with the columns they wrote,
    # so an example that reached for one would not merely fail — it cannot be written at all. Asserted
    # rather than left implied, because "the trait is gone" is exactly the fact a later reader
    # re-adding the shape would have to overturn on purpose.
    it "cannot construct the building shape at all" do
      expect { create(:budget, :building, category: groceries) }
        .to raise_error(KeyError, /building/)
    end

    # ** AND A RULE WITH NO ANCHOR IS A RATE RULE WHATEVER ELSE IS TRUE OF IT. ** The shape used to be
    # a fact about a NEIGHBOURING record (the category's figure), then about two of the rule's own
    # columns; it is one column now, so there is nothing left that could answer differently.
    it "reads the shape off the anchor and nothing beside it", :aggregate_failures do
      owner = create(:category, :expense, user: user, name: "Old Goal", funded_since: Date.new(2026, 1, 1))
      rule = create(:budget, :per_period_rate, category: owner, amount: 150, created_at: born)

      expect(calc(rule).shape).to eq(:rate)
      expect(calc(rule).target).to eq(0)
      expect(calc(rule).built_up).to eq(0)
    end
  end

  # ===========================================================================================
  # §3.2 — a rule cannot accrue before it existed. `funded_since` is stamped by a category's FIRST
  # rule, so for that rule the two dates coincide; for every rule added afterwards they do not.
  # ===========================================================================================
  describe "a rule younger than its category" do
    let(:vacation) do
      create(
        :category,
        :expense,
        user: user,
        name: "Vacation",
        funded_since: Date.new(2024, 9, 1)
      )
    end

    def calc(rule, on) = described_class.new(rule, today: on)

    # The category has held money for two years. A rule written on Sep 1 this year has not, so it
    # walks ONE period — not the two years the category could show. ONE period of a $1,200 goal due
    # Mar 31 2027: the boundaries left from Sep 1 are Sep, Oct, Nov, Dec, Jan, Feb, Mar = 7, so the
    # share is `1,200 ÷ 7` = **$171.43**.
    it "starts on the day the rule was written, not on the day the category was funded" do
      born_today = goal_born_on("Vacation", Time.utc(2026, 9, 1, 9, 0), funded_since: Date.new(2024, 9, 1))

      expect(calc(born_today, Date.new(2026, 9, 3)).built_up).to eq(171.43)
    end

    # THE OTHER DIRECTION, and it is what says the ruling did not simply replace one date with the
    # other: the FIRST rule on a category is written the day the category starts holding, so the two
    # dates coincide and the whole history is walked. FOUR periods from a June start, with ten
    # boundaries left in June (Jun … Mar) and one fewer each month — so the share is `1,200 ÷ 10` =
    # $120 every period and four of them hold **$480.00**.
    it "starts on the funding date for the rule that put it there" do
      first = goal_born_on("Trip", Time.utc(2026, 6, 1, 9, 0), funded_since: Date.new(2026, 6, 1))

      expect(calc(first, Date.new(2026, 9, 3)).built_up).to eq(480)
    end

    # ** A RULE BORN MID-PERIOD ACCRUES THAT WHOLE PERIOD. ** The birth date decides which period the
    # walk OPENS in, and §3.2's "a period's accrual counts in FULL the day the period opens" then
    # applies to it like any other. The pair varies only the day within one month — a rule written on
    # the 1st and one written on the 31st hold the same $150 on the 31st — because pro-rating would be
    # a second, finer clock beside the period grid and would make the figure depend on the hour the
    # user clicked Save.
    it "accrues the whole period it was written into, whichever day that was", :aggregate_failures do
      opened = goal_born_on("Opened", Time.utc(2026, 8, 1, 9, 0))
      closed = goal_born_on("Closed", Time.utc(2026, 8, 31, 21, 0))

      expect(calc(opened, Date.new(2026, 8, 31)).built_up).to eq(150)
      expect(calc(closed, Date.new(2026, 8, 31)).built_up).to eq(150)
    end

    # ** AND THE ARM THAT ANSWERS FOR AN UNSAVED RULE DOES NOT REACH A SAVED ONE (two-shapes Task 4,
    # fix round 1 — M1). ** `#rule_born_on` answers `today` for a NEW record, because the rule form's
    # preview prices a rule that has no `created_at` to be born on — and the hazard of that arm is
    # that it might be taken by rows which DO have one, making every saved rule's standing figure
    # move with the afternoon it is asked on. `created_at` governs, and the two literals are what say
    # so: born Sep 1, this goal spreads $1,200 over the seven boundaries left to Mar 31 (Sep … Mar) =
    # **$171.43** whichever day it is asked about, where the SAME SHAPE unsaved on Dec 3 opens in
    # December and spreads it over four (Dec, Jan, Feb, Mar) = **$300.00**.
    it "spreads a saved rule over the periods since it was written, not since today", :aggregate_failures do
      written = goal_born_on("Vacation", Time.utc(2026, 9, 1, 9, 0), funded_since: Date.new(2024, 9, 1))
      unsaved = Budget.new(
        category: written.category, amount: 1_200, basis: :monthly, anchor_date: Date.new(2027, 3, 31)
      )

      expect(calc(written, Date.new(2026, 12, 3)).standing_ask).to eq(171.43)
      expect(calc(unsaved, Date.new(2026, 12, 3)).standing_ask).to eq(300)
    end

    # ** A RULE ASKED ABOUT A DAY BEFORE IT EXISTED HOLDS NOTHING. ** The walk visits no periods at
    # all, and zero is the answer rather than the current period invented in its place — which is what
    # the old `visited.presence || [current_period]` fallback did, accruing a period the rule was not
    # alive for.
    it "holds nothing on a day before it was written", :aggregate_failures do
      backdated = calc(goal_born_on("Later", Time.utc(2026, 9, 1, 9, 0)), Date.new(2026, 8, 15))

      expect(backdated.built_up).to eq(0)
      expect(backdated.claim).to eq(0)
      expect(backdated.planned_this_period).to eq(0)
    end
  end

  # ===========================================================================================
  # ** THE BIRTH DAY IS THE OWNER'S, NOT UTC'S — ruling 1's timezone arm. ** 15:00 UTC on Aug 31 is
  # midnight on Sep 1 in Tokyo, so one instant opens the walk in two different months. A DATED rule,
  # so the walk actually runs: two periods against one, by Sep 3 — and the two owners read DIFFERENT
  # figures rather than the same one twice, because a catch-up share is derived from the periods left
  # to the deadline and August has one more of them than September does.
  # ===========================================================================================
  describe "a rule written at 15:00 UTC on the last day of August" do
    def written_then = goal_born_on("Trip", Time.utc(2026, 8, 31, 15, 0))

    it "opens the walk in August for an owner reading the clock in UTC" do
      expect(described_class.new(written_then, today: Date.new(2026, 9, 3)).built_up).to eq(300)
    end

    context "when the owner lives in Tokyo" do
      let(:user) do
        create(:user, period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 1), timezone: "Asia/Tokyo")
      end

      # ONE period, opened in September: seven boundaries left to Mar 31 2027, so `1,200 ÷ 7` =
      # **$171.43**. The UTC owner's two periods above are `1,200 ÷ 8` = $150 twice.
      it "opens it in September, the day the owner was living in" do
        expect(described_class.new(written_then, today: Date.new(2026, 9, 3)).built_up).to eq(171.43)
      end
    end
  end

  # ===========================================================================================
  # The boundary day, in the owner's zone — the one lane, asserted at the one instant that tells
  # UTC and Tokyo apart.
  # ===========================================================================================
  describe "the period boundary in Tokyo" do
    let(:user) do
      create(:user, period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 1), timezone: "Asia/Tokyo")
    end
    let(:rule) { create(:budget, :per_period_rate, category: groceries, amount: 400) }
    let(:calc) { described_class.new(rule, today: Date.new(2026, 9, 3)) }

    # 15:00 UTC on Aug 31 is midnight on Sep 1 in Tokyo, and 14:00 UTC is still Aug 31 there.
    it "counts an entry on the calendar day its owner was living in", :aggregate_failures do
      spend(30, on: Time.utc(2026, 8, 31, 15, 0))
      spend(7, on: Time.utc(2026, 8, 31, 14, 0))

      expect(calc.spent_this_period).to eq(30)
      expect(calc.claim).to eq(370)
    end

    it "files an adjustment in the period its owner dated it in" do
      adjust(rule, 100, on: Time.utc(2026, 8, 31, 15, 0))
      adjust(rule, 50, on: Time.utc(2026, 8, 31, 14, 0))

      expect(calc.accrued_this_period).to eq(500)
    end
  end

  # ===========================================================================================
  # THE STANDING ASK IS A CONSTANT OF THE RULE AND THE GRID (fix wave 2 — MED-A). It is what
  # `Budget#steady_ask` answers for a one-time bill and therefore what §9's structural verdict — "your
  # budget doesn't fit your income", a sentence about the SHAPE of the rules — is computed from. The
  # wave before this one read `#planned_this_period` there, which is catch-up and moves with the
  # fund, the spending and the calendar; every example below is a day, a payment or an adjustment
  # that must NOT move the figure, plus the three inputs that must.
  # ===========================================================================================
  describe "#standing_ask" do
    # $600 due Jun 1, no interval, born Jan 1 on a category funded Jan 1 — six monthly periods from
    # the accrual start's period through the period the bill falls due in (Jan, Feb, Mar, Apr, May,
    # Jun), so $100 a period. The divisor is asserted through a figure that changes if the fencepost
    # does: five periods would read $120 and seven $85.71.
    let(:bill) do
      create(
        :budget,
        category: groceries,
        amount: 600,
        interval_months: nil,
        anchor_date: Date.new(2026, 6, 1),
        created_at: born
      )
    end

    def calc(on) = described_class.new(bill, today: on)

    it "spreads the amount over the periods from the accrual start to the due date" do
      expect(calc(Date.new(2026, 3, 15)).standing_ask).to eq(100)
    end

    it "answers a BigDecimal" do
      expect(calc(Date.new(2026, 3, 15)).standing_ask).to be_a(BigDecimal)
    end

    # THE SAME FIGURE ON THREE DATES: before the bill is due, on the day it is due, and two months
    # after it went by unpaid. `#planned_this_period` reads $100, $100 and $0 across those same three
    # days (the third because the fund is full), and the third pair is the divergence that matters —
    # a verdict about the shape of a budget cannot be allowed to depend on which afternoon it is
    # asked on.
    it "reads the same before, on and after the due date", :aggregate_failures do
      expect(calc(Date.new(2026, 3, 15)).standing_ask).to eq(100)
      expect(calc(Date.new(2026, 6, 1)).standing_ask).to eq(100)
      expect(calc(Date.new(2026, 8, 15)).standing_ask).to eq(100)
    end

    # A PAYMENT MOVES THE ROW AND NOT THE SHAPE. $200 spent on the category's lane in February empties
    # what had accrued, so March's catch-up share rises to (600 − 0) ÷ 4 = $150 — and the standing ask
    # does not move at all. Both are asserted on one calculator, so the pair cannot pass by the two
    # readers having become the same method.
    it "does not move when the bill is part paid, though this period's share does", :aggregate_failures do
      spend(200, on: Date.new(2026, 2, 10))
      march = calc(Date.new(2026, 3, 15))

      expect(march.standing_ask).to eq(100)
      expect(march.planned_this_period).to eq(150)
    end

    # AND A SETTLED BILL STILL DECLARES ITS COST — the ruling taken in full (fix wave 2 — MED-A). The
    # catch-up share is zero for ever after `#settled?`; the standing ask is what the rule costs a
    # period for as long as the user keeps it. This is the shape whose bar had stopped being drawn
    # (`EntryImpactPresenter#bar?`, LOW-2), and it is what makes a paid one-off go on counting toward
    # `Budget.steady_need`.
    it "still asks after the bill has been paid in full", :aggregate_failures do
      spend(600, on: Date.new(2026, 2, 10))
      august = calc(Date.new(2026, 8, 15))

      expect(august.planned_this_period).to eq(0)
      expect(august.standing_ask).to eq(100)
    end

    # An adjustment is a delta on ONE period's accrual (§3.3). It moves the fund and therefore the
    # catch-up share; the standing figure reads the rule, not the fund.
    it "does not move when the fund is topped up by hand" do
      adjust(bill, 300, on: Date.new(2026, 2, 10))

      expect(calc(Date.new(2026, 3, 15)).standing_ask).to eq(100)
    end

    # THE THREE INPUTS THAT DO MOVE IT, one example each — without these the figure could be a
    # constant for the wrong reason (a method returning the amount, or zero, would pass every
    # example above except the divisor's).
    it "moves with the amount" do
      bill.update!(amount: 1_200)

      expect(calc(Date.new(2026, 3, 15)).standing_ask).to eq(200)
    end

    # A bill due four months earlier has four fewer periods to be found in: Jan and Feb, so $300.
    it "moves with the anchor" do
      bill.update!(anchor_date: Date.new(2026, 2, 1))

      expect(calc(Date.new(2026, 3, 15)).standing_ask).to eq(300)
    end

    # ** THE GRID IS AN INPUT, AND A CADENCE CHANGE IS HOW A USER MOVES IT (§3.5). ** The same bill on
    # the same dates under a WEEKLY grid has 22 boundaries in Jan 1..Jun 1 rather than 6, so it costs
    # $27.27 of a week instead of $100 of a month. That is the figure changing because the PERIOD
    # changed, which is exactly what "a constant of the rule and the grid" means.
    it "moves when the user's cadence does" do
      user.update!(period_cadence: :weekly)

      expect(calc(Date.new(2026, 3, 15)).standing_ask).to eq(BigDecimal("27.27"))
    end

    # THE FLOOR AT ONE PERIOD, on the shape that reaches it: a bill anchored before the rule was even
    # written has no boundary between its accrual start and its due date, and dividing by zero periods
    # would raise on a page whose only job is to render figures.
    it "asks for the whole amount when the date was already past when the rule was written" do
      overdue = create(
        :budget,
        category: create(:category, :expense, user: user, name: "Car Service", funded_since: Date.new(2026, 1, 1)),
        amount: 600,
        interval_months: nil,
        anchor_date: Date.new(2025, 12, 20),
        created_at: born
      )

      expect(described_class.new(overdue, today: Date.new(2026, 3, 15)).standing_ask).to eq(600)
    end

    # THE OTHER TWO SHAPES ARE `Budget#steady_ask`'s OWN ARITHMETIC, delegated rather than re-derived
    # — an interval rule's per-cycle figure and a rate rule's rate. Asserted against that method on
    # the same records, because the ruling is that this reader ANSWERS FOR EVERY SHAPE and the one-off
    # arm is the only one it computes itself.
    # $600 every six months under a monthly grid is $100 a period — the interval's own arithmetic,
    # nothing to do with the anchor's distance.
    it "delegates the interval shape to Budget#steady_ask" do
      recurring = create(
        :budget,
        category: create(:category, :expense, user: user, name: "Premiums", funded_since: Date.new(2026, 1, 1)),
        amount: 600,
        interval_months: 6,
        anchor_date: Date.new(2026, 6, 1)
      )

      expect(described_class.new(recurring, today: Date.new(2026, 3, 15)).standing_ask).to eq(100)
    end

    it "delegates the rate shape to Budget#steady_ask", :aggregate_failures do
      march = Date.new(2026, 3, 15)
      rate = create(:budget, :per_period_rate, category: groceries, amount: 400)

      expect(described_class.new(rate, today: march).standing_ask).to eq(400)
      expect(described_class.new(rate, today: march).standing_ask).to eq(rate.steady_ask(user, today: march))
    end

    # ** THE BUILDING RULE'S ARM IS DELETED WITH THE SHAPE (two-shapes spec §7). ** It said a fund's
    # standing ask is its plain rate, constant like a rate rule's, because it had no deadline for a
    # divisor to be the periods UNTIL. A goal has a deadline now and takes the ONE-OFF arm above —
    # `target ÷ periods to fund` — which is constant for exactly the same reason and is derived from
    # the rule and the grid rather than declared.
    #
    # WHAT SURVIVES IS THE HALF THAT WAS NEVER ABOUT THE SHAPE: a goal goes on declaring its cost
    # after it is MET, which is the settled one-off's own ruling. Eight periods of $150 fill a $1,200
    # goal due Aug 31 by August, so September's SHARE is zero and its standing cost is still $150.
    # Both on one calculator, so the pair cannot pass by the two readers having become one method.
    it "keeps asking once a goal is full, though this period's share is nothing",
       :aggregate_failures do
         september = described_class.new(full_goal, today: Date.new(2026, 9, 15))

         expect(september.built_up).to eq(1_200)
         expect(september.planned_this_period).to eq(0)
         expect(september.standing_ask).to eq(150)
       end

    # $1,200 due Aug 31 from a Jan 1 start is eight periods of $150, so September's share is nothing
    # and its standing cost is still $150.
    def full_goal
      create(
        :budget,
        category: create(:category, :expense, user: user, name: "Vacation", funded_since: Date.new(2026, 1, 1)),
        amount: 1_200,
        basis: :monthly,
        interval_months: nil,
        anchor_date: Date.new(2026, 8, 31),
        created_at: born
      )
    end

    # IT COSTS NO QUERY, and that is the property three call sites lean on: `Budget#steady_ask`'s
    # one-off branch builds an UNBATCHED calculator at `EntryImpactPresenter#steady_claim`,
    # `SacrificePresenter#rows` and `SuggestionEngine#dead_rule_suggestion`. Under
    # `#planned_this_period` each of those ran a spending query and an adjustment query per one-off
    # rule; this reader touches neither lane.
    it "reads no spending and no adjustment rows" do
      spend(200, on: Date.new(2026, 2, 10))
      calculator = calc(Date.new(2026, 3, 15))
      statements = []
      recorder = lambda do |_name, _start, _finish, _id, payload|
        statements << payload[:sql] unless ["SCHEMA", "TRANSACTION"].include?(payload[:name])
      end

      ActiveSupport::Notifications.subscribed(recorder, "sql.active_record") { calculator.standing_ask }

      expect(statements).to be_empty
    end
  end

  # ===========================================================================================
  # ONE SPELLING OF THE PRE-CLAMP FIGURE (fix wave — LOW-2). `#raw_rate` and its negation `#over_by`
  # are what `EntryImpactPresenter#pre_clamp_claim` adds an edited entry back to and what
  # `HomeHelper#claim_trouble_label` prints as `over by $60.00`; both used to spell the subtraction
  # themselves. Pinned against the members the two readers previously composed it out of, so the
  # exposed figure cannot drift from what those screens used to compute.
  # ===========================================================================================
  describe "#raw_rate and #over_by" do
    let(:today) { Date.new(2026, 9, 3) }
    let(:rule) { create(:budget, :per_period_rate, category: groceries, amount: 400) }

    it "is this period's accrual less its spending, and survives the clamp", :aggregate_failures do
      spend(460, on: Date.new(2026, 9, 2))
      calculator = described_class.new(rule, today: today)

      expect(calculator.raw_rate).to eq(-60)
      expect(calculator.raw_rate).to eq(calculator.accrued_this_period - calculator.spent_this_period)
      expect(calculator.over_by).to eq(60)
      expect(calculator.over?).to be(true)
      # The clamp has eaten the difference by the time the claim is read, which is why the readers
      # that need the excess need this figure and not that one.
      expect(calculator.claim).to eq(0)
    end

    # THE OTHER DIRECTION: under the rate it is simply what is left, with the sign the other way
    # round, and `#over?` is false.
    it "is positive and reads as no overspend at all while the rate holds", :aggregate_failures do
      spend(310, on: Date.new(2026, 9, 2))
      calculator = described_class.new(rule, today: today)

      expect(calculator.raw_rate).to eq(90)
      expect(calculator.over_by).to eq(-90)
      expect(calculator.over?).to be(false)
    end

    # ** ON AN ACCRUING SHAPE THE TWO FIGURES ARE DIFFERENT EXCESSES, AND `#over_by` USED TO REPORT
    # THE WRONG ONE (Task 1's concern 5). ** `#over?` reads the WALK's pre-clamp figure — the fund's
    # whole running total less what was spent — while `#raw_rate` is THIS PERIOD's accrual less this
    # period's spending. On a rate rule they are the same subtraction; on a building or dated rule
    # they are not, because the fund carries money in from earlier periods that `#raw_rate` cannot
    # see. `#over_by` negated `#raw_rate` for every shape, so Home fired the label off one figure
    # and printed the other.
    #
    # BOTH ARMS ARE THE SAME `#rate?` SPLIT `#over?` MAKES, so the predicate and the amount are now
    # answers about one subtraction. The DATED shape takes the identical arm (`shape != :rate`);
    # what varies between the two accruing shapes is the walk, which the groups above pin.
    #
    # PLANTED, re-derived by hand. A $1,000-a-period UNCAPPED building rule on a category funded
    # Jan 1, born Jan 1, read on Feb 15 of a monthly grid — so the walk visits January and February:
    #
    #   Jan  planned 1,000 · accrued 0 + 1,000 = 1,000 · spent 0     → raw  1,000 · built up 1,000
    #   Feb  planned 1,000 · accrued 1,000 + 1,000 = 2,000 · spent 2,600
    #                                                              → raw   −600 · built up     0
    #
    # So the fund was spent **$600** past everything it had, which is what the strip must say. This
    # period's own arithmetic is `1,000 − 2,600` = **−$1,600**, and the old reader printed
    # "over by $1,600.00" about a fund that had $1,000 carried in.
    describe "on an accruing shape" do
      let(:emergency) do
        create(:category, :expense, user: user, name: "Emergency", funded_since: Date.new(2026, 1, 1))
      end

      # ** A $12,000 GOAL DUE DEC 31, WHICH IS $1,000 A PERIOD FROM JANUARY. ** Twelve monthly
      # boundaries from Jan 1 through Dec 31, one fewer each month against a gap falling by the same
      # share — so the catch-up share is `12,000 ÷ 12` = $1,000 and stays there. It was a $1,000-a-
      # period building rule with no ceiling; the walk's figures are identical and the shape is one
      # the app still has.
      def fund
        create(
          :budget,
          category: emergency,
          amount: 12_000,
          basis: :monthly,
          interval_months: nil,
          anchor_date: Date.new(2026, 12, 31),
          created_at: born
        )
      end

      def spend_in_february(amount)
        create(:entry, item: create(:item, category: emergency), amount: amount, date: Date.new(2026, 2, 10))
      end

      it "reports the excess the walk measured and not this period's", :aggregate_failures do
        rule = fund
        spend_in_february(2_600)
        calculator = described_class.new(rule, today: Date.new(2026, 2, 15))

        expect(calculator.over?).to be(true)
        expect(calculator.over_by).to eq(600)
        # The figure the old reader would have negated, asserted so the two cannot silently converge.
        expect(calculator.raw_rate).to eq(-1_600)
        expect(calculator.claim).to eq(0)
      end

      # ** THE OTHER DIRECTION, AND IT IS THE HALF THAT WAS ACTIVELY WRONG. ** $1,600 spent against
      # $2,000 accrued leaves the fund $400 in hand — `raw` is +400, so `#over?` is FALSE — while
      # this period's own arithmetic is `1,000 − 1,600` = −$600. The old `#over_by` answered a
      # positive $600 for a fund nothing had overspent; a caller that printed it without asking
      # `#over?` first would have invented an overspend outright.
      it "is what the fund has left, signed the other way, while nothing is overspent", :aggregate_failures do
        rule = fund
        spend_in_february(1_600)
        calculator = described_class.new(rule, today: Date.new(2026, 2, 15))

        expect(calculator.over?).to be(false)
        expect(calculator.over_by).to eq(-400)
        expect(calculator.built_up).to eq(400)
        expect(calculator.raw_rate).to eq(-600)
      end
    end
  end

  # ===========================================================================================
  # WHICH DAYS' SPENDING THIS CLAIM COUNTS (fix wave — MED-1). `#counts_spending_on?` is
  # `#spent_within`'s own predicate, exposed for the one reader that has to ask it from outside:
  # the entry form's impact card, which gives an edited entry back to the figure only where the
  # figure had already taken it out. It asked `#countable_span` instead and got the ADJUSTMENT
  # question's answer — bounded at today — so a receipt dated later this period was subtracted by
  # the claim and again by the card. Both directions, on both shapes.
  # ===========================================================================================
  describe "#counts_spending_on?" do
    let(:today) { Date.new(2026, 9, 3) }

    # ** THE BITING CASE. ** Sep 10 is four days out and squarely inside the Sep 1 – Sep 30 period,
    # so `#spent_within(current_period)` sums an entry dated then — measured on the next line, where
    # a $50 receipt dated Sep 10 drops the claim to $350. `#countable_span` closes at Sep 3 and
    # would have said no.
    it "counts a day later in the current period for a rate rule", :aggregate_failures do
      rule = create(:budget, :per_period_rate, category: groceries, amount: 400)
      spend(50, on: Date.new(2026, 9, 10))

      expect(described_class.new(rule, today: today).counts_spending_on?(Date.new(2026, 9, 10))).to be(true)
      expect(described_class.new(rule, today: today).claim).to eq(350)
      expect(described_class.new(rule, today: today).countable_span).not_to cover(Date.new(2026, 9, 10))
    end

    # THE OTHER DIRECTION: a rate rule is use-it-or-lose-it, so August's spending is in no period
    # this claim is made of and moves nothing.
    it "does not count a day in a period a rate rule never walks" do
      rule = create(:budget, :per_period_rate, category: groceries, amount: 400)

      expect(described_class.new(rule, today: today).counts_spending_on?(Date.new(2026, 8, 31))).to be(false)
    end

    # AN ACCRUING RULE WALKS FROM ITS ACCRUAL START, so the same August day IS one of its days —
    # the predicate is the walk's, not the current period's.
    it "counts every day the accrual walk passes through", :aggregate_failures do
      rule = goal_born_on("Vacation", born)
      calculator = described_class.new(rule, today: today)

      expect(calculator.counts_spending_on?(Date.new(2026, 8, 31))).to be(true)
      expect(calculator.counts_spending_on?(Date.new(2026, 9, 10))).to be(true)
      expect(calculator.counts_spending_on?(Date.new(2025, 12, 31))).to be(false)
    end
  end

  # ===========================================================================================
  # §3.3 — WHICH DAYS AN ADJUSTMENT CAN LAND ON AND STILL BE COUNTED. `#countable_span` is the
  # walk read as a range of days, asked by `AdjustmentForm` and mirrored by the adjust panel's date
  # field: a row dated outside it sums into nothing, so writing one is a claim that never moves
  # under a flash that says it did. It is NOT "did the claim count this entry" — see
  # `#counts_spending_on?` above, and the double subtraction that came of confusing the two.
  # ===========================================================================================
  describe "#countable_span" do
    let(:today) { Date.new(2026, 9, 3) }

    # A RATE RULE WALKS ONE PERIOD, so its span is that period — closed at TODAY and not at the
    # period's end. Sep 30 is inside the period and outside the span: `#adjustments_within` would
    # sum a row dated then, but it is money moved on a day that has not happened, and every figure
    # this class answers is a figure for today.
    it "is the current period up to today for a rate rule", :aggregate_failures do
      rule = create(:budget, :per_period_rate, category: groceries, amount: 400)

      expect(described_class.new(rule, today: today).countable_span).to eq(Date.new(2026, 9, 1)..today)
      expect(described_class.new(rule, today: today).countable_span).not_to cover(Date.new(2026, 9, 30))
    end

    # AN ACCRUING RULE REACHES BACK TO WHERE ITS WALK OPENS, which is the FIRST DAY OF THE PERIOD
    # CONTAINING its accrual start rather than that date itself — §3.2's "a period's accrual counts
    # in full the day the period opens" applies to the first period like any other, so a delta
    # dated Feb 1 on a rule born Feb 10 is summed by the walk. The span is what the walk counts,
    # and refusing a date the walk would count would be a false refusal.
    it "reaches back to the open of the period the rule was born in", :aggregate_failures do
      rule = goal_born_on("Vacation", Time.utc(2026, 2, 10, 9, 0))

      expect(described_class.new(rule, today: today).countable_span).to eq(Date.new(2026, 2, 1)..today)
      expect(described_class.new(rule, today: today).countable_span).not_to cover(Date.new(2026, 1, 31))
    end

    # ** A RULE THAT HAS NOT STARTED COUNTING HAS AN EMPTY SPAN (fix round 2, NEW-4). ** The walk
    # visits nothing for a rule asked about a day before it was written — which is what every
    # backdated `today:` on a fresh rule is — and `#window_start` answers `current_period.first`
    # there because `ClaimLedger` has to be told SOME day to query from. Reading that fallback as a
    # span would invent the very period the walk itself stopped inventing: "pick a date between
    # Aug 1 and Aug 15" for a rule that counts nothing dated anywhere. Empty is the honest answer
    # and `AdjustmentForm` turns it into a sentence of its own.
    it "is empty for a rule asked about a day before it was written", :aggregate_failures do
      span = described_class.new(goal_born_on("Later", Time.utc(2026, 9, 1, 9, 0)), today: Date.new(2026, 8, 15)).countable_span

      expect(span.none?).to be(true)
      expect(span).not_to cover(Date.new(2026, 8, 15))
      expect(span).not_to cover(Date.new(2026, 8, 1))
    end

    # ** THE SPAN CANNOT OUTRUN THE WALK (fix round 2, NEW-2). ** `PERIOD_WALK_LIMIT` stops the walk
    # at 520 periods, which on the densest cadence this app offers is ten YEARS — so a fund funded
    # in 2010 accrues from Jan 2010 to Dec 2019 and the walk never reaches today at all. A span
    # closed at `today` would accept a row dated 2026 that `#adjustments_within` sums into none of
    # the periods visited: written, counted nowhere, and invisible in the row's list, which is
    # exactly the state the span exists to forbid.
    #
    # BY HAND: the 520th period opens 3,633 days after Jan 1 2010 (519 strides of seven) and closes
    # six days later — Dec 13 to Dec 19, 2019.
    describe "a goal on a weekly grid that has been saving since 2010" do
      let(:user) { create(:user, period_cadence: :weekly, period_anchor_date: Date.new(2010, 1, 1)) }

      def ark_goal
        ark = create(:category, :expense, user: user, name: "Ark", funded_since: Date.new(2010, 1, 1))
        create(
          :budget,
          category: ark,
          amount: 100_000,
          basis: :monthly,
          interval_months: nil,
          anchor_date: Date.new(2030, 1, 1),
          created_at: Time.utc(2010, 1, 1, 9, 0)
        )
      end

      it "ends where the truncated walk stopped rather than at today", :aggregate_failures do
        span = described_class.new(ark_goal, today: today).countable_span

        expect(span).to eq(Date.new(2010, 1, 1)..Date.new(2019, 12, 19))
        expect(span).not_to cover(today)
      end
    end
  end

  # ===========================================================================================
  # The injection seam — the same figures whether the calculator queries for itself or a ledger
  # hands it the rows, which is the contract `ClaimLedger` is built on.
  # ===========================================================================================
  describe "injected rows" do
    let(:rule) { create(:budget, :per_period_rate, category: groceries, amount: 400) }
    let(:today) { Date.new(2026, 9, 3) }

    it "reads the rows it is handed instead of the database", :aggregate_failures do
      injected = described_class.new(
        rule, today: today, spending: [[Date.new(2026, 9, 2), 150.to_d]], adjustments: [[Date.new(2026, 9, 2), 100.to_d]]
      )

      expect(injected.spent_this_period).to eq(150)
      expect(injected.claim).to eq(350)
    end

    # AN EMPTY LIST IS AN ANSWER, NOT A MISS — the calculator must not fall back to a query for a
    # rule the ledger found nothing for, or every empty lane would cost the statement it saved.
    it "treats an empty list as nothing spent rather than as nothing known" do
      spend(150, on: Date.new(2026, 9, 2))

      expect(described_class.new(rule, today: today, spending: [], adjustments: []).claim).to eq(400)
    end
  end
end
