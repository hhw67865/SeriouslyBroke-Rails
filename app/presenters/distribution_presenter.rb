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
  # THERE IS DELIBERATELY NO `proposed` MEMBER. The row briefly carried what this envelope would
  # have received had nothing been edited at all, and it was a trap rather than a fact: it is the
  # obvious thing to measure an edit against and it is the WRONG thing, because two rows edited at
  # once each have to answer for their own money and not for the other's. Both sentences compare
  # against #without_override — this distribution with one edit undone and the others left in
  # place — and #consequence_for records the contradiction the untouched figure produced. Once
  # both had moved, nothing read the member; it is gone rather than left as a second answer
  # waiting to be picked up.
  #
  # `overridden` is likewise NOT `funded != <anything>`: with the money cascading, a row below an
  # override changes its funding without anybody typing in it, so it is carried from
  # AllocationCalculator#overridden?.
  Line = Data.define(
    :pool,
    :needed,
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
  # ONE EDIT PUTS IT ON ITS ROW; TWO OR MORE GET A SINGLE LINE ABOVE THE TABLE, and that split is
  # the whole design rather than a presentation choice.
  #
  # A per-row sentence is measured against #without_override — this split with that one edit
  # undone — which is exactly right for one edit and DOES NOT COMPOSE. Two per-row answers are
  # each true in isolation and do not sum, which is the one thing a money screen may not do:
  #
  #   they OVERSTATE the buffer, because each row's share is measured against a different
  #   counterfactual and the residual overlaps — two rows honestly claiming $300 apiece of a
  #   buffer that moved $500;
  #
  #   and they UNDERSTATE the envelopes, which is worse because it is silent. Where either edit
  #   ALONE would have funded a row, both per-row deltas compute to zero and that row is named by
  #   nobody, while it visibly gains money on the same screen. Two edits with an unfunded row
  #   below them is this feature's central case, not a corner.
  #
  # The aggregate is computed ONCE against the untouched proposal: one decomposition, one
  # baseline, `|moved| == Σ recipients + buffer` guaranteed, and every recipient named exactly
  # once whether one edit funded it or three did between them.
  #
  # `moved` is signed: positive when the edits freed money on net, negative when they took more.
  # Both directions are real — an override above the proposal takes its extra out of the
  # envelopes below, and "where did my money go" has the same force asked in reverse.
  #
  # `recipients` is `[pool, amount]` in descending order of amount, holding MAGNITUDES; `buffer`
  # likewise. The identity is asserted against the SCREEN's own before-and-after figures rather
  # than against itself, which would be `x == x`.
  Redirect = Data.define(:moved, :sources, :recipients, :buffer, :aggregate) do
    def freed? = moved.positive?

    # Edits that CANCEL on net. Nothing left the group, so neither "freed" nor "took" is true and
    # there is no lead figure to state — but money still went from one envelope to another, and
    # the line that exists to say where money went may not fall silent on the one screen where
    # the user has just reshuffled their budget. `sources` is populated only here, and only here
    # do the two lists name both ends of the same movement.
    def shifted? = moved.zero?

    # What the sentence leads with. For a shift there is no net, so the figure is the total that
    # changed hands — which is the sum of either side, and they are equal by construction.
    def total = shifted? ? recipients.sum(0.to_d, &:last) : moved.abs

    # Nothing below was waiting for it. The case the plan singled out, because it is the one
    # where a user who is told nothing concludes the money vanished.
    def buffer_only? = recipients.empty?

    def buffer? = buffer.positive?

    def aggregate? = aggregate
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
    :alerts,
    :redirect
  )

  attr_reader :user, :account, :today, :overrides

  # `overrides` arrives exactly as the form submitted it — `{pool_id => amount}`, both sides
  # strings — and is NOT coerced here. It goes onto the PROPOSAL, which owns the coercion and
  # applies the figures inside its own fill; this screen then reads the fill's answer back.
  # One override path, and the thing that reads it is the thing that will write it.
  # `expanded:` is the user ASKING for the full table on a period that does not need it. The
  # all-clear density renders no rows at all (spec §5: headline, one line, one button), which is
  # right — and it also leaves someone who simply wants to put more into savings on a comfortable
  # period with nothing to type in. One more term in the density switch, not a second screen.
  def initialize(user:, account:, today: Date.current, overrides: {}, expanded: false)
    @user = user
    @account = account
    @today = today
    @overrides = overrides
    @expanded = expanded
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
  # `overridden?` is in the switch for a reason the data terms are not: an override can make the
  # screen ALL CLEAR — type a zero into the only starved row and nothing is short any more — and
  # collapsing then takes the boxes off the screen, leaving no way to undo what was just typed.
  # An edit in progress is data too.
  #
  # `@expanded` is the one term that is not data at all: it is the user asking. Spec §5 chooses
  # the density by the DATA and never by a setting, and this does not break that rule — nothing
  # is remembered, nothing is stored, and a fresh visit collapses again. It only answers the gap
  # the two-density design leaves: a comfortable period renders no rows, so there is nothing to
  # type in even when the user wants to put more into savings.
  def expanded? = @expanded || short? || overridden? || needs_attention?

  # Something below is genuinely wrong: a red pool with no row of its own, or a row in a red
  # state. Named because the header has to tell it apart from the two OTHER reasons the table can
  # be open — the user asking, and the user's own edit — which are not problems and must not be
  # described as one.
  def needs_attention? = alerts.any? || lines.any? { |line| line.status.red? }

  # Whether the user ASKED for the table, as opposed to the data having demanded it. A different
  # question from #expanded? and read in one place only: the form carries it forward, so clearing
  # the last edit on a comfortable period does not collapse the table out from under the boxes.
  def expand_requested? = @expanded

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

  # WHERE THE MONEY RAN OUT, or nil when nothing is short. One rule, shared with Home's band
  # (Waterfall.cutoff); only the gate is this screen's, and it is the simple one — a distribution
  # is scoped to one account by definition, so there is no per-account caveat here.
  #
  # Read off the SAME fill as everything else on this card. An override re-runs the waterfall
  # below it, so the money genuinely does reach further down when a high row is cut — a cutoff
  # computed against the un-overridden proposal would sit above envelopes the edit had just
  # funded, and the unfunded total beside it would refuse to move while the buffer grew.
  #
  # `nil` unless something is actually short: with every envelope funded the index finds nothing,
  # falls back to the row count and draws "ran out here · $0.00 unfunded" under the last row of a
  # screen where nothing ran out — which is what this table renders whenever an overdue bill
  # opens it on a covered period.
  def cutoff
    return nil unless short?

    Waterfall.cutoff(lines) { |line| [line.funded, line.short] }
  end

  # True on any row the user has actually changed. The screen says so once, above the table,
  # rather than per row: the edited rows already carry their own consequence line, and a screen
  # that never mentions the edits at all after a reload reads as if they had been discarded.
  def overridden? = lines.any?(&:overridden?)

  # The aggregate destination sentence, or nil when fewer than two rows were edited (the row
  # carries its own then) or when the edits cancelled out. See Redirect.
  delegate :redirect, to: :snapshot

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
    edited = fresh.rows.select { |row| fresh.overridden?(row.pool) }
    lines = fresh.rows.map { |row| line_for(row, fresh, standings, edited.size) }

    snapshot_from(fresh, committer, standings, lines, aggregate_redirect(fresh, edited))
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
  #
  # MEMOISED PER POOL. It used to be called twice for every edited row — once by the consequence
  # and once by the destination sentence — so N edits cost 2N extra fills, each a full pass over
  # every envelope. The destination sentence no longer calls it at all (with two or more edits it
  # is the aggregate, which reads @baseline), so the memo is what holds the cost at ONE fill per
  # edited row rather than at whatever the next caller happens to make it.
  #
  # `@baseline || @live` rather than a bare `@baseline`, and this is not defensive tidiness:
  # #baseline_fill is nil when nothing is overridden, and this method was safe only because its
  # caller happened to check `overridden?` first. Measured — calling it unguarded raised
  # `undefined method 'for' for nil` and took the whole screen down with a 500. With no override
  # to undo, "the same distribution with this edit undone" IS the live fill, so the fallback is
  # the right answer rather than a shrug: #redirect_for then measures zero and says nothing.
  def without_override(pool, fresh)
    return @baseline || @live if fresh.overrides.size <= 1

    (@without ||= {})[pool.id] ||= fill_of(
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
  def snapshot_from(fresh, committer, standings, lines, redirect)
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
      alerts: alerts_from(standings, lines),
      redirect: redirect
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
  def line_for(row, fresh, standings, edits)
    pool = row.pool
    swept = fresh.sweeps.fetch(pool, 0.to_d)
    overridden = fresh.overridden?(pool)

    Line.new(
      pool: pool,
      needed: row.needed,
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
      period_closed: pool.calculator(today: today, terms: ledger.terms_for(pool)).period_closed?,
      # Both sentences are only ever computed for a row the USER typed in. The cascade moves the
      # funding of rows below an override without anybody editing them, and "you're moving $200
      # onto your next period" about a row the waterfall reached on its own names the wrong
      # actor — the edit that caused it is two rows up, and it says so there.
      consequence: overridden ? consequence_for(pool, row.funded, fresh, swept) : nil,
      # ONE EDIT ONLY. With two or more the destination sentence moves above the table as a
      # single aggregate (see Redirect): two per-row decompositions do not sum, and showing both
      # forms at once would put three descriptions of one movement on one screen. The consequence
      # line stays per row either way — it is about what THIS row's edit costs THIS envelope
      # later, which is per-row by nature and composes fine.
      redirect: overridden && edits == 1 ? redirect_for(pool, fresh) : nil,
      **schedule_for(pool)
    )
  end

  # What this one edit did to everything else, or nil when it moved nothing — which is the
  # ordinary shape of an override the account could not honour (ask $350 with $185 left and the
  # row still receives $185, so no other row and no buffer figure changes).
  def redirect_for(pool, fresh)
    without = without_override(pool, fresh)

    build_redirect(
      without.for(pool) - @live.for(pool),
      fresh.rows.reject { |row| row.pool.id == pool.id },
      without,
      aggregate: false
    )
  end

  # EVERY EDIT AT ONCE, against the untouched proposal — the only baseline against which a
  # decomposition is guaranteed to sum. `moved` is what the edited rows gave up between them;
  # every other row's change and the buffer's are what became of it, and the three are the same
  # subtraction rearranged rather than three independent measurements.
  #
  # Keyed off the edited ROWS and not off `overrides.size`, which counts an override naming a
  # pool the proposal has no row for — a hand-built URL would otherwise switch a single-edit
  # screen to the aggregate form and take the row's own sentence away.
  def aggregate_redirect(fresh, edited)
    return nil if edited.size < 2

    moved = edited.sum(0.to_d) { |row| @baseline.for(row.pool) - @live.for(row.pool) }
    return shifted_redirect(fresh) if moved.zero?

    build_redirect(moved, untouched_rows(fresh, edited), @baseline, aggregate: true)
  end

  # The rows nobody typed in. In the freed/taken modes the edited rows are the source and the
  # lead names their total, so listing them again as destinations would say the same money twice.
  def untouched_rows(fresh, edited)
    edited_ids = edited.to_set { |row| row.pool.id }

    fresh.rows.reject { |row| edited_ids.include?(row.pool.id) }
  end

  # `moved.zero?` is nil HERE and only here — one row whose funding the account could not change
  # (ask $350 with $185 left and the row still receives $185) has changed nothing below it either,
  # because `remaining` leaves it exactly as it arrived. The aggregate's zero means something
  # entirely different and is handled by #shifted_redirect.
  def build_redirect(moved, others, without, aggregate:)
    return nil if moved.zero?

    direction = moved.positive? ? 1 : -1
    Redirect.new(
      moved: moved,
      sources: [],
      recipients: recipients_of(others, without, direction),
      buffer: (@live.leftover - without.leftover) * direction,
      aggregate: aggregate
    )
  end

  # EDITS THAT CANCEL ON NET — cut Groceries $300 and raise Rent $300 and nothing left the group,
  # so the net is zero while $300 has plainly moved between two envelopes.
  #
  # The gate was on the wrong quantity. What decides whether there is anything to say is whether
  # ANY row's funding differs from the untouched proposal, not whether the net is non-zero — and
  # measured on the net, this screen went silent at exactly the moment a user had reshuffled their
  # budget. Same decomposition as the other two modes, read in both directions: the negative
  # deltas are where the money came from and the positive ones are where it went.
  #
  # EVERY row, not only the un-edited ones, because in this mode both ends are usually rows the
  # user typed in. The buffer joins the lists as a `nil` pool rather than staying a member of its
  # own: here it is one party among several rather than the residual, and it has to be able to
  # appear on either side.
  def shifted_redirect(fresh)
    deltas = shift_deltas(fresh)
    recipients = largest_first(deltas.select { |_party, delta| delta.positive? })
    return nil if recipients.empty?

    Redirect.new(
      moved: 0.to_d,
      sources: largest_first(deltas.filter_map { |party, delta| [party, -delta] if delta.negative? }),
      recipients: recipients,
      buffer: 0.to_d,
      aggregate: true
    )
  end

  # Every party to the split against the untouched proposal, the buffer included as a `nil` pool.
  def shift_deltas(fresh)
    fresh.rows.map { |row| [row.pool, @live.for(row.pool) - @baseline.for(row.pool)] } +
      [[nil, @live.leftover - @baseline.leftover]]
  end

  def largest_first(parties) = parties.sort_by { |_party, amount| -amount }

  # The other rows this edit moved money to (or took it from), largest first. Signs are folded
  # away here rather than in the view: a row that GAINED when the edit freed money and a row that
  # LOST when the edit took more are the same sentence with one preposition changed, and the copy
  # should not have to know which.
  def recipients_of(others, without, direction)
    others
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
  def standing_for(pool, pending: PoolProjection::Pending.none)
    status = pool.status(today: today, pending: pending, terms: ledger.terms_for(pool))

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
  #
  # MEASURED AGAINST #without_override, THE SAME COUNTERFACTUAL THE REDIRECT LINE USES, and this
  # was a real defect until the review probed for it. Fed the untouched `proposed` instead, the
  # two sentences on one row could point in OPPOSITE directions: with Rent cut to $200 funding
  # Dentist in full, cutting Dentist $300 → $250 withholds $50, but against the untouched fill
  # Dentist looked like it had GAINED $50 — so the row read "That frees $50.00…" above
  # "You're covering $50.00 early…", and the "$400.00" it quoted was next period's ask in a
  # world where neither edit exists, which is not the world the screen is showing.
  #
  # The same substitution also LOST a consequence: an override set to exactly the untouched
  # figure tripped the `funded == baseline` early return, so the row said what it freed and
  # nothing about what it costs later — which amendment B forbids. Neither shape is reachable
  # with only one row edited, which is why no example caught it.
  def consequence_for(pool, funded, fresh, swept)
    baseline = without_override(pool, fresh).for(pool)
    return nil if funded == baseline

    consequence = build_consequence(pool, pending(funded, swept), pending(baseline, swept))
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
  # confirm is actually going to write: both come from AllocationCalculator — `funded` from the
  # fill (the override applied, then clamped to the cash), `swept` from #sweeps.
  def pending(funded, swept) = PoolProjection::Pending.new(funded: funded, swept: swept, on: today)

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
    pool.calculator(
      today: next_period_start, net_of_sweep: true, pending: pending, terms: ledger.terms_for(pool)
    ).required
  end

  # ONE LEDGER FOR THE SCREEN'S OWN CALCULATORS — the row's ` · last period` marker and the two
  # projected asks behind every consequence line, which are four calculators per edited row and a
  # `net_of_sweep` twin inside each of the two.
  #
  # `today:` VARIES ACROSS THESE CALLERS AND `as_of:` DOES NOT, which is the whole reason one
  # ledger can serve them: the five terms are a reading of the ledger, so they depend on the pool
  # and on `as_of` alone. `today` chooses which period a RULE is measured in and moves no term
  # here. #opening_buffer is the one reader on this screen with an `as_of` of its own, and it
  # stays unbatched over its single pool — a second ledger for one account would be five queries
  # either way.
  #
  # Built lazily and therefore INSIDE #build_snapshot's transaction, after the deletion, like
  # every other figure on this screen. A ledger built in #initialize would be the one thing here
  # measured against a world where this period's split still exists.
  def ledger = @ledger ||= PoolBalanceLedger.new(envelopes)

  # The day the next period opens, off User#period_containing rather than a cadence of its own —
  # the same reader the header prints, so the date in the sentence and the date in the subtitle
  # cannot name different periods.
  def next_period_start = @next_period_start ||= period.last + 1

  # The rule whose schedule the row prints: the earliest-due dated rule, by
  # BudgetCalculator#due_order — the one place that `[due_date, -amount, id]` key lives, shared
  # with the fill order itself and with the two other presenters that name a rule. `pool.budgets`
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
      .min_by { |_budget, calculator| calculator.due_order }
      &.last
  end
end
