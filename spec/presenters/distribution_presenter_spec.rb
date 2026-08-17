# frozen_string_literal: true

require "rails_helper"

RSpec.describe DistributionPresenter, type: :model do
  # The same calendar AllocationCalculator's and AllocationCommitter's specs use: biweekly,
  # anchored Fri 6 Feb 2026, so the boundaries around August are Aug 7 and Aug 21 and the period
  # containing Aug 20 is Aug 7..Aug 20. Money paid in on Jul 12 belongs to a period that ended
  # Jul 23 — closed, and therefore swept.
  let(:user) { create(:user, :biweekly) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  def today = Date.new(2026, 8, 20)
  def last_period = Date.new(2026, 7, 12)
  def this_period = Date.new(2026, 8, 15)

  # A FRESH presenter every time, because a presenter memoises its snapshot — which is right
  # for one render and wrong for a spec reading the screen on both sides of a commit.
  def presenter(account: checking) = described_class.new(user: user, account: account, today: today)

  def rate_envelope(name, rate, funded: nil, priority: 0)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    create(:pool_budget, :per_period_rate, pool: pool, amount: rate)
    fund(pool, funded, on: last_period) if funded
    pool
  end

  def fund(pool, amount, on:)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: amount, date: on)
  end

  # A bill whose date has passed with no payment recorded against its item. The ITEM is what makes
  # a rule payable and therefore what makes it late: without one, BudgetCalculator assumes it was
  # paid on time and the pool never reads :overdue.
  def overdue_envelope(name, amount, funded: nil, priority: 0)
    pool = create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
    category = create(:category, :expense, user: user, pool: pool)
    create(
      :pool_budget,
      pool: pool,
      item: create(:item, category: category),
      amount: amount,
      interval_months: nil,
      anchor_date: today - 10
    )
    fund(pool, funded, on: this_period) if funded
    pool
  end

  def deposit(amount, on:)
    category = create(:category, :income, user: user, pool: checking)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  def spend(amount, on:)
    category = create(:category, :expense, user: user, pool: checking)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  def line_for(subject, name) = subject.lines.find { |line| line.pool.name == name }

  # THE worked example. $500 of income arrived last period and $85 of it went out to Groceries,
  # so the buffer carried $415 into this one; $2,400 landed this period; Groceries' rate period
  # has closed, so its $85 comes back. Every one of those four figures is put there by this
  # setup, which is what lets the breakdown below be checked against something other than itself.
  #
  # The asks — $400, $2,600, $150 — drain the $2,900 in priority order and run out inside Car,
  # so one envelope is partly funded and one gets nothing at all: the two shapes the waterfall
  # has to tell apart.
  describe "a period that has not been distributed" do
    before do
      rate_envelope("Groceries", 400, funded: 85, priority: 1)
      rate_envelope("Car", 2_600, priority: 2)
      rate_envelope("Vacation", 150, priority: 3)
      deposit(500, on: last_period)
      deposit(2_400, on: this_period)
    end

    # The lines of the sources breakdown, each against the figure the fixture put there — never
    # against each other. Three are measured independently (an `as_of` balance, an income query,
    # the proposal's sweeps) and the fourth is the residual, so asserting that they add up would
    # be `x == x` and would pass on any three numbers at all.
    #
    # `moved_this_period` is zero here and that is an assertion, not an omission: nothing left
    # this account inside the period, so the residual has nothing to absorb — which is what makes
    # the $415 above a real opening balance rather than a plug.
    it "breaks the available money into where it came from", :aggregate_failures do
      subject = presenter

      expect(subject.buffer_carried).to eq(415)
      expect(subject.income_this_period).to eq(2_400)
      expect(subject.moved_this_period).to eq(0)
      expect(subject.total_swept).to eq(85)
      expect(subject.available).to eq(2_900)
    end

    # Money by TYPE, not by value: `sum(:amount)` over an empty set is the Integer literal 0,
    # and an Integer here divides wrong two screens later rather than failing here.
    it "answers in BigDecimal on every figure the screen prints", :aggregate_failures do
      subject = presenter

      expect(subject.buffer_carried).to be_a(BigDecimal)
      expect(subject.moved_this_period).to be_a(BigDecimal)
      expect(subject.income_this_period).to be_a(BigDecimal)
      expect(subject.total_swept).to be_a(BigDecimal)
      expect(subject.available).to be_a(BigDecimal)
      expect(subject.leftover).to be_a(BigDecimal)
      expect(subject.shortfall).to be_a(BigDecimal)
      expect(subject.lines.map(&:needed)).to all(be_a(BigDecimal))
      expect(subject.lines.map(&:funded)).to all(be_a(BigDecimal))
    end

    # Income belongs to the period it arrived in. The $500 from July is NOT in this figure — it
    # is in the buffer that carried over — and a screen that summed all income ever would report
    # $2,900 here and a $0 buffer, which is a different and wrong story about the same account.
    it "counts only the income that arrived inside this period" do
      expect(presenter.income_this_period).to eq(2_400)
    end

    it "fills the envelopes in priority order until the money runs out", :aggregate_failures do
      subject = presenter

      expect(subject.lines.map { |line| line.pool.name }).to eq(["Groceries", "Car", "Vacation"])
      expect(subject.lines.map(&:needed)).to eq([400, 2_600, 150])
      expect(subject.lines.map(&:funded)).to eq([400, 2_500, 0])
      expect(subject.lines.map(&:short?)).to eq([false, true, true])
    end

    it "is short, and says by how much", :aggregate_failures do
      subject = presenter

      expect(subject).to be_short
      expect(subject).not_to be_covered
      expect(subject).to be_expanded
      expect(subject.shortfall).to eq(250)
      expect(subject.leftover).to eq(0)
    end

    # The sweep is named by the envelope it came out of, because that is the line the user
    # recognises — and the amount is the one the row prints, so the breakdown and the row cannot
    # disagree about how much Groceries handed back.
    it "names the envelope each swept dollar came out of", :aggregate_failures do
      subject = presenter

      expect(subject.swept_pools.map(&:name)).to eq(["Groceries"])
      expect(subject.sweeps.map(&:last)).to eq([85])
      expect(line_for(subject, "Groceries").swept).to eq(85)
      expect(line_for(subject, "Car")).not_to be_swept
    end

    it "has nothing to replace" do
      expect(presenter).not_to be_redistribution
    end
  end

  # The other direction of the density switch, on the same fixture shape: only Car's ask
  # changes, from $2,600 to $100, and the screen has to stop rendering a waterfall because of
  # it. A presenter that reported `short?` unconditionally would pass the example above.
  describe "a period where everything is funded" do
    before do
      rate_envelope("Groceries", 400, funded: 85, priority: 1)
      rate_envelope("Car", 100, priority: 2)
      rate_envelope("Vacation", 150, priority: 3)
      deposit(500, on: last_period)
      deposit(2_400, on: this_period)
    end

    it "is covered, with the whole ask funded and the rest left in the buffer", :aggregate_failures do
      subject = presenter

      expect(subject).to be_covered
      expect(subject).not_to be_short
      expect(subject.shortfall).to eq(0)
      expect(subject.lines.map(&:funded)).to eq([400, 100, 150])
      expect(subject.total_allocated).to eq(650)
      expect(subject.leftover).to eq(2_250)
    end

    # The collapsed half of the density switch: nothing short, nothing red, so the screen has one
    # line to say and says it.
    it "collapses", :aggregate_failures do
      subject = presenter

      expect(subject).not_to be_expanded
      expect(subject.alerts).to be_empty
    end
  end

  # Spec §5 says "anything short OR OVERDUE → the full waterfall". The overdue half is not a
  # variation on the short one: this envelope ALREADY HOLDS its $120, so it asks for nothing, so
  # it is rejected from #rows — and a short-only switch collapses the whole screen to "everything
  # is funded, one button" over a bill that is already late.
  describe "a covered period with an overdue bill that needs no money" do
    before do
      rate_envelope("Groceries", 400, priority: 1)
      overdue_envelope("Utilities", 120, funded: 120, priority: 2)
      deposit(2_400, on: this_period)
    end

    it "opens the full table even though every envelope is funded", :aggregate_failures do
      subject = presenter

      expect(subject).to be_covered
      expect(subject).to be_expanded
    end

    # The pool that fired the switch has no row, so unless it is named here the table opens and
    # says nothing about why. Both halves pinned: it is IN the alerts and NOT in the rows.
    it "names the pool nothing else on the screen can mention", :aggregate_failures do
      subject = presenter

      expect(subject.alerts.map { |pool, _standing| pool.name }).to eq(["Utilities"])
      expect(subject.alerts.map { |_pool, standing| standing.state }).to eq([:overdue])
      expect(subject.lines.map { |line| line.pool.name }).to eq(["Groceries"])
    end
  end

  # The other direction of the alerts list. A red pool that DOES have a row is already named by
  # that row's own detail line, and listing it again would print one problem twice.
  describe "a covered period with an overdue bill that still needs money" do
    before do
      rate_envelope("Groceries", 400, priority: 1)
      overdue_envelope("Utilities", 120, priority: 2)
      deposit(2_400, on: this_period)
    end

    it "expands on the row rather than on an alert", :aggregate_failures do
      subject = presenter

      expect(subject).to be_expanded
      expect(subject.alerts).to be_empty
      expect(line_for(subject, "Utilities").status.state).to eq(:overdue)
      expect(line_for(subject, "Utilities").needed).to eq(120)
    end
  end

  # Amendment B. #available is deliberately unclamped: one account has no sibling overdraft to
  # cancel against, so a floor at zero would hide a real negative. Three figures, all negative,
  # all different — a clamp anywhere on the path shows up as a zero in one of them.
  describe "an account that is already overdrawn" do
    before do
      rate_envelope("Groceries", 400, priority: 1)
      deposit(100, on: this_period)
      spend(300, on: this_period)
    end

    it "reports the negative rather than flooring it at zero", :aggregate_failures do
      subject = presenter

      expect(subject.available).to eq(-200)
      expect(subject.leftover).to eq(-200)
      expect(subject.available).to be_negative
    end

    # The four sources against their four causes. The account opened the period holding nothing,
    # $100 came in, $300 went out — and it is the SPENDING line that carries the overdraft, not
    # the carried-over one, which is the whole point of measuring the opening buffer rather than
    # deriving it. Derived, this line printed -$300.00 "carried over" into a period the account
    # opened at zero.
    it "blames the overdraft on the spending, not on the buffer it started with", :aggregate_failures do
      subject = presenter

      expect(subject.buffer_carried).to eq(0)
      expect(subject.income_this_period).to eq(100)
      expect(subject.moved_this_period).to eq(-300)
      expect(subject.total_swept).to eq(0)
    end

    it "funds nothing out of money that is not there", :aggregate_failures do
      subject = presenter

      expect(subject.lines.map(&:funded)).to eq([0])
      expect(subject.lines.map(&:needed)).to eq([400])
      expect(subject).to be_short
    end
  end

  # The schedule clause behind a row's ask: one rule, so the date and the count cannot describe
  # two different bills. $1,200 due Oct 1 with three biweekly boundaries left (Aug 21, Sep 4,
  # Sep 18) asks $400 a period — and the $400 is what makes the count checkable rather than
  # decorative, since a different count would move it.
  describe "an envelope funding a dated bill" do
    before do
      pool = create(:pool, :budget_pool, user: user, account: checking, name: "Rent", priority: 1)
      create(:pool_budget, pool: pool, amount: 1_200, interval_months: 12, anchor_date: Date.new(2026, 10, 1))
      deposit(2_000, on: this_period)
    end

    it "carries the due date and the periods left from the rule that set the ask", :aggregate_failures do
      line = line_for(presenter, "Rent")

      expect(line.due_on).to eq(Date.new(2026, 10, 1))
      expect(line.periods_left).to eq(3)
      expect(line.needed).to eq(400)
    end

    # `:behind` is deliberately NOT a trigger for the full table: it is amber, it is the ordinary
    # state of a bill being saved for, and expanding on it would collapse the two-density design
    # into one. The pool here is genuinely behind and the screen still says its one line.
    it "does not open the full table merely for being behind", :aggregate_failures do
      subject = presenter

      expect(line_for(subject, "Rent").status.state).to eq(:behind)
      expect(subject).not_to be_expanded
      expect(subject.alerts).to be_empty
    end
  end

  # THE reason this presenter deletes anything. Once a split is committed the envelopes are
  # funded and a proposal built over the ledger as it stands asks for NOTHING — so the screen
  # would read "nothing to distribute" above a button that replaces the whole split.
  #
  # Pinned at the same literal figures as the undistributed period above, not merely "equal to
  # what it was before": a screen that quietly recomputed both sides to zero would satisfy an
  # equality between two of its own readings.
  describe "a period that has already been distributed" do
    before do
      rate_envelope("Groceries", 400, funded: 85, priority: 1)
      rate_envelope("Car", 2_600, priority: 2)
      rate_envelope("Vacation", 150, priority: 3)
      deposit(500, on: last_period)
      deposit(2_400, on: this_period)
      AllocationCommitter.new(AllocationCalculator.new(user: user, account: checking, today: today)).call
    end

    it "proposes the same split again rather than an empty one", :aggregate_failures do
      subject = presenter

      expect(subject.available).to eq(2_900)
      expect(subject.buffer_carried).to eq(415)
      expect(subject.income_this_period).to eq(2_400)
      expect(subject.total_swept).to eq(85)
      expect(subject.lines.map(&:needed)).to eq([400, 2_600, 150])
      expect(subject.lines.map(&:funded)).to eq([400, 2_500, 0])
      expect(subject).to be_short
    end

    # A row's STATE is part of the same snapshot as its amounts. Groceries holds $85 of a closed
    # period before this split and $400 after it, so the state and the figure beside it have to
    # describe the same world or the row is two worlds wide.
    #
    # The type assertion is a contract, not a proof: it pins that the view is handed values rather
    # than a live PoolStatus, which is the only thing that makes the amounts below stable after
    # the rollback. PoolStatus today happens to memoise its balance once `#amount` has been asked,
    # so a live object would return these same numbers — the point is that nothing outside this
    # class guarantees it will keep doing so.
    it "freezes each row's state at the same moment as its figures", :aggregate_failures do
      line = line_for(presenter, "Groceries")

      expect(line.status).to be_a(described_class::Standing)
      expect(line.status.state).to eq(:left_to_spend)
      expect(line.status.amount).to eq(85)
      expect(line.period_closed).to be(true)
    end

    # The label the user needs in order to consent: this is a REPLACEMENT, and what it replaces
    # is $2,985 across three rows — the $85 sweep and the two allocations that were written.
    it "says what it is about to discard", :aggregate_failures do
      subject = presenter

      expect(subject).to be_redistribution
      expect(subject.replaced.size).to eq(3)
      expect(subject.replaced_total).to eq(2_985)
    end

    # The deletion is a means, not an effect: rendering the screen must leave the ledger exactly
    # as it found it.
    #
    # Read off the database rather than off the presenter, and pinned by SUM as well as by
    # count, so restoring three rows of the wrong size would still fail.
    it "leaves the committed split exactly where it found it", :aggregate_failures do
      expect(PoolMovement.distributed.count).to eq(3)

      presenter.lines

      expect(PoolMovement.distributed.count).to eq(3)
      expect(PoolMovement.distributed.sum(:amount)).to eq(2_985)
      # `Σ pools == your bank balance`, read off the pool ledger against the $2,900 the two
      # deposits put into this user's life. A rollback that half-fired would show up here as
      # money that exists in no pool at all.
      expect(checking.total).to eq(2_900)
    end

    # The `requires_new: true` guard, and it takes a caller's own transaction to reach it.
    #
    # MEASURED, because the example above does not reach it: RSpec's transactional fixtures
    # open their wrapper with `joinable: false`, so even a plain `transaction` opens a savepoint
    # inside a spec and the Rollback lands. Dropping `requires_new` therefore passes every other
    # example in this file — the screen would look correct in the whole suite while deleting the
    # user's last split on any request that already had a transaction open. Inside a JOINABLE
    # transaction, which is what a caller in the app would give it, the plain form joins, the
    # Rollback is swallowed, and the three rows below are gone.
    it "keeps the split even when rendered inside a transaction of its own caller" do
      ActiveRecord::Base.transaction do
        presenter.lines
      end

      expect(PoolMovement.distributed.count).to eq(3)
    end
  end

  # The buffer target is a health marker and never a cap (spec §7.1), so it is a separate
  # question from the buffer itself — and an account with no target must not print a `you
  # wanted $0.00` clause.
  describe "the buffer target" do
    it "reports the account's target when it has one", :aggregate_failures do
      checking.update!(target_amount: 2_000)

      expect(presenter.buffer_target).to eq(2_000)
      expect(presenter).to be_buffer_target
    end

    it "reports no target when the account has none", :aggregate_failures do
      expect(presenter.buffer_target).to eq(0)
      expect(presenter).not_to be_buffer_target
    end
  end
end
