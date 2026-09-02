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
    create(:budget, :per_period_rate, pool: nil, category: category, amount: amount)
  end

  # A rule that rolls: its due date moves with the cycles gone by, which is what makes it
  # answer something other than its own anchor.
  def rolling(category, amount:, anchor:, every: 1)
    create(:budget, pool: nil, category: category, amount: amount, interval_months: every, anchor_date: anchor)
  end

  # `#orphan_rules`, `#orphan_reason`, `Rule#reason` AND THE `_orphans` PARTITION ARE ALL DELETED
  # (two-ledger spec §5), and with them the one example that survived here — "leaves a rule that
  # does fill an envelope out of the orphans". A rule belongs to a category and every category is in
  # the waterfall, so there is no shape left to be outside the fill order; the half of that example
  # that still says something (a rule appears under its owner) is `#category_groups`' first example.

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
      small = rolling(category, amount: 100, anchor: Date.new(2026, 3, 1))
      large = rolling(category, amount: 500, anchor: Date.new(2026, 3, 1))

      expect(names(presenter.category_groups.first.rules)).to eq([large.id, small.id])
      expect(small.created_at).to be < large.created_at
    end

    it "orders an earlier due date ahead of a larger amount" do
      category = holder("Pet Care")
      later = rolling(category, amount: 900, anchor: Date.new(2026, 4, 1))
      sooner = rolling(category, amount: 100, anchor: Date.new(2026, 3, 1))

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

  describe "a group's own reading" do
    it "reports the category's holdings and its status against the ledger", :aggregate_failures do
      category = holder("Groceries")
      rate(category, 400)
      create(:allocation, to_category: category, amount: 250, date: today)
      group = presenter.category_groups.first

      expect(group.balance).to eq(250)
      expect(group.balance).to be_a(BigDecimal)
      expect(group.status.state).to eq(:left_to_spend)
    end

    # A category with no money in any term must not turn a money figure into an Integer: the empty
    # `sum(:amount)` calls each answer the literal 0, and this page divides nothing but prints
    # everything.
    it "reports a decimal zero for an untouched category", :aggregate_failures do
      rate(holder("Groceries"), 400)

      expect(presenter.category_groups.first.balance).to eq(0)
      expect(presenter.category_groups.first.balance).to be_a(BigDecimal)
    end

    it "states the category's priority position" do
      rate(holder("Groceries", priority: 4), 400)

      expect(presenter.category_groups.first.priority).to eq(4)
    end
  end

  describe "a rule's due date" do
    # THE NEXT OCCURRENCE, NOT THE ANCHOR. A recurring bill's anchor is its FIRST occurrence —
    # printing the column would show a date in the past as the next thing to pay.
    it "is the calculator's next occurrence for a recurring rule", :aggregate_failures do
      category = holder("Car Insurance")
      budget = rolling(category, amount: 1_200, anchor: Date.new(2025, 9, 1), every: 6)
      rule = presenter.category_groups.first.rules.first

      expect(rule.due_on).to eq(Date.new(2026, 3, 1))
      expect(rule.due_on).not_to eq(budget.anchor_date)
      expect(rule).to be_anchored
    end

    # An anchorless rate rule is never due. BudgetCalculator#due_date answers the end of the
    # period for one, which is a real number for the maths and a lie on screen.
    it "is nil for an anchorless rate rule", :aggregate_failures do
      rate(holder("Groceries"), 400)
      rule = presenter.category_groups.first.rules.first

      expect(rule.due_on).to be_nil
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

    # THE TRANSITIONAL GAP, PINNED RATHER THAN LEFT TO BE DISCOVERED (Task 8 closes it).
    # `Budget.for_user` still spans both owner lanes, so a rule written before the cutover names
    # only a pool and no group on this page can show it — and telling that user they have no rules
    # would be this screen contradicting the rules they can see elsewhere. `#no_rules?` asks about
    # every rule the user has; `budget_page/show` prints its own sentence for the difference.
    it "is false for a rule that names only a pool, which no group can show", :aggregate_failures do
      account = create(:pool, :account, user: user, name: "Checking")
      create(
        :pool_budget,
        :per_period_rate,
        amount: 90,
        pool: create(:pool, :budget_pool, user: user, account: account, name: "Legacy")
      )

      expect(presenter).not_to be_no_rules
      expect(presenter.category_groups).to be_empty
    end
  end

  # §8's three lines and §9's gate. Every figure is pinned against a planted literal rather than
  # against a sum recomputed from the same records — `rules_need == Σ steady_ask` over the fixture
  # that produced it is an identity, and it passes whichever way both sides are wrong.
  describe "the structural check" do
    describe "#rules_need" do
      it "sums what every rule claims from one period", :aggregate_failures do
        rate(holder("Groceries"), 400) # $400 a period
        create(:budget, :rate, pool: nil, category: holder("Utilities", priority: 2), amount: 260) # $120
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
end
