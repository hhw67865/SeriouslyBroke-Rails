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
  #
  # `status` holds a Standing, NOT a PoolStatus — see Standing for why that distinction is the
  # whole of this class's safety rather than a tidiness.
  #
  # `needed` IS THE USER'S FIGURE where they typed one, because the fill uses it — so `short`,
  # the cutoff marker, the unfunded total and the buffer are four views of ONE fill rather than
  # four readings of a proposal the user has already overruled. An earlier version of this class
  # kept a second `unfunded` reader measured against the un-overridden proposal, so that "ran out
  # here" could stay a fact about the account alone; the plan ruled against it, and rightly —
  # the freed money now cascades, so a cutoff computed off the old fill would sit above
  # envelopes that had just been funded by the edit.
  #
  # `proposed` is what this envelope WOULD have received had nothing been edited, taken from a
  # second fill with no overrides at all. It answers two questions and only two: how much a row
  # the user edited is moving (Consequence#moving), and what next period would have asked had
  # the proposal stood (Consequence#baseline_ask). It is NOT how the screen decides a row was
  # edited — with the money cascading, a row below an override changes its `funded` without
  # anybody typing in it, so `overridden` is carried from AllocationCalculator#overridden?
  # instead.
  Line = Data.define(
    :pool,
    :needed,
    :proposed,
    :funded,
    :overridden,
    :swept,
    :status,
    :period_closed,
    :due_on,
    :periods_left,
    :consequence,
    :redirect
  ) do
    def short = needed - funded

    def short? = short.positive?

    # The user typed in THIS box. Not `funded != proposed`, which is also true of every row the
    # cascade reached.
    def overridden? = overridden

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

  # WHERE THE MONEY WENT — the other half of an edit, and the half the cascade made necessary.
  #
  # Consequence says what an edit costs the envelope LATER. This says what the edit did to the
  # rest of the split NOW. Cutting one row re-runs the waterfall beneath it, so envelopes the
  # user never touched change their figures; unexplained, that is money moving on screen for
  # reasons the screen does not state, which is the one real objection to cascading at all.
  #
  # IT BELONGS TO THE ROW THAT WAS EDITED, never to the rows that received. A clause on each
  # recipient would be noise, would shout at rows nobody touched, and would double-count the
  # moment two rows are edited at once — each recipient would carry a share of both edits with
  # no way to tell whose it was.
  #
  # `moved` is signed: positive when the edit freed money, negative when it took more. Both
  # directions are real — an override above the proposal takes its extra out of the envelopes
  # below, and "where did my money go" has the same force asked in reverse.
  #
  # `recipients` is `[pool, amount]` in descending order of amount, holding MAGNITUDES; `buffer`
  # likewise. `|moved| == Σ recipients + buffer` is an identity of two fills over one `available`
  # and is therefore not asserted anywhere.
  Redirect = Data.define(:moved, :recipients, :buffer) do
    def freed? = moved.positive?

    # Nothing below was waiting for it. The case the plan singled out, because it is the one
    # where a user who is told nothing concludes the money vanished.
    def buffer_only? = recipients.empty?
  end

  # One fill reduced to the two things the redirect arithmetic asks of it: what each envelope
  # got, and what was left over. A value rather than a live calculator, for Line's reason — it
  # is read outside the transaction that built it.
  Fill = Data.define(:funded, :leftover) do
    def for(pool) = funded.fetch(pool.id, 0.to_d)
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
  # strings — and is NOT coerced here. It goes onto the PROPOSAL, which owns the coercion and
  # applies the figures inside its own fill; this screen then reads the fill's answer back.
  # One override path, and the thing that reads it is the thing that will write it.
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
  # `overridden?` is in the switch for a reason the other three are not: an override can make
  # the screen ALL CLEAR — type a zero into the only starved row and nothing is short any more —
  # and collapsing then takes the boxes off the screen, leaving no way to undo what was just
  # typed. An edit in progress is data too.
  def expanded? = short? || overridden? || alerts.any? || lines.any? { |line| line.status.red? }

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
  # Summed over the SAME fill the rows and the buffer come from, so cutting a high row and
  # watching the envelope below it fill up drops this figure by exactly what that envelope
  # gained. It moving is the point: a total that stayed still while the buffer grew was the
  # screen saying money could not be found while holding money that could have funded it.
  def shortfall = lines.sum(0.to_d, &:short)

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
    committer = AllocationCommitter.new(proposal)
    snapshot = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      snapshot = capture(committer.replace_previous_distribution, committer)
      raise ActiveRecord::Rollback
    end
    snapshot
  end

  # The proposal handed to the committer names the account, the user and the day; its FIGURES
  # are the ones the committer re-derives after the deletion, which is what #capture reads.
  def proposal = AllocationCalculator.new(user: user, account: account, today: today, overrides: overrides)

  # Standings are taken for EVERY envelope in the account, not only the ones with a row: the
  # density switch has to see a red pool that is asking for nothing, which by definition has no
  # row. Keyed by pool id, so a line and an alert can never disagree about how one pool is doing.
  def capture(fresh, committer)
    standings = envelopes.to_h { |pool| [pool.id, standing_for(pool)] }
    @baseline = baseline_fill(fresh)
    @live = fill_of(fresh)
    lines = fresh.rows.map { |row| line_for(row, fresh, standings) }

    snapshot_from(fresh, committer, standings, lines)
  end

  def fill_of(calculator)
    Fill.new(funded: calculator.rows.to_h { |row| [row.pool.id, row.funded] }, leftover: calculator.leftover)
  end

  # What each envelope would have received HAD NOTHING BEEN EDITED, keyed by pool id: a second
  # fill over the same post-deletion ledger, with no overrides at all.
  #
  # This is the price of the cascade, and it is worth naming. While overrides were substituted
  # after the fill, "what would have happened" was sitting right there on the row. Now that an
  # override re-runs the whole waterfall below it, the only honest way to answer is to run the
  # waterfall again without it — a row two places down can change its funding because of an
  # edit nobody made to it.
  #
  # Built ONLY when something is actually overridden (`fresh.overrides`, the coerced set, not
  # the raw params — a form submitting nothing but blanks overrides nothing). Nil otherwise, and
  # #line_for then falls back to the live fill, which is provably the same numbers.
  def baseline_fill(fresh)
    return nil if fresh.overrides.empty?

    fill_of(AllocationCalculator.new(user: user, account: fresh.account, today: today))
  end

  # The same distribution WITH ONE EDIT UNDONE — the counterfactual a redirect sentence is
  # measured against, and the only honest way to attribute a cascade to the edit that caused it.
  #
  # With a single override that is exactly the baseline fill, already built, so the ordinary case
  # costs nothing extra. With several, each edited row gets its own fill holding the OTHERS in
  # place: "what this edit did, given everything else you have typed". Comparing every edited row
  # against the untouched baseline instead would credit each of them with all the others' money.
  # `@baseline || @live` rather than a bare `@baseline`, and this is not defensive tidiness:
  # #baseline_fill is nil when nothing is overridden, and this method was safe only because its
  # caller happened to check `overridden?` first. Measured — calling it unguarded raised
  # `undefined method 'for' for nil` and took the whole screen down with a 500. With no override
  # to undo, "the same distribution with this edit undone" IS the live fill, so the fallback is
  # the right answer rather than a shrug: #redirect_for then measures zero and says nothing.
  def without_override(pool, fresh)
    return @baseline || @live if fresh.overrides.size <= 1

    fill_of(
      AllocationCalculator.new(
        user: user,
        account: fresh.account,
        today: today,
        overrides: fresh.overrides.except(pool.id.to_s)
      )
    )
  end

  # `total_allocated` and `leftover` come straight off the calculator again. They were summed
  # from the lines while the committer substituted overrides after the fill — the calculator did
  # not know about them then, so its own totals described a split nobody was going to write.
  # With the override inside the fill there is one set of figures, and taking them from anywhere
  # but their source would be the second reader all over again.
  def snapshot_from(fresh, committer, standings, lines)
    Snapshot.new(
      available: fresh.available,
      carried: opening_buffer(fresh),
      income: income_this_period_from(fresh),
      sweeps: fresh.sweeps.to_a,
      total_swept: fresh.total_swept,
      total_allocated: fresh.total_allocated,
      leftover: fresh.leftover,
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
  def line_for(row, fresh, standings)
    pool = row.pool
    swept = fresh.sweeps.fetch(pool, 0.to_d)
    proposed = (@baseline || @live).for(pool)
    overridden = fresh.overridden?(pool)

    Line.new(
      pool: pool,
      needed: row.needed,
      proposed: proposed,
      funded: row.funded,
      overridden: overridden,
      swept: swept,
      # LEFT AS THE STANDING TODAY, deliberately, and a red label beside a funded box is not the
      # contradiction it looks like: today the money genuinely has not moved. With the redirect
      # sentence below it naming what this distribution is about to do, the row reads "here is
      # where you stand, and this split fixes it" — which is the sentence the screen is for. Do
      # not "fix" this by projecting the status; the projection already exists, on the row that
      # was edited, as Consequence#standing.
      status: standings.fetch(pool.id),
      period_closed: pool.calculator(today: today).period_closed?,
      # Both sentences are only ever computed for a row the USER typed in. The cascade moves the
      # funding of rows below an override without anybody editing them, and "you're moving $200
      # onto your next period" about a row the waterfall reached on its own names the wrong
      # actor — the edit that caused it is two rows up, and it says so there.
      consequence: overridden ? consequence_for(pool, row.funded, proposed, swept) : nil,
      redirect: overridden ? redirect_for(pool, fresh) : nil,
      **schedule_for(pool)
    )
  end

  # What this one edit did to everything else, or nil when it moved nothing — which is the
  # ordinary shape of an override the account could not honour (ask $350 with $185 left and the
  # row still receives $185, so no other row and no buffer figure changes).
  def redirect_for(pool, fresh)
    without = without_override(pool, fresh)
    moved = without.for(pool) - @live.for(pool)
    return nil if moved.zero?

    Redirect.new(
      moved: moved,
      recipients: recipients_of(pool, fresh, without, moved),
      buffer: (@live.leftover - without.leftover) * (moved.positive? ? 1 : -1)
    )
  end

  # The other rows this edit moved money to (or took it from), largest first. Signs are folded
  # away here rather than in the view: a row that GAINED when the edit freed money and a row that
  # LOST when the edit took more are the same sentence with one preposition changed, and the copy
  # should not have to know which.
  def recipients_of(pool, fresh, without, moved)
    direction = moved.positive? ? 1 : -1

    fresh.rows
      .reject { |row| row.pool.id == pool.id }
      .map { |row| [row.pool, (@live.for(row.pool) - without.for(row.pool)) * direction] }
      .select { |_recipient, amount| amount.positive? }
      .sort_by { |_recipient, amount| -amount }
  end

  # The row's own schedule clause, as the two members that carry it. Split out only because
  # #line_for was over rubocop's ABC limit; the pair travels together because they come from
  # ONE rule (see #next_dated_rule) and reading them apart is how a row ends up naming two bills.
  def schedule_for(pool)
    rule = next_dated_rule(pool)

    { due_on: rule&.due_date, periods_left: rule&.periods_until_due }
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
  # Only ever called for a row the user typed in (see #line_for), and nil again when the money
  # that reaches the envelope is unchanged — which is the ordinary shape of an override the
  # account could not honour: type $350 with $185 of cash left and the row still receives $185,
  # so nothing downstream moves and there is nothing to say. The row says the rest itself, in
  # red, as `$185.00 of $350.00`.
  def consequence_for(pool, funded, proposed, swept)
    return nil if funded == proposed

    consequence = build_consequence(pool, pending(funded, swept), pending(proposed, swept))
    consequence if consequence.worth_saying?
  end

  def build_consequence(pool, chosen, baseline)
    rule = next_dated_rule(pool, on: next_period_start)
    Consequence.new(
      moving: baseline.funded - chosen.funded,
      next_ask: projected_ask(pool, chosen),
      baseline_ask: projected_ask(pool, baseline),
      opens_on: next_period_start,
      due_on: rule&.due_date,
      periods_left: rule&.periods_until_due,
      standing: standing_for(pool, pending: chosen)
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
