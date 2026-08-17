# frozen_string_literal: true

require "rails_helper"

# THE NEW SEAM, AND ONLY THE NEW SEAM. What the projections MEAN — that a closed rate envelope
# nets its own leftover off, that a $0 override must not reopen a period, that a mixed envelope
# re-derives a plausible second sweep — is measured where it always was, in
# `spec/services/pool_calculator_spec.rb`, through `pool.calculator(net_of_sweep:, pending:)`.
# Plan 2d decision 4 moved the machinery under that door and did not touch a single one of those
# assertions, which is the whole contract of the split.
#
# What is new is the door itself: which object a caller gets back, what it delegates, what it
# refuses, when it first touches the database, and whether the ledger world it was built over
# reaches the twin it builds. Those are what this file pins.
#
# `today` is Thu 20 Aug 2026, the last day of a biweekly period anchored Fri 6 Feb 2026: boundaries
# fall on Aug 7 and Aug 21, so money dated Aug 15 is inside the live period and money dated Jul 12
# is two periods back. The same clock as the sweep examples next door, so a closed period here
# means what it means there.
RSpec.describe PoolProjection, type: :model do
  let(:user) { create(:user, :biweekly) }
  let(:account) { create(:pool, :account, user: user) }
  let(:today) { Date.new(2026, 8, 20) }
  let(:last_period) { Date.new(2026, 7, 12) }
  let(:this_period) { Date.new(2026, 8, 15) }

  # A rate envelope holding $85 from a period that ended over a month ago: closed, so a
  # `net_of_sweep` projection actually derives a sweep rather than subtracting zero.
  let(:groceries) do
    pool = create(:pool, :budget_pool, user: user, account: account, name: "Groceries")
    create(:pool_budget, :per_period_rate, pool: pool, amount: 400)
    pool
  end

  def fund(pool, amount, on:)
    create(:pool_movement, from_pool: account, to_pool: pool, amount: amount, date: on)
  end

  # The statements a block actually issued, which is the only way to tell "did not run a query yet"
  # apart from "ran one and memoised it" — both answer the same figures.
  def sql_for
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      statements << payload[:sql] unless ["SCHEMA", "TRANSACTION"].include?(payload[:name])
    end
    yield
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  # A PROJECTION WITH NOTHING TO PROJECT IS THE PLAIN CALCULATOR, and `.for` hands the calculator
  # itself back rather than a wrapper around it. That is not tidiness: nearly every calculator in
  # the app asks no projected question, and this keeps all of them on exactly the object — and the
  # class — they were on before the split.
  describe ".for" do
    it "hands back a plain calculator when nothing is projected", :aggregate_failures do
      expect(described_class.for(groceries, today: today)).to be_a(PoolCalculator)
      expect(described_class.for(groceries, today: today, pending: described_class::Pending.none))
        .to be_a(PoolCalculator)
    end

    # Pool#calculator is the app's one door onto a pool's figures and it kept its whole signature,
    # so this is the assertion that the delegation behind it is invisible to its callers.
    it "leaves Pool#calculator handing back a calculator for an unprojected question" do
      expect(groceries.calculator(today: today)).to be_a(PoolCalculator)
    end

    it "wraps when a sweep is netted off" do
      expect(groceries.calculator(today: today, net_of_sweep: true)).to be_a(described_class)
    end

    # THE PENDING THAT MOVES NO MONEY AND IS STILL A PROJECTION. `funded: 100, swept: 100` nets to
    # zero, so a `net`-only test for "is anything being projected" would call it inert — and lose
    # the DATE, which is the member PoolCalculator#last_funded_on reads and the one that decides
    # whether a rate period is live. This envelope has never been funded, so the date is the whole
    # difference between "that period is over" and "there is no period yet": dropped, the same
    # projection reports an open period over the same unmoved $0 balance.
    it "wraps a pending that moves nothing but names a funding date", :aggregate_failures do
      pending_move = described_class::Pending.new(funded: 100.to_d, swept: 100.to_d, on: last_period)
      projection = groceries.calculator(today: today, pending: pending_move)

      expect(projection).to be_a(described_class)
      expect(projection.balance).to eq(0)
      expect(projection.period_closed?).to be(true)
      expect(groceries.calculator(today: today).period_closed?).to be(false)
    end
  end

  # Both projections are adjustments to the BALANCE, so every reader derived from the balance
  # inherits them and no reader has to learn about them. `delegate_missing_to` is that sentence as
  # code; these are the two halves of it — the money readers answering over the projected balance,
  # and the readers that are not about money at all still answering.
  describe "delegation" do
    before { fund(groceries, 85, on: last_period) }

    it "answers the balance-derived readers over the projected balance", :aggregate_failures do
      projection = groceries.calculator(today: today, net_of_sweep: true)

      expect(groceries.calculator(today: today).balance).to eq(85)
      expect(projection.balance).to eq(0)
      expect(projection.required).to eq(400)
      expect(projection.free_amount).to eq(0)
      expect(projection.reserve).to eq(0)
    end

    # An enumerated `delegate :balance, :required, …` list would have answered the four above and
    # dropped these two on the floor — they are not money, so nobody would have thought to list
    # them, and `PoolStatus` reads `today` off the calculator it was handed.
    it "delegates the readers that are not projections at all", :aggregate_failures do
      projection = groceries.calculator(today: today, net_of_sweep: true)

      expect(projection.pool).to eq(groceries)
      expect(projection.today).to eq(today)
      expect(projection).to respond_to(:income_within)
    end
  end

  # THE REFUSAL, AT ITS NEW ADDRESS. The reasoning is PoolProjection#refuse_when_net_of_sweep's and
  # the examples that pin what it saves are in pool_calculator_spec; what is new is WHERE it lives
  # — on the projection, with the calculator underneath carrying no guard at all — and that the
  # public constant survived the move.
  describe "the refusal" do
    before { fund(groceries, 85, on: last_period) }

    # A pending-only projection has no sweep netted off it, so it answers both readers rather than
    # refusing them — and it answers them about the balance the pending leaves. $85 already in the
    # envelope from July, $85 more proposed with no arrival date of its own: the pool's last real
    # funding still governs the period, it is over, and the whole $170 is what the next
    # distribution would take back.
    it "does not refuse a projection that nets no sweep off", :aggregate_failures do
      pending_move = described_class::Pending.new(funded: 85.to_d, swept: 0.to_d, on: nil)
      projection = groceries.calculator(today: today, pending: pending_move)

      expect(projection.period_closed?).to be(true)
      expect(projection.sweepable_amount).to eq(170)
    end

    it "refuses both sweep readers once a sweep is netted off", :aggregate_failures do
      projection = groceries.calculator(today: today, net_of_sweep: true)

      expect { projection.sweepable_amount }.to raise_error(described_class::NetOfSweepError, /sweepable_amount/)
      expect { projection.period_closed? }.to raise_error(described_class::NetOfSweepError, /period_closed\?/)
    end

    # THE OLD NAME IS THE SAME CLASS, not a second error that happens to be spelled alike. A rescue
    # written against `PoolCalculator::NetOfSweepError` — AllocationCommitter names it, and it is
    # the constant the calculator's own examples assert — must go on catching exactly this raise,
    # and `rescue` compares by object identity.
    it "raises under its old public name too", :aggregate_failures do
      projection = groceries.calculator(today: today, net_of_sweep: true)

      expect(PoolCalculator::NetOfSweepError).to equal(described_class::NetOfSweepError)
      expect { projection.sweepable_amount }.to raise_error(PoolCalculator::NetOfSweepError)
    end
  end

  # WHEN IT FIRST TOUCHES THE DATABASE, which is a money question and not a performance one.
  # /distributions/new renders inside a transaction that has just DELETED this period's split, and
  # AllocationCommitter re-derives its proposal after the same deletion — so an object that ran its
  # aggregates when it was CONSTRUCTED would answer about a world neither screen is showing. The
  # ledger keeps that promise in PoolBalanceLedger#totals; this keeps it one layer up.
  describe "when it reads" do
    before { fund(groceries, 85, on: last_period) }

    it "runs no query until a reader asks", :aggregate_failures do
      projection = nil

      expect(sql_for { projection = groceries.calculator(today: today, net_of_sweep: true) }).to be_empty
      expect(sql_for { projection.balance }).not_to be_empty
    end

    # THE TWIN IS BUILT OVER THE SAME LEDGER WORLD, and `as_of:` is the member that proves it
    # because it changes what the twin can SEE. Bounded to Jul 31 the pool holds $85, all of it
    # last period's, and all of it sweeps — so the projection is empty. A twin built without the
    # bound would sweep the $125 it can see and hand the projection a balance of -$40.
    #
    # This is the same passing-through that `terms:` depends on for batching (pinned by SUM count
    # in pool_balance_ledger_spec); the keywords travel as one splat precisely so a later edit
    # cannot thread one of them and forget the other.
    it "builds its twin over the same ledger world it was built over", :aggregate_failures do
      fund(groceries, 40, on: this_period)
      bounded = groceries.calculator(as_of: Date.new(2026, 7, 31), today: today, net_of_sweep: true)

      expect(groceries.calculator(as_of: Date.new(2026, 7, 31), today: today).balance).to eq(85)
      expect(bounded.balance).to eq(0)
    end
  end
end
