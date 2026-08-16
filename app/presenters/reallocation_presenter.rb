# frozen_string_literal: true

# ONE MOVEMENT BETWEEN TWO POOLS INSIDE ONE ACCOUNT — spec §5's reallocation, and the
# single-row twin of the distribution screen. READ-ONLY: this presenter writes nothing, and it
# opens no transaction, so unlike DistributionPresenter it may hand live PoolStatus objects to
# the view (HomePresenter#status_for does the same). There is no rollback here for a lazily
# re-executed reader to fall out of.
#
# The invariant is `Σ pools == your bank balance`. A reallocation moves money between two pools
# in ONE account, so the bank balance cannot move — which is why every figure below is a
# before/after pair on one pool and never a total.
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §4.2, §5
class ReallocationPresenter
  # WHY A POOL'S MONEY IS NOT FREE, named rather than left as a bare subtraction (amendment D).
  # "only $40.00 free" and "its own bill is due first" are different sentences and send the user
  # to different places, so the rule that is holding the money travels with the figure.
  #
  # Carries the Budget rather than a string: `HomeHelper#pool_rule_label` is this app's one
  # answer to what a rule is called, and a second one here would drift from the pool page.
  Holder = Data.define(:budget, :allocated, :due_on)

  # A rule whose allocation FELL because of this move — "Maintenance slips to $494 of $800".
  # Read off PoolCalculator#allocated_balances, the same earliest-due-first fill every other
  # reader in the app uses, so an under-funded rule slips by what it actually loses.
  Slip = Data.define(:budget, :allocated)

  # WHAT THE MOVE COSTS THE SOURCE, before it is committed.
  #
  # `ask_before` and `ask_after` are two REAL RECOMPUTATIONS of PoolCalculator#required, not a
  # figure derived by dividing the amount moved by something — amendment C, and on this plan
  # that mistake printed `$206.43` where the truth was `$194.17`.
  #
  # Both are taken with `net_of_sweep: true`, which is Task 5's shape (DistributionPresenter
  # #projected_ask) and is load-bearing on exactly one shape: an envelope whose rate period has
  # closed is going to hand its leftover back and be topped up to its full rate either way, so
  # taking money out of it changes its ask by NOTHING. Read plainly, the screen would print a
  # per-period cost that the next distribution erases. The two readers agree everywhere else —
  # #sweepable_amount is zero unless the period is closed — so the flag only ever removes a lie.
  Damage = Data.define(:balance_before, :balance_after, :ask_before, :ask_after, :slip, :status_after) do
    # Say it only when it is real (spec §5, amendment C). A rate envelope's ask and a dateless
    # goal's rate do not move when money leaves, and a screen that prints "+$0.00 a period" on
    # them is the warning-on-a-normal-state that principle 3 forbids.
    def ask_changed? = ask_after != ask_before

    def slipped? = slip.present?
  end

  # One row of the sources list. `requested` is on the row rather than read off the presenter
  # because affordability is a comparison between this pool's money and the amount asked for, and
  # splitting the two halves across two objects is how they come to disagree.
  #
  # TWO THRESHOLDS, NOT ONE, AND THIS IS A CORRECTION TO THE BRIEF — mine, not the plan's, so it
  # is stated in full rather than folded in quietly.
  #
  # The brief (amendment D) makes `free_amount` the affordability gate: a source with less free
  # money than the move asks for is disabled. Built that way and then measured, that gate makes
  # amendment C's own damage statement UNREACHABLE, and the proof is short:
  #
  #   free   = max(balance − reserve, 0), and #allocated_balances fills greedily, so
  #   reserve = min(balance, Σ rule amounts) and free = max(balance − Σ amounts, 0).
  #   A move of `amount ≤ free` leaves balance_after ≥ Σ amounts, so EVERY rule still takes its
  #   full amount: no allocation moves, so no rule can slip and #required cannot change.
  #
  # So under the brief's gate the damage line can only ever print its balance arrow. Amendment C's
  # worked example is exactly the shape the gate forbids — rebuilt verbatim in the console, Car
  # holding $1,340 against a $628 rule due first and a $800 Maintenance rule reserves the whole
  # $1,340, reports `free_amount` of $0.00, and drops Maintenance to $494 of $800 on a $218 move.
  # Spec §4.2's own fix ("Take $300 from Rent … you'd put in $800 next period instead of $500") is
  # the same shape: Rent's rule holds all of Rent, so Task 8 could never offer that button.
  #
  # The correction keeps every purpose amendment D names and moves only the threshold at which a
  # row goes dead:
  #
  #   requested > balance  → DISABLED, with the reason. "Cannot afford it" now means the envelope
  #                          does not physically hold it, which is also the floor that keeps a
  #                          reallocation from overdrawing the source.
  #   requested > free     → allowed, and the damage statement fires — this is where money that a
  #                          rule was holding gets taken, and stating that cost is what this whole
  #                          screen is for (principle 5). `free_amount` is still the reader that
  #                          decides it, and still the figure every row prints.
  #   requested <= free    → allowed, and there is nothing to say beyond the balance arrow.
  #
  # `sweepable_amount` is nowhere near any of this, which is the confusion amendment D was
  # written to prevent and which the correction does not reopen.
  Candidate = Data.define(
    :pool, :pool_balance, :free, :status, :period_closed, :requested, :holder, :damage, :selected
  ) do
    # `pool_balance.positive?` FIRST, so an empty or overdrawn envelope is dead even before an
    # amount is typed — with no amount on screen `requested` is zero and would wave it through.
    def affordable? = pool_balance.positive? && requested <= pool_balance

    # The move reaches past what is unpromised and into money a rule is holding. Not "has damage":
    # a dateless savings goal's ask moves on a move well inside its free money, because
    # PoolCalculator#goal_required reads the balance directly rather than through an allocation.
    def promised? = requested.positive? && requested > free

    def selected? = selected

    # The move pushes this envelope into a different state — the "Rent still makes Mar 1" half
    # of spec §4.2's fix, said in the app's own row vocabulary rather than in a sentence of its
    # own.
    def state_changed? = damage.present? && damage.status_after.state != status.state
  end

  # THE OTHER END. The damage statement is about the source, but a screen that only states costs
  # never says what the move is for, and the destination's status flipping out of `overdue` is
  # the whole reason someone is here.
  Gain = Data.define(:pool, :balance_before, :balance_after, :status_before, :status_after) do
    def state_changed? = status_after.state != status_before.state
  end

  # THE ORDER MONEY IS OFFERED IN, and the ONE place it lives. Home's fix button ranks the same set
  # by calling this rather than sorting its own way (it used to sort richest-first), because a
  # button reading "take it from House Down Payment" that opens a screen ranking the buffer first
  # is a screen disagreeing with the button that opened it — the defect class this plan has hit in
  # every task where two readers answered one question.
  #
  # THE ACCOUNT COMES FIRST. It is the buffer, the money no envelope has claimed (spec §7.1), and
  # the source spec §4.2's "this has to come from money you already have" most often means. Idle
  # cash costs nothing to move; a savings goal is money the user decided to protect, and richest-
  # first proposed exactly that — a $950 down payment while $330 of buffer sat unoffered.
  #
  # Then `[priority, name]`, the order the user ranked their envelopes in. It is a TOTAL order —
  # `Pool` validates name uniqueness per user — so it is also the tie-break: priority alone would
  # fall through to database order, which is the defect Plan 1 shipped in its allocation waterfall.
  #
  # A class method rather than an instance one because it is a property of the pool, not of any one
  # proposed movement, and Home holds no ReallocationPresenter when it ranks its candidates.
  def self.source_order(pool) = [pool.pool_type_account? ? 0 : 1, pool.priority, pool.name]

  attr_reader :user, :to_pool, :from_pool, :amount, :today

  # `amount` arrives as the form's String and is coerced ONCE, here. nil for a blank box rather
  # than zero, so a submitted blank reads "Amount can't be blank" instead of the arithmetic's
  # "must be greater than 0" — the box is empty, not set to nothing.
  def initialize(user:, to_pool: nil, from_pool: nil, amount: nil, today: Date.current)
    @user = user
    @to_pool = to_pool
    @from_pool = from_pool
    @amount = amount.presence&.to_d
    @today = today
  end

  # The arithmetic's view of the box: zero when nothing has been typed. Kept apart from #amount
  # so the movement below can still tell "blank" from "zero".
  def requested = amount || 0.to_d

  def requested? = requested.positive?

  # THE MOVEMENT ITSELF, unsaved. `kind` is not set: `transfer` is the column default, and that
  # is exactly what keeps a reallocation invisible to `PoolMovement.distributed` — the scope
  # AllocationCommitter deletes when a period is redistributed (amendment A). A user who moves
  # $50 between envelopes and then redistributes still has their $50 move.
  def movement
    PoolMovement.new(from_pool: from_pool, to_pool: to_pool, amount: amount, date: today)
  end

  # Every pool the money could come from: the ones PoolMovement itself says are in the same
  # account (amendment B). Asked of the model rather than re-derived from `account_id` here —
  # an account stands in as its own container, which is the part a second implementation gets
  # wrong, and it is the same reader the write path is refused by.
  #
  # Ranked by ::source_order — the account first, then the envelopes in the order the user ranked
  # them. Home's fix button calls that same method rather than sorting its own way, so the button
  # and the screen it opens cannot name different sources.
  def sources
    return [] if to_pool.nil?

    @sources ||= same_account_pools.map { |pool| source_for(pool) }
  end

  # ONE ROW, for a caller that already knows which source it means — Home's fix button, which
  # renders exactly one candidate and must not pay for the other twelve. #sources builds a Candidate
  # for every pool in the account, and an affordable one costs four calculators over that pool.
  #
  # The SAME #candidate_for the list is built from, so this is not a second answer to "what would
  # this move cost" (amendment A): Home prints the damage through the same PoolMovementsHelper
  # sentence this screen does, off the same Data object.
  #
  # No same-account check here, deliberately. That question belongs to #sources, which is the list
  # of what may be OFFERED; this is a lookup by a caller that has already chosen. A caller passing a
  # pool from another account gets an honest reading of a move the write path would then refuse.
  def source_for(pool) = (@source_for ||= {})[pool.id] ||= candidate_for(pool)

  def gain
    return nil if to_pool.nil? || !requested?

    @gain ||= build_gain(incoming)
  end

  # The destination select's pools, grouped by the account each one sits in. An account appears
  # inside its own group, because moving an envelope's money back to the unallocated cash is a
  # real reallocation — it is what a sweep does (spec §7.2) — and it is the same one movement.
  #
  # Pools rather than option pairs: what an account is CALLED when it is one end of a movement is
  # copy, and `PoolMovementsHelper#reallocation_pool_name` is the one place it is decided, for the
  # dropdown and the source rows alike.
  def destination_groups
    groups = accounts.map { |account| [account.name, members_of(account)] }
    groups << ["No account", orphans] if orphans.any?
    groups
  end

  # What goes in the amount box: the user's own figure and nothing else. Plain digits, no
  # currency symbol and no delimiter, for `distribution_override_placeholder`'s reason — a
  # `number_field` holding "$1,340.00" reports itself empty to the browser.
  #
  # Two decimals, not BigDecimal#to_s("F"), which rendered a link carrying `amount=300` back into
  # the box as "300.0" — measured on screen. A money box showing one decimal place invites the
  # reader to wonder which figure the screen is actually working with.
  def amount_value
    return nil if amount.nil?

    ActiveSupport::NumberHelper.number_to_rounded(amount, precision: 2, delimiter: "")
  end

  private

  def build_gain(pending)
    Gain.new(
      pool: to_pool,
      balance_before: calculator_for(to_pool).balance,
      balance_after: to_pool.calculator(today: today, pending: pending).balance,
      status_before: to_pool.status(today: today),
      status_after: to_pool.status(today: today, pending: pending)
    )
  end

  def incoming = PoolCalculator::Pending.new(funded: requested, swept: 0.to_d, on: today)

  # THE TWO PENDINGS ARE THE LEDGER THIS MOVE WOULD WRITE, not a signed number, and each side
  # gets the member that matches what actually happens to it.
  #
  # Money OUT is `swept:`, so `Pending#funded_on` stays nil and the source's rate period is not
  # reopened by money leaving it — which is also what the ledger says afterwards, since
  # PoolCalculator#last_funded_on reads `movements_in` alone. Money IN is `funded:` with today's
  # date, which is what the destination's own `movements_in` will report the moment this saves.
  # Measured against that: the spec asserts the previewed figures equal the ones read back from
  # the database after the write.
  def outgoing = PoolCalculator::Pending.new(funded: 0.to_d, swept: requested, on: today)

  # BUILT BARE, THEN ASKED. The row is constructed with no holder and no damage, and the two
  # branches below are chosen by asking the ROW ITSELF whether it can make the move — so
  # `Candidate#affordable?` is the ONE spelling of the affordability gate in this file.
  #
  # It used to be two: this method computed the damage behind an independently written
  # `requested? && balance.positive? && requested <= balance`, beside the row's own predicate.
  # They agreed, and that is the problem — diverge them and the screen either states damage on a
  # disabled row or refuses one silently, with nothing to say which is right. Same argument as
  # reaching for PoolMovement#crosses_accounts? rather than re-deriving "same account" here: one
  # method, not two that agree today.
  #
  # `Data#with` rather than a second constructor call, so the ten members are written once and a
  # new member cannot be added to one branch and forgotten in the other. It also stops the two
  # readers being computed where nothing renders them: a holder only ever explains a DISABLED row,
  # and damage only ever describes an affordable one.
  def candidate_for(pool)
    calculator = calculator_for(pool)
    candidate = Candidate.new(
      pool: pool,
      pool_balance: calculator.balance,
      free: calculator.free_amount,
      status: pool.status(today: today),
      # The ` · last period` marker (spec §7.2), and it earns its place on this screen more than
      # on any other: an envelope whose rate period has closed is about to hand its leftover back
      # to the buffer anyway, so a user reaching for it should know they are taking money that was
      # already on its way out. Plain calculator, which is the only kind that may be asked.
      period_closed: calculator.period_closed?,
      requested: requested,
      holder: nil,
      damage: nil,
      selected: pool == from_pool
    )

    return candidate.with(holder: holder_for(pool)) unless candidate.affordable?
    return candidate unless requested?

    candidate.with(damage: damage_for(pool))
  end

  # What the move costs this source. Only ever called for a row that can make it and an amount
  # that exists — see #candidate_for, which owns both gates.
  def damage_for(pool)
    after = pool.calculator(today: today, pending: outgoing)
    Damage.new(
      balance_before: calculator_for(pool).balance,
      balance_after: after.balance,
      ask_before: ask_of(pool, PoolCalculator::Pending.none),
      ask_after: ask_of(pool, outgoing),
      slip: slip_for(pool, after),
      status_after: pool.status(today: today, pending: outgoing)
    )
  end

  # PoolCalculator#required, asked about the same day with the balance this move would leave.
  # `net_of_sweep: true` for the reason on Damage.
  def ask_of(pool, pending)
    pool.calculator(today: today, net_of_sweep: true, pending: pending).required
  end

  # The rule that visibly took the damage: the one whose allocation fell furthest.
  #
  # `allocated_balances` fills earliest-due first, so money leaving starves the rules at the BACK
  # of that order — several can move at once and naming them all is a paragraph. The largest drop
  # is the one a person would point at, and `budget.id` breaks a tie so two equal drops cannot
  # swap between page loads. Budgets compare by id across the two calculators, so `fetch` lines
  # the same rule up on both sides.
  def slip_for(pool, after)
    fallen = calculator_for(pool).allocated_balances.filter_map do |budget, allocated|
      remaining = after.allocated_balances.fetch(budget, 0.to_d)
      [budget, remaining, allocated - remaining] if remaining < allocated
    end
    budget, remaining, = fallen.min_by { |candidate, _remaining, fell| [-fell, candidate.id] }
    budget && Slip.new(budget: budget, allocated: remaining)
  end

  # The dated rule holding this pool's money, earliest due first — "its own bill is due first".
  #
  # Read off `allocated_balances`, which already gives a settled rule nothing, so a paid bill
  # never explains a shortage it is not causing. Rate rules are deliberately absent: they hold
  # money too, and #free_amount already subtracts them, but "only $40.00 free" is the whole of
  # what there is to say about a grocery budget — a date is the part that changes the answer.
  def holder_for(pool)
    dated = calculator_for(pool).allocated_balances.select do |budget, allocated|
      budget.anchor_date.present? && allocated.positive?
    end
    budget, allocated = dated.min_by { |b, _| [b.calculator(today: today).due_date, -b.amount, b.id] }
    return nil if budget.nil?

    Holder.new(budget: budget, allocated: allocated, due_on: budget.calculator(today: today).due_date)
  end

  # SAME ACCOUNT, ANSWERED BY THE MODEL. `PoolMovement#crosses_accounts?` is the constraint spec
  # §5 expresses and it already knows that an account sits inside no other account and stands in
  # as its own — the exact case a `where(account_id:)` of my own would get wrong. The write path
  # is refused by the same reader (PoolMovement's `:reallocation` context), so the list and the
  # refusal cannot disagree.
  def same_account_pools
    user.pools.includes(:budgets, :account).reject { |pool| pool == to_pool }
      .reject { |pool| PoolMovement.new(from_pool: pool, to_pool: to_pool).crosses_accounts? }
      .sort_by { |pool| self.class.source_order(pool) }
  end

  def accounts = @accounts ||= all_pools.select(&:pool_type_account?).sort_by(&:name)

  def orphans
    @orphans ||= by_priority(all_pools.reject { |pool| pool.pool_type_account? || pool.account_id })
  end

  def members_of(account)
    [account] + by_priority(all_pools.select { |pool| pool.account_id == account.id })
  end

  def by_priority(pools) = pools.sort_by { |pool| [pool.priority, pool.name] }

  def all_pools = @all_pools ||= user.pools.includes(:account).to_a

  # One calculator per pool, for HomePresenter#calculator_for's reason: #free_amount,
  # #allocated_balances and #balance are all asked of the same pool on one render, and each
  # fresh calculator is five aggregate queries that memoise nothing for the next one.
  def calculator_for(pool) = (@calculators ||= {})[pool.id] ||= pool.calculator(today: today)
end
