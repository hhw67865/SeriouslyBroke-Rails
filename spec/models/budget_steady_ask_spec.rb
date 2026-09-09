# frozen_string_literal: true

require "rails_helper"

# WHAT A RULE CLAIMS FROM A TYPICAL PERIOD (spec §8, §9) — the steady figure, deliberately not
# `ClaimCalculator#planned_this_period`'s this-period ask. Every shape is asserted in both directions
# and by type, because the whole file is money arithmetic: an Integer leaking out of one branch
# changes what `Budget.steady_need` sums to and therefore whether the structural check fires.
#
# `today:` is passed explicitly everywhere and every anchor is a literal offset from it. The suite
# runs on whatever day it runs on, and a fixed calendar date would flip the one-off shape from
# unfulfilled to fulfilled the moment it passed.
RSpec.describe Budget, type: :model do
  let(:today) { Date.new(2026, 2, 6) }

  # Biweekly, so 26 periods a year — the cadence that separates a correct normalisation from the
  # mixed-unit bug. Under a monthly user every "a month" figure passes through unchanged and the
  # trap below cannot fire at all.
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: today) }

  # ** THE FUNDING DATE IS A LITERAL RATHER THAN THE `:funded` TRAIT'S `1.year.ago` (fix wave —
  # MED-3, and it still bites in fix wave 2). ** `#steady_ask`'s one-off branch divides by the periods
  # from the ACCRUAL START — the later of `funded_since` and the rule's own birthday — to the due
  # date. A wall-clock funding date one real year from now would land after every anchor in this file,
  # leaving no boundary between the two, and every one-off example here would quietly assert against
  # the floor of one period. CLAUDE.md's third flake cause, closed by planting the date.
  let(:owner) { create(:category, :expense, user: user, name: "Car", funded_since: Date.new(2025, 1, 1)) }

  # ** A CATEGORY MAY CARRY ONLY ONE ITEM-LESS RULE (`Budget#category_may_hold_one_item_less_rule`,
  # computed-claims ruling of 2026-09-03), and every helper here plants on the SAME `owner`. ** So
  # the second and later catch-all rules get an item of their own. `#steady_ask` never reads the item
  # on any of these three shapes — only its one-off branch does, and `#one_off` below takes its item
  # from the caller — so this is fixture plumbing and not a change of subject.
  def rate(amount) = plant(:per_period_rate, amount: amount)

  def monthly(amount) = plant(:rate, amount: amount)

  def every(months, amount:, anchor:)
    plant(amount: amount, interval_months: months, anchor_date: anchor)
  end

  def plant(trait = nil, **attrs)
    attrs = attrs.merge(item: create(:item, category: owner, name: "Lane #{Budget.count}")) if second_catch_all?
    create(:budget, *Array(trait), category: owner, **attrs)
  end

  def second_catch_all? = Budget.exists?(category_id: owner.id, item_id: nil)

  # ** `born:` IS THE DAY THE RULE EXISTED FROM, AND IT IS THE FIXTURE'S SUBJECT RATHER THAN ITS
  # PLUMBING (fix wave — MED-3, re-aimed in fix wave 2 — MED-A). ** The one-off branch is
  # `ClaimCalculator#standing_ask`: the amount over the periods from the accrual start's period
  # THROUGH the period the bill falls due in, and the accrual start is the later of the category's
  # funding date and this. So `born:` is one end of the divisor, and every example below states it
  # rather than inheriting the factory's wall clock — which writes `created_at` months after this
  # file's fixed `today` and would collapse every divisor to the floor of one period.
  def one_off(amount, anchor:, item: nil, born: today)
    create(
      :budget,
      category: owner,
      amount: amount,
      interval_months: nil,
      anchor_date: anchor,
      item: item,
      created_at: Time.utc(born.year, born.month, born.day, 9, 0)
    )
  end

  describe "#steady_ask on a per-period rate rule" do
    subject(:ask) { rate(300).steady_ask(user, today: today) }

    # A per-period amount IS a per-period amount. Nothing to normalise, and normalising it
    # anyway is the mirror image of the bug below.
    it "passes the amount straight through" do
      expect(ask).to eq(300)
    end

    # `amount: 300` on an in-memory record is an Integer, and `Integer / Integer` truncates cents
    # three call sites downstream. Asserted on the shape that does no arithmetic at all, because
    # that is the one where a bare column would sail through.
    it "answers a BigDecimal" do
      expect(ask).to be_a(BigDecimal)
    end
  end

  # THE MIXED-UNIT TRAP, and it has already bitten once: 2b's Task 1 found `per_period_rate`
  # treating a monthly amount as per-period, which asked a biweekly user for 2x the rate.
  # $260 a month under 26 periods a year is $120 a period — the figure is chosen so the bug's
  # answer ($260) and the right one ($120) cannot be confused with a rounding difference.
  describe "a rate rule on a monthly basis", :aggregate_failures do
    subject(:ask) { monthly(260).steady_ask(user, today: today) }

    it "normalises the month into the user's period" do
      expect(ask).to eq(120)
    end

    it "does not treat the monthly amount as a per-period one" do
      expect(ask).not_to eq(260)
    end

    it "answers a BigDecimal" do
      expect(ask).to be_a(BigDecimal)
    end

    # The same rule under a user whose period IS a month: 12 periods a year, so the figure passes
    # through. Both directions of the same normalisation, so a method that simply returned the
    # amount could not pass the pair.
    it "passes through unchanged for a monthly user" do
      monthly_user = create(:user, period_cadence: :monthly, period_anchor_date: today)

      expect(monthly(260).steady_ask(monthly_user, today: today)).to eq(260)
    end

    # Weekly is 52 and semimonthly is 24 — twice a month, not every fourteen days. A single
    # `PERIODS_PER_YEAR` typo between them is an 8% error in every normalised figure on the page.
    it "divides by the cadence's own period count" do
      weekly = create(:user, period_cadence: :weekly, period_anchor_date: today)
      semimonthly = create(:user, period_cadence: :semimonthly, period_anchor_date: today)

      expect(monthly(260).steady_ask(weekly, today: today)).to eq(60)
      expect(monthly(260).steady_ask(semimonthly, today: today)).to eq(130)
    end
  end

  # A rule that recurs on a schedule claims its amount spread over the periods in ONE interval,
  # not over the periods until its next occurrence — that second figure is #required's, and it
  # shrinks as the date approaches. The steady claim does not move.
  describe "an anchored recurring rule" do
    subject(:ask) { every(6, amount: 1_200, anchor: today + 3.months).steady_ask(user, today: today) }

    # 26 periods a year x 6/12 = 13 periods in the interval. $1,200 / 13 = $92.3076…
    it "spreads the amount over the periods in its interval" do
      expect(ask).to eq(BigDecimal("92.31"))
    end

    it "answers a BigDecimal" do
      expect(ask).to be_a(BigDecimal)
    end

    # THE FIGURE DOES NOT MOVE WITH THE CALENDAR. The same rule read four periods later, with its
    # due date that much closer, still claims the same amount from a period — which is exactly
    # what distinguishes it from `BudgetCalculator#required`.
    it "reads the same as its due date approaches" do
      rule = every(6, amount: 1_200, anchor: today + 3.months)

      expect(rule.steady_ask(user, today: today + 8.weeks)).to eq(rule.steady_ask(user, today: today))
    end

    # A 12-month interval is the shape most likely to be confused with a monthly one, and the
    # divisor differs twelvefold. $2,600 a year under biweekly is $100 a period.
    it "handles an annual interval" do
      expect(every(12, amount: 2_600, anchor: today + 1.month).steady_ask(user, today: today)).to eq(100)
    end

    # An interval of 1 with an anchor is `Budget#cadence`'s `:monthly`, and it must land on the
    # same normalisation as the anchorless monthly rate rule above — the anchor says when, not
    # how much.
    it "reads an interval of one month exactly as an anchorless monthly rule does" do
      expect(every(1, amount: 260, anchor: today + 10.days).steady_ask(user, today: today)).to eq(120)
    end
  end

  # A ONE-TIME RULE HAS NO INTERVAL, so there is nothing to divide by but the calendar: what it
  # costs to have the money ready by the day it is due.
  describe "an anchored one-time rule, unfulfilled" do
    # Ten biweekly boundaries fall in Feb 6..Jun 12 inclusive — the divisor counts the boundary the
    # accrual start sits on, so a 126-day horizon is 10 periods, not 9. $2,000 over them is $200
    # a period. (The first literal here was 11-periods-wrong and the example caught it: the count
    # is asserted through a figure that changes if the fencepost does.)
    subject(:ask) { one_off(2_000, anchor: today + 126.days).steady_ask(user, today: today) }

    it "amortises the amount over the periods before it falls due" do
      expect(ask).to eq(200)
    end

    it "answers a BigDecimal" do
      expect(ask).to be_a(BigDecimal)
    end

    # The floor at 1, asserted on the shape that reaches it: a bill due inside the current period
    # has no boundary between now and then, and dividing by zero periods would raise on a page
    # whose only job is to render figures.
    it "claims the whole amount when it falls due inside this period" do
      expect(one_off(500, anchor: today + 2.days).steady_ask(user, today: today)).to eq(500)
    end

    # ** THE FIGURE DOES NOT MOVE AS THE DUE DATE APPROACHES (fix wave — MED-3, re-derived in fix
    # wave 2 — MED-A). ** This example asserted `be >` against `BudgetCalculator#periods_until_due`,
    # which divided the whole amount by a SHRINKING number of periods and so re-asked for money the
    # user had already set aside; the wave after that read §3.2's catch-up share, which holds only
    # while the fund keeps pace and moves the moment it does not. `#standing_ask` is a constant of the
    # rule and the grid: $2,000 due Jun 26, born Feb 6, is 11 biweekly periods (Feb 6 … Jun 26) and
    # therefore $181.82 a period on every day of the rule's life.
    it "reads the same as its due date approaches", :aggregate_failures do
      rule = one_off(2_000, anchor: today + 140.days)

      expect(rule.steady_ask(user, today: today)).to eq(BigDecimal("181.82"))
      expect(rule.steady_ask(user, today: today + 70.days)).to eq(BigDecimal("181.82"))
    end

    # ** AND IT DOES NOT MOVE WHEN THE FUND IS SPENT DOWN, which is the whole of MED-A. ** The same
    # rule with $909.10 — every penny it had accrued through Apr 3 — spent out of the category IN the
    # Apr 3 period. The walk clamps that period to zero and the last one starts from nothing, so THIS
    # PERIOD'S share rises to (2000 − 0) ÷ 6 = $333.33 while the standing figure stays where the rule
    # put it. Both are asserted, so the pair cannot pass by the two readers having become one:
    #
    #   Feb 6 – Mar 20   181.82 a period               built up 727.28
    #   Apr 3            (2000 − 727.28) ÷ 7 = 181.82  accrued 909.10, spent 909.10 → built up 0
    #   Apr 17           steady 181.82   ·   this period's catch-up share 333.33
    #
    # A structural verdict computed from the second figure moves with a receipt — the defect this
    # example now guards. THE SPENDING IS DATED A PERIOD EARLY on purpose: §3.2's order inside a
    # period is accrue, adjust, cap, THEN spend, so a receipt dated in the last period has not
    # reached `planned` yet.
    it "does not move when the fund has been spent down", :aggregate_failures do
      rule = one_off(2_000, anchor: today + 140.days)
      create(:entry, item: create(:item, category: owner), amount: 909.10, date: today + 56.days)

      expect(rule.steady_ask(user, today: today + 70.days)).to eq(BigDecimal("181.82"))
      expect(rule.claim_calculator(today: today + 70.days).planned_this_period).to eq(BigDecimal("333.33"))
    end
  end

  # ** A SETTLED BILL STILL DECLARES ITS STANDING COST (fix wave 2 — MED-A, the ruling in full). **
  # This group asserted `eq(0)` while the branch read the catch-up share, whose `#settled?` gate zeroes
  # a paid one-off for ever. The standing ask is a fact about the RULE: for as long as the user keeps
  # a $500 bill on the books it costs what it always cost, and the figure that drops to zero on
  # payment is `ClaimCalculator#planned_this_period`, asserted beside it here.
  #
  # THE CONSEQUENCE, STATED: a one-time bill that has been paid goes on counting toward
  # `Budget.steady_need` until the rule is deleted. That is the price of a verdict about the shape of
  # the rules that no afternoon's cash can move, and it is the shape `EntryImpactPresenter#bar?`
  # needs a positive denominator for.
  describe "an anchored one-time rule, fulfilled" do
    let(:category) { owner }
    let(:item) { create(:item, category: category, name: "Dentist") }
    # BORN A PERIOD EARLY, so the walk visits Jan 23 – Feb 5 as well as this one and the payment
    # dated Feb 1 lands inside a period it passes through — which is what makes the catch-up figure
    # below a real zero rather than an accident of the rule being too young to have seen the entry.
    # The divisor is Jan 23 through the Jan 27 due date: one period, so the standing ask is $500.
    let(:rule) { one_off(500, anchor: today - 10.days, item: item, born: today - 14.days) }

    before { create(:entry, item: item, amount: 500, date: today - 5.days) }

    it "goes on claiming what it always claimed", :aggregate_failures do
      expect(rule.steady_ask(user, today: today)).to eq(500)
      expect(rule.claim_calculator(today: today).planned_this_period).to eq(0)
    end

    it "answers a BigDecimal" do
      expect(rule.steady_ask(user, today: today)).to be_a(BigDecimal)
    end

    # The same rule read four periods later, with the payment four periods further back: still $500.
    # A figure that read the fund at all would have to move on one of these two days.
    it "reads the same long after the bill was paid" do
      expect(rule.steady_ask(user, today: today + 56.days)).to eq(500)
    end

    # The other direction on the same day and the same shape: a part payment changes neither figure's
    # answer about the standing cost. $100 of a $500 bill leaves $400 still to find over the one
    # period `#periods_left` floors at, so the catch-up share is $100 and the standing ask is $500 —
    # two different numbers about one rule, which is the point of there being two readers.
    it "makes the same standing claim when the bill was only part paid", :aggregate_failures do
      partial_item = create(:item, category: category, name: "Optician")
      create(:entry, item: partial_item, amount: 100, date: today - 5.days)
      partial = one_off(500, anchor: today - 10.days, item: partial_item, born: today - 14.days)

      expect(partial.steady_ask(user, today: today)).to eq(500)
      expect(partial.claim_calculator(today: today).planned_this_period).to eq(100)
    end
  end

  # THE CATEGORY-MODE CAP GROUP IS DELETED (plan 3, task 3). It pinned that `#steady_ask`
  # normalised a $260 monthly cap into $120 a fortnight, and its long comment argued the method
  # should answer for a shape no reader passed it — which is exactly the argument the cap's
  # deletion settles. `#steady_ask` is still a per-rule normaliser and the monthly branch it
  # reached is still pinned, by the anchorless monthly rate rule above.

  # THE UNDECLARED USER. The structural-check block renders nothing without a cadence, so this path
  # feeds no verdict yet — but the drift detector calls `steady_ask` for every rate rule
  # regardless of whether a period has been declared, and a divisor of zero here would 500 the very
  # page that exists to fix the missing declaration. The shapes below are asserted because the
  # method must ANSWER for all of them, not because a screen prints them.
  describe "a user who has declared no period" do
    let(:undeclared) { create(:user) }
    let(:their_owner) { create(:category, :expense, :funded, user: undeclared, name: "Car") }

    it "passes a per-period amount through" do
      rule = create(:budget, :per_period_rate, category: their_owner, amount: 300)

      expect(rule.steady_ask(undeclared, today: today)).to eq(300)
    end

    # The documented answer: with no period declared the period IS the calendar month, matching
    # what `BudgetCalculator#period_end` and `User#period_containing` already fall back to.
    it "leaves a monthly amount monthly" do
      rule = create(:budget, :rate, category: their_owner, amount: 260)

      expect(rule.steady_ask(undeclared, today: today)).to eq(260)
    end

    it "still answers for a dated rule rather than dividing by zero" do
      rule = create(
        :budget,
        category: their_owner,
        amount: 1_200,
        interval_months: 6,
        anchor_date: today + 3.months
      )

      expect(rule.steady_ask(undeclared, today: today)).to eq(200)
    end

    it "gives a one-off rule the whole amount, there being no periods to spread over" do
      rule = create(
        :budget,
        category: their_owner,
        amount: 500,
        interval_months: nil,
        anchor_date: today + 140.days,
        created_at: Time.utc(today.year, today.month, today.day, 9, 0)
      )

      expect(rule.steady_ask(undeclared, today: today)).to eq(500)
    end
  end

  # THE SUM BEHIND §9's CHECK. Pinned against PLANTED LITERALS rather than against
  # `rules.sum(&:steady_ask)` — the same records recomputed by the same method is `x == x`, and it
  # passes just as happily when every term is wrong.
  describe ".steady_need", :aggregate_failures do
    it "sums every pool-mode rule the user owns" do
      rate(300) # $300 a period
      monthly(260) # $120 a period
      every(6, amount: 1_200, anchor: today + 3.months) # $92.31 a period

      expect(described_class.steady_need(user, today: today)).to eq(BigDecimal("512.31"))
    end

    # THE THREE CAP-EXCLUSION EXAMPLES ARE DELETED (plan 3, task 3). They pinned that a $650
    # monthly cap contributed nothing to this sum, that a user whose only rules were caps read
    # $0.00, and that a stranger's cap was excluded too — the whole `where.not(pool_id: nil)`
    # boundary this method was built around. A cap is not a shape the app can hold, `#for_user` is
    # pool-scoped by construction, and the filter is gone; examples asserting an exclusion that can
    # no longer exclude anything would be green whatever the code did.

    # DELETED (plan 3, task 6): "counts a rule on a pool no account can reach". It pinned 2b's
    # ruling that an orphan's rule is a real claim with a broken route — in the need, out of the
    # waterfall. `#steady_need` has no owner filter to lose (it sums every rule `Budget.for_user`
    # answers), so the ruling survives its example; the shape does not, and the layer that could
    # express it is deleted outright (two-ledger spec §5, Task 8).

    it "does not count another user's rules" do
      rate(300)
      stranger = create(:user, period_cadence: :biweekly, period_anchor_date: today)
      stranger_owner = create(:category, :expense, :funded, user: stranger, name: "Car")
      create(:budget, :per_period_rate, category: stranger_owner, amount: 999)

      expect(described_class.steady_need(user, today: today)).to eq(300)
    end

    # `sum(:amount)` over an empty relation is Integer `0`, and this figure is subtracted from
    # `typical_income` and compared against it. A user with no rules must not be on a different
    # numeric type from one with rules.
    it "answers a BigDecimal zero for a user with no rules at all" do
      expect(described_class.steady_need(user, today: today)).to eq(0)
      expect(described_class.steady_need(user, today: today)).to be_a(BigDecimal)
    end
  end

  # THE PRELOAD IS A CLAIM ABOUT COST, AND NOTHING ELSE IN THIS FILE CAN SEE IT. Every example above
  # asserts a FIGURE, and `#steady_need` answers the same figure whether it preloads the owner or
  # loads it one rule at a time — so a preload that stops covering a lane is invisible here without
  # counting statements. This block is that count.
  #
  # THE SHAPE IS THE MIGRATED ONE: both `pool_id` AND `category_id`, which is what Task 1's
  # migration wrote onto every rule in the database. It matters because `Budget#user` asks the
  # CATEGORY first — a relation preloading only `pool: :user` pays two queries per dated rule (the
  # category, then its user) on rows that look, from the pool column, fully preloaded. That was
  # live for one commit; this is what would have caught it.
  #
  # DATED rules specifically: the rate branches divide by the `user` handed in as an argument and
  # never ask the rule who owns it. Only the one-off branch builds a `ClaimCalculator`, and that is
  # the reader that walks `budget.user` — for the period grid its divisor is counted off.
  describe ".steady_need query cost" do
    def sql_for(&block)
      statements = []
      recorder = lambda do |_name, _start, _finish, _id, payload|
        statements << payload[:sql] unless ["SCHEMA", "TRANSACTION"].include?(payload[:name])
      end
      ActiveSupport::Notifications.subscribed(recorder, "sql.active_record", &block)
      statements
    end

    # A rule with a category of its OWN — sharing one category between rules would hide a per-rule
    # load behind a repeated id.
    def migrated_one_off(amount)
      create(
        :budget,
        amount: amount,
        interval_months: nil,
        anchor_date: today + 60,
        category: create(:category, :expense, :funded, user: user)
      )
    end

    it "costs the same number of queries for five migrated dated rules as for one", :aggregate_failures do
      migrated_one_off(120)
      one = sql_for { described_class.steady_need(user, today: today) }
      4.times { migrated_one_off(120) }
      five = sql_for { described_class.steady_need(user, today: today) }

      expect(five.size).to eq(one.size)
      # THREE, NAMED: the rules themselves, then the two preloads that answer for every row at once —
      # `categories` and the `users` the owner lane resolves to. Nothing else. It was FIVE for one
      # wave (fix wave — MED-3), when the one-off branch read `ClaimCalculator#planned_this_period`
      # and this method had to build a `ClaimLedger`'s two grouped row statements to keep that off a
      # per-rule footing; `#standing_ask` reads no rows at all, so the ledger is asked only for its
      # `#rules` and the lazy lanes are never touched (fix wave 2 — MED-A). Before EITHER it was
      # three plus one `SUM` PER ONE-OFF RULE through `BudgetCalculator`, which is the count
      # `one.size` would have matched while `five.size` did not. `:item` is in the `includes` and
      # costs nothing here, because every rule in this fixture is item-less and the preloader skips a
      # branch whose foreign keys are all nil.
      expect(five.size).to eq(3)
    end
  end
end
