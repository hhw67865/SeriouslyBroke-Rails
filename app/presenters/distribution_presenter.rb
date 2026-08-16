# frozen_string_literal: true

# Everything the distribution screen renders: where the money came from, which envelope gets
# what, and what stays in the buffer. READ-ONLY — this presenter writes nothing, and the
# deletion it performs on the way to its answer is rolled back before it returns (see
# #build_snapshot).
#
# It shows the period AS IF ITS DISTRIBUTION HAD NOT HAPPENED, because that is exactly what
# confirming does: AllocationCommitter deletes this period's `allocation` and `sweep` rows and
# only then computes the proposal it writes. A screen that instead computed against the ledger
# as it stands would read "nothing to distribute" — the envelopes are already funded — above a
# button that replaces the whole split. Both halves come from
# AllocationCommitter#replace_previous_distribution, so the screen cannot drift from the action.
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §5
class DistributionPresenter
  # One waterfall row, with everything the view needs already read off it.
  #
  # A snapshot rather than the live objects, and that is the whole point: every figure here is
  # measured inside the rolled-back transaction, where this period's split does not exist. A
  # view holding the Pool and asking it for a status afterwards would get an answer from the
  # ledger WITH the split back in place — half the row describing one world and half the other,
  # which is the exact confusion this screen exists to remove.
  #
  # `short` is derived rather than stored for AllocationCalculator::Row's reason: it is
  # `needed - funded` by definition, and a stored field is a second place for it to be wrong.
  Line = Data.define(:pool, :needed, :funded, :swept, :status, :period_closed, :due_on, :periods_left) do
    def short = needed - funded

    def short? = short.positive?

    def swept? = swept.positive?

    # Whether this line's own rule has a date to print. `due_on` alone is not the question:
    # PoolStatus prints a date of its own for three of its six states, and a row carrying two
    # dates from two different rules reads as a contradiction (see DistributionsHelper).
    def scheduled? = due_on.present?
  end

  # The one moment this screen describes. Built inside the transaction, read outside it.
  Snapshot = Data.define(
    :available, :income, :sweeps, :total_swept, :total_allocated, :leftover, :lines, :short, :replaced
  )

  attr_reader :user, :account, :today

  def initialize(user:, account:, today: Date.current)
    @user = user
    @account = account
    @today = today
  end

  delegate :available, :total_swept, :total_allocated, :leftover, :lines, :replaced, to: :snapshot

  # Named for the period it covers, because the buffer line beside it is a figure about a
  # different moment and this screen has already learned once (HomePresenter#current_buffer_for)
  # what happens when two money figures from two moments share a bare noun.
  def income_this_period = snapshot.income

  # The density switch, and it is chosen by the DATA, never by a setting (spec §5): all clear
  # gets a headline and one summary line, anything short gets the full waterfall with no
  # collapse. A single confirm button over a collapsed short distribution lets someone quietly
  # starve the bottom rows.
  #
  # Read off AllocationCalculator#short?, which reads its own rows — not from
  # `total_allocated < Σ needed`, which disagrees the moment a zero-need pool is rejected.
  def short? = snapshot.short

  def covered? = !short?

  # What the envelopes below the cutoff miss, summed from the rows for HomePresenter#shortfall's
  # reason: only the rows can say WHICH envelope is starved, and `needed - available` answers a
  # different question.
  def shortfall = lines.sum(0.to_d, &:short)

  # `[pool, amount]` pairs in fill order, for the sources line that names them.
  #
  # Read from AllocationCalculator#sweeps, NOT from #lines. The two sets are not the same: a
  # row is rejected when the envelope asks for nothing, and an envelope can sweep while asking
  # for nothing — a mixed envelope whose rate period has ended hands back what its dated rule
  # is not holding, and if that reserve already covers its remaining rules its ask is zero.
  # Built off the rows, such a sweep would raise Available with nothing on screen saying where
  # the money came from. Reasoned from #fill's reject and #sweepable_amount rather than
  # measured; no example below constructs that envelope.
  delegate :sweeps, to: :snapshot

  def swept_pools = sweeps.map(&:first)

  # The buffer as it stood before this period's income arrived — the left-hand side of the
  # buffer line's `$382 → $1,419`, and the first line of the sources breakdown.
  #
  # Derived by subtraction from #available so the three sources provably add up to the total
  # they are a breakdown OF. That makes `buffer_carried + income + total_swept == available` an
  # identity rather than a check, which is why no example asserts it: the examples pin the
  # three lines against figures the fixture put there, which is the only way this can be shown
  # to be right.
  #
  # It absorbs everything else that moved the account this period — an expense paid straight
  # out of the buffer lands here rather than in a line of its own. "Carried over" is therefore
  # the buffer you actually still have, not the buffer you opened the period with, and that is
  # the honest figure for a screen deciding what to hand out today.
  def buffer_carried = available - income_this_period - total_swept

  # A health marker, never a cap (spec §7.1). Zero on an account with no target set, which is
  # the shape the view suppresses the `you wanted …` clause on.
  def buffer_target = account.target_amount.to_d

  def buffer_target? = buffer_target.positive?

  # True when this period has already been distributed and confirming would REPLACE that split
  # rather than add to it. A user who cannot see that their last split is about to be discarded
  # cannot consent to it, so the screen says so — and the figures above it are already the
  # as-if-undistributed ones, which is the same fact stated in numbers.
  def redistribution? = replaced.any?

  def replaced_total = replaced.sum(0.to_d, &:amount)

  # The period being distributed, as dates, for the header. `period_containing`, not the
  # timestamp widening the queries use: this is read by a human.
  def period = @period ||= user.period_containing(today)

  private

  def snapshot = @snapshot ||= build_snapshot

  # The delete-compute-rollback that lets this screen describe an already-distributed period.
  #
  # `requires_new: true` IS THE LOAD-BEARING WORD. A plain nested `transaction` opens no
  # savepoint, so `ActiveRecord::Rollback` is swallowed by the inner block and the outer
  # transaction commits — this method would then delete the user's last split for real, on a
  # GET request, and report success. Every spec in this suite runs inside a transaction, so
  # that is not a theoretical outer.
  #
  # Everything is read INSIDE the block. AllocationCalculator is lazy and memoised, so a
  # snapshot built lazily would compute half its figures here and half after the rollback, off
  # a ledger where the split is back.
  def build_snapshot
    committer = AllocationCommitter.new(proposal)
    snapshot = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      snapshot = capture(committer.replace_previous_distribution, committer.replaced)
      raise ActiveRecord::Rollback
    end
    snapshot
  end

  # The proposal handed to the committer names the account, the user and the day; its FIGURES
  # are the ones the committer re-derives after the deletion, which is what #capture reads.
  def proposal = AllocationCalculator.new(user: user, account: account, today: today)

  def capture(fresh, replaced)
    Snapshot.new(
      available: fresh.available,
      income: account.calculator(today: today).income_within(user.period_datetimes_containing(today)),
      sweeps: fresh.sweeps.to_a,
      total_swept: fresh.total_swept,
      total_allocated: fresh.total_allocated,
      leftover: fresh.leftover,
      lines: fresh.rows.map { |row| line_for(row, fresh.sweeps) },
      short: fresh.short?,
      replaced: replaced
    )
  end

  # `sweeps.fetch(pool, 0.to_d)`, because #sweeps holds only the envelopes with something to
  # give. Keyed by the Pool record, exactly as AllocationCommitter reads it, so the amount the
  # row prints is the amount the movement will carry.
  def line_for(row, sweeps)
    pool = row.pool
    rule = next_dated_rule(pool)
    Line.new(
      pool: pool,
      needed: row.needed,
      funded: row.funded,
      swept: sweeps.fetch(pool, 0.to_d),
      status: warmed(pool.status(today: today)),
      period_closed: pool.calculator(today: today).period_closed?,
      due_on: rule&.due_date,
      periods_left: rule&.periods_until_due
    )
  end

  # A PoolStatus is lazy: it decides its state, and the balance it decides from, on first ask.
  # Handed back cold it would be asked by the VIEW, after the rollback has put this period's
  # split back — so a row's amounts would describe the undistributed period and its state the
  # distributed one. Forced here, inside the transaction, where all three of its readers memoise
  # off one balance.
  #
  # #state and #amount are not enough on their own: #due_on branches on the state and reaches a
  # different rule for three of the six, and the label prints it.
  def warmed(status)
    status.state
    status.amount
    status.due_on
    status
  end

  # The rule whose schedule the row prints: the earliest-due dated rule, with the same
  # `[due_date, -amount, id]` tie-break HomePresenter#dated_rules_for uses — `pool.budgets`
  # carries no ORDER BY, so without it two rules sharing a date could swap between page loads.
  #
  # Returns a BudgetCalculator, not a Budget, so the date and the count come from ONE object.
  # Read separately they could name different rules, and "due Mar 1 · 3 periods left" about two
  # different bills is a sentence with no true reading.
  #
  # Anchorless rules are excluded because they have no date to print — a rate envelope's ask
  # is due every period by definition, and the row says so with its rate instead.
  def next_dated_rule(pool)
    pool.budgets
      .select { |budget| budget.anchor_date.present? }
      .map { |budget| [budget, budget.calculator(today: today)] }
      .min_by { |budget, calculator| [calculator.due_date, -budget.amount, budget.id] }
      &.last
  end
end
