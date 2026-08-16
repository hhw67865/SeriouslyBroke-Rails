# frozen_string_literal: true

# Turns a proposal into movements. Sweeps first (envelope -> account), then allocations
# (account -> envelope), all inside one transaction so a failure leaves the ledger exactly as
# it was. This is the first thing in the app that moves money, and the only invariant that
# matters is that it never creates or destroys any: every line is a movement between two of
# the user's own pools, so `Σ pools == your bank balance` before and after.
#
# See docs/superpowers/plans/2026-08-16-distribution.md Task 3, spec §5
class AllocationCommitter
  # One shape for both outcomes, so a caller cannot read a success off a failure by accident:
  # a failure carries no movements and a success carries no errors, and every reader answers
  # on either. `0.to_d` seeds both totals — an empty commit is the emptiest possible sum and
  # exactly where a bare Integer 0 would leak out into whatever Task 6 renders.
  Result = Data.define(:movements, :errors) do
    def success? = errors.empty?

    def allocated = total_for(:kind_allocation?)

    def swept = total_for(:kind_sweep?)

    private

    def total_for(predicate) = movements.select(&predicate).sum(0.to_d, &:amount)
  end

  attr_reader :proposal, :overrides

  # `proposal` names the account, the user and the day being distributed — the context the
  # caller already holds. The FIGURES are re-derived (see #live_proposal); a proposal that
  # was rendered and then confirmed is a snapshot, and this class writes against the ledger.
  #
  # `overrides` is keyed by pool id, matching what a form submits, and coerced here so the
  # write loop never has to wonder whether it is holding a String. A blank override coerces
  # to zero and is therefore skipped, which is the same reading as "the user cleared the box".
  def initialize(proposal, overrides: {})
    @proposal = proposal
    @overrides = overrides.to_h { |pool_id, amount| [pool_id.to_s, amount.to_d] }
    @errors = []
    @lines = []
  end

  # ONE transaction, and the sweeps are what make it load-bearing: they are written first, so
  # a bad allocation has to take an already-saved sweep back out with it. Every line is
  # attempted rather than stopping at the first bad one, so a form comes back with all of its
  # bad lines marked at once.
  def call
    ActiveRecord::Base.transaction do
      previous_distribution.destroy_all
      @lines = movements
      @lines.each { |movement| record_failure(movement) unless movement.save }
      raise ActiveRecord::Rollback if @errors.any?
    end
    result
  end

  private

  def account = proposal.account

  # The proposal this class actually commits: built AFTER the previous distribution has been
  # deleted, and read in full before the first save.
  #
  # MEASURED, because the plan said to commit the proposal it was handed. Doing that undoes
  # the distribution on any re-run. Confirming a period a second time deletes the first
  # split's rows, but the proposal describing the replacement was computed while those rows
  # were still there — so the envelopes report themselves funded and ask for nothing, and the
  # commit deletes three rows and writes none. Measured on the spec's re-run fixture:
  # Groceries $400 / Water $350 / buffer $250 fell back to $85 / $50 / $865 and the period's
  # movement count went to zero, with the button labelled "distribute". The mistyped-override
  # case, which is the reason replacement was chosen over refusal, was wrong in the other
  # direction: overriding Groceries to $40 and re-running left it at $445 rather than $400,
  # because the second proposal asked for the $360 gap while the deletion had already handed
  # the $40 back.
  #
  # Amendment A's own rule is the fix: a deletion is a write, so a calculator built before it
  # is stale and a fresh one must be built after it. Re-derived UNCONDITIONALLY rather than
  # only when something was deleted — with nothing deleted the two computations have the same
  # inputs and no write between them, so they are provably the same answer, and one path
  # through the money is worth more than the queries a second path would save.
  #
  # The caller's overrides survive the re-derivation because they are keyed by pool, not by
  # row position. An override naming a pool that no longer has a row is ignored: an override
  # edits a line, and a pool with no line has no line to edit.
  def live_proposal
    @live_proposal ||= AllocationCalculator.new(user: proposal.user, account: account, today: proposal.today)
  end

  # Built, not saved. Every figure is read out of the proposal here, before the first save,
  # because the calculators underneath memoise and go stale the moment a movement is written.
  def movements = sweep_movements + allocation_movements

  # Sweeps are movements too, so the ledger explains the money's whole journey rather than
  # showing an envelope mysteriously topped up by less than its rule.
  #
  # The amount comes from `sweeps`, which is keyed by the Pool record precisely so the sweep
  # needs no second lookup. Asking a calculator again inside this loop is what
  # PoolCalculator::NetOfSweepError exists to refuse: the pool's own post-sweep view would
  # re-derive a second, smaller sweep.
  def sweep_movements
    live_proposal.sweeps.map do |pool, amount|
      build(from: pool, to: account, amount: amount, kind: :sweep)
    end
  end

  # A $0 allocation is not an event, and `PoolMovement` would refuse it anyway. Only an exact
  # zero is skipped: a NEGATIVE override is bad input the user has to see, and it fails the
  # amount validation loudly rather than vanishing from a split it was meant to change.
  def allocation_movements
    live_proposal.rows.filter_map do |row|
      amount = overrides.fetch(row.pool.id, row.funded)
      next if amount.zero?

      build(from: account, to: row.pool, amount: amount, kind: :allocation)
    end
  end

  def build(from:, to:, amount:, kind:)
    PoolMovement.new(from_pool: from, to_pool: to, amount: amount, date: proposal.today, kind: kind)
  end

  # Everything this account's last distribution wrote inside this period, and nothing else.
  # Three filters, each doing work the others cannot: `distributed` spares the user's own
  # reallocations, the period spares earlier distributions, and the account spares a second
  # account distributing on the same day.
  #
  # Every distribution row touches the account itself — sweeps arrive there, allocations leave
  # from there — so the two-sided match needs no join through the envelopes.
  def previous_distribution
    in_period = PoolMovement.distributed.where(date: period)
    in_period.where(from_pool: account).or(in_period.where(to_pool: account))
  end

  # A period is a RANGE, and `date` is a datetime column: bounded by dates alone the last day
  # would end at its own midnight and a distribution written later that day would survive its
  # own replacement.
  def period
    range = proposal.user.period_containing(proposal.today)
    range.first.beginning_of_day..range.last.end_of_day
  end

  # Named by the envelope, which is the line the user recognises: the account is on every
  # line and identifies none of them. "The side that is not the account" reads both
  # directions without branching on kind — a branch whose sweep arm would be unreachable,
  # since #sweeps only ever yields positive amounts between an envelope and its own account.
  # The two pools always differ (model validation and a check constraint), so exactly one of
  # them can be the account and the other is always found.
  def record_failure(movement)
    envelope = [movement.from_pool, movement.to_pool].find { |pool| pool != account }
    @errors.concat(movement.errors.full_messages.map { |message| "#{envelope.name}: #{message}" })
  end

  # A rolled-back commit reports no movements, because the rows those records describe are
  # gone: handing them back would let a caller read amounts off a ledger that never happened.
  def result
    @errors.any? ? Result.new(movements: [], errors: @errors) : Result.new(movements: @lines, errors: [])
  end
end
