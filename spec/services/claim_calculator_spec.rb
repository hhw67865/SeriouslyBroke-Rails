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

  # A $150-a-period goal on a category of its OWN, born on the moment given. A category may carry only
  # one rule whose lane is the whole of it (`Budget#category_may_hold_one_item_less_rule`), so two
  # birth dates need two categories.
  #
  # ** THE TARGET IS ON THE RULE AND THE CATEGORY NAMES NONE (rules-own-the-budget spec §2.1). ** It
  # used to be the other way round, and planting the figure only where the calculator no longer looks
  # is what makes every walk below a pin on the new reading rather than a pin that would pass either
  # way.
  def goal_born_on(name, moment)
    goal = create(:category, :expense, user: user, name: name, funded_since: Date.new(2026, 1, 1))
    create(:budget, :capped, category: goal, amount: 150, target_amount: 1_200, created_at: moment)
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
    end
  end

  # ===========================================================================================
  # §3.2/§3.3 — the capped building rule (rules-own-the-budget §2.1 row 3): the savings goal,
  # accruing at its rate toward the figure ON THE RULE, with no due date to spread it over.
  #
  # THE CATEGORY NAMES NOTHING. `categories.target_amount` still exists until the data migration,
  # and every fixture in this file leaves it NULL on purpose: the walk below is the new reading or
  # it is nothing.
  # ===========================================================================================
  describe "a capped building rule" do
    let(:vacation) do
      create(
        :category,
        :expense,
        user: user,
        name: "Vacation",
        funded_since: Date.new(2026, 1, 1)
      )
    end
    let(:rule) { create(:budget, :capped, category: vacation, amount: 150, target_amount: 1_200, created_at: born) }

    def calc(on) = described_class.new(rule, today: on)

    def withdraw(amount, on:)
      create(:entry, item: create(:item, category: vacation), amount: amount, date: on)
    end

    it "accrues at its own rate, one period at a time" do
      expect(calc(Date.new(2026, 4, 15)).built_up).to eq(600) # four periods of $150
    end

    it "has no due date and no periods to count down to one", :aggregate_failures do
      april = calc(Date.new(2026, 4, 15))

      expect(april.next_due_on).to be_nil
      expect(april.periods_left).to be_nil
      expect(april.planned_this_period).to eq(150)
    end

    # THE CAP IS THE RULE'S OWN FIGURE, and the final contribution is the remainder rather than the
    # rate: eight periods reach $1,200 and the ninth asks for nothing.
    it "stops at the target the rule names", :aggregate_failures do
      september = calc(Date.new(2026, 9, 15))

      expect(september.built_up).to eq(1_200)
      expect(september.planned_this_period).to eq(0)
    end

    it "takes a set-aside on top of its rate" do
      adjust(rule, 500, on: Time.utc(2026, 2, 10, 12))

      expect(calc(Date.new(2026, 2, 20)).built_up).to eq(800) # 150 + 150 + 500
    end

    # THE CAP HOLDS AGAINST A SET-ASIDE TOO, which is the one way an accrual can arrive above the
    # target at all: the catch-up formula and the rate are both bounded by the gap, so without this
    # example nothing in the matrix could tell a capped walk from an uncapped one.
    it "does not build past the target on a set-aside that overshoots it" do
      adjust(rule, 2_000, on: Time.utc(2026, 2, 10, 12))

      expect(calc(Date.new(2026, 2, 20)).built_up).to eq(1_200)
    end

    # A RAID IS A NEGATIVE DELTA, and the rate rebuilds from where it left off — there is no due
    # date to catch up to, so the recovery is the rate and nothing faster.
    it "gives money back on a negative delta", :aggregate_failures do
      adjust(rule, -200, on: Time.utc(2026, 3, 10, 12))

      expect(calc(Date.new(2026, 3, 20)).built_up).to eq(250) # 150 + 150 + 150 − 200
      expect(calc(Date.new(2026, 4, 20)).built_up).to eq(400)
    end

    it "drops by what is spent out of the goal" do
      withdraw(300, on: Date.new(2026, 3, 10))

      expect(calc(Date.new(2026, 3, 20)).built_up).to eq(150) # 450 accrued, 300 taken
    end

    # ** A GOAL FED ONLY BY HAND (§3.2's "otherwise only by positive adjustments"; §2.1 row 4). ** A
    # capped building rule with an amount of ZERO is the shape that says "no standing rate": it
    # accrues nothing on its own and every penny it holds arrived as a set-aside. Both directions —
    # the rate arm is the group above, and this arm is the same walk with the rate taken out.
    describe "with no rate at all" do
      let(:rule) { create(:budget, :hand_fed, category: vacation, target_amount: 1_200, created_at: born) }

      it "accrues nothing of its own" do
        expect(calc(Date.new(2026, 4, 15)).built_up).to eq(0)
      end

      it "builds up out of its set-asides and nothing else", :aggregate_failures do
        adjust(rule, 400, on: Time.utc(2026, 2, 10, 12))
        adjust(rule, 250, on: Time.utc(2026, 3, 10, 12))

        expect(calc(Date.new(2026, 2, 20)).built_up).to eq(400)
        expect(calc(Date.new(2026, 4, 15)).built_up).to eq(650)
      end

      it "still stops at the target the rule names" do
        adjust(rule, 5_000, on: Time.utc(2026, 2, 10, 12))

        expect(calc(Date.new(2026, 4, 15)).built_up).to eq(1_200)
      end
    end
  end

  # ===========================================================================================
  # ** THE SHAPE MATRIX (rules-own-the-budget spec §2.1), ROW BY ROW. ** Seven ways a user can
  # write a rule and the three formulas they map onto, read off the rule's OWN columns and no
  # neighbouring record's. `#shape`, `#capped?` and `#target` are asserted together on each row
  # because they are one classification: the shape says which formula, `capped?` says whether that
  # formula has a ceiling, and `#target` is the ceiling — a row that got one of the three right and
  # the others wrong would be a walk that ran the right arithmetic against the wrong bound.
  #
  # ONE CATEGORY PER ROW, because `Budget#category_may_hold_one_item_less_rule` allows a category
  # exactly one rule whose lane is the whole of it.
  # ===========================================================================================
  describe "#shape, #capped? and #target across §2.1" do
    def rule_for(name, *traits, **attrs)
      owner = create(:category, :expense, user: user, name: name, funded_since: Date.new(2026, 1, 1))
      create(:budget, *traits, category: owner, created_at: born, **attrs)
    end

    def calc(rule) = described_class.new(rule, today: Date.new(2026, 9, 3))

    # ROW 1 — $400 a period, resets. Today's rate rule, and `carries_over false` is what it has
    # always meant. `#target` is ZERO rather than nil, unchanged: a rate rule accrues toward nothing,
    # and zero is what `#standing_ask`'s siblings have always read there.
    it "calls a per-period rule whose money resets a rate rule", :aggregate_failures do
      rule = rule_for("Groceries", :per_period_rate, amount: 400)

      expect(calc(rule).shape).to eq(:rate)
      expect(calc(rule)).to be_rate
      expect(calc(rule)).not_to be_capped
      expect(calc(rule).target).to eq(0)
    end

    # ROW 2 — $300 a period, builds up, no ceiling. The emergency fund: the §3.2 walk with `gap`
    # unbounded, so `#target` is NIL and not zero. The difference is load-bearing — zero would make
    # `gap` negative on the first period and the walk would plan nothing for ever.
    it "calls a per-period rule that builds up an uncapped building rule", :aggregate_failures do
      rule = rule_for("Emergency", :building, amount: 300)

      expect(calc(rule).shape).to eq(:building)
      expect(calc(rule)).to be_building
      expect(calc(rule)).not_to be_capped
      expect(calc(rule).target).to be_nil
    end

    # ROW 3 — $200 a period toward $5,000. Today's goal, reading the RULE.
    it "calls a building rule that names a figure a capped one", :aggregate_failures do
      rule = rule_for("Vacation", :building, amount: 200, target_amount: 5_000)

      expect(calc(rule).shape).to eq(:building)
      expect(calc(rule)).to be_capped
      expect(calc(rule).target).to eq(5_000)
    end

    # ROW 4 — $0 a period toward $5,000: fed by hand, and the only shape `Budget#set_aside_only?`
    # exempts from `amount > 0`. It is a capped building rule like row 3 in every respect but its
    # rate, which is what makes the classification independent of the amount.
    it "calls a hand-fed goal a capped building rule too", :aggregate_failures do
      rule = rule_for("Someday", :hand_fed, target_amount: 5_000)

      expect(calc(rule).shape).to eq(:building)
      expect(calc(rule)).to be_capped
      expect(calc(rule).target).to eq(5_000)
    end

    # ROW 5 — $260 a month, both ways. The BASIS is not part of the classification: a monthly rule
    # that carries is a building rule exactly as a per-period one is, and `Budget#steady_ask` is what
    # divides the month over the user's grid. Both arms in one example, because the row's whole
    # content is that `carries_over` is the only column that moves.
    it "reads carries_over on a monthly rule and nothing else", :aggregate_failures do
      resets = rule_for("Power", :rate, amount: 260)
      builds = rule_for("Repairs", :rate, amount: 260, carries_over: true)

      expect(calc(resets).shape).to eq(:rate)
      expect(calc(builds).shape).to eq(:building)
      expect(calc(builds)).not_to be_capped
    end

    # ROW 6 — $600 every 6 months from Dec 1. Unchanged: the anchor wins over everything, and a
    # dated rule's target IS its amount — what has to be there on the day.
    it "calls an anchored interval rule dated, capped at its own amount", :aggregate_failures do
      rule = rule_for("Insurance", amount: 600, interval_months: 6, anchor_date: Date.new(2026, 12, 1))

      expect(calc(rule).shape).to eq(:dated)
      expect(calc(rule)).to be_capped
      expect(calc(rule).target).to eq(600)
    end

    # ROW 7 — $600 once on Dec 1. The one-time bill, which §1 rules is all the "one-time concept"
    # there is: a date and no interval.
    it "calls an anchored rule with no interval dated as well", :aggregate_failures do
      rule = rule_for("Registration", amount: 600, interval_months: nil, anchor_date: Date.new(2026, 12, 1))

      expect(calc(rule).shape).to eq(:dated)
      expect(calc(rule)).to be_capped
      expect(calc(rule).target).to eq(600)
    end

    # ** THE COLUMN THAT MOVED, ASKED IN THE DIRECTION THAT USED TO PASS. ** A figure on the CATEGORY
    # made a rule `:target`-shaped until this task; the calculator does not read it at all now, so
    # the identical rule beside the identical category figure is a plain rate rule. Without this the
    # rows above would all pass against a class that still consulted the category.
    it "does not read a figure the category names", :aggregate_failures do
      owner = create(:category, :expense, user: user, name: "Old Goal", funded_since: Date.new(2026, 1, 1), target_amount: 5_000)
      rule = create(:budget, :per_period_rate, category: owner, amount: 150, created_at: born)

      expect(calc(rule).shape).to eq(:rate)
      expect(calc(rule).target).to eq(0)
      expect(calc(rule).built_up).to eq(0)
    end
  end

  # ===========================================================================================
  # ** THE UNCAPPED BUILDING RULE (§2.1 row 2) — THE WALK WITH NO CEILING. ** `gap` is unbounded, so
  # `planned_for` returns the plain rate every period and `accrued_in` applies no `min`. Three
  # periods, planted literals, with spending and a negative adjustment in the middle one.
  # ===========================================================================================
  describe "an uncapped building rule" do
    let(:emergency) do
      create(:category, :expense, user: user, name: "Emergency", funded_since: Date.new(2026, 1, 1))
    end
    let(:rule) { create(:budget, :building, category: emergency, amount: 300, created_at: born) }

    def calc(on) = described_class.new(rule, today: on)

    def withdraw(amount, on:)
      create(:entry, item: create(:item, category: emergency), amount: amount, date: on)
    end

    # BY HAND, and it is the whole of the group's arithmetic:
    #   Jan  planned 300, accrued 0 + 300           → built 300
    #   Feb  planned 300, accrued 300 + 300 − 150   → 450, less 100 spent → built 350
    #   Mar  planned 300, accrued 350 + 300         → built 650
    before do
      adjust(rule, -150, on: Time.utc(2026, 2, 10, 12))
      withdraw(100, on: Date.new(2026, 2, 12))
    end

    it "keeps every period's plain rate and never stops growing", :aggregate_failures do
      expect(calc(Date.new(2026, 1, 20)).built_up).to eq(300)
      expect(calc(Date.new(2026, 2, 20)).built_up).to eq(350)
      expect(calc(Date.new(2026, 3, 20)).built_up).to eq(650)
    end

    # ** ADJUSTMENTS ON A BUILDING RULE TOUCH ONLY THEIR PERIOD (§2.1, ruled 2026-09-04). ** There is
    # no catch-up without a deadline — `planned_for` returns the rate and never `gap ÷ periods_left`
    # — so the −$150 dated in February leaves March asking its plain $300 rather than $450. This is
    # the exact opposite of a DATED rule, whose "after a period is skipped" group above raises every
    # later share to recover the due date, and the two are pinned against each other by name.
    it "asks the plain rate in the period after a negative adjustment", :aggregate_failures do
      expect(calc(Date.new(2026, 2, 20)).planned_this_period).to eq(300)
      expect(calc(Date.new(2026, 3, 20)).planned_this_period).to eq(300)
    end

    # THE CLAIM IS THE BUILT-UP, not this period's leftover rate: the money's whole purpose is to
    # still be there next period.
    it "claims what it has built rather than what is left of this period" do
      expect(calc(Date.new(2026, 3, 20)).claim).to eq(650)
    end
  end

  # ===========================================================================================
  # ** THE CAP REFILLS, AND THAT IS NOT CATCH-UP (fix round 1 — LOW). ** The comment on
  # `#planned_for` used to say "adjustments on a building rule touch only their period" flat, which
  # is true of the UNCAPPED shape and only half true of the capped one: a capped rule sitting AT its
  # cap plans nothing, and a −$150 leaves a $150 gap that the next period plans `min(rate, gap)`
  # against — the fund refills. It never exceeds the rate and there is no deadline it is racing, so
  # it is the cap's own arithmetic rather than §3.2's catch-up. Both arms are pinned, because the
  # sentence is only meaningful as the pair.
  # ===========================================================================================
  describe "a negative adjustment on a capped building rule at its cap" do
    # $150 a period toward $1,200 from Jan 1: eight periods fill it, so August closes full and
    # September opens planning nothing.
    let(:full_goal) do
      create(
        :budget,
        :capped,
        category: create(:category, :expense, user: user, name: "Vacation", funded_since: Date.new(2026, 1, 1)),
        amount: 150,
        target_amount: 1_200,
        created_at: born
      )
    end

    def calc(on) = described_class.new(full_goal, today: on)

    before { adjust(full_goal, -150, on: Time.utc(2026, 9, 10, 12)) }

    # SEPTEMBER: `gap` is zero when the period opens, so it plans $0; the −$150 lands after the plan
    # and takes the fund to $1,050.
    it "takes the money out of the period it is dated in", :aggregate_failures do
      september = calc(Date.new(2026, 9, 20))

      expect(september.planned_this_period).to eq(0)
      expect(september.built_up).to eq(1_050)
    end

    # OCTOBER: the gap is $150, so it plans `min($150, $150)` and the fund is whole again. This is
    # the arm the old comment denied.
    it "plans the gap back up to the cap in the next period, and no faster", :aggregate_failures do
      october = calc(Date.new(2026, 10, 20))

      expect(october.planned_this_period).to eq(150)
      expect(october.built_up).to eq(1_200)
    end

    # AND IT IS BOUNDED BY THE RATE, which is what makes it the cap's arithmetic rather than
    # catch-up: a −$600 leaves a $600 gap and October still plans only its $150.
    it "never asks for more than its rate to close a bigger gap", :aggregate_failures do
      create(:adjustment, rule: full_goal, amount: -450, date: Time.utc(2026, 9, 11, 12))
      october = calc(Date.new(2026, 10, 20))

      expect(october.planned_this_period).to eq(150)
      expect(october.built_up).to eq(750)
    end
  end

  # ===========================================================================================
  # ** THE CAP, WITH AND WITHOUT (§2.1 rows 2 and 3). ** The same rate, the same grid, the same six
  # periods — one rule names $5,000 and stops there, the other names nothing and keeps going. The
  # pair is the whole content of `#capped?`, and neither half means anything alone: a walk that
  # ignored the target would pass the second and a walk that capped everything would pass the first.
  # ===========================================================================================
  describe "at the cap" do
    def thousand_a_period(name, **attrs)
      owner = create(:category, :expense, user: user, name: name, funded_since: Date.new(2026, 1, 1))
      create(:budget, :building, category: owner, amount: 1_000, created_at: born, **attrs)
    end

    def calc(rule) = described_class.new(rule, today: Date.new(2026, 6, 15))

    # Jan through May is five periods of $1,000, which is the target exactly; June's share is the
    # remainder, which is nothing.
    it "stops a capped rule at its target and asks for nothing more", :aggregate_failures do
      capped = thousand_a_period("Vacation", target_amount: 5_000)

      expect(calc(capped).built_up).to eq(5_000)
      expect(calc(capped).planned_this_period).to eq(0)
    end

    # THE SAME SIX PERIODS WITH NO CEILING: $6,000, and June still asks its full rate.
    it "lets an uncapped rule pass the same figure and go on asking", :aggregate_failures do
      uncapped = thousand_a_period("Emergency")

      expect(calc(uncapped).built_up).to eq(6_000)
      expect(calc(uncapped).planned_this_period).to eq(1_000)
    end

    # AND A SET-ASIDE THAT OVERSHOOTS IS NOT CLIPPED EITHER, which is the `min` in `accrued_in` —
    # the other of the two sites `#capped?` gates. $6,000 of accrual plus a $2,000 delta is $8,000.
    it "does not clip an uncapped rule's set-aside" do
      uncapped = thousand_a_period("Emergency")
      adjust(uncapped, 2_000, on: Time.utc(2026, 3, 10, 12))

      expect(calc(uncapped).built_up).to eq(8_000)
    end

    # ** SPENT PAST WHAT IT HAD BUILT (§3.2's spill, on the new shape). ** Jan builds $1,000; February
    # accrues another $1,000 for $2,000 and $2,500 goes out of the category — the pre-clamp figure is
    # −$500, so the rule reads OVER and the fund starts March from zero rather than from minus five
    # hundred.
    it "reads over when the spending outruns the build-up", :aggregate_failures do
      uncapped = thousand_a_period("Emergency")
      create(:entry, item: create(:item, category: uncapped.category), amount: 2_500, date: Date.new(2026, 2, 12))
      february = described_class.new(uncapped, today: Date.new(2026, 2, 20))

      expect(february).to be_over
      expect(february.built_up).to eq(0)
      expect(february.claim).to eq(0)
      expect(described_class.new(uncapped, today: Date.new(2026, 3, 20)).built_up).to eq(1_000)
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
    # walks ONE period and holds one period's rate — not the two years the category could show.
    it "starts on the day the rule was written, not on the day the category was funded" do
      born_today = create(
        :budget,
        :capped,
        category: vacation,
        amount: 150,
        target_amount: 1_200,
        created_at: Time.utc(2026, 9, 1, 9, 0)
      )

      expect(calc(born_today, Date.new(2026, 9, 3)).built_up).to eq(150)
    end

    # THE OTHER DIRECTION, and it is what says the ruling did not simply replace one date with the
    # other: the FIRST rule on a category is written the day the category starts holding, so the two
    # dates coincide and the whole history is walked. Four periods of $150 from a June start.
    it "starts on the funding date for the rule that put it there" do
      fresh = create(:category, :expense, user: user, name: "Trip", funded_since: Date.new(2026, 6, 1))
      first = create(:budget, :capped, category: fresh, amount: 150, target_amount: 1_200, created_at: Time.utc(2026, 6, 1, 9, 0))

      expect(calc(first, Date.new(2026, 9, 3)).built_up).to eq(600)
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
  # midnight on Sep 1 in Tokyo, so one instant opens the walk in two different months. A TARGET rule,
  # so the walk actually runs: two periods against one, by Sep 3.
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

      it "opens it in September, the day the owner was living in" do
        expect(described_class.new(written_then, today: Date.new(2026, 9, 3)).built_up).to eq(150)
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

    # ** A BUILDING RULE'S STANDING ASK IS ITS RATE (rules-own-the-budget spec §2.2), CONSTANT LIKE A
    # RATE RULE'S. ** It has no deadline, so there is nothing for a divisor to be the periods UNTIL —
    # what it costs a typical period is simply what it puts in every period, for as long as the user
    # keeps it. §9's structural check counts it on those terms.
    it "asks its plain rate for an uncapped building rule, whatever it has built", :aggregate_failures do
      fund = create(
        :budget,
        :building,
        category: create(:category, :expense, user: user, name: "Emergency", funded_since: Date.new(2026, 1, 1)),
        amount: 300,
        created_at: born
      )

      expect(described_class.new(fund, today: Date.new(2026, 3, 15)).standing_ask).to eq(300)
      expect(described_class.new(fund, today: Date.new(2026, 8, 15)).standing_ask).to eq(300)
    end

    # AND A CAPPED ONE GOES ON DECLARING ITS COST AFTER THE GOAL IS MET, which is the settled
    # one-off's ruling asked of the other accruing shape: eight periods of $150 fill a $1,200 target
    # by August, so September's SHARE is zero and its standing cost is still $150. Both on one
    # calculator, so the pair cannot pass by the two readers having become the same method.
    it "keeps asking once a capped building rule is full, though this period's share is nothing",
       :aggregate_failures do
         september = described_class.new(full_goal, today: Date.new(2026, 9, 15))

         expect(september.built_up).to eq(1_200)
         expect(september.planned_this_period).to eq(0)
         expect(september.standing_ask).to eq(150)
       end

    # Eight periods of $150 from a Jan 1 start fill a $1,200 target by August, so September's share
    # is nothing and its standing cost is still $150.
    def full_goal
      create(
        :budget,
        :capped,
        category: create(:category, :expense, user: user, name: "Vacation", funded_since: Date.new(2026, 1, 1)),
        amount: 150,
        target_amount: 1_200,
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
    describe "a fund on a weekly grid that has been building since 2010" do
      let(:user) { create(:user, period_cadence: :weekly, period_anchor_date: Date.new(2010, 1, 1)) }

      it "ends where the truncated walk stopped rather than at today", :aggregate_failures do
        ark = create(:category, :expense, user: user, name: "Ark", funded_since: Date.new(2010, 1, 1))
        rule = create(:budget, :capped, category: ark, amount: 5, target_amount: 100_000, created_at: Time.utc(2010, 1, 1, 9, 0))

        span = described_class.new(rule, today: today).countable_span

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
