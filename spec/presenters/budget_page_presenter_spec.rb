# frozen_string_literal: true

require "rails_helper"

RSpec.describe BudgetPagePresenter do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6), typical_income: 2_400)
  end
  let(:today) { Date.new(2026, 2, 6) }
  let(:presenter) { described_class.new(user: user, today: today) }

  # A CATEGORY THAT HOLDS MONEY (two-ledger spec §3) — `:funded` is what makes `Category#holder?`
  # true, and a rule is one of the two things that stamp it in the app. Every `envelope(...)` in the
  # pool era of this file became this: the fixture is one record shorter, because the envelope and
  # the category it was twinned with were always one thing.
  def holder(name, priority: 1)
    create(:category, :expense, :funded, user: user, name: name, priority: priority)
  end

  # A flat per-period rule: no anchor, so no date to be due on.
  def rate(category, amount)
    create(:budget, :per_period_rate, category: category, amount: amount)
  end

  def lane(category, name) = create(:item, category: category, name: name)

  # A rule that rolls: its due date moves with the cycles gone by, which is what makes it
  # answer something other than its own anchor.
  #
  # `item:` because a category may carry only ONE item-less rule
  # (`Budget#category_may_hold_one_item_less_rule`, computed-claims ruling of 2026-09-03), and the
  # due-order examples below need two rules on one category. It is passed for BOTH rules where it is
  # passed at all: a rule with an item has its cycle rolled by PAYMENTS rather than by the calendar,
  # so giving only one of a pair an item would settle the order on the item rather than on the key
  # the example is about.
  #
  # `created_at:` IS PLANTED WHEREVER A FUND IS SUPPOSED TO HAVE BEEN BUILDING (computed-claims
  # ruling of 2026-09-03): a rule accrues from the LATER of its category's `funded_since` and its own
  # birthday, so a rule created by the factory "now" — which is after this file's `today` — walks no
  # periods at all and holds nothing. Left alone where the example is about a rule that has only just
  # been written.
  def rolling(category, amount:, anchor:, every: 1, **plant)
    create(:budget, category: category, amount: amount, interval_months: every, anchor_date: anchor, **plant)
  end

  # THE THREE DUE-DATE EXAMPLES SHARE ONE FIXTURE: a $1,200 six-monthly bill anchored Sep 1 2025 whose
  # rule was written the same day, on a category that has held money since. What differs between them
  # is only what has been PAID into it, which is the whole subject.
  def car_insurance
    holder("Car Insurance").tap do |category|
      rolling(
        category,
        amount: 1_200,
        anchor: Date.new(2025, 9, 1),
        every: 6,
        created_at: Time.zone.local(2025, 9, 1)
      )
    end
  end

  def pay(category, amount)
    create(:entry, item: create(:item, category: category), amount: amount, date: today)
  end

  # `#orphan_rules`, `#orphan_reason`, `Rule#reason` AND THE `_orphans` PARTITION ARE ALL DELETED
  # (two-ledger spec §5), and with them the one example that survived here — "leaves a rule that
  # does fill an envelope out of the orphans". A rule belongs to a category and every category is in
  # the waterfall, so there is no shape left to be outside the fill order; the half of that example
  # that still says something (a rule appears under its owner) is `#category_groups`' first example.

  # A RULE NO GROUP CAN SHOW. It was a rule that named a POOL and no category at all — a shape the
  # drop deleted outright (two-ledger spec §5, Task 8) — and the surviving shape with the same
  # property is a rule on a category that holds nothing: `Category.in_fill_order` is holders, so it
  # draws no group, while `Budget.for_user` still counts it among the user's rules.
  def unshowable_rule
    create(:budget, :per_period_rate, amount: 90, category: create(:category, :expense, user: user, name: "Coffee"))
  end

  def names(rules) = rules.map { |rule| rule.budget.id }

  describe "#category_groups" do
    it "puts each rule under the category it fills", :aggregate_failures do
      groceries = holder("Groceries")
      rent = holder("Rent", priority: 2)
      groceries_rule = rate(groceries, 400)
      rent_rule = rate(rent, 1_500)

      expect(presenter.category_groups.map(&:category)).to eq([groceries, rent])
      expect(names(presenter.category_groups.first.rules)).to eq([groceries_rule.id])
      expect(names(presenter.category_groups.last.rules)).to eq([rent_rule.id])
    end

    # PRIORITY FIRST, NAME AS THE TIE-BREAK, on a fixture where all three candidate orders
    # disagree. Insertion order is Zebra, Alpha, Middle — the exact reverse of the answer — and
    # name order alone is Alpha, Middle, Zebra. `categories` carries no ORDER BY, so without the key
    # the order is whatever Postgres hands back, and a plain UPDATE relocates a row in the heap:
    # renaming a category would reshuffle the fill order with no change to what actually fills
    # first.
    it "orders categories by priority and then by name" do
      ["Zebra", "Alpha"].each { |name| rate(holder(name, priority: 2), 100) }
      rate(holder("Middle", priority: 1), 100)

      expect(presenter.category_groups.map { |group| group.category.name }).to eq(["Middle", "Alpha", "Zebra"])
    end

    # BudgetCalculator#due_order breaks a shared due date toward the LARGER obligation, because
    # the bigger bill is the one you can least afford to be short on. Insertion order says the
    # $100 rule first, so a sort that fell through to it would pass a bare "both rules render".
    it "orders rules within a category by due order, larger amount first on a tie", :aggregate_failures do
      category = holder("Pet Care")
      small = rolling(category, amount: 100, anchor: Date.new(2026, 3, 1), item: lane(category, "Small"))
      large = rolling(category, amount: 500, anchor: Date.new(2026, 3, 1), item: lane(category, "Large"))

      expect(names(presenter.category_groups.first.rules)).to eq([large.id, small.id])
      expect(small.created_at).to be < large.created_at
    end

    it "orders an earlier due date ahead of a larger amount" do
      category = holder("Pet Care")
      later = rolling(category, amount: 900, anchor: Date.new(2026, 4, 1), item: lane(category, "Later"))
      sooner = rolling(category, amount: 100, anchor: Date.new(2026, 3, 1), item: lane(category, "Sooner"))

      expect(names(presenter.category_groups.first.rules)).to eq([sooner.id, later.id])
    end

    it "leaves out a category with no rule at all, and another user's rules", :aggregate_failures do
      holder("Empty")
      rate(holder("Groceries"), 400)
      stranger = create(:user)
      rate(create(:category, :expense, :funded, user: stranger, name: "Their Rent"), 900)

      expect(presenter.category_groups.map { |group| group.category.name }).to eq(["Groceries"])
      expect(presenter.category_groups.first.rules.size).to eq(1)
    end
  end

  # ** `Group#balance` AND `Group#status` ARE DELETED (computed-claims Task 3), and the two examples
  # that asserted them are converted below rather than dropped. ** Both read a `HoldingStatus` over a
  # `CategoryLedger` — what had been ALLOCATED into the category — and nothing is allocated any more
  # (spec §5). The figure a category has is `Σ its rules' claims` (§3), which is what `free`
  # subtracted on Home and what the header prints. The `:left_to_spend` state that the first example
  # asserted is the same $150 said the other way round, and is now the row's own `$250.00 of $400.00`.
  describe "a group's own reading" do
    # PLANTED: a $400-a-period rate rule with $250 spent inside the period. §3.1 —
    # `claim = max(0, rate + Σ adjustments − spent)` = max(0, 400 + 0 − 250) = **$150.00**, and
    # `Group#claim` is Σ over the category's rules, which is that one rule.
    it "reports the sum of its rules' claims", :aggregate_failures do
      category = holder("Groceries")
      rate(category, 400)
      create(:entry, item: create(:item, category: category), amount: 250, date: today)
      group = presenter.category_groups.first

      expect(group.claim).to eq(150)
      expect(group.claim).to be_a(BigDecimal)
    end

    # A category no money has moved through must not turn a money figure into an Integer: the empty
    # `sum(:amount)` calls each answer the literal 0, and this page divides nothing but prints
    # everything. Untouched, the whole $400 rate is claimed.
    it "reports a decimal claim for an untouched category", :aggregate_failures do
      rate(holder("Groceries"), 400)

      expect(presenter.category_groups.first.claim).to eq(400)
      expect(presenter.category_groups.first.claim).to be_a(BigDecimal)
    end

    # TWO RULES, TWO DENOMINATIONS, ONE HEADER. §3.4 gives a rate rule and a dated one different
    # sentences, so the header cannot print either of them — it prints the SUM, which is exactly what
    # `free` subtracted. Planted: $400 rate, nothing spent → $400; a $1,200 bill whose accrual has not
    # started (its rule is younger than `today`, see the file header) → $0.
    it "sums across shapes, because that is what free subtracted" do
      category = holder("Pet Care")
      rate(category, 400)
      rolling(category, amount: 1_200, anchor: Date.new(2025, 9, 1), every: 6, item: lane(category, "Vet"))

      expect(presenter.category_groups.first.claim).to eq(400)
    end

    # RED WHERE A RULE UNDER IT NEEDS A HUMAN, and quiet where none does — the same two facts Home's
    # trouble strip fires on, asked of the same rows.
    it "needs attention only where one of its rules does", :aggregate_failures do
      quiet = holder("Groceries")
      rate(quiet, 400)
      loud = holder("Dining", priority: 2)
      rate(loud, 180)
      create(:entry, item: create(:item, category: loud), amount: 220, date: today)

      expect(presenter.category_groups.first).not_to be_needs_attention
      expect(presenter.category_groups.last).to be_needs_attention
    end

    it "states the category's priority position" do
      rate(holder("Groceries", priority: 4), 400)

      expect(presenter.category_groups.first.priority).to eq(4)
    end
  end

  describe "a rule's due date" do
    # ** THE CLAIM'S OWN READING, NOT `BudgetCalculator#due_date`'S (Task 3). ** This example used to
    # assert Mar 1 2026 — that class rolls an item-less rule's cycle on the CALENDAR, because it has
    # no fulfilment signal without an item and assumes every bill was paid on time. The computed model
    # has the signal (§3.2: an item-less rule's lane is the category), finds nothing spent, and leaves
    # the occurrence anchored where it was so the row can read overdue. That is the law going forward
    # (ruling of 2026-09-03), and the page now ORDERS on the same date it PRINTS.
    # PLANTED: a $1,200 six-monthly bill anchored Sep 1 2025, its rule born the same day, nothing
    # ever spent. §3.2's catch-up formula — `planned(P) = (target − built_up) ÷ periods_left`, and
    # `periods_left` floors at 1 for a date already past — fills the fund in its first walked period,
    # so `built_up` is **$1,200.00** while the occurrence stays anchored at Sep 1 2025.
    #
    # ** AND THE ROW READS OVERDUE (fix round 1 — MED-1). ** This pinned the opposite. `#overdue?`
    # carried a `built_up < target` half, on the reasoning that a whole fund is waiting to be PAID
    # rather than saved into — but the floor at 1 above means a whole fund is the ORDINARY shape of a
    # bill past its date, so the gate silenced the common case rather than a corner of it: five months
    # after the date, this row printed `next due Sep 1` with no trouble line at all. The trigger is
    # the unfulfilled occurrence; the fund state splits the strip's SENTENCE, not the verdict.
    it "is overdue on a date that has passed, with the fund whole", :aggregate_failures do
      car_insurance
      rule = presenter.category_groups.first.rules.first

      expect(rule.next_due_on).to eq(Date.new(2025, 9, 1))
      expect(rule.built_up).to eq(1_200)
      expect(rule).to be_anchored
      expect(rule).to be_overdue
    end

    # THE SAME VERDICT WITH THE FUND SHORT, which is what says the predicate stopped reading the fund.
    # Planted: the same bill, $500 paid inside this period. §3.2's walk settles the period AFTER the
    # accrual — `raw = 1,200 − 500` = **$700.00** — and $500 is less than one whole cycle, so
    # `cycles_paid_by` stays at 0 and the occurrence does NOT roll.
    it "is overdue where the date has passed and the fund is short", :aggregate_failures do
      pay(car_insurance, 500)
      rule = presenter.category_groups.first.rules.first

      expect(rule.next_due_on).to eq(Date.new(2025, 9, 1))
      expect(rule.built_up).to eq(700)
      expect(rule).to be_overdue
    end

    # THE OTHER DIRECTION: paid in full, the cycle rolls, and the row reads the NEXT occurrence rather
    # than the anchor. $1,200 of category spending settles the September occurrence, so the
    # six-monthly rule re-aims at Mar 1 2026.
    it "rolls to the next occurrence once the bill has been paid", :aggregate_failures do
      pay(car_insurance, 1_200)
      rule = presenter.category_groups.first.rules.first

      expect(rule.next_due_on).to eq(Date.new(2026, 3, 1))
      expect(rule).not_to be_overdue
    end

    # An anchorless rate rule is never due. `BudgetCalculator#due_date` answers the end of the period
    # for one, which is a real number for the maths and a lie on screen; `ClaimCalculator#next_due_on`
    # answers nil, which is the fact.
    it "is nil for an anchorless rate rule", :aggregate_failures do
      rate(holder("Groceries"), 400)
      rule = presenter.category_groups.first.rules.first

      expect(rule.next_due_on).to be_nil
      expect(rule).not_to be_anchored
    end
  end

  describe "#no_rules?" do
    it "is true for a user with no rules anywhere" do
      holder("Groceries")

      expect(presenter).to be_no_rules
    end

    it "is false for a rule in the fill order" do
      rate(holder("Groceries"), 400)

      expect(presenter).not_to be_no_rules
    end

    # THE GAP BETWEEN "has rules" AND "has groups", pinned rather than left to be discovered. A rule
    # on a category that holds nothing draws no group here — `Category.in_fill_order` is holders —
    # and telling that user they have no rules would be this screen contradicting the rules they can
    # see elsewhere. `#no_rules?` asks about every rule the user has; `budget_page/show` prints its
    # own sentence for the difference.
    it "is false for a rule no group can show", :aggregate_failures do
      unshowable_rule

      expect(presenter).not_to be_no_rules
      expect(presenter.category_groups).to be_empty
    end
  end

  # THE POPULATION IS `Category.in_fill_order.with_a_rule` — the SAME set `.apply_fill_order`
  # refuses any other list than (fix round 1, MED-1). It was `with_a_rule` alone, which is wider by
  # exactly the rules on categories that hold nothing, and every one of those rendered a group with
  # a priority badge and two reorder arrows the endpoint would refuse: the page offering a control
  # whose every use is rejected, and rejected with a message about the order the page itself had
  # just drawn.
  describe "#unfilled_rules" do
    def unfunded_rule(name, amount)
      create(
        :budget,
        :per_period_rate,
        amount: amount,
        category: create(:category, :expense, user: user, name: name)
      )
    end

    # BOTH DIRECTIONS ON ONE FIXTURE, and `funded_since` is the only variable that moves: two rules
    # of the same shape, one on a category that holds money and one on a category that does not.
    it "takes the rule on a category that holds nothing, and leaves the holder's alone", :aggregate_failures do
      filling = rate(holder("Groceries"), 400)
      waiting = unfunded_rule("Coffee", 35)

      expect(names(presenter.unfilled_rules)).to eq([waiting.id])
      expect(presenter.category_groups.map { |group| group.category.name }).to eq(["Groceries"])
      expect(names(presenter.category_groups.sole.rules)).to eq([filling.id])
    end

    # THE ALIGNMENT ITSELF, asserted as the identity it is rather than inferred from the two lists
    # above: what the page draws a card for and what the endpoint will accept are one set, so the
    # page can never render an order its own button is refused for. The savings category is in the
    # fill order and carries no rule, which is the one shape that is in neither list.
    it "leaves the groups exactly the set apply_fill_order accepts" do
      rate(holder("Groceries"), 400)
      unfunded_rule("Coffee", 35)
      create(:category, :expense, :funded, user: user, name: "Vacation")

      expect(presenter.category_groups.map { |group| group.category.id })
        .to match_array(user.categories.in_fill_order.with_a_rule.ids)
    end

    it "takes a rule no group can show too" do
      unshowable = unshowable_rule

      expect(names(presenter.unfilled_rules)).to eq([unshowable.id])
    end

    it "is empty when every rule fills a holder" do
      rate(holder("Groceries"), 400)

      expect(presenter.unfilled_rules).to be_empty
    end
  end

  # §8's three lines and §9's gate. Every figure is pinned against a planted literal rather than
  # against a sum recomputed from the same records — `rules_need == Σ steady_ask` over the fixture
  # that produced it is an identity, and it passes whichever way both sides are wrong.
  describe "the structural check" do
    describe "#rules_need" do
      it "sums what every rule claims from one period", :aggregate_failures do
        rate(holder("Groceries"), 400) # $400 a period
        create(:budget, :rate, category: holder("Utilities", priority: 2), amount: 260) # $120
        rolling(holder("Car Insurance", priority: 3), amount: 1_200, anchor: today + 3.months, every: 6)

        expect(presenter.rules_need).to eq(BigDecimal("612.31"))
        expect(presenter.rules_need).to be_a(BigDecimal)
      end

      # A user with no rules at all is on the same numeric type as one with rules — an empty
      # `sum` is Integer 0, and this figure is subtracted from and compared against income.
      it "is a BigDecimal zero when there are no rules", :aggregate_failures do
        expect(presenter.rules_need).to eq(0)
        expect(presenter.rules_need).to be_a(BigDecimal)
      end
    end

    describe "#typical_income and #leftover" do
      it "reports the declared income and what survives the rules", :aggregate_failures do
        rate(holder("Groceries"), 400)

        expect(presenter.typical_income).to eq(2_400)
        expect(presenter.typical_income).to be_a(BigDecimal)
        expect(presenter.leftover).to eq(2_000)
      end

      # NIL, NOT ZERO. Zero is a claim about the user's income; nil is the absence of one, and
      # the block renders its invitation off exactly that distinction.
      it "answers nil for both when no income is declared", :aggregate_failures do
        user.update!(typical_income: nil)
        rate(holder("Groceries"), 400)

        expect(presenter.typical_income).to be_nil
        expect(presenter.leftover).to be_nil
      end

      it "goes negative when the rules outrun the income" do
        rate(holder("Rent"), 3_000)

        expect(presenter.leftover).to eq(-600)
      end
    end

    describe "#underwater?" do
      it "is true when the rules claim more than the declared income" do
        rate(holder("Rent"), 3_000)

        expect(presenter).to be_underwater
      end

      it "is false when they fit" do
        rate(holder("Rent"), 500)

        expect(presenter).not_to be_underwater
      end

      # The boundary `>` sits on: rules that consume the income exactly are not a structural
      # problem, and a `>=` would tell a user their budget is impossible on the day it balances.
      it "is false when they land exactly on the income" do
        rate(holder("Rent"), 2_400)

        expect(presenter).not_to be_underwater
      end

      # Unanswered is not covered. Without this gate a user who has declared nothing would be
      # told their budget fits an income they never stated.
      it "is false when no income is declared" do
        user.update!(typical_income: nil)
        rate(holder("Rent"), 3_000)

        expect(presenter).not_to be_underwater
      end

      # THE SAME DIVERGENCE HomePresenter's redefinition pins, from this page's side: a $5,200
      # premium due inside this period asks for all of it now, and this page must still read the
      # standing claim of $200 a period.
      it "is false in a catch-up period whose rules still fit", :aggregate_failures do
        rolling(holder("Car Insurance"), amount: 5_200, anchor: today + 3.days, every: 12)

        expect(presenter.rules_need).to eq(200)
        expect(presenter).not_to be_underwater
      end

      # THE HALF OF THE GATE THAT WAS MISSING, asserted on the presenter rather than through the
      # page. `#underwater?` used to ask only `typical_income.present?`, and it was unreachable in
      # this state solely because the view nests it inside `if declared?` — a layout fact standing
      # in for a money gate. Asked directly, the old reader answered TRUE here.
      #
      # An income with NO CADENCE is a comparison with two units in it: `Budget#steady_ask` falls
      # back to treating the period as a calendar month, so this reads $3,000 A MONTH against
      # $2,400 "a period" the user has never defined — and decides whether the app offers to cut
      # their budget on the strength of it. `rules_need` is asserted non-zero on the same line so
      # the false cannot be mistaken for a user whose rules claim nothing.
      #
      # BOTH DIRECTIONS ON ONE FIXTURE, and the cadence is the only variable that moves: the same
      # rule and the same income answer false without it and true with it. A second example
      # planting the declared case from scratch would be the affirmative one four lines above,
      # which pins nothing about this gate.
      it "is false when an income is declared but no cadence is", :aggregate_failures do
        user.update!(period_cadence: nil, period_anchor_date: nil)
        rate(holder("Rent"), 3_000)

        expect(presenter.rules_need).to eq(3_000)
        expect(presenter).not_to be_underwater

        user.update!(period_cadence: :biweekly, period_anchor_date: today)

        expect(described_class.new(user: user.reload, today: today)).to be_underwater
      end
    end

    describe "#declared?" do
      it "is true once income and cadence are both set" do
        expect(presenter).to be_declared
      end

      it "is false without an income" do
        user.update!(typical_income: nil)

        expect(presenter).not_to be_declared
      end

      # A figure printed "a period" at a user who has not said how long a period is has no unit,
      # so the block withholds the three lines until both halves exist.
      it "is false without a cadence" do
        user.update!(period_cadence: nil, period_anchor_date: nil)

        expect(presenter).not_to be_declared
      end
    end
  end

  # ── THE CLAIM FIGURES ON A ROW (computed-claims spec §3.3; Task 2) ────────────────────────────

  describe "a rule's claim figures" do
    # A $1,200 goal fed by a $150-a-period rule BORN JAN 6, on this file's biweekly grid anchored
    # Feb 6. `created_at` is planted because a rule accrues from the later of its category's funding
    # date and its OWN birth (computed-claims ruling of 2026-09-03) — a rule created at the wall
    # clock would be born months after this file's `today` and hold nothing at all.
    #
    # BY HAND: the boundaries are Feb 6 minus multiples of 14, so the walk visits Dec 26–Jan 8,
    # Jan 9–22, Jan 23–Feb 5 and Feb 6–19 — four periods at $150 each, which is $600 built up, with
    # $150 planned for the period `today` is in and $1,200 still a long way off.
    #
    # ** A GOAL IS A DATED RULE WHOSE AMOUNT IS ITS TARGET (two-shapes spec §2 row 5). ** It was a
    # $150-a-period rule that carried its money over toward $1,200; the horizon replaces the rate.
    # THE PERIODS, on the biweekly grid anchored Feb 6: the rule is born Jan 6, which sits in
    # Dec 26 – Jan 8, and there are EIGHT boundaries from there through Apr 16 (Dec 26, Jan 9, Jan 23,
    # Feb 6, Feb 20, Mar 6, Mar 20, Apr 3). So §3.2's share is `1,200 ÷ 8` = **$150.00** every period
    # and today — the fourth — holds **$600.00**: every figure below is the one the retired shape
    # produced.
    def goal_rule
      create(
        :budget,
        amount: 1_200,
        basis: :monthly,
        interval_months: nil,
        anchor_date: Date.new(2026, 4, 16),
        created_at: today - 1.month,
        category: holder("Vacation")
      )
    end

    def row_for(name) = presenter.category_groups.find { |group| group.category.name == name }.rules.sole

    it "carries the built-up, the planned share and the shape for an accruing rule", :aggregate_failures do
      goal_rule

      expect(row_for("Vacation")).to have_attributes(
        shape: :dated,
        built_up: BigDecimal("600"),
        planned_this_period: BigDecimal("150"),
        claim: BigDecimal("600"),
        target: BigDecimal("1200")
      )
    end

    # ** THE SKIP IS OFFERED OFF THE ACCRUAL, NEVER OFF THE PLAN (fix round MED-2). ** A period
    # planning $150 with a −$150 already dated inside it accrues nothing, so there is nothing left
    # to skip — and the button rendered there would write a SECOND −$150, a raid on the fund's
    # prior savings under a flash saying the period was skipped. Both directions on one fixture:
    # the same rule is skippable before the delta and not after, so a reader that always answered
    # either way would fail one half.
    it "offers a skip while the period still accrues, and stops once it does not", :aggregate_failures do
      rule = goal_rule
      expect(row_for("Vacation")).to be_skippable

      create(:adjustment, rule: rule, amount: -150, date: today)

      after = described_class.new(user: user, today: today).category_groups.sole.rules.sole
      expect(after).not_to be_skippable
    end

    # ** THE SPAN RIDES ON THE ROW, OFF THE PAGE'S ONE LEDGER (fix round 2, NEW-5). ** The panel's
    # date field carries `min`/`max` and its hint says where the rule counts, and both must be the
    # range `AdjustmentForm` refuses a date outside of — a second derivation in the view would be
    # free to offer a bound the writer then rejects, which is a field that lies about what it takes.
    #
    # BOTH SHAPES ON ONE PRESENTER, because the two spans differ by exactly what the hint is about:
    # the fund reaches back to the open of the period it was born in (Jan 6 sits in Dec 26 – Jan 8),
    # the envelope carries nothing from last period and opens today.
    it "carries the span a delta may be dated in, per shape", :aggregate_failures do
      goal_rule
      rate(holder("Groceries", priority: 2), 400)

      expect(row_for("Vacation").countable_span).to eq(Date.new(2025, 12, 26)..today)
      expect(row_for("Groceries").countable_span).to eq(today..today)
    end

    # A RATE RULE'S BUILT-UP IS ZERO AND ITS CLAIM IS THE ENVELOPE — the pair, on one row, because
    # the row picks which of the two to print off `#rate?` and a shape read the wrong way would
    # print "$0.00 built up" over $400.
    it "carries a claim and no built-up for a rate rule", :aggregate_failures do
      rate(holder("Groceries"), 400)

      expect(row_for("Groceries")).to have_attributes(shape: :rate, claim: BigDecimal("400"), built_up: 0)
      expect(row_for("Groceries")).to be_rate
    end

    # THIS PERIOD'S ROWS AND ONLY THIS PERIOD'S. The list under a row explains the figure beside it,
    # and the figure is about this period — a delta from last month is already spent into the
    # built-up and listing it would invite the user to remove a row that is not what they are
    # looking at. Both directions on one fixture, because a filter that dropped everything would
    # pass the negative half alone.
    it "lists only the deltas dated inside the current period", :aggregate_failures do
      rule = goal_rule
      # `today` (Feb 6) opens a period that runs to Feb 19; Feb 3 is inside the one before it.
      this_period = create(:adjustment, rule: rule, amount: 90, date: today + 2.days)
      create(:adjustment, rule: rule, amount: 40, date: today - 3.days)

      expect(row_for("Vacation").adjustments).to eq([this_period])
    end

    # ** ONE LEDGER FOR THE PAGE, AND THE COST IS PINNED IN THE HOUSE IDIOM. ** Five rules on one
    # category must cost exactly what one costs: the categories, the statuses and the fill order are
    # identical between the two measurements, so any difference at all is a per-ROW query — a
    # partial that built a calculator of its own, or an `Adjustment#local_day` reaching for its
    # rule's owner without a preload. Both are invisible to every other example in this file.
    #
    # The rules are ITEM-BACKED because a category may hold only one item-less rule
    # (`Budget#category_may_hold_one_item_less_rule`), and the ledger's item lane is one statement
    # for any number of them.
    describe "what the page costs" do
      def count_statements(&)
        statements = 0
        counter = ->(*, payload) { statements += 1 unless payload[:name].to_s.match?(/SCHEMA|TRANSACTION/) }
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
        statements
      end

      # ** EVERY READER THE RENDERED PAGE ASKS FOR, IN THE ORDER `show.html.erb` ASKS IT. ** A cost
      # pin is only as honest as the reader list it walks: a reader this method never calls is a
      # reader free to open a `ClaimLedger` of its own without either figure below moving. The three
      # panels the partials read are the type overview, the give-way order's groups, the "not
      # filling" band and the structural check.
      #
      # ** THE TYPE OVERVIEW IS READ THROUGH THIS PIN (rules-own-the-budget spec §3). ** It sums
      # `ClaimCalculator#standing_ask` over every rule the user owns, off the page's ONE ledger — a
      # reader that reached for `Budget#steady_ask` instead would build a second calculator per
      # DATED bill, which is why the fixture below carries one.
      #
      # ** `#suggestions` IS DELIBERATELY ABSENT. ** It is `SuggestionEngine`'s cost, not this
      # class's — eight statements of detectors this presenter only forwards — and folding it in
      # would put the engine's query plan inside a pin about the page's own ledger. Its own spec
      # owns it.
      def read_the_page(page)
        page.no_rules?
        page.type_overview
        page.category_groups.each do |group|
          group.rules.each { |rule| [rule.claim, rule.built_up, rule.planned_this_period, rule.adjustments.size] }
        end
        page.unfilled_rules
        read_the_structural_check(page)
      end

      # THE ADJUST PANEL'S OWN FOUR (`_structural_check.html.erb`). `#rules_need` is the one that
      # matters: `Budget.steady_need` takes the page's `ledger:` and a version that built its own
      # would cost the whole set of grouped aggregates twice — invisible to every other example here.
      def read_the_structural_check(page)
        page.declared?
        page.rules_need
        page.typical_income
        page.underwater?
        page.leftover
      end

      # A FRESH PRESENTER EACH TIME. Every reader on this class is memoised, so a second read
      # through the same instance would answer out of memory and hide the statements this pins.
      def read_every_row = read_the_page(described_class.new(user: user, today: today))

      # EACH RULE CARRIES A DELTA OF ITS OWN, and that half of the fixture is what catches the
      # second per-row cost: `Adjustment#local_day` walks `rule → category → user` for the owner's
      # zone, so a listing without the preload is three lookups PER DELTA. Measured: dropping
      # `includes(rule: { category: :user })` takes the five-rule reading twelve statements past the
      # one-rule reading, and this example is the only one in the suite that sees it.
      def rule_with_a_delta(category, name, amount)
        rule = create(:budget, :per_period_rate, category: category, item: lane(category, name), amount: amount)
        create(:adjustment, rule: rule, amount: 25, date: today)
        rule
      end

      # ** A ONE-TIME DATED BILL, AND IT IS THE ONE SHAPE THE COMMENT ABOVE IS ABOUT (MED-2). **
      # `Budget#cadence` calls an anchored rule with no interval `:one_off`, and that is the only arm
      # of `#steady_ask` that BUILDS a `ClaimCalculator` — the second-door hazard both `#type_overview`
      # and `#rules_need` are written to avoid. Every rule in this fixture used to be per-period, so
      # the claim was untestable: the arm it warns about was never reached.
      #
      # `created_at:` PLANTED as the current period opens, so the rule walks exactly one period and
      # nothing here depends on the wall clock.
      def dated_bill(category, amount:, due:)
        create(
          :budget,
          category: category,
          amount: amount,
          interval_months: nil,
          anchor_date: due,
          created_at: Time.zone.local(2026, 2, 6)
        )
      end

      # THE WHOLE PAGE, AT ITS SMALLEST HONEST SIZE: a group with a rule and a delta on it, a DATED
      # bill on a second category (the `:one_off` arm, and a second group for the give-way order), and
      # a rule on a category that holds nothing — which is the only thing `#unfilled_rules` can list.
      def a_whole_page
        rule_with_a_delta(holder("Groceries"), "Bread", 100)
        dated_bill(holder("Rent", priority: 2), amount: 1_500, due: today + 3.days)
        unshowable_rule
      end

      it "costs the same for five rules on a category as for one", :aggregate_failures do
        category = holder("Groceries")
        rule_with_a_delta(category, "Bread", 100)

        one_rule = count_statements { read_every_row }

        4.times { |n| rule_with_a_delta(category, "Item #{n}", 50) }

        expect(count_statements { read_every_row }).to eq(one_rule)
        expect(one_rule).to be_positive
      end

      # ** THE SECOND COUNT IS THE ONE THAT PINS THE DESIGN (Home's own pin, MED-2). ** Every figure
      # on this page is composed from readers the presenter already holds, so once anything has been
      # read, reading all of it costs nothing. A reader added here that opened a ledger of its own
      # would fail this and not the delta pin above.
      it "reads the whole page a second time for nothing at all", :aggregate_failures do
        a_whole_page
        page = described_class.new(user: user, today: today)

        expect(count_statements { read_the_page(page) }).to be_positive
        expect(count_statements { read_the_page(page) }).to eq(0)
      end

      # ** FIFTEEN, AND EACH ONE IS NAMED — a bare number is a pin nobody can maintain (MED-2). **
      #
      #    1. `#rules` — `User#all_budgets`, every rule the user owns …
      #  2-4. … and its `includes(:item, category: :user)` preload: the one item a rule names, the
      #       three categories, the one user. One statement each, whatever the row count.
      #    5. `ClaimLedger#rules` — the SAME set again, loaded by the ledger for its own probes …
      #  6-8. … and its own copy of that preload. ** THE FOUR ARE A KNOWN DUPLICATE AND THIS PIN IS
      #       WHERE IT IS VISIBLE: ** the presenter's set is `User#all_budgets` and the ledger's is
      #       `Budget.for_user`, two spellings of one population, and closing the gap is a change to
      #       what `#rules` MEANS rather than a cost fix — so it is named here rather than silently
      #       carried.
      #    9. the ledger's ITEM spending lane (the Bread rule names an item).
      #   10. its adjustment lane — one grouped statement for every delta the claims read.
      #   11. its CATCH-ALL spending lane (the Rent bill and the Coffee rule name no item).
      #   12. `#adjustments_this_period` — ONE listing of this period's deltas for every row …
      #  13-15. … and its `includes(rule: { category: :user })` preload, which is what keeps
      #       `Adjustment#local_day` from walking `rule → category → user` per delta.
      #
      # NOTHING BELOW IS A STATEMENT AND THAT IS THE POINT: `#type_overview` and `#rules_need` read
      # `ClaimCalculator#standing_ask`, which touches two columns and the period grid; `#unfilled_rules`
      # is `rules - grouped_rules` in memory; `#category_groups` sorts the preloaded categories rather
      # than re-asking `Category.in_fill_order`.
      #
      # ** WHY THIS PIN AND THE DELTA PIN ARE BOTH HERE, AND WHAT EACH ONE ALONE CANNOT SEE (LOW-1).
      # ** The delta pin is a DIFFERENCE — five rules on a category cost exactly what one costs — so
      # it catches anything that grows with the ROW COUNT: a calculator built inside a partial, a
      # preload dropped. It is BLIND to a constant: a second `ClaimLedger` opened once per render adds
      # the same statements to both sides of the equality and cancels, and the pin stays green. This
      # one is the ABSOLUTE figure and sees exactly that. Measured on this fixture: dropping
      # `ledger:` from `#rules_need` — `Budget.steady_need` building its own ledger — takes it from
      # **15 to 19** (that ledger's rules and its three preloads; its lanes stay lazy because
      # `#standing_ask` reads no rows), and a `#type_overview` that built a ledger per rule instead of
      # reading the page's takes it to **36**. Both readings leave the delta pin passing. Neither pin
      # is redundant and neither subsumes the other.
      it "costs fifteen statements for a whole render" do
        a_whole_page

        expect(count_statements { read_every_row }).to eq(15)
      end
    end
  end

  # ── ** WHAT EACH KIND OF RULE ASKS OF A PERIOD (rules-own-the-budget spec §3) ** ────────────────
  #
  # The line above the groups: `Bills $1,400.00 · Usage $600.00 · Choice $300.00 a period`. Every
  # figure is `ClaimCalculator#standing_ask` — a constant of the rule and the grid — and not `Σ
  # claims`, which is this afternoon's answer and would report a different split tomorrow with
  # nothing edited.
  #
  # EVERY RULE BELOW IS PER-PERIOD, so `standing_ask` IS the rule's own amount and no example has to
  # divide a monthly figure by a cadence to say what a period asks. `Budget#steady_ask`'s
  # normalisation is `budget_steady_ask_spec`'s subject, not this one's.
  describe "#type_overview" do
    def typed(category, amount, type)
      create(:budget, :per_period_rate, category: category, amount: amount, rule_type: type)
    end

    # PLANTED: Rent $1,000 and Insurance $400 as bills, Groceries $600 as usage, Fun $300 as choice.
    # Bills sum to **$1,400.00**, which is the spec's own example line, and the three arrive in
    # reading order — bills, usage, choice — whatever order the rules were written in.
    it "sums the standing ask of each kind, heaviest commitment first" do
      typed(holder("Fun"), 300, :choice)
      typed(holder("Groceries"), 600, :usage)
      typed(holder("Rent"), 1_000, :bill)
      typed(holder("Insurance"), 400, :bill)

      expect(presenter.type_overview).to eq([[:bill, 1_400], [:usage, 600], [:choice, 300]])
    end

    # ** A TYPE WITH NO RULES IS ABSENT, NOT $0.00. ** A figure that is true and reports nothing, on
    # a line whose whole job is the split. Both directions live in one file: the example above has
    # all three.
    it "omits a type no rule carries" do
      typed(holder("Groceries"), 600, :usage)
      typed(holder("Fun"), 300, :choice)

      expect(presenter.type_overview).to eq([[:usage, 600], [:choice, 300]])
    end

    # THE EMPTY USER. The caller renders this only inside the `no_rules?` else-branch, so the empty
    # array is what that gate is asked about rather than a row of zeroes.
    it "is empty for a user with no rules at all" do
      expect(presenter.type_overview).to eq([])
    end

    # ** IT COUNTS A RULE NO GROUP CAN SHOW, and that is the same population `Budget.steady_need`
    # sums. ** A rule on a category with no `funded_since` is a claim on income that the fill order
    # cannot reach — `#unfilled_rules` is the band that says so — and an overview that omitted it
    # would split a total the structural check two blocks down prints whole.
    it "counts a rule whose category is not filling yet", :aggregate_failures do
      typed(holder("Groceries"), 600, :usage)
      typed(create(:category, :expense, user: user, name: "Someday"), 300, :choice)

      expect(presenter.unfilled_rules.map { |rule| rule.budget.category.name }).to eq(["Someday"])
      expect(presenter.type_overview).to eq([[:usage, 600], [:choice, 300]])
    end

    # ** THE THREE FIGURES ARE THE STRUCTURAL CHECK'S ONE FIGURE, SPLIT (fix round 1 — LOW-6). **
    # `#rules_need` is `Budget.steady_need`, which sums `Budget#steady_ask`; this sums
    # `ClaimCalculator#standing_ask`. The two CANNOT diverge by construction — `standing_ask` IS
    # `steady_ask`'s one-off arm and delegates straight back to that method for every other shape —
    # so this is NOT a pin on two derivations agreeing, which is what it used to claim.
    #
    # WHAT IT PINS is that the overview reads the STANDING figure at all. `Σ claims` is a perfectly
    # reasonable-looking thing for a screen to sum, and a reader that switched to it would print a
    # three-way split that does not add up to the total two blocks beneath it — on the same page, an
    # inch apart — with nothing else in this file saying so.
    #
    # THE BILL IS A ONE-OFF because that is the only shape where `standing_ask` does ARITHMETIC OF
    # ITS OWN: the amount over the periods from the accrual start to the due date, rather than a
    # delegation to the rate. A rolling bill would have exercised the delegation a third time and
    # proved nothing about the arm.
    def one_rule_of_every_type
      typed(holder("Groceries"), 600, :usage)
      typed(holder("Fun"), 300, :choice)
      rolling(
        holder("Insurance"),
        amount: 1_200,
        anchor: Date.new(2026, 8, 1),
        every: nil,
        created_at: Time.zone.local(2025, 9, 1)
      )
    end

    it "adds up to what the structural check says the rules need", :aggregate_failures do
      one_rule_of_every_type

      expect(presenter.type_overview.sum { |(_type, amount)| amount }).to eq(presenter.rules_need)
      expect(presenter.rules_need).to be_positive
    end
  end

  # ** EACH ROW SAYS WHICH KIND IT IS (spec §3). ** The label beside a rule and the overview above
  # the groups are two readings of one column, so the row carries `rule_type` off the record rather
  # than as a member a build step could fill in differently.
  describe "Rule#rule_type" do
    it "carries the rule's own type onto the row" do
      create(:budget, :per_period_rate, category: holder("Fun"), amount: 300, rule_type: :choice)

      expect(presenter.category_groups.sole.rules.sole.rule_type).to eq("choice")
    end
  end
end
