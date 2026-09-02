# frozen_string_literal: true

require "rails_helper"

# THE NEW SEAM, AND ONLY THE NEW SEAM — the port of `spec/services/pool_projection_spec.rb`. What
# the projections MEAN — that a closed rate envelope nets its own leftover off, that a $0 override
# must not reopen a period, that a mixed envelope re-derives a plausible second sweep — is measured
# where it always was, in `spec/services/holding_calculator_spec.rb`, through
# `category.holding_calculator(net_of_sweep:, pending:)`.
#
# What this file pins is the door itself: which object a caller gets back, what it delegates, what
# it refuses, when it first touches the database, and whether the ledger world it was built over
# reaches the twin it builds.
#
# `today` is Thu 20 Aug 2026, the last day of a biweekly period anchored Fri 6 Feb 2026: boundaries
# fall on Aug 7 and Aug 21, so money dated Aug 15 is inside the live period and money dated Jul 12
# is two periods back. The same clock as the sweep examples next door, so a closed period here
# means what it means there.
RSpec.describe HoldingProjection, type: :model do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 8, 20) }
  let(:last_period) { Date.new(2026, 7, 12) }
  let(:this_period) { Date.new(2026, 8, 15) }

  # A rate envelope holding $85 from a period that ended over a month ago: closed, so a
  # `net_of_sweep` projection actually derives a sweep rather than subtracting zero.
  let(:groceries) do
    category = create(:category, :expense, :funded, user: user, name: "Groceries")
    create(:budget, :per_period_rate, pool: nil, category: category, amount: 400)
    category
  end

  def fund(category, amount, on:)
    create(:allocation, to_category: category, amount: amount, date: on)
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
  # class — they would otherwise have been on.
  describe ".for" do
    it "hands back a plain calculator when nothing is projected", :aggregate_failures do
      expect(described_class.for(groceries, today: today)).to be_a(HoldingCalculator)
      expect(described_class.for(groceries, today: today, pending: described_class::Pending.none))
        .to be_a(HoldingCalculator)
    end

    # Category#holding_calculator is the app's one door onto a category's figures, so this is the
    # assertion that the delegation behind it is invisible to its callers.
    it "leaves Category#holding_calculator handing back a calculator for an unprojected question" do
      expect(groceries.holding_calculator(today: today)).to be_a(HoldingCalculator)
    end

    it "wraps when a sweep is netted off" do
      expect(groceries.holding_calculator(today: today, net_of_sweep: true)).to be_a(described_class)
    end

    # THE PENDING THAT MOVES NO MONEY AND IS STILL A PROJECTION. `funded: 100, swept: 100` nets to
    # zero, so a `net`-only test for "is anything being projected" would call it inert — and lose
    # the DATE, which is the member HoldingCalculator#last_funded_on reads and the one that decides
    # whether a rate period is live. This category has never been funded, so the date is the whole
    # difference between "that period is over" and "there is no period yet": dropped, the same
    # projection reports an open period over the same unmoved $0 balance.
    it "wraps a pending that moves nothing but names a funding date", :aggregate_failures do
      pending_move = described_class::Pending.new(funded: 100.to_d, swept: 100.to_d, on: last_period)
      projection = groceries.holding_calculator(today: today, pending: pending_move)

      expect(projection).to be_a(described_class)
      expect(projection.balance).to eq(0)
      expect(projection.period_closed?).to be(true)
      expect(groceries.holding_calculator(today: today).period_closed?).to be(false)
    end
  end

  # Both projections are adjustments to the BALANCE, so every reader derived from the balance
  # inherits them and no reader has to learn about them. Delegating through #method_missing is that
  # sentence as code, and it is what makes a reader added to HoldingCalculator tomorrow projected
  # the day it is written: the object it reaches was constructed with the adjustment already in it.
  describe "delegation" do
    before { fund(groceries, 85, on: last_period) }

    it "answers the balance-derived readers over the projected balance", :aggregate_failures do
      projection = groceries.holding_calculator(today: today, net_of_sweep: true)

      expect(groceries.holding_calculator(today: today).balance).to eq(85)
      expect(projection.balance).to eq(0)
      expect(projection.required).to eq(400)
      expect(projection.free_amount).to eq(0)
      expect(projection.reserve).to eq(0)
    end

    # THE SURFACE, DOCUMENTED, AND NOT A HAZARD AVERTED. An enumerated delegate list would have
    # dropped the two readers that are not money at all, and it would have raised NoMethodError
    # rather than answering wrongly, because HoldingProjection does not inherit from
    # HoldingCalculator. They are here to say what the object IS: the same reading of the same
    # category, not a money-only facade.
    it "delegates the readers that are not projections at all", :aggregate_failures do
      projection = groceries.holding_calculator(today: today, net_of_sweep: true)

      expect(projection.category).to eq(groceries)
      expect(projection.today).to eq(today)
      expect(projection).to respond_to(:contributions)
    end

    # #respond_to? IS ANSWERED FROM THE CLASS, so asking what a projection can do does not make it
    # derive a sweep. This is the sharp edge of the adjustment being a constructor argument — the
    # first delegated CALL builds the twin — and the one place it was cheap to keep flat.
    it "answers respond_to? without touching the database", :aggregate_failures do
      projection = groceries.holding_calculator(today: today, net_of_sweep: true)

      expect(sql_for { projection.respond_to?(:balance) }).to be_empty
      expect(projection).not_to respond_to(:anchored_reserve)
    end
  end

  # THE REFUSAL. The reasoning is HoldingProjection#refuse_when_net_of_sweep's and the examples
  # that pin what it saves are in holding_calculator_spec; what this pins is that it lives on the
  # projection, with the calculator underneath carrying no guard at all, and that the public
  # constant answers under both of its names.
  describe "the refusal" do
    before { fund(groceries, 85, on: last_period) }

    # A pending-only projection has no sweep netted off it, so it answers both readers rather than
    # refusing them — and it answers them about the balance the pending leaves. $85 already in the
    # category from July, $85 more proposed with no arrival date of its own: the category's last
    # real funding still governs the period, it is over, and the whole $170 is what the next
    # distribution would take back.
    it "does not refuse a projection that nets no sweep off", :aggregate_failures do
      pending_move = described_class::Pending.new(funded: 85.to_d, swept: 0.to_d, on: nil)
      projection = groceries.holding_calculator(today: today, pending: pending_move)

      expect(projection.period_closed?).to be(true)
      expect(projection.sweepable_amount).to eq(170)
    end

    it "refuses both sweep readers once a sweep is netted off", :aggregate_failures do
      projection = groceries.holding_calculator(today: today, net_of_sweep: true)

      expect { projection.sweepable_amount }.to raise_error(described_class::NetOfSweepError, /sweepable_amount/)
      expect { projection.period_closed? }.to raise_error(described_class::NetOfSweepError, /period_closed\?/)
    end

    # THE LIST IS THE GUARD, AND THE GUARD IS THE LIST. The delegation projects a new reader
    # automatically and refuses nothing automatically, so a second reader of the sweep added to
    # HoldingCalculator later is refused only if it is named in SWEEP_READERS. Written as a loop
    # over the constant rather than over two literal names: a third entry is covered the moment it
    # is added, and an entry REMOVED fails here rather than quietly re-opening the phantom sweep.
    it "refuses every reader named in SWEEP_READERS", :aggregate_failures do
      projection = groceries.holding_calculator(today: today, net_of_sweep: true)

      expect(HoldingCalculator::SWEEP_READERS).to include(:sweepable_amount, :period_closed?)
      HoldingCalculator::SWEEP_READERS.each do |reader|
        expect { projection.public_send(reader) }.to raise_error(described_class::NetOfSweepError, /#{reader}/)
      end
    end

    # The other direction, on the same object: a reader NOT in the list is delegated and answers
    # over the projected balance. Without this the guard could be a blanket refusal of everything —
    # which is the shape the whole `net_of_sweep` keyword exists to avoid, since #required is the
    # reader these projections are built for.
    it "delegates the readers that are not in it", :aggregate_failures do
      projection = groceries.holding_calculator(today: today, net_of_sweep: true)

      expect(HoldingCalculator::SWEEP_READERS).not_to include(:required, :free_amount)
      expect(projection.required).to eq(400)
      expect(projection.free_amount).to eq(0)
    end

    # THE OTHER NAME IS THE SAME CLASS, not a second error that happens to be spelled alike. A
    # rescue written against `HoldingCalculator::NetOfSweepError` must go on catching exactly this
    # raise, and `rescue` compares by object identity.
    it "raises under its other public name too", :aggregate_failures do
      projection = groceries.holding_calculator(today: today, net_of_sweep: true)

      expect(HoldingCalculator::NetOfSweepError).to equal(described_class::NetOfSweepError)
      expect { projection.sweepable_amount }.to raise_error(HoldingCalculator::NetOfSweepError)
    end
  end

  # WHEN IT FIRST TOUCHES THE DATABASE, which is a money question and not a performance one. The
  # distribution screen renders inside a transaction that has just DELETED this period's split, and
  # the committer re-derives its proposal after the same deletion — so an object that ran its
  # aggregates when it was CONSTRUCTED would answer about a world neither screen is showing.
  describe "when it reads" do
    before { fund(groceries, 85, on: last_period) }

    it "runs no query until a reader asks", :aggregate_failures do
      projection = nil

      expect(sql_for { projection = groceries.holding_calculator(today: today, net_of_sweep: true) }).to be_empty
      expect(sql_for { projection.balance }).not_to be_empty
    end

    # THE TWIN IS BUILT OVER THE SAME LEDGER WORLD, and `as_of:` is the member that proves it
    # because it changes what the twin can SEE. Bounded to Jul 31 the category holds $85, all of it
    # last period's, and all of it sweeps — so the projection is empty. A twin built without the
    # bound would sweep the $125 it can see and hand the projection a balance of -$40.
    #
    # This is the same passing-through that `terms:` depends on for batching; the keywords travel
    # as one splat precisely so a later edit cannot thread one of them and forget the other.
    it "builds its twin over the same ledger world it was built over", :aggregate_failures do
      fund(groceries, 40, on: this_period)
      bounded = groceries.holding_calculator(as_of: Date.new(2026, 7, 31), today: today, net_of_sweep: true)

      expect(groceries.holding_calculator(as_of: Date.new(2026, 7, 31), today: today).balance).to eq(85)
      expect(bounded.balance).to eq(0)
    end
  end
end
