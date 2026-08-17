# frozen_string_literal: true

require "rails_helper"

# WHAT A RULE CLAIMS FROM A TYPICAL PERIOD (spec §8, §9) — the steady figure, deliberately not
# `BudgetCalculator#required`'s this-period ask. Every shape is asserted in both directions and by
# type, because the whole file is money arithmetic: an Integer leaking out of one branch changes
# what `Budget.steady_need` sums to and therefore whether the structural check fires.
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
  let(:account) { create(:pool, :account, user: user) }
  let(:pool) { create(:pool, :budget_pool, user: user, account: account) }

  def rate(amount) = create(:pool_budget, :per_period_rate, pool: pool, amount: amount)

  def monthly(amount) = create(:pool_budget, :rate, pool: pool, amount: amount)

  def every(months, amount:, anchor:)
    create(:pool_budget, pool: pool, amount: amount, interval_months: months, anchor_date: anchor)
  end

  def one_off(amount, anchor:, item: nil)
    create(:pool_budget, pool: pool, amount: amount, interval_months: nil, anchor_date: anchor, item: item)
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
    # Ten biweekly boundaries fall in Feb 6..Jun 12 inclusive — `periods_until_due` counts the
    # boundary today sits on, so a 126-day horizon is 10 periods, not 9. $2,000 over them is $200
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

    # The one shape whose steady figure DOES move with the calendar, and it moves because the rule
    # itself is finite — there are fewer periods left to save in.
    it "claims more per period as the due date approaches" do
      rule = one_off(2_000, anchor: today + 140.days)

      expect(rule.steady_ask(user, today: today + 70.days)).to be > rule.steady_ask(user, today: today)
    end
  end

  # A SETTLED BILL CLAIMS NOTHING. Without this gate a one-off rule bills its owner forever and the
  # structural check sits permanently underwater on money that has already left the account — the
  # same fulfilled gate `BudgetCalculator#shortfall` applies to the same shape.
  describe "an anchored one-time rule, fulfilled" do
    let(:category) { create(:category, :expense, user: user, pool: pool) }
    let(:item) { create(:item, category: category, name: "Dentist") }
    let(:rule) { one_off(500, anchor: today - 10.days, item: item) }

    before { create(:entry, item: item, amount: 500, date: today - 5.days) }

    it "claims nothing" do
      expect(rule.steady_ask(user, today: today)).to eq(0)
    end

    it "answers a BigDecimal rather than a bare zero" do
      expect(rule.steady_ask(user, today: today)).to be_a(BigDecimal)
    end

    # The other direction on the same record and the same day: a part payment leaves the rule
    # asking, so "zero" is a statement about fulfillment and not about the anchor being in the past.
    it "still claims when the bill was only part paid" do
      partial_item = create(:item, category: category, name: "Optician")
      create(:entry, item: partial_item, amount: 100, date: today - 5.days)

      expect(one_off(500, anchor: today - 10.days, item: partial_item).steady_ask(user, today: today))
        .to be_positive
    end
  end

  # THE CATEGORY-MODE CAP GROUP IS DELETED (plan 3, task 3). It pinned that `#steady_ask`
  # normalised a $260 monthly cap into $120 a fortnight, and its long comment argued the method
  # should answer for a shape no reader passed it — which is exactly the argument the cap's
  # deletion settles. `#steady_ask` is still a per-rule normaliser and the monthly branch it
  # reached is still pinned, by the anchorless monthly rate rule above.

  # THE UNDECLARED USER. The structural-check block renders nothing without a cadence, so this path
  # feeds no verdict yet — but the drift detector calls `steady_ask` for every pool-mode rate rule
  # regardless of whether a period has been declared, and a divisor of zero here would 500 the very
  # page that exists to fix the missing declaration. The shapes below are asserted because the
  # method must ANSWER for all of them, not because a screen prints them.
  describe "a user who has declared no period" do
    let(:undeclared) { create(:user) }
    let(:their_account) { create(:pool, :account, user: undeclared) }
    let(:their_pool) { create(:pool, :budget_pool, user: undeclared, account: their_account) }

    it "passes a per-period amount through" do
      rule = create(:pool_budget, :per_period_rate, pool: their_pool, amount: 300)

      expect(rule.steady_ask(undeclared, today: today)).to eq(300)
    end

    # The documented answer: with no period declared the period IS the calendar month, matching
    # what `BudgetCalculator#period_end` and `User#period_containing` already fall back to.
    it "leaves a monthly amount monthly" do
      rule = create(:pool_budget, :rate, pool: their_pool, amount: 260)

      expect(rule.steady_ask(undeclared, today: today)).to eq(260)
    end

    it "still answers for a dated rule rather than dividing by zero" do
      rule = create(
        :pool_budget,
        pool: their_pool,
        amount: 1_200,
        interval_months: 6,
        anchor_date: today + 3.months
      )

      expect(rule.steady_ask(undeclared, today: today)).to eq(200)
    end

    it "gives a one-off rule the whole amount, there being no periods to spread over" do
      rule = create(
        :pool_budget,
        pool: their_pool,
        amount: 500,
        interval_months: nil,
        anchor_date: today + 140.days
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

    # An account-less pool's rule is still money the user has committed. It is unreachable by any
    # distribution — which is exactly why leaving it out of the need would understate the budgets
    # that are hardest to fix, and it is the line 2b already drew when orphans left the waterfall
    # but stayed in HomePresenter#total_required. The contrast with the cap above is the whole
    # ruling that survives the cap's deletion: an orphan is a real claim with a broken route.
    it "counts a rule on a pool no account can reach" do
      rate(300)
      orphan = create(:pool, :savings_pool, user: user, account: nil)
      create(:pool_budget, :per_period_rate, pool: orphan, amount: 150)

      expect(described_class.steady_need(user, today: today)).to eq(450)
    end

    it "does not count another user's rules" do
      rate(300)
      stranger = create(:user, period_cadence: :biweekly, period_anchor_date: today)
      stranger_account = create(:pool, :account, user: stranger)
      stranger_pool = create(:pool, :budget_pool, user: stranger, account: stranger_account)
      create(:pool_budget, :per_period_rate, pool: stranger_pool, amount: 999)

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
end
