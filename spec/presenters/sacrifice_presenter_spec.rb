# frozen_string_literal: true

require "rails_helper"

# THE SACRIFICE VIEW'S ARITHMETIC (spec §9). Every figure here is a PER-PERIOD claim, and the
# fixtures are chosen so a monthly rule's own amount and its per-period claim are never the same
# number — a suite whose rules are all per-period would pass with the unit slip in place.
RSpec.describe SacrificePresenter do
  # Biweekly, so `periods_per_year` is 26 and a monthly rule's claim is `amount * 12 / 26` — a
  # figure that is nothing like the amount. A monthly user would make the two equal and hide the
  # whole class of defect this file exists for.
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6), typical_income: 2_400)
  end
  let(:today) { Date.new(2026, 2, 6) }
  let(:presenter) { described_class.new(user: user, today: today) }

  # A CATEGORY THAT HOLDS MONEY (two-ledger spec §3) — what `envelope(...)` built in the pool era,
  # one record shorter. `:funded` is what makes `Category#holder?` true.
  def holder(name, priority: 1)
    create(:category, :expense, :funded, user: user, name: name, priority: priority)
  end

  # Anchorless: a rate, and therefore cuttable.
  def rate(category, amount) = create(:budget, :per_period_rate, category: category, amount: amount)

  # Anchored and recurring: a bill, and therefore fixed.
  def rolling(category, amount:, anchor: Date.new(2026, 3, 1), every: 1)
    create(:budget, category: category, amount: amount, interval_months: every, anchor_date: anchor)
  end

  # Anchored with no interval: a one-off, marked `dated` rather than `fixed`.
  def one_off(category, amount:, anchor:)
    create(:budget, category: category, amount: amount, interval_months: nil, anchor_date: anchor)
  end

  # `#cap` is deleted with the shape it built (plan 3, task 3): a rule owned by a category. The
  # three examples that used it — the gap counting no cap, the cut list excluding one, and
  # `#rows_total` adding up with one on the fixture — are deleted with it. Nothing is left out of
  # this page's arithmetic now, which is a stronger statement than the one they made.

  def ids(rows) = rows.map { |row| row.budget.id }

  describe "#gap" do
    # THE SAME TWO READERS THE BUDGET PAGE PRINTS, and the fixture pins the figure rather than the
    # subtraction: $1,500 a month at 26 periods is $692.31, so a gap computed off `budget.amount`
    # would read $500 short and a gap computed off a monthly divisor would read something else
    # again. Only the per-period normaliser lands on this number.
    it "is what the rules claim from a period less the declared income" do
      rate(holder("Groceries"), 2_000)
      rolling(holder("Rent", priority: 2), amount: 1_500)

      expect(presenter.gap).to eq(BigDecimal("292.31"))
    end

    it "agrees with the Budget page's own structural check on the same fixture" do
      rate(holder("Groceries"), 2_000)
      rolling(holder("Rent", priority: 2), amount: 1_500)

      budget_page = BudgetPagePresenter.new(user: user, today: today)

      expect(presenter.gap).to eq(budget_page.rules_need - budget_page.typical_income)
    end

    # Negative is a budget that fits. The controller refuses the route there, and #underwater? is
    # what it asks — but the arithmetic itself stays total rather than clamping, so a reader who
    # asks the gap directly on a covered user is not handed a zero that reads as "exactly level".
    it "goes negative when the rules fit" do
      rate(holder("Groceries"), 400)

      expect(presenter.gap).to eq(BigDecimal("-2000.00"))
    end
  end

  describe "#declared? and #underwater?" do
    before { rate(holder("Groceries"), 3_000) }

    it "is underwater when both halves are declared and the rules exceed the income", :aggregate_failures do
      expect(presenter.declared?).to be(true)
      expect(presenter.underwater?).to be(true)
    end

    # INCOME WITHOUT A CADENCE IS A REACHABLE STATE — the declaration form offers "Not set" for the
    # period and keeps the income — and in it `Budget.steady_need` falls back to treating a period
    # as a calendar month. That fallback is right for a per-rule normaliser and useless as a
    # verdict: "$600.00 underwater every period" at a user who has not said how long a period is
    # states a figure with no unit, and this whole screen is that figure.
    it "is not underwater when the period is undeclared, however large the rules", :aggregate_failures do
      user.update!(period_cadence: nil, period_anchor_date: nil)

      expect(presenter.declared?).to be(false)
      expect(presenter.underwater?).to be(false)
    end

    it "is not underwater when no income has been declared", :aggregate_failures do
      user.update!(typical_income: nil)

      expect(presenter.declared?).to be(false)
      expect(presenter.underwater?).to be(false)
      # The gap is still a number, and it is the whole requirement — which is exactly why the
      # predicate gates on #declared? first rather than on the sign.
      expect(presenter.gap).to eq(BigDecimal("3000.00"))
    end

    it "is not underwater when the rules fit exactly" do
      user.update!(typical_income: 3_000)

      expect(presenter.underwater?).to be(false)
    end
  end

  describe "#cuttable_rows" do
    # THE CUT LIST IS THE ANCHORLESS RULES. All the kinds this app can hold are on the fixture at
    # once so the boundary is drawn rather than merely reported: two rates in, a recurring bill and
    # a one-off out. (A category cap used to be a third arm — off the page entirely — and is
    # deleted with the shape.)
    it "holds the anchorless rules and nothing else", :aggregate_failures do
      groceries = rate(holder("Groceries"), 400)
      dining = rate(holder("Dining Out", priority: 2), 150)
      rent = rolling(holder("Rent", priority: 3), amount: 1_500)
      dentist = one_off(holder("Dentist", priority: 4), amount: 300, anchor: Date.new(2026, 3, 4))

      expect(ids(presenter.cuttable_rows)).to contain_exactly(groceries.id, dining.id)
      expect(ids(presenter.fixed_rows)).to contain_exactly(rent.id, dentist.id)
    end

    # ** A GOAL MOVED FROM THE CUT LIST TO THE FIXED ONE, AND IT IS A CONSEQUENCE OF §2 RATHER THAN A
    # CHOICE THIS PAGE MADE (two-shapes spec §2). ** The example used to read "includes a building
    # rule saving toward a target": a goal was a `carries over` rule with a figure and NO anchor, and
    # `#reason_for` marks a rule uncuttable by its anchor alone — so it landed among the cuttable rows.
    # A goal is a dated one-off now, so the same declaration answers `:dated` and the page offers it
    # as fixed instead.
    #
    # ASSERTED RATHER THAN DELETED, because it is a real change in what the sacrifice view offers and
    # a later reader has to be able to find where it came from. `#reason_for` itself is untouched: its
    # sentence — a date is what a rule is FOR, so it cannot be trimmed — is unchanged, and it is the
    # population under it that moved.
    it "marks a goal fixed, because a goal is a dated rule", :aggregate_failures do
      goal = create(:category, :expense, :funded, user: user, name: "Retirement Supplement")
      goal_rule = create(:budget, :by_date, category: goal, amount: 5_000)

      expect(ids(presenter.cuttable_rows)).not_to include(goal_rule.id)
      expect(presenter.fixed_rows.to_h { |row| [row.budget.id, row.reason] }.fetch(goal_rule.id)).to eq(:dated)
    end

    # PER-PERIOD CLAIMS, NOT AMOUNTS — the one assertion that catches the mixed-unit slip head on.
    # $1,500 a month is $692.31 of a biweekly period; a row carrying $1,500 would offer the user
    # five sixths of a period they do not have.
    it "carries each rule's per-period claim rather than its own amount", :aggregate_failures do
      rate(holder("Groceries"), 400)
      monthly = create(:budget, :rate, category: holder("Streaming", priority: 2), amount: 1_500)

      claims = presenter.cuttable_rows.to_h { |row| [row.budget.id, row.claim] }

      expect(claims.fetch(monthly.id)).to eq(BigDecimal("692.31"))
      expect(claims.fetch(monthly.id)).not_to eq(monthly.amount)
    end

    # Biggest claim first, and the fixture makes every other plausible order wrong: insertion
    # order is Small, Big, Middle, and name order is Big, Middle, Small.
    it "orders by per-period claim, largest first" do
      rate(holder("Small"), 50)
      rate(holder("Big", priority: 2), 900)
      rate(holder("Middle", priority: 3), 300)

      expect(presenter.cuttable_rows.map { |row| row.budget.category.name }).to eq(["Big", "Middle", "Small"])
    end
  end

  describe "#fixed_rows" do
    # TWO MARKINGS FOR TWO REASONS (spec §9's "can't cut — dated" against "fixed"). A one-off falls
    # on a day; everything else anchored is a recurring bill somebody else sets.
    it "tells a dated one-off from a recurring bill", :aggregate_failures do
      rent = rolling(holder("Rent"), amount: 1_500)
      dentist = one_off(holder("Dentist", priority: 2), amount: 300, anchor: Date.new(2026, 3, 4))

      reasons = presenter.fixed_rows.to_h { |row| [row.budget.id, row.reason] }

      expect(reasons.fetch(rent.id)).to eq(:fixed)
      expect(reasons.fetch(dentist.id)).to eq(:dated)
    end

    it "marks every cuttable row with no reason at all" do
      rate(holder("Groceries"), 400)

      expect(presenter.cuttable_rows.map(&:reason)).to eq([nil])
    end
  end

  # THE PAGE MUST ADD UP. Its headline is `rules_need` and its list is these two groups; a reader
  # who sums the column and lands somewhere else has been shown a list that is missing a rule.
  # Every kind of rule at once, including one whose claim is zero.
  describe "#rows_total" do
    it "is exactly the rules_need the headline prints" do
      rate(holder("Groceries"), 400)
      rolling(holder("Rent", priority: 2), amount: 1_500)
      rolling(holder("Car Insurance", priority: 3), amount: 1_200, anchor: Date.new(2026, 5, 1), every: 6)
      one_off(holder("Dentist", priority: 4), amount: 300, anchor: Date.new(2026, 3, 4))

      expect(presenter.rows_total).to eq(presenter.rules_need)
    end
  end

  describe "#unwinnable?" do
    # WINNABLE: the cuts on the table are larger than the gap. $2,000 of rate rules against a
    # $292.31 gap — the dial can close it, so the page must not say it cannot.
    it "is false when the cuttable rules exceed the gap", :aggregate_failures do
      rate(holder("Groceries"), 2_000)
      rolling(holder("Rent", priority: 2), amount: 1_500)

      expect(presenter.gap).to eq(BigDecimal("292.31"))
      expect(presenter.cuttable_total).to eq(BigDecimal("2000.00"))
      expect(presenter.unwinnable?).to be(false)
    end

    # UNWINNABLE: the rent alone outruns the income and there is $200 of rate to cut against a
    # $1,061.54 gap. Cutting every dollar available still leaves $861.54, and that is the number
    # the page has to print — "the app says so instead of offering false comfort".
    it "is true when every cuttable dollar still leaves a gap", :aggregate_failures do
      rate(holder("Groceries"), 200)
      rolling(holder("Rent", priority: 2), amount: 7_500)

      expect(presenter.gap).to eq(BigDecimal("1261.54"))
      expect(presenter.cuttable_total).to eq(BigDecimal("200.00"))
      expect(presenter.unwinnable?).to be(true)
      expect(presenter.unclosable).to eq(BigDecimal("1061.54"))
    end

    # THE EDGE, AND IT FALLS ON THE WINNABLE SIDE: cutting everything to zero closes the gap
    # exactly, so there IS an arrangement that works and the page must not claim otherwise. `<`
    # rather than `<=` is the whole of this example.
    it "is false when the cuts close the gap exactly", :aggregate_failures do
      rate(holder("Groceries"), 1_000)
      rolling(holder("Rent", priority: 2), amount: 5_200)

      expect(presenter.gap).to eq(BigDecimal("1000.00"))
      expect(presenter.cuttable_total).to eq(presenter.gap)
      expect(presenter.unwinnable?).to be(false)
    end

    # EVERY RULE ANCHORED: there is nothing to dial at all, which is the worst version of the
    # unwinnable case and the one whose list renders empty.
    it "is true when there is nothing anchorless to cut", :aggregate_failures do
      rolling(holder("Rent"), amount: 7_500)

      expect(presenter.cuttable_rows).to be_empty
      expect(presenter.cuttable_total).to eq(0)
      expect(presenter.unwinnable?).to be(true)
    end
  end

  # PLAIN, UNDELIMITED DIGITS FOR THE DIAL — the attribute `parseFloat` reads.
  #
  # THE FOUR-FIGURE CLAIM IS THE POINT OF THE SECOND EXAMPLE, and it is the live hazard rather
  # than a decoration: `number_to_rounded` delimits by default, so this claim would reach the DOM
  # as "1,500.00" and `parseFloat("1,500.00")` is 1.5. The row would offer to free a dollar fifty
  # out of fifteen hundred, and every figure on the page would still look right.
  describe "Row#claim_param" do
    it "prints a fractional claim to the cent" do
      monthly = create(:budget, :rate, category: holder("Streaming"), amount: 1_500)

      row = presenter.cuttable_rows.find { |candidate| candidate.budget.id == monthly.id }

      expect(row.claim_param).to eq("692.31")
    end

    it "prints a four-figure claim with no thousands separator", :aggregate_failures do
      rule = rate(holder("Rent"), 1_500)

      row = presenter.cuttable_rows.find { |candidate| candidate.budget.id == rule.id }

      expect(row.claim_param).to eq("1500.00")
      expect(row.claim_param).not_to include(",")
    end
  end

  # ** WHAT THE CUT LIST COSTS, AND THE PRESENTER SAYS SO IN AS MANY WORDS (fix wave — INFO). **
  # `#rules` states "this class does not batch, and the cost is stated rather than hidden — an
  # unbatched one-off rule costs two statements", and nothing asserted it. A stated cost nobody pins
  # is a comment, not a property: the figure can drift in either direction with the sentence intact.
  describe "what the cut list costs" do
    def count_statements(&block)
      statements = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        statements += 1 unless payload[:name].to_s.match?(/SCHEMA|TRANSACTION/)
      end
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      statements
    end

    # EVERY READER `sacrifices/show.html.erb` ASKS FOR, in the order it asks.
    def read_the_page(page)
      page.rules_need
      page.typical_income
      page.gap
      page.gap_param
      page.underwater?
      page.unwinnable?
      page.cuttable_rows
      page.fixed_rows
      page.unclosable
    end

    def read_the_page_fresh = read_the_page(described_class.new(user: user, today: today))

    # ** SIX STATEMENTS, WHATEVER THE ROW COUNT — AND THE ONE-OFF COSTS NOTHING (fix wave — INFO). **
    #
    #   1. `Budget.steady_need`'s own `ClaimLedger#rules` — every rule the user owns …
    # 2-3. … and its `includes(:item, category: :user)` preload: the categories and the one user.
    #      (`:item` runs no statement here — no rule in this fixture names one. A fixture with an
    #      item-backed rule would read SEVEN, which is the preload and not a per-row cost.)
    #   4. `SacrificePresenter#rules` — the SAME set again, the deliberate second pass its own
    #      comment argues for: the rows and the figure they must add up to come from one population
    #      and the alternative is this page summing the rules itself …
    # 5-6. … and its own copy of that preload.
    #
    # ** THE STATED COST WAS WRONG IN THE SAFE DIRECTION, AND THE PIN IS WHY IT IS NOW RIGHT. ** The
    # `#rules` comment said "an unbatched one-off rule costs two statements", which was true while
    # `#steady_ask`'s one-off arm read `#planned_this_period` — a spending query and an adjustment
    # query per rule. Fix wave 2 (MED-A) moved that arm onto `ClaimCalculator#standing_ask`, which
    # reads two columns and the period grid and nothing else, so the calculator it builds is an
    # object and not a query. Measured here: ONE one-off costs six, FIVE cost six.
    #
    # STRICT EQUALITY AND THE FIGURE NAMED, not "no more than": a bound pins nothing, and the whole
    # subject is a per-rule cost that a bound would hide.
    it "costs six statements for five one-off rules, exactly what it costs for one", :aggregate_failures do
      one_off(holder("Roof", priority: 1), amount: 3_000, anchor: Date.new(2026, 6, 1))

      one = count_statements { read_the_page_fresh }

      4.times { |n| one_off(holder("Thing #{n}", priority: n + 2), amount: 300, anchor: Date.new(2026, 6, 1)) }

      expect(count_statements { read_the_page_fresh }).to eq(one)
      expect(one).to eq(6)
      expect(presenter.cuttable_rows).to be_empty
    end
  end
end
