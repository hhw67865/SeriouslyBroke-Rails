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
  end

  # ONE transaction, and the sweeps are what make it load-bearing: they are written first, so
  # a bad allocation has to take an already-saved sweep back out with it. The DELETION is
  # inside it too, and that is the half with no compensating write to give it away: hoisted
  # out, a failed re-run destroys the previous split, writes nothing in its place and still
  # reports `success? == false`.
  #
  # `requires_new: true`, and it is not decoration. A `transaction` block inside an already
  # open transaction opens no savepoint by default, so `ActiveRecord::Rollback` is swallowed
  # and the OUTER transaction commits: the sweeps and the valid allocations land, the bad line
  # does not, and this class reports a failure over a half-written split — the one outcome it
  # exists to prevent. No caller wraps #call today; Task 6's controller committing alongside
  # anything else is one line away from it.
  #
  # Every line is attempted rather than stopping at the first bad one, so a form comes back
  # with all of its bad lines marked at once.
  #
  # The three memos are reset here rather than in #initialize, so a second #call replaces its
  # own split from a proposal built against the ledger as it stands. Left memoised, the second
  # call would delete this period's rows and re-commit the FIRST call's snapshot — exactly the
  # staleness this class exists to defend against.
  def call
    @errors = []
    @lines = []
    @live_proposal = nil
    @replaced = []
    ActiveRecord::Base.transaction(requires_new: true) do
      replace_previous_distribution
      @lines = movements
      @lines.each { |movement| record_failure(movement) unless movement.save }
      raise ActiveRecord::Rollback if @errors.any?
    end
    result
  end

  # The period as if its distribution had not happened: this period's `allocation` and `sweep`
  # rows are DELETED, and only then is a fresh proposal built over what is left. Returns that
  # proposal; the rows it deleted are in #replaced.
  #
  # Public because the distribution SCREEN needs the same answer as the action underneath it.
  # Once a period has been committed its envelopes are funded, so a proposal computed against
  # the ledger as it stands asks for nothing — the screen would read "nothing to distribute"
  # over a button that replaces the whole split. Confirming does exactly what this method
  # does, so the screen runs it inside a transaction it rolls back and the action runs it for
  # real. One code path, so the two cannot drift.
  #
  # THIS DESTROYS ROWS. A caller that only wants to look must wrap it in
  # `ActiveRecord::Base.transaction(requires_new: true)` and `raise ActiveRecord::Rollback` —
  # and `requires_new` is not optional there either: a plain nested `transaction` opens no
  # savepoint, so the Rollback is swallowed and the deletion COMMITS. That is a screen
  # silently destroying the user's last split, which is the loudest failure in this plan.
  #
  # Not guarded by a `transaction_open?` check, deliberately: under
  # `use_transactional_fixtures` every example already runs inside one, so the guard would be
  # green in the tests and untested where it matters. The rule is stated here and both callers
  # are one file away.
  def replace_previous_distribution
    @replaced = previous_distribution.destroy_all
    live_proposal
  end

  # What #replace_previous_distribution deleted — the last split for this period, in memory
  # after its rows are gone. Empty when the period had never been distributed, which is how
  # the screen knows whether to say it is REPLACING a split rather than writing the first one.
  def replaced = @replaced ||= []

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

  # A $0 allocation is not an event, and `PoolMovement` would refuse it anyway. This is NOT an
  # override-only case: #fill rejects rows whose NEED is zero but keeps a row whose FUNDING is
  # zero — the envelope below the point the money ran out, which is the ordinary shape of a
  # short period. Left unskipped, that line fails `amount > 0` and rolls the whole
  # distribution back, so one envelope getting nothing would leave every envelope unfunded.
  #
  # Only an exact zero is skipped: a NEGATIVE override is bad input the user has to see, and
  # it fails the amount validation loudly rather than vanishing from a split it was meant to
  # change. The key is stringified for the same reason it is stringified on the way in — a
  # lookup that misses is an override silently not applied, which is money not moved with
  # nothing said about it.
  def allocation_movements
    live_proposal.rows.filter_map do |row|
      amount = overrides.fetch(row.pool.id.to_s, row.funded)
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
  # `order(:id)` is not cosmetic. Every destroy here `touch`es both of its pools, and the
  # distribution SCREEN holds this deletion open inside a transaction for the whole of its
  # snapshot — so two renders of the same period taking the same `pools` rows in different orders
  # deadlock, and a `create` can block behind a page view. Unordered, the order is heap order,
  # which a plain UPDATE changes. One fixed order for every caller costs nothing and makes the
  # lock sequence deterministic.
  def previous_distribution
    in_period = PoolMovement.distributed.where(date: period)
    in_period.where(from_pool: account).or(in_period.where(to_pool: account)).order(:id)
  end

  # A period is a RANGE, and `date` is a datetime column: bounded by dates alone the last day
  # would end at its own midnight and a distribution written later that day would survive its
  # own replacement. The widening moved onto User so the distribution screen's income query —
  # `entries.date` is a datetime too — cannot disagree with this one about where the period
  # ends.
  def period = proposal.user.period_datetimes_containing(proposal.today)

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
