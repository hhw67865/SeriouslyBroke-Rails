# frozen_string_literal: true

require "rails_helper"

# THE SACRIFICE VIEW'S ARITHMETIC (spec §9). Every figure here is a PER-PERIOD claim, and the
# fixtures are chosen so a monthly rule's own amount and its per-period claim are never the same
# number — a suite whose rules are all per-paycheck would pass with the unit slip in place.
RSpec.describe SacrificePresenter do
  # Biweekly, so `periods_per_year` is 26 and a monthly rule's claim is `amount * 12 / 26` — a
  # figure that is nothing like the amount. A monthly user would make the two equal and hide the
  # whole class of defect this file exists for.
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6), typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:today) { Date.new(2026, 2, 6) }
  let(:presenter) { described_class.new(user: user, today: today) }

  def envelope(name, priority: 1, account: checking)
    create(:pool, :budget_pool, user: user, account: account, name: name, priority: priority)
  end

  # Anchorless: a rate, and therefore cuttable.
  def rate(pool, amount) = create(:pool_budget, :per_paycheck_rate, pool: pool, amount: amount)

  # Anchored and recurring: a bill, and therefore fixed.
  def rolling(pool, amount:, anchor: Date.new(2026, 3, 1), every: 1)
    create(:pool_budget, pool: pool, amount: amount, interval_months: every, anchor_date: anchor)
  end

  # Anchored with no interval: a one-off, marked `dated` rather than `fixed`.
  def one_off(pool, amount:, anchor:)
    create(:pool_budget, pool: pool, amount: amount, interval_months: nil, anchor_date: anchor)
  end

  def cap(name, amount)
    create(:budget, category: create(:category, :expense, user: user, name: name), amount: amount)
  end

  def ids(rows) = rows.map { |row| row.budget.id }

  describe "#gap" do
    # THE SAME TWO READERS THE BUDGET PAGE PRINTS, and the fixture pins the figure rather than the
    # subtraction: $1,500 a month at 26 periods is $692.31, so a gap computed off `budget.amount`
    # would read $500 short and a gap computed off a monthly divisor would read something else
    # again. Only the per-period normaliser lands on this number.
    it "is what the rules claim from a period less the declared income" do
      rate(envelope("Groceries"), 2_000)
      rolling(envelope("Rent", priority: 2), amount: 1_500)

      expect(presenter.gap).to eq(BigDecimal("292.31"))
    end

    it "agrees with the Budget page's own structural check on the same fixture" do
      rate(envelope("Groceries"), 2_000)
      rolling(envelope("Rent", priority: 2), amount: 1_500)

      budget_page = BudgetPagePresenter.new(user: user, today: today)

      expect(presenter.gap).to eq(budget_page.rules_need - budget_page.typical_income)
    end

    # A CAP IS NOT A CLAIM ON INCOME (Task 4's ruling). Nothing fills one, so cutting one frees
    # nothing and counting one would inflate the gap by money that will never be asked for. Pinned
    # as a figure that does NOT move rather than as a row that is absent, because the row's absence
    # is asserted separately and this is the arithmetic consequence.
    it "counts no category cap" do
      rate(envelope("Groceries"), 2_500)
      cap("Food & Dining", 600)

      expect(presenter.gap).to eq(BigDecimal("100.00"))
    end

    # Negative is a budget that fits. The controller refuses the route there, and #underwater? is
    # what it asks — but the arithmetic itself stays total rather than clamping, so a reader who
    # asks the gap directly on a covered user is not handed a zero that reads as "exactly level".
    it "goes negative when the rules fit" do
      rate(envelope("Groceries"), 400)

      expect(presenter.gap).to eq(BigDecimal("-2000.00"))
    end
  end

  describe "#declared? and #underwater?" do
    before { rate(envelope("Groceries"), 3_000) }

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
    # THE CUT LIST IS ANCHORLESS POOL-MODE RULES. All four kinds are on the fixture at once so the
    # boundary is drawn rather than merely reported: two rates in, a recurring bill and a one-off
    # out, and a category cap out of the page entirely.
    it "holds the anchorless pool rules and nothing else", :aggregate_failures do
      groceries = rate(envelope("Groceries"), 400)
      dining = rate(envelope("Dining Out", priority: 2), 150)
      rent = rolling(envelope("Rent", priority: 3), amount: 1_500)
      dentist = one_off(envelope("Dentist", priority: 4), amount: 300, anchor: Date.new(2026, 3, 4))
      food_cap = cap("Food & Dining", 600)

      expect(ids(presenter.cuttable_rows)).to contain_exactly(groceries.id, dining.id)
      expect(ids(presenter.fixed_rows)).to contain_exactly(rent.id, dentist.id)
      expect(ids(presenter.cuttable_rows + presenter.fixed_rows)).not_to include(food_cap.id)
    end

    # A RULE ON AN ACCOUNT-LESS POOL IS A REAL CLAIM the user declared — it is inside
    # `Budget.steady_need` — so leaving it out of the cut list would put money in the gap that
    # nothing on this page could reach.
    it "includes a rule on a pool with no account" do
      orphan = create(:pool, user: user, name: "Retirement Supplement", target_amount: 5_000)
      orphan_rule = create(:pool_budget, :per_paycheck_rate, pool: orphan, amount: 150)

      expect(ids(presenter.cuttable_rows)).to include(orphan_rule.id)
    end

    # PER-PERIOD CLAIMS, NOT AMOUNTS — the one assertion that catches the mixed-unit slip head on.
    # $1,500 a month is $692.31 of a biweekly period; a row carrying $1,500 would offer the user
    # five sixths of a paycheck they do not have.
    it "carries each rule's per-period claim rather than its own amount", :aggregate_failures do
      rate(envelope("Groceries"), 400)
      monthly = create(:pool_budget, :rate, pool: envelope("Streaming", priority: 2), amount: 1_500)

      claims = presenter.cuttable_rows.to_h { |row| [row.budget.id, row.claim] }

      expect(claims.fetch(monthly.id)).to eq(BigDecimal("692.31"))
      expect(claims.fetch(monthly.id)).not_to eq(monthly.amount)
    end

    # Biggest claim first, and the fixture makes every other plausible order wrong: insertion
    # order is Small, Big, Middle, and name order is Big, Middle, Small.
    it "orders by per-period claim, largest first" do
      rate(envelope("Small"), 50)
      rate(envelope("Big", priority: 2), 900)
      rate(envelope("Middle", priority: 3), 300)

      expect(presenter.cuttable_rows.map { |row| row.budget.pool.name }).to eq(["Big", "Middle", "Small"])
    end
  end

  describe "#fixed_rows" do
    # TWO MARKINGS FOR TWO REASONS (spec §9's "can't cut — dated" against "fixed"). A one-off falls
    # on a day; everything else anchored is a recurring bill somebody else sets.
    it "tells a dated one-off from a recurring bill", :aggregate_failures do
      rent = rolling(envelope("Rent"), amount: 1_500)
      dentist = one_off(envelope("Dentist", priority: 2), amount: 300, anchor: Date.new(2026, 3, 4))

      reasons = presenter.fixed_rows.to_h { |row| [row.budget.id, row.reason] }

      expect(reasons.fetch(rent.id)).to eq(:fixed)
      expect(reasons.fetch(dentist.id)).to eq(:dated)
    end

    it "marks every cuttable row with no reason at all" do
      rate(envelope("Groceries"), 400)

      expect(presenter.cuttable_rows.map(&:reason)).to eq([nil])
    end
  end

  # THE PAGE MUST ADD UP. Its headline is `rules_need` and its list is these two groups; a reader
  # who sums the column and lands somewhere else has been shown a list that is missing a rule.
  # Every kind of rule at once, including one whose claim is zero.
  describe "#rows_total" do
    it "is exactly the rules_need the headline prints" do
      rate(envelope("Groceries"), 400)
      rolling(envelope("Rent", priority: 2), amount: 1_500)
      rolling(envelope("Car Insurance", priority: 3), amount: 1_200, anchor: Date.new(2026, 5, 1), every: 6)
      one_off(envelope("Dentist", priority: 4), amount: 300, anchor: Date.new(2026, 3, 4))
      cap("Food & Dining", 600)

      expect(presenter.rows_total).to eq(presenter.rules_need)
    end
  end

  describe "#unwinnable?" do
    # WINNABLE: the cuts on the table are larger than the gap. $2,000 of rate rules against a
    # $292.31 gap — the dial can close it, so the page must not say it cannot.
    it "is false when the cuttable rules exceed the gap", :aggregate_failures do
      rate(envelope("Groceries"), 2_000)
      rolling(envelope("Rent", priority: 2), amount: 1_500)

      expect(presenter.gap).to eq(BigDecimal("292.31"))
      expect(presenter.cuttable_total).to eq(BigDecimal("2000.00"))
      expect(presenter.unwinnable?).to be(false)
    end

    # UNWINNABLE: the rent alone outruns the income and there is $200 of rate to cut against a
    # $1,061.54 gap. Cutting every dollar available still leaves $861.54, and that is the number
    # the page has to print — "the app says so instead of offering false comfort".
    it "is true when every cuttable dollar still leaves a gap", :aggregate_failures do
      rate(envelope("Groceries"), 200)
      rolling(envelope("Rent", priority: 2), amount: 7_500)

      expect(presenter.gap).to eq(BigDecimal("1261.54"))
      expect(presenter.cuttable_total).to eq(BigDecimal("200.00"))
      expect(presenter.unwinnable?).to be(true)
      expect(presenter.unclosable).to eq(BigDecimal("1061.54"))
    end

    # THE EDGE, AND IT FALLS ON THE WINNABLE SIDE: cutting everything to zero closes the gap
    # exactly, so there IS an arrangement that works and the page must not claim otherwise. `<`
    # rather than `<=` is the whole of this example.
    it "is false when the cuts close the gap exactly", :aggregate_failures do
      rate(envelope("Groceries"), 1_000)
      rolling(envelope("Rent", priority: 2), amount: 5_200)

      expect(presenter.gap).to eq(BigDecimal("1000.00"))
      expect(presenter.cuttable_total).to eq(presenter.gap)
      expect(presenter.unwinnable?).to be(false)
    end

    # EVERY RULE ANCHORED: there is nothing to dial at all, which is the worst version of the
    # unwinnable case and the one whose list renders empty.
    it "is true when there is nothing anchorless to cut", :aggregate_failures do
      rolling(envelope("Rent"), amount: 7_500)

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
      monthly = create(:pool_budget, :rate, pool: envelope("Streaming"), amount: 1_500)

      row = presenter.cuttable_rows.find { |candidate| candidate.budget.id == monthly.id }

      expect(row.claim_param).to eq("692.31")
    end

    it "prints a four-figure claim with no thousands separator", :aggregate_failures do
      rule = rate(envelope("Rent"), 1_500)

      row = presenter.cuttable_rows.find { |candidate| candidate.budget.id == rule.id }

      expect(row.claim_param).to eq("1500.00")
      expect(row.claim_param).not_to include(",")
    end
  end
end
