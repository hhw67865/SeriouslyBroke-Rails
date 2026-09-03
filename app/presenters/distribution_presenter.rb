# frozen_string_literal: true

# Everything the distribution screen renders: where the money came from, which category gets
# what, and what stays in the buffer. READ-ONLY — this presenter writes nothing, and the
# deletion it performs on the way to its answer is rolled back before it returns (see
# #build_snapshot).
#
# It shows the period AS IF ITS DISTRIBUTION HAD NOT HAPPENED, because that is exactly what
# confirming does: AllocationCommitter deletes this period's `allocation` and `sweep` rows and
# only then computes the proposal it writes. A screen that instead computed against the ledger
# as it stands would read "nothing to distribute" — the categories are already funded — above a
# button that replaces the whole split. Both halves come from
# AllocationCommitter#replace_previous_distribution, so the screen cannot drift from the action.
#
# ONE SCREEN PER PERIOD, NOT ONE PER ACCOUNT (two-ledger spec §2). The purpose ledger has a single
# root, so this presenter takes a user and a day and no account at all: `buffer` on this screen is
# `CategoryLedger#available` throughout — see #buffer_carried for why the pool era's word is kept.
#
# See docs/superpowers/specs/2026-08-21-two-ledger-design.md §2 and
# docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §5
class DistributionPresenter
  # One waterfall row, with everything the view needs already read off it.
  #
  # A snapshot rather than the live objects, and that is the whole point: every figure here is
  # measured inside the rolled-back transaction, where this period's split does not exist. A
  # view holding the Category and asking it for a status afterwards would get an answer from the
  # ledger WITH the split back in place — half the row describing one world and half the other,
  # which is the exact confusion this screen exists to remove.
  #
  # `short` is derived rather than stored for AllocationCalculator::Row's reason: it is
  # `needed - funded` by definition, and a stored field is a second place for it to be wrong.
  #
  # `status` holds a Standing, NOT a HoldingStatus — see Standing for why that distinction is the
  # whole of this class's safety rather than a tidiness.
  #
  # `needed` IS THE USER'S FIGURE where they typed one, because the fill uses it — so `short`,
  # the cutoff marker, the unfunded total and the buffer are four views of ONE fill rather than
  # four readings of a proposal the user has already overruled. An earlier version of this class
  # kept a second `unfunded` reader measured against the un-overridden proposal, so that "ran out
  # here" could stay a fact about the root alone; the plan ruled against it, and rightly —
  # the freed money now cascades, so a cutoff computed off the old fill would sit above
  # categories that had just been funded by the edit.
  #
  # THERE IS DELIBERATELY NO `proposed` MEMBER. The row briefly carried what this category would
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
    :category,
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
    # two of HoldingStatus's six states print a date of their own, and a row carrying two dates from
    # two different rules reads as a contradiction (see DistributionsHelper::DATED_STATES).
    def scheduled? = due_on.present?
  end

  # A HoldingStatus reduced to the four values its label is made of, read inside the transaction.
  #
  # This replaced handing the live HoldingStatus to the view, and the reason is worth stating
  # exactly, because the thing it replaced LOOKED safe. HoldingStatus memoises `#state` and nothing
  # else: `#amount` and `#due_on` are plain `case` expressions that re-execute on every call, so
  # a "warmed" status handed to a view still ran real work after the rollback — on the
  # :overdue/:wont_make_it branches, a live SQL SUM. That happened to be safe only because those
  # branches read `entries`, which the rollback did not touch, while the rows it DID restore are
  # `allocations`. Safety by coincidence in another class's internals: a seventh state, or a
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

  # THE FIFTH MEMBER IS `period_closed`, AND THE VOCABULARY IS WHY (2d whole-plan review, fix 3).
  #
  # This object is "a HoldingStatus reduced to the values its label is made of", and the label grew a
  # clause this list did not have. `HomeHelper#pool_status_label` appends ` · last period` from
  # `period_closed:`, so the alerts band — the only place on this screen that labels a Standing
  # with no row of its own — had no way to pass it, while every other status on the screen does.
  #
  # HOW BAD IS IT TODAY: NOT BAD, AND THE HONEST ANSWER IS "UNREACHABLE" (measured, not assumed —
  # see the reachability example in distribution_presenter_spec). The band holds red categories with
  # NO ROW, and a `period_closed?` category always has one: #fill asks with `net_of_sweep: true`,
  # so a closed category's leftover is swept off its balance and its rate rules ask for their full
  # amounts again, while `BudgetCalculator#shortfall` clamps at zero so no other rule can subtract
  # that back down. Ask positive → row → not an alert. The two screens cannot currently disagree.
  #
  # IT IS FIXED ANYWAY, because that argument is a proof about ANOTHER class's fill semantics
  # holding a property of THIS one's vocabulary. It is exactly the shape of reasoning that made
  # `shared/_holding_status` necessary: two screens that agree by argument rather than by
  # construction, with nothing to fail when the argument stops being true. Reject zero-ask rows a
  # different way, or admit a red state that does not ask for money, and the band starts printing a
  # shorter sentence about the same category than Home does — silently, because a missing suffix
  # still renders.
  #
  # CAPTURED INSIDE THE TRANSACTION LIKE ITS SIBLINGS, and for the same reason: `HoldingStatus`
  # delegates `#period_closed?` to a calculator whose `#last_funded_on` is three MAX(date)s over
  # allocations and entries, so asked after the rollback it would answer against a ledger where this
  # period's split is back — the half-row defect the whole snapshot exists to prevent.
  #
  # IT ANSWERS RATHER THAN REFUSING, verified and not assumed. `HoldingCalculator::SWEEP_READERS`
  # lists `:period_closed?`, and `HoldingProjection` refuses every name on that list — but only when
  # `net_of_sweep` (see HoldingProjection#refuse_when_net_of_sweep). Both Standings built here come
  # through `#standing_for`, which passes `pending:` and never `net_of_sweep:`, so the alerts
  # band's is a plain HoldingCalculator (`HoldingProjection.for` returns one when neither projection is
  # asked for) and the consequence line's is a projection with the refusal switched off.
  #
  # ONE OF THE TWO CONSUMERS IGNORES IT, deliberately. `DistributionsHelper
  # #distribution_unrecoverable_sentence` labels `Consequence#standing`, which is a projected
  # state — what this category BECOMES if the edit is confirmed — and hanging "last period" off a
  # world that does not exist yet would date a sentence about the future.
  Standing = Data.define(:state, :amount, :due_on, :target, :period_closed) do
    def red? = RED_STATES.include?(state)

    # The reader `pool_status_label` consumes, spelled as HoldingStatus spells it so a caller reading
    # one and a caller reading the other cannot come to mean different things.
    def period_closed? = period_closed
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
  # `standing` is the category's OWN status (HoldingStatus, through Standing) taken as of TODAY with
  # the override's money already in the category: "would this category still make it". Today
  # rather than next period, because :wont_make_it asks whether any boundary is left between
  # tomorrow and the due date, and the distribution being edited is the one happening now.
  #
  # `opens_on` is the date the sentence names ("Feb 20 will need …"), `due_on`/`periods_left`
  # come from the rule as it will stand THEN, so "it's the last period before Mar 1" is read off
  # the projection rather than asserted about it.
  Consequence = Data.define(:moving, :next_ask, :baseline_ask, :opens_on, :due_on, :periods_left, :standing) do
    # The gate, and the whole of it: state the consequence ONLY when the per-period ask actually
    # changes (spec §5). A dateless goal funds at a fixed rate, so underfunding it once leaves
    # next period's rate exactly where it was and this is false — and so is a rate category,
    # whose leftover is swept back and topped up to the full rate again regardless.
    #
    # OR unrecoverable, because an category that can no longer make its date is a consequence
    # even in the arithmetic corner where the next ask happens to land on the same figure.
    def worth_saying? = next_ask != baseline_ask || unrecoverable?

    # The one red case (spec §5, amendment C): the override left the category unable to recover,
    # which is :wont_make_it — a state HoldingStatus already produces, in the red the app already
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
  # Consequence says what an edit costs the category LATER. This says what the edit did to the
  # rest of the split NOW. Cutting one row re-runs the waterfall beneath it, so categories the
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
  #   and they UNDERSTATE the categories, which is worse because it is silent. Where either edit
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
  # categories below, and "where did my money go" has the same force asked in reverse.
  #
  # `recipients` is `[category, amount]` in descending order of amount, holding MAGNITUDES; `buffer`
  # likewise. The identity is asserted against the SCREEN's own before-and-after figures rather
  # than against itself, which would be `x == x`.
  Redirect = Data.define(:moved, :sources, :recipients, :buffer, :aggregate) do
    def freed? = moved.positive?

    # Edits that CANCEL on net. Nothing left the group, so neither "freed" nor "took" is true and
    # there is no lead figure to state — but money still went from one category to another, and
    # the line that exists to say where money went may not fall silent on the one screen where
    # the user has just reshuffled their budget. `sources` is populated only here, and only here
    # do the two lists name both ends of the same move.
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

  # One fill reduced to the two things the redirect arithmetic asks of it: what each category
  # got, and what was left over. A value rather than a live calculator, for Line's reason — it
  # is read outside the transaction that built it.
  Fill = Data.define(:funded, :leftover) do
    def for(category) = funded.fetch(category.id, 0.to_d)
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

  attr_reader :user, :today, :overrides

  # `overrides` arrives exactly as the form submitted it — `{category_id => amount}`, both sides
  # strings — and is NOT coerced here. It goes onto the PROPOSAL, which owns the coercion and
  # applies the figures inside its own fill; this screen then reads the fill's answer back.
  # One override path, and the thing that reads it is the thing that will write it.
  # `expanded:` is the user ASKING for the full table on a period that does not need it. The
  # all-clear density renders no rows at all (spec §5: headline, one line, one button), which is
  # right — and it also leaves someone who simply wants to put more into savings on a comfortable
  # period with nothing to type in. One more term in the density switch, not a second screen.
  def initialize(user:, today: Date.current, overrides: {}, expanded: false)
    @user = user
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
  # `total_allocated < Σ needed`, which disagrees the moment a zero-need category is rejected.
  def short? = snapshot.short

  def covered? = !short?

  # THE DENSITY SWITCH, chosen by the DATA and never by a setting (spec §5): all clear gets a
  # headline and one summary line, anything short OR OVERDUE gets the full waterfall with no
  # collapse. A single confirm button over a collapsed distribution lets someone quietly starve
  # the bottom rows — or, on the overdue half, tells them everything is fine over a bill that is
  # already late.
  #
  # "Or overdue" is the spec's own wording and it is not decoration: an overdue bill whose
  # category ALREADY HOLDS the money asks for nothing, so it is rejected from #rows, so a
  # short-only switch collapses the screen and never mentions it. That is the one shape where
  # the money is fine and the user is not.
  #
  # `alerts` as well as the rows, for exactly that reason: the trigger has to see the categories that
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

  # Something below is genuinely wrong: a red category with no row of its own, or a row in a red
  # state. Named because the header has to tell it apart from the two OTHER reasons the table can
  # be open — the user asking, and the user's own edit — which are not problems and must not be
  # described as one.
  def needs_attention? = alerts.any? || lines.any? { |line| line.status.red? }

  # Whether the user ASKED for the table, as opposed to the data having demanded it. A different
  # question from #expanded? and read in one place only: the form carries it forward, so clearing
  # the last edit on a comfortable period does not collapse the table out from under the boxes.
  def expand_requested? = @expanded

  # Red-state categories with NO row of their own — the ones #expanded? exists for, and the ones
  # nothing else on this screen can say. A red category that HAS a row is already named by that row's
  # own detail line, so listing it here would print the same problem twice.
  #
  # `[category, standing]` pairs, in fill order.
  delegate :alerts, to: :snapshot

  # What the categories below the cutoff miss, summed from the rows for HomePresenter#shortfall's
  # reason: only the rows can say WHICH category is starved, and `needed - available` answers a
  # different question.
  #
  # Summed over the SAME fill the rows and the buffer come from, so cutting a high row and
  # watching the category below it fill up drops this figure by exactly what that category
  # gained. It moving is the point: a total that stayed still while the buffer grew was the
  # screen saying money could not be found while holding money that could have funded it.
  def shortfall = lines.sum(0.to_d, &:short)

  # WHERE THE MONEY RAN OUT, or nil when nothing is short. One rule, shared with Home's band
  # (Waterfall.cutoff); only the gate is this screen's, and it is the simple one — a distribution
  # covers ONE root by definition (§2), so there is no per-account caveat here — and after the
  # two-ledger cutover there is no account to caveat about at all.
  #
  # Read off the SAME fill as everything else on this card. An override re-runs the waterfall
  # below it, so the money genuinely does reach further down when a high row is cut — a cutoff
  # computed against the un-overridden proposal would sit above categories the edit had just
  # funded, and the unfunded total beside it would refuse to move while the buffer grew.
  #
  # `nil` unless something is actually short: with every category funded the index finds nothing,
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

  # `[category, amount]` pairs in fill order, for the sources line that names them.
  #
  # Read from AllocationCalculator#sweeps, NOT from #lines. The two sets are not the same: a
  # row is rejected when the category asks for nothing, and an category can sweep while asking
  # for nothing — a mixed category whose rate period has ended hands back what its dated rule
  # is not holding, and if that reserve already covers its remaining rules its ask is zero.
  # Built off the rows, such a sweep would raise Available with nothing on screen saying where
  # the money came from. Reasoned from #fill's reject and #sweepable_amount rather than
  # measured; no example below constructs that category.
  delegate :sweeps, to: :snapshot

  def swept_categories = sweeps.map(&:first)

  # WHAT HAD NO JOB YET THE MOMENT THIS PERIOD OPENED — the left-hand side of the buffer line's
  # `$382 → $1,419`, and the first line of the sources breakdown.
  #
  # "BUFFER" IS AVAILABLE, AND THE WORD SURVIVES ONLY IN THE METHOD NAME. Spec §7.1's buffer is
  # "the money no envelope has claimed", which is exactly what the purpose ledger's root is (§2:
  # money with no job yet) — the pool era happened to keep it in an account. Every reader on this
  # screen that says buffer means `CategoryLedger#available`. THE SCREENS SAY "AVAILABLE" (the
  # answers-first Home spec §3 sweep): the row this feeds reads "Available carried over", and these
  # method names were left alone deliberately, because renaming a reader is mechanism churn and the
  # sweep was over what the user reads.
  #
  # MEASURED with an `as_of` ledger, not derived by subtracting the other lines from #available.
  # It was derived at first, which made the breakdown add up by construction and made this line
  # a bin for everything the other lines did not name: on the demo data it printed
  # "carried over -$2,270.00" over an available holding $330, because $2,000 of category
  # funding and spending that happened DURING the period had nowhere else to go. A figure whose
  # only guarantee is that it makes the column add up is not an answer to "where did this money
  # come from", which is the one question this band exists for.
  #
  # #moved_this_period is now the residual instead, and it is named as one.
  def buffer_carried = snapshot.carried

  # Everything else that moved available inside this period: money spent by a category that holds
  # none of its own (§4's start-date rule sends it to the root), and reallocations the user made by
  # hand. Signed — a hand move back INTO available is positive — and the view drops the line when it
  # is zero, which is the ordinary shape of a period whose distribution has not been touched since
  # it was written.
  #
  # This is the derived line, so `carried + income + moved + swept == available` is an identity
  # and no example asserts it. The other three are pinned against figures their fixture put
  # there; this one is pinned by its own cause (a $300 expense inside the period).
  #
  # An allocation written by a PREVIOUS confirm of this same period is NOT here: the snapshot is
  # taken after those rows are deleted, so a period that has been distributed reads exactly as it
  # did before, which is what the rest of this screen promises.
  def moved_this_period = available - buffer_carried - income_this_period - total_swept

  # THE BUFFER TARGET IS DELETED (Task 7). `#buffer_target` read `user.default_account.target_amount`
  # and `#buffer_target?` gated the ` · you wanted $2,000.00` clause on two lines of this screen.
  # It was the LAST pool read on the distribution screen, and it was already reading the wrong
  # ledger: the target sat on the POT (an account's column) while every figure beside it is about
  # AVAILABLE (the purpose ledger's root) — they coincide only for a user with one checking account
  # who allocates all of it. Two-ledger §2 gives accounts no target semantics at all, and the plan's
  # T8 drops the column, so there is nothing left to re-aim this at: the concept goes rather than
  # moving. `DistributionsHelper#buffer_target_clause` and its two call sites
  # (`distributions/_sources`, `distributions/_waterfall`) went with it.

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

  # The proposal handed to the committer names the user and the day; its FIGURES are the ones the
  # committer re-derives after the deletion, which is what #capture reads.
  def proposal = AllocationCalculator.new(user: user, today: today, overrides: overrides)

  # Standings are taken for EVERY category in the fill order, not only the ones with a row: the
  # density switch has to see a red category that is asking for nothing, which by definition has no
  # row. Keyed by category id, so a line and an alert can never disagree about how one category is doing.
  def capture(fresh, committer)
    standings = categories.to_h { |category| [category.id, standing_for(category)] }
    @baseline = baseline_fill(fresh)
    @live = fill_of(fresh)
    edited = fresh.rows.select { |row| fresh.overridden?(row.category) }
    lines = fresh.rows.map { |row| line_for(row, fresh, standings, edited.size) }

    snapshot_from(fresh, committer, standings, lines, aggregate_redirect(fresh, edited))
  end

  def fill_of(calculator)
    Fill.new(funded: calculator.rows.to_h { |row| [row.category.id, row.funded] }, leftover: calculator.leftover)
  end

  # What each category would have received HAD NOTHING BEEN EDITED, keyed by category id: a second
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
  #
  # `fresh.with_overrides({})` RATHER THAN A FRESH AllocationCalculator, so this fill runs over
  # the ledger `fresh` already built rather than eight grouped queries of its own. That method
  # carries the whole argument for why the two may share one; the half that belongs here is WHICH
  # `fresh` this is — the committer's post-deletion re-derivation, handed to #capture inside
  # #build_snapshot's transaction with nothing written between. It also stops `user:` and `today:`
  # being restated at a call site, which is two chances for this fill to describe a different moment
  # from the one it is the baseline for.
  def baseline_fill(fresh)
    return nil if fresh.overrides.empty?

    fill_of(fresh.with_overrides({}))
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
  # every category. The destination sentence no longer calls it at all (with two or more edits it
  # is the aggregate, which reads @baseline), so the memo is what holds the cost at ONE fill per
  # edited row rather than at whatever the next caller happens to make it.
  #
  # `@baseline || @live` rather than a bare `@baseline`, and this is not defensive tidiness:
  # #baseline_fill is nil when nothing is overridden, and this method was safe only because its
  # caller happened to check `overridden?` first. Measured — calling it unguarded raised
  # `undefined method 'for' for nil` and took the whole screen down with a 500. With no override
  # to undo, "the same distribution with this edit undone" IS the live fill, so the fallback is
  # the right answer rather than a shrug: #redirect_for then measures zero and says nothing.
  def without_override(category, fresh)
    return @baseline || @live if fresh.overrides.size <= 1

    # Over `fresh`'s own ledger, for #baseline_fill's reason and with the same guarantee: these
    # are N more fills of the SAME instant, and the memo above holds them at one per edited row.
    (@without ||= {})[category.id] ||= fill_of(fresh.with_overrides(fresh.overrides.except(category.id.to_s)))
  end

  # `total_allocated` and `leftover` come straight off the calculator again. They were summed
  # from the lines while the committer substituted overrides after the fill — the calculator did
  # not know about them then, so its own totals described a split nobody was going to write.
  # With the override inside the fill there is one set of figures, and taking them from anywhere
  # but their source would be the second reader all over again.
  def snapshot_from(fresh, committer, standings, lines, redirect)
    Snapshot.new(
      available: fresh.available,
      carried: opening_buffer,
      income: income_this_period_from,
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

  # INCOME THAT ARRIVED IN THIS PERIOD, off `AccountLedger` — the PHYSICAL ledger, and deliberately
  # so: income raises the pot and raises available at the same instant (§2), and "which entries are
  # this user's income" is one question with one answer that a presenter must not re-derive.
  #
  # Allocations are what the rollback restores and this reads `entries`, so it is stable either way —
  # it is captured in here anyway so that every figure on the screen comes from one moment rather
  # than most of them.
  def income_this_period_from
    AccountLedger.new(user).income_within(period_timestamps)
  end

  # AVAILABLE the instant before this period opened, through `CategoryLedger`'s own `as_of` rather
  # than a query of its own — one definition of "money with no job yet", asked about an earlier
  # moment.
  #
  # INSIDE the transaction, and here it matters: `as_of` bounds the allocation query by date, not by
  # kind, so a distribution written earlier in this same period would otherwise be included or not
  # depending on when the caller asked. Taken here, it is measured against the same deleted ledger as
  # everything else on the screen.
  #
  # A LEDGER OF ITS OWN, and it has to be: `#ledger` below is unbounded, and `CategoryLedger
  # #for_as_of!` refuses a handover between two moments precisely so a figure from one cannot be read
  # as a figure from the other.
  #
  # `- 1.second`, because the period range starts at midnight and `as_of` is inclusive: bounded
  # at the period's own first instant, an allocation stamped exactly midnight would count as both
  # carried over and moved this period.
  def opening_buffer
    CategoryLedger.new(categories, user: user, as_of: period_timestamps.first - 1.second).available
  end

  def period_timestamps = @period_timestamps ||= user.period_datetimes_containing(today)

  # The user's holder categories in the order the money reaches them — the same one-line scope
  # AllocationCalculator#categories reads, so the two lists cannot fall into different orders.
  def categories = @categories ||= user.categories.in_fill_order.to_a

  # Red categories MINUS the ones that already have a row. Matched by category id rather than by record so
  # the two collections need not be the same objects.
  def alerts_from(standings, lines)
    with_rows = lines.to_set { |line| line.category.id }
    categories
      .reject { |category| with_rows.include?(category.id) }
      .filter_map { |category| [category, standings.fetch(category.id)] if standings.fetch(category.id).red? }
  end

  # `sweeps.fetch(category, 0.to_d)`, because #sweeps holds only the categories with something to
  # give. Keyed by the Category record, exactly as AllocationCommitter reads it, so the amount the
  # row prints is the amount the allocation will carry.
  def line_for(row, fresh, standings, edits)
    category = row.category
    swept = fresh.sweeps.fetch(category, 0.to_d)
    overridden = fresh.overridden?(category)

    Line.new(
      category: category,
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
      status: standings.fetch(category.id),
      # OFF THE SAME STANDING AS THE LINE'S STATE, not a calculator of its own. This used to build
      # a second `category.calculator(today:, terms:)` — provably the same object HoldingStatus builds
      # internally, and therefore provably the same answer — but "provably" is the word #capture's
      # own comment refuses to rest on for `status`: one Standing per category id is what stops a line
      # and an alert disagreeing about one category, and the suffix is now part of what they agree
      # about. The member stays because DistributionsHelper reads `line.period_closed`.
      period_closed: standings.fetch(category.id).period_closed?,
      # Both sentences are only ever computed for a row the USER typed in. The cascade moves the
      # funding of rows below an override without anybody editing them, and "you're moving $200
      # onto your next period" about a row the waterfall reached on its own names the wrong
      # actor — the edit that caused it is two rows up, and it says so there.
      consequence: overridden ? consequence_for(category, row.funded, fresh, swept) : nil,
      # ONE EDIT ONLY. With two or more the destination sentence moves above the table as a
      # single aggregate (see Redirect): two per-row decompositions do not sum, and showing both
      # forms at once would put three descriptions of one move on one screen. The consequence
      # line stays per row either way — it is about what THIS row's edit costs THIS category
      # later, which is per-row by nature and composes fine.
      redirect: overridden && edits == 1 ? redirect_for(category, fresh) : nil,
      **schedule_for(category)
    )
  end

  # What this one edit did to everything else, or nil when it moved nothing — which is the
  # ordinary shape of an override available could not honour (ask $350 with $185 left and the
  # row still receives $185, so no other row and no buffer figure changes).
  def redirect_for(category, fresh)
    without = without_override(category, fresh)

    build_redirect(
      without.for(category) - @live.for(category),
      fresh.rows.reject { |row| row.category.id == category.id },
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
  # category the proposal has no row for — a hand-built URL would otherwise switch a single-edit
  # screen to the aggregate form and take the row's own sentence away.
  def aggregate_redirect(fresh, edited)
    return nil if edited.size < 2

    moved = edited.sum(0.to_d) { |row| @baseline.for(row.category) - @live.for(row.category) }
    return shifted_redirect(fresh) if moved.zero?

    build_redirect(moved, untouched_rows(fresh, edited), @baseline, aggregate: true)
  end

  # The rows nobody typed in. In the freed/taken modes the edited rows are the source and the
  # lead names their total, so listing them again as destinations would say the same money twice.
  def untouched_rows(fresh, edited)
    edited_ids = edited.to_set { |row| row.category.id }

    fresh.rows.reject { |row| edited_ids.include?(row.category.id) }
  end

  # `moved.zero?` is nil HERE and only here — one row whose funding available could not change
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
  # so the net is zero while $300 has plainly moved between two categories.
  #
  # The gate was on the wrong quantity. What decides whether there is anything to say is whether
  # ANY row's funding differs from the untouched proposal, not whether the net is non-zero — and
  # measured on the net, this screen went silent at exactly the moment a user had reshuffled their
  # budget. Same decomposition as the other two modes, read in both directions: the negative
  # deltas are where the money came from and the positive ones are where it went.
  #
  # EVERY row, not only the un-edited ones, because in this mode both ends are usually rows the
  # user typed in. The buffer joins the lists as a `nil` category rather than staying a member of its
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

  # Every party to the split against the untouched proposal, the buffer included as a `nil` category.
  def shift_deltas(fresh)
    fresh.rows.map { |row| [row.category, @live.for(row.category) - @baseline.for(row.category)] } +
      [[nil, @live.leftover - @baseline.leftover]]
  end

  def largest_first(parties) = parties.sort_by { |_party, amount| -amount }

  # The other rows this edit moved money to (or took it from), largest first. Signs are folded
  # away here rather than in the view: a row that GAINED when the edit freed money and a row that
  # LOST when the edit took more are the same sentence with one preposition changed, and the copy
  # should not have to know which.
  def recipients_of(others, without, direction)
    others
      .map { |row| [row.category, (@live.for(row.category) - without.for(row.category)) * direction] }
      .select { |_recipient, amount| amount.positive? }
      .sort_by { |_recipient, amount| -amount }
  end

  # The row's own schedule clause, as the two members that carry it. Split out only because
  # #line_for was over rubocop's ABC limit; the pair travels together because they come from
  # ONE rule (see #next_dated_rule) and reading them apart is how a row ends up naming two bills.
  def schedule_for(category)
    rule = next_dated_rule(category)

    { due_on: rule&.due_date, periods_left: rule&.periods_until_due }
  end

  # A HoldingStatus, read down to values while the transaction is still open. See Standing: the
  # readers below are `case` expressions rather than memos, so anything that calls them later
  # calls them against a ledger where this period's split is back.
  #
  # `pending:` is how the SAME reader answers the projected question. There is one
  # definition of how a category is doing in this app and this is it; the override case differs only
  # in which balance it is asked about.
  def standing_for(category, pending: HoldingProjection::Pending.none)
    status = category.status(today: today, pending: pending, terms: ledger.terms_for(category))

    Standing.new(
      state: status.state,
      amount: status.amount,
      due_on: status.due_on,
      target: status.target,
      # `HoldingStatus#period_closed?`, the same delegation Home's row reads, off the calculator this
      # status already holds — never a second `category.calculator`, which is the two-objects-one-category
      # shape HoldingStatus's own comment on that delegation refuses.
      period_closed: status.period_closed?
    )
  end

  # The consequence of one override, or nil — nil both when the user changed nothing and when
  # what they changed moves nothing downstream. See Consequence#worth_saying?: a screen that
  # always prints a line and a screen that never prints one are equally wrong, and the gate
  # between them is a comparison of two real recomputations.
  #
  # `pending` is THIS DISTRIBUTION'S WHOLE EFFECT on the category — the allocation in, less the
  # sweep out. Both halves matter: the sweep is written by the same confirm, so a projection
  # that added the funding without removing the leftover would credit the category with money
  # it is about to hand back.
  # Only ever called for a row the user typed in (see #line_for), and nil again when the money
  # that reaches the category is unchanged — which is the ordinary shape of an override the
  # available could not honour: type $350 with $185 left and the row still receives $185,
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
  def consequence_for(category, funded, fresh, swept)
    baseline = without_override(category, fresh).for(category)
    return nil if funded == baseline

    consequence = build_consequence(category, pending(funded, swept), pending(baseline, swept))
    consequence if consequence.worth_saying?
  end

  def build_consequence(category, chosen, baseline)
    rule = next_dated_rule(category, on: next_period_start)
    Consequence.new(
      moving: baseline.funded - chosen.funded,
      next_ask: projected_ask(category, chosen),
      baseline_ask: projected_ask(category, baseline),
      opens_on: next_period_start,
      due_on: rule&.due_date,
      periods_left: rule&.periods_until_due,
      standing: standing_for(category, pending: chosen)
    )
  end

  # The two allocations this distribution would put through one category, dated the day it happens.
  # Built here rather than inside HoldingCalculator because only this class knows which of them the
  # confirm is actually going to write: both come from AllocationCalculator — `funded` from the
  # fill (the override applied, then clamped to the cash), `swept` from #sweeps.
  def pending(funded, swept) = HoldingProjection::Pending.new(funded: funded, swept: swept, on: today)

  # What this category will ask for at the START OF THE NEXT PERIOD, having had `pending` moved
  # through it by the distribution on screen.
  #
  # HoldingCalculator#required, which is the SAME reader AllocationCalculator#fill uses to compute
  # this period's `needed` — so "will need $800 instead of $500" is the row's own figure asked
  # about a later day, not a second definition of an ask. It divides by
  # BudgetCalculator#periods_until_due, which is what makes an underfunding spread across the
  # periods that remain rather than landing whole on the next one.
  #
  # `net_of_sweep: true` for AllocationCalculator#ask_calculator_for's reason, and it is
  # load-bearing here in a way that is easy to miss: a rate category's leftover is swept back at
  # the next distribution and the category is topped up to its full rate again, so underfunding
  # it now changes NOTHING about next period's ask. Without the flag the projection would report
  # a well-funded rate category as asking for nothing and print a consequence on every one of
  # them.
  def projected_ask(category, pending)
    category.holding_calculator(
      today: next_period_start, net_of_sweep: true, pending: pending, terms: ledger.terms_for(category)
    ).required
  end

  # ONE LEDGER FOR THE SCREEN'S OWN CALCULATORS — the row's ` · last period` marker and the two
  # projected asks behind every consequence line, which are four calculators per edited row and a
  # `net_of_sweep` twin inside each of the two.
  #
  # `today:` VARIES ACROSS THESE CALLERS AND `as_of:` DOES NOT, which is the whole reason one
  # ledger can serve them: the five terms are a reading of the ledger, so they depend on the category
  # and on `as_of` alone. `today` chooses which period a RULE is measured in and moves no term
  # here. #opening_buffer is the one reader on this screen with an `as_of` of its own, and it builds
  # a ledger of its own for exactly that reason — see its comment, and `CategoryLedger#for_as_of!`.
  #
  # Built lazily and therefore INSIDE #build_snapshot's transaction, after the deletion, like
  # every other figure on this screen. A ledger built in #initialize would be the one thing here
  # measured against a world where this period's split still exists.
  def ledger = @ledger ||= CategoryLedger.new(categories, user: user)

  # The day the next period opens, off User#period_containing rather than a cadence of its own —
  # the same reader the header prints, so the date in the sentence and the date in the subtitle
  # cannot name different periods.
  def next_period_start = @next_period_start ||= period.last + 1

  # The rule whose schedule the row prints: the earliest-due dated rule, by
  # BudgetCalculator#due_order — the one place that `[due_date, -amount, id]` key lives, shared
  # with the fill order itself and with the two other presenters that name a rule. `category.budgets`
  # carries no ORDER BY, so without it two rules sharing a date could swap between page loads.
  #
  # Returns a BudgetCalculator, not a Budget, so the date and the count come from ONE object.
  # Read separately they could name different rules, and "due Mar 1 · 3 periods left" about two
  # different bills is a sentence with no true reading.
  #
  # Anchorless rules are excluded because they have no date to print — a rate category's ask
  # is due every period by definition, and the row says so with its rate instead.
  #
  # `on:` is the day the schedule is read from, defaulting to the day being distributed. The
  # consequence line asks for it as of the NEXT period's opening, because both the date it names
  # and the count of periods behind "it's the last period before Mar 1" are statements about
  # where the rule will stand then — and a recurring rule's #due_date rolls, so asking today
  # and reporting it as next period's would be a different bill.
  def next_dated_rule(category, on: today)
    category.budgets
      .select { |budget| budget.anchor_date.present? }
      .map { |budget| [budget, budget.calculator(today: on)] }
      .min_by { |_budget, calculator| calculator.due_order }
      &.last
  end
end
