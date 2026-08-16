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
  # `short` and `unfunded` are both derived rather than stored, for AllocationCalculator::Row's
  # reason: each is a subtraction of two members that are already here, and a stored field is a
  # second place for the same number to be wrong.
  #
  # `status` holds a Standing, NOT a PoolStatus — see Standing for why that distinction is the
  # whole of this class's safety rather than a tidiness.
  #
  # `proposed` is what the WATERFALL would hand this envelope; `funded` is what it will actually
  # get once the user's override is applied, and with no override the two are the same number.
  # Both are kept because the screen asks two different questions of them and answering either
  # with the other tells a lie:
  #
  #   #unfunded (needed − proposed) is WHAT THE CASH COULD NOT COVER. It is what the cutoff line
  #   is about — "ran out here" is a fact about the account running dry, and folding the user's
  #   own edits into it would blame the bank for a choice the user made two rows up.
  #
  #   #short (needed − funded) is WHAT THIS ENVELOPE ENDS UP MISSING, which is what its own row
  #   has to say and what its consequence line is computed from.
  #
  # Both are clamped at zero rather than left signed. Under the proposal alone `funded` can
  # never exceed `needed` (#fill clamps it), so the clamp is a no-op on an untouched screen —
  # but an override CAN exceed it, and a signed #short would let one over-funded envelope
  # cancel another envelope's shortfall inside #shortfall's sum, reporting an account that
  # covered everything while a row below it got nothing.
  Line = Data.define(
    :pool,
    :needed,
    :proposed,
    :funded,
    :swept,
    :status,
    :period_closed,
    :due_on,
    :periods_left,
    :consequence
  ) do
    def short = [needed - funded, 0.to_d].max

    def short? = short.positive?

    def unfunded = [needed - proposed, 0.to_d].max

    # Whether the user typed something different into this row's box. Compared by VALUE, so a
    # box submitted with exactly the proposal's own figure in it — which is what every
    # untouched box submits, because the screen renders the proposal into it — is correctly not
    # an override, and no consequence is computed for it.
    def overridden? = funded != proposed

    def swept? = swept.positive?

    # Whether this line's own rule has a date to print. `due_on` alone is not the question:
    # two of PoolStatus's six states print a date of their own, and a row carrying two dates from
    # two different rules reads as a contradiction (see DistributionsHelper::DATED_STATES).
    def scheduled? = due_on.present?
  end

  # A PoolStatus reduced to the four values its label is made of, read inside the transaction.
  #
  # This replaced handing the live PoolStatus to the view, and the reason is worth stating
  # exactly, because the thing it replaced LOOKED safe. PoolStatus memoises `#state` and nothing
  # else: `#amount` and `#due_on` are plain `case` expressions that re-execute on every call, so
  # a "warmed" status handed to a view still ran real work after the rollback — on the
  # :overdue/:wont_make_it branches, a live SQL SUM. That happened to be safe only because those
  # branches read `entries`, which the rollback did not touch, while the rows it DID restore are
  # `pool_movements`. Safety by coincidence in another class's internals: a seventh state, or a
  # future `#amount` branch reaching `allocated_balances` outside a memo, would silently produce
  # the half-row defect this whole snapshot exists to prevent, and no test would catch it.
  #
  # Values cannot re-execute. The four readers are exactly what `HomeHelper#pool_status_label`
  # and `#saving_label` ask for, so the row keeps the app's one row vocabulary (spec §4.4) rather
  # than growing a second copy of it here.
  # The two states this app draws in red, and the reason the screen refuses to collapse (spec §5).
  # Deliberately NOT :behind — amber, common, and including it would collapse the two-density
  # design into one. The same two states DistributionsHelper::DATED_STATES names, for a different
  # reason: these are the labels that carry their own date, and they are red because a date that
  # has passed or cannot be reached is the app's loudest fact.
  RED_STATES = [:overdue, :wont_make_it].freeze

  Standing = Data.define(:state, :amount, :due_on, :target) do
    def red? = RED_STATES.include?(state)
  end

  # WHAT AN OVERRIDE COSTS YOU LATER — the sentence this screen exists to be able to say, and
  # the only thing on it that is about a period other than this one.
  #
  # `next_ask` and `baseline_ask` are both REAL RECOMPUTATIONS at the next period's opening
  # date: what the row will ask for having been funded the user's figure, against what it would
  # have asked for having been funded the proposal's. They are NOT `baseline + shortfall`, and
  # the two coincide only when one period remains — $300 underfunded with three periods left is
  # $100 a period, not $300, and a subtraction would overstate it by triple.
  #
  # `standing` is the pool's OWN status (PoolStatus, through Standing) taken as of TODAY with
  # the override's money already in the envelope: "would this envelope still make it". Today
  # rather than next period, because :wont_make_it asks whether any boundary is left between
  # tomorrow and the due date, and the distribution being edited is the one happening now.
  #
  # `opens_on` is the date the sentence names ("Feb 20 will need …"), `due_on`/`periods_left`
  # come from the rule as it will stand THEN, so "it's the last period before Mar 1" is read off
  # the projection rather than asserted about it.
  Consequence = Data.define(:moving, :next_ask, :baseline_ask, :opens_on, :due_on, :periods_left, :standing) do
    # The gate, and the whole of it: state the consequence ONLY when the per-period ask actually
    # changes (spec §5). A dateless goal funds at a fixed rate, so underfunding it once leaves
    # next period's rate exactly where it was and this is false — and so is a rate envelope,
    # whose leftover is swept back and topped up to the full rate again regardless.
    #
    # OR unrecoverable, because an envelope that can no longer make its date is a consequence
    # even in the arithmetic corner where the next ask happens to land on the same figure.
    def worth_saying? = next_ask != baseline_ask || unrecoverable?

    # The one red case (spec §5, amendment C): the override left the envelope unable to recover,
    # which is :wont_make_it — a state PoolStatus already produces, in the red the app already
    # draws it in. Not a new state and not a new colour; read off #standing rather than
    # re-derived here, so the sentence and the row label can never disagree.
    def unrecoverable? = standing.state == :wont_make_it

    # Money pushed onto later periods (positive) or covered early (negative). Signed rather
    # than two members: it is one subtraction, and a second field would be a second place for
    # its sign to be wrong.
    def moving_later? = moving.positive?

    # "…the last period before Mar 1", and only when that is true of the projection. The date
    # guard is not decoration: `periods_until_due` floors at 1, so a bill already past its due
    # date by the time the next period opens also reports one period left, and saying "the last
    # period before Mar 1" about a date that has already gone is the opposite of the truth.
    def last_period? = periods_left == 1 && due_on.present? && due_on >= opens_on
  end

  # The one moment this screen describes. Built inside the transaction, read outside it.
  Snapshot = Data.define(
    :available,
    :carried,
    :income,
    :sweeps,
    :total_swept,
    :total_allocated,
    :leftover,
    :lines,
    :short,
    :replaced,
    :alerts
  )

  attr_reader :user, :account, :today, :overrides

  # `overrides` arrives exactly as the form submitted it — `{pool_id => amount}`, both sides
  # strings — and is NOT coerced here. It is handed straight to AllocationCommitter, which
  # already owns the coercion and already owns the "override or the proposal's own figure"
  # decision (#amount_for), and this screen reads its answer back. One override path, and the
  # thing that reads it is the thing that will write it.
  def initialize(user:, account:, today: Date.current, overrides: {})
    @user = user
    @account = account
    @today = today
    @overrides = overrides
  end

  delegate :available, :total_swept, :total_allocated, :leftover, :lines, :replaced, to: :snapshot

  # Named for the period it covers, because the buffer line beside it is a figure about a
  # different moment and this screen has already learned once (HomePresenter#current_buffer_for)
  # what happens when two money figures from two moments share a bare noun.
  def income_this_period = snapshot.income

  # Read off AllocationCalculator#short?, which reads its own rows — not from
  # `total_allocated < Σ needed`, which disagrees the moment a zero-need pool is rejected.
  def short? = snapshot.short

  def covered? = !short?

  # THE DENSITY SWITCH, chosen by the DATA and never by a setting (spec §5): all clear gets a
  # headline and one summary line, anything short OR OVERDUE gets the full waterfall with no
  # collapse. A single confirm button over a collapsed distribution lets someone quietly starve
  # the bottom rows — or, on the overdue half, tells them everything is fine over a bill that is
  # already late.
  #
  # "Or overdue" is the spec's own wording and it is not decoration: an overdue bill whose
  # envelope ALREADY HOLDS the money asks for nothing, so it is rejected from #rows, so a
  # short-only switch collapses the screen and never mentions it. That is the one shape where
  # the money is fine and the user is not.
  #
  # `alerts` as well as the rows, for exactly that reason: the trigger has to see the pools that
  # have no row, or it cannot fire on the case that motivates it.
  def expanded? = short? || alerts.any? || lines.any? { |line| line.status.red? }

  # Red-state envelopes with NO row of their own — the ones #expanded? exists for, and the ones
  # nothing else on this screen can say. A red pool that HAS a row is already named by that row's
  # own detail line, so listing it here would print the same problem twice.
  #
  # `[pool, standing]` pairs, in the account's fill order.
  delegate :alerts, to: :snapshot

  # What the envelopes below the cutoff miss, summed from the rows for HomePresenter#shortfall's
  # reason: only the rows can say WHICH envelope is starved, and `needed - available` answers a
  # different question.
  #
  # #unfunded, NOT #short: this figure sits on the cutoff line and in the waterfall's header,
  # both of which are sentences about the account running out of money. An override is not the
  # account running out of money — it is the user choosing — so the user's edits stay out of
  # this number and appear on their own row's consequence line and in the buffer figure instead.
  def shortfall = lines.sum(0.to_d, &:unfunded)

  # True on any row the user has actually changed. The screen says so once, above the table,
  # rather than per row: the edited rows already carry their own consequence line, and a screen
  # that never mentions the edits at all after a reload reads as if they had been discarded.
  def overridden? = lines.any?(&:overridden?)

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

  # What the account actually held the moment this period opened — the left-hand side of the
  # buffer line's `$382 → $1,419`, and the first line of the sources breakdown.
  #
  # MEASURED with an `as_of` balance, not derived by subtracting the other lines from #available.
  # It was derived at first, which made the breakdown add up by construction and made this line
  # a bin for everything the other lines did not name: on the demo account it printed
  # "Buffer carried over -$2,270.00" over an account holding $330, because $2,000 of envelope
  # funding and spending that happened DURING the period had nowhere else to go. A figure whose
  # only guarantee is that it makes the column add up is not an answer to "where did this money
  # come from", which is the one question this band exists for.
  #
  # #moved_this_period is now the residual instead, and it is named as one.
  def buffer_carried = snapshot.carried

  # Everything else that moved the account inside this period: money spent straight out of the
  # buffer, and reallocations the user made by hand. Signed — a manual transfer back INTO the
  # account is positive — and the view drops the line when it is zero, which is the ordinary
  # shape of a period whose distribution has not been touched since it was written.
  #
  # This is the derived line, so `carried + income + moved + swept == available` is an identity
  # and no example asserts it. The other three are pinned against figures their fixture put
  # there; this one is pinned by its own cause (a $300 expense inside the period).
  #
  # An allocation written by a PREVIOUS confirm of this same period is NOT here: the snapshot is
  # taken after those rows are deleted, so a period that has been distributed reads exactly as it
  # did before, which is what the rest of this screen promises.
  def moved_this_period = available - buffer_carried - income_this_period - total_swept

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
    committer = AllocationCommitter.new(proposal, overrides: overrides)
    snapshot = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      snapshot = capture(committer.replace_previous_distribution, committer)
      raise ActiveRecord::Rollback
    end
    snapshot
  end

  # The proposal handed to the committer names the account, the user and the day; its FIGURES
  # are the ones the committer re-derives after the deletion, which is what #capture reads.
  def proposal = AllocationCalculator.new(user: user, account: account, today: today)

  # Standings are taken for EVERY envelope in the account, not only the ones with a row: the
  # density switch has to see a red pool that is asking for nothing, which by definition has no
  # row. Keyed by pool id, so a line and an alert can never disagree about how one pool is doing.
  def capture(fresh, committer)
    standings = envelopes.to_h { |pool| [pool.id, standing_for(pool)] }
    lines = fresh.rows.map { |row| line_for(row, fresh.sweeps, standings, committer) }

    snapshot_from(fresh, committer, standings, lines)
  end

  # `total_allocated` and `leftover` are summed from the LINES rather than read off the
  # calculator's own #total_allocated / #leftover, because the calculator does not know about
  # the overrides and those two figures are the ones that have to match the ledger the confirm
  # will write. The account ends the distribution holding `available − Σ allocations`, and every
  # allocation is AllocationCommitter#amount_for's answer — so summing the same answers is the
  # only way `Σ pools == your bank balance` can be shown on screen before it is written.
  #
  # They agree with the calculator's own figures exactly when nothing is overridden, which is
  # every screen Task 4 pinned.
  def snapshot_from(fresh, committer, standings, lines)
    allocated = lines.sum(0.to_d, &:funded)
    Snapshot.new(
      available: fresh.available,
      carried: opening_buffer(fresh),
      income: income_this_period_from(fresh),
      sweeps: fresh.sweeps.to_a,
      total_swept: fresh.total_swept,
      total_allocated: allocated,
      leftover: fresh.available - allocated,
      lines: lines,
      short: fresh.short?,
      replaced: committer.replaced,
      alerts: alerts_from(standings, lines)
    )
  end

  # A fresh calculator over the account, not the proposal's own: `fresh` names the account this
  # figure belongs to, and its internal account calculator is private. Movements are what the
  # rollback restores and this reads `entries`, so it is stable either way — it is captured in
  # here anyway so that every figure on the screen comes from one moment rather than most of them.
  def income_this_period_from(fresh)
    fresh.account.calculator(today: today).income_within(period_timestamps)
  end

  # The account's balance the instant before this period opened, through PoolCalculator's own
  # `as_of` rather than a query of its own — one definition of "what this pool holds", asked
  # about an earlier moment.
  #
  # INSIDE the transaction, and here it matters: `as_of` bounds the movement query by date, not
  # by kind, so a distribution written earlier in this same period would otherwise be included
  # or not depending on when the caller asked. Taken here, it is measured against the same
  # deleted ledger as everything else on the screen.
  #
  # `- 1.second`, because the period range starts at midnight and `as_of` is inclusive: bounded
  # at the period's own first instant, a movement stamped exactly midnight would count as both
  # carried over and moved this period.
  def opening_buffer(fresh)
    fresh.account.calculator(as_of: period_timestamps.first - 1.second, today: today).balance
  end

  def period_timestamps = @period_timestamps ||= user.period_datetimes_containing(today)

  # The account's envelopes in the order the money reaches them — the same one-line scope
  # AllocationCalculator#envelopes reads, so the two lists cannot fall into different orders.
  def envelopes = account.child_pools.by_priority.to_a

  # Red pools MINUS the ones that already have a row. Matched by pool id rather than by record so
  # the two collections need not be the same objects.
  def alerts_from(standings, lines)
    with_rows = lines.to_set { |line| line.pool.id }
    envelopes
      .reject { |pool| with_rows.include?(pool.id) }
      .filter_map { |pool| [pool, standings.fetch(pool.id)] if standings.fetch(pool.id).red? }
  end

  # `sweeps.fetch(pool, 0.to_d)`, because #sweeps holds only the envelopes with something to
  # give. Keyed by the Pool record, exactly as AllocationCommitter reads it, so the amount the
  # row prints is the amount the movement will carry.
  def line_for(row, sweeps, standings, committer)
    pool = row.pool
    rule = next_dated_rule(pool)
    swept = sweeps.fetch(pool, 0.to_d)
    funded = committer.amount_for(row)
    Line.new(
      pool: pool,
      needed: row.needed,
      proposed: row.funded,
      funded: funded,
      swept: swept,
      status: standings.fetch(pool.id),
      period_closed: pool.calculator(today: today).period_closed?,
      due_on: rule&.due_date,
      periods_left: rule&.periods_until_due,
      consequence: consequence_for(row, funded, swept)
    )
  end

  # A PoolStatus, read down to values while the transaction is still open. See Standing: the
  # readers below are `case` expressions rather than memos, so anything that calls them later
  # calls them against a ledger where this period's split is back.
  #
  # `pending:` is how the SAME reader answers the projected question. There is one
  # definition of how a pool is doing in this app and this is it; the override case differs only
  # in which balance it is asked about.
  def standing_for(pool, pending: PoolCalculator::Pending.none)
    status = pool.status(today: today, pending: pending)

    Standing.new(state: status.state, amount: status.amount, due_on: status.due_on, target: status.target)
  end

  # The consequence of one override, or nil — nil both when the user changed nothing and when
  # what they changed moves nothing downstream. See Consequence#worth_saying?: a screen that
  # always prints a line and a screen that never prints one are equally wrong, and the gate
  # between them is a comparison of two real recomputations.
  #
  # `pending` is THIS DISTRIBUTION'S WHOLE EFFECT on the envelope — the allocation in, less the
  # sweep out. Both halves matter: the sweep is written by the same confirm, so a projection
  # that added the funding without removing the leftover would credit the envelope with money
  # it is about to hand back.
  def consequence_for(row, funded, swept)
    return nil if funded == row.funded

    consequence = build_consequence(row, pending(funded, swept), pending(row.funded, swept))
    consequence if consequence.worth_saying?
  end

  def build_consequence(row, chosen, baseline)
    rule = next_dated_rule(row.pool, on: next_period_start)
    Consequence.new(
      moving: baseline.funded - chosen.funded,
      next_ask: projected_ask(row.pool, chosen),
      baseline_ask: projected_ask(row.pool, baseline),
      opens_on: next_period_start,
      due_on: rule&.due_date,
      periods_left: rule&.periods_until_due,
      standing: standing_for(row.pool, pending: chosen)
    )
  end

  # The two movements this distribution would put through one pool, dated the day it happens.
  # Built here rather than inside PoolCalculator because only this class knows which of them the
  # confirm is actually going to write: `funded` is AllocationCommitter#amount_for's answer and
  # `swept` is AllocationCalculator#sweeps'.
  def pending(funded, swept) = PoolCalculator::Pending.new(funded: funded, swept: swept, on: today)

  # What this envelope will ask for at the START OF THE NEXT PERIOD, having had `pending` moved
  # through it by the distribution on screen.
  #
  # PoolCalculator#required, which is the SAME reader AllocationCalculator#fill uses to compute
  # this period's `needed` — so "will need $800 instead of $500" is the row's own figure asked
  # about a later day, not a second definition of an ask. It divides by
  # BudgetCalculator#periods_until_due, which is what makes an underfunding spread across the
  # periods that remain rather than landing whole on the next one.
  #
  # `net_of_sweep: true` for AllocationCalculator#ask_calculator_for's reason, and it is
  # load-bearing here in a way that is easy to miss: a rate envelope's leftover is swept back at
  # the next distribution and the envelope is topped up to its full rate again, so underfunding
  # it now changes NOTHING about next period's ask. Without the flag the projection would report
  # a well-funded rate envelope as asking for nothing and print a consequence on every one of
  # them.
  def projected_ask(pool, pending)
    pool.calculator(today: next_period_start, net_of_sweep: true, pending: pending).required
  end

  # The day the next period opens, off User#period_containing rather than a cadence of its own —
  # the same reader the header prints, so the date in the sentence and the date in the subtitle
  # cannot name different periods.
  def next_period_start = @next_period_start ||= period.last + 1

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
  #
  # `on:` is the day the schedule is read from, defaulting to the day being distributed. The
  # consequence line asks for it as of the NEXT period's opening, because both the date it names
  # and the count of periods behind "it's the last period before Mar 1" are statements about
  # where the rule will stand then — and a recurring rule's #due_date rolls, so asking today
  # and reporting it as next period's would be a different bill.
  def next_dated_rule(pool, on: today)
    pool.budgets
      .select { |budget| budget.anchor_date.present? }
      .map { |budget| [budget, budget.calculator(today: on)] }
      .min_by { |budget, calculator| [calculator.due_date, -budget.amount, budget.id] }
      &.last
  end
end
