# frozen_string_literal: true

# Computes a pool's balance and how that balance is spoken for by its rules.
# See docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md §2.2, §4.3
class PoolCalculator
  attr_reader :pool, :today

  def initialize(pool, as_of: nil, today: Date.current)
    @pool = pool
    @as_of = as_of
    @today = today
  end

  # Deliberately start-date-agnostic. The balance this replaces filtered entries to
  # `pool.start_date..`; a pool's balance is all the money in it, with no cutoff — the
  # movement ledger simply starts empty. `start_date` survives as a savings-goal display
  # attribute, not a balance filter. See the spec example that pins this.
  #
  # `.to_d` on the RESULT, and it is not decoration: every term here is a `sum(:amount)`
  # over a `money` column, and an empty sum returns the Integer literal 0 rather than a
  # BigDecimal zero. A pool holding nothing at all — a fresh envelope, the first shape a
  # sweep meets — made all five Integers, so #balance, #reserve, #free_amount and
  # PoolStatus#balance/#amount all changed TYPE on exactly the pools that are emptiest.
  # Coerced once here so every reader downstream inherits the guarantee.
  def balance
    (income_entries_total + savings_entries_total +
      movements_in_total - movements_out_total - expense_entries_total).to_d
  end

  # Retained for the savings-pool views; identical to #balance.
  alias current_balance balance

  # Earliest due date fills first: the money you need soonest must actually be there.
  #
  # A SETTLED obligation holds nothing, and skips the fill without consuming `remaining` — so
  # the rules behind it in the order receive what it used to hold. It previously kept its whole
  # amount forever, which put two readers of the same pool at odds: #free_amount subtracted a
  # paid bill's allocation while #sweepable_amount (which already excludes settled rules) did
  # not, so Home could render `$300.00 left · last period` on a row the next distribution
  # empties by $900. A screen disagreeing with the action it is offering is the same defect as
  # rendering `$0` for a closed envelope.
  #
  # This cannot move the settled rule's own #required: BudgetCalculator#shortfall returns
  # `0.to_d` for a fulfilled rule BEFORE it looks at `allocated`, so the figure we hand it is
  # already ignored. It does move the pool's #required, downward, when a live rule behind it
  # picks up the freed money — that rule is now genuinely funded, and reporting a shortfall
  # against money the envelope is holding was the same lie one level down.
  #
  # `0.to_d`, not a bare `0`: #reserve sums these values, and the whole class's type guarantee
  # (see #balance) is that a money reader never changes shape with how the pool is funded.
  def allocated_balances
    @allocated_balances ||= begin
      remaining = balance
      budgets_by_due_date.index_with do |budget|
        next 0.to_d if fulfilled?(budget)

        # `clamp(0, negative)` raises ArgumentError, which would take down every caller of
        # allocated_balances — reserve, free_amount, required, the whole pool page. Budget
        # validates the sign, but a validation is an input rule and this is a rendering
        # path: one bad row must not be able to turn a page into a 500.
        taken = remaining.clamp(0, [budget.amount, 0].max)
        remaining -= taken
        taken
      end
    end
  end

  # Seeded, for the pool that holds no rules at all: an unseeded `sum` over an empty set
  # returns the Integer literal 0. And `remaining.clamp(0, ...)` hands back the bare `0`
  # low bound whenever the balance is negative, so even a non-empty set can be all
  # Integers. Same guarantee as #balance's, one level up.
  def reserve = allocated_balances.values.sum(0.to_d)

  # `.to_d` on the SUBTRACTION, not on the clamp bound. `[x, 0.to_d].max` only coerces
  # when the clamp actually FIRES — `[0, BigDecimal("0")].max` returns the Integer — so
  # seeding the bound alone left every entry-less pool reporting an Integer here, which is
  # the one shape Plan 2b's sweep divides by first. The `max` stays: this must never go
  # below zero.
  #
  # Belt to #balance's braces: with both operands now coerced at their own source this
  # cannot fire, and it is kept because this is the reader the sweep divides BY — the one
  # place in the class where the guarantee has to hold locally rather than by inheritance.
  def free_amount = [(balance - reserve).to_d, 0.to_d].max

  # A dateless goal funds at its rate until the POOL reaches its target. A rate rule's
  # usual "satisfied at my own amount" semantics do not apply here: an ordinary rule is
  # satisfied once the envelope holds its amount, which is right for a budget envelope
  # because a budget envelope is swept and topped back up every period. Savings pools
  # never sweep, so that same reading would leave a $2,400 goal reporting itself funded
  # forever at $150 — the rule's amount is a contribution RATE, not a per-period ceiling.
  #
  # Savings-only, and dateless-only. A budget envelope's target is a display marker, and
  # an account's is the buffer marker — a health line, never a cap. A savings pool that
  # names an anchor_date has a deadline, and the anchored maths already spreads the goal
  # across the periods remaining; that path must keep winning.
  def dateless_goal?
    pool.pool_type_savings? &&
      pool.target_amount.to_d.positive? &&
      pool.budgets.none? { |budget| budget.anchor_date.present? }
  end

  # `min(rate, remaining)`: the final contribution is the remainder, not the rate. Asking
  # for $150 when $40 would finish the goal overshoots the target the user set.
  #
  # `0.to_d`, not a bare `0`: #required feeds a summing caller, and an Integer leaking out
  # of the reached-goal branch makes the return type depend on how well funded the pool is.
  def goal_required
    remaining = pool.target_amount.to_d - balance
    return 0.to_d if remaining <= 0

    rate = pool.budgets.sum(0.to_d) { |budget| per_period_rate(budget) }
    [rate, remaining].min
  end

  # A rule's amount is per-period or per-month depending on its basis, and Budget blesses
  # both shapes without an anchor. Summing them raw mixes units: a $600-a-month rule would
  # ask $600 every fortnight, more than twice the rate the user set, funding a four-month
  # goal in under two. Normalise to a per-period figure before adding.
  #
  # The WHOLE month, not what is left of it, so the goal contributes the same amount every
  # period regardless of when it is asked. Dividing by the periods REMAINING would make the
  # ask lumpier as the month wears on — right for a dated bill catching up, wrong for a goal.
  #
  # `[periods, 1].max` because a user with no cadence configured has no boundaries at all:
  # fall back to the full amount rather than dividing by zero.
  def per_period_rate(budget)
    return budget.amount.to_d if budget.basis_per_paycheck?

    periods = pool.user.period_boundaries(from: today.beginning_of_month, to: today.end_of_month).count
    budget.amount.to_d / [periods, 1].max
  end

  # The `sum` seed is the same type guarantee as #goal_required's, for the pool that holds
  # no rules at all: an unseeded `sum` over an empty set returns the Integer literal 0.
  def required
    return goal_required if dateless_goal?

    budgets_by_due_date.sum(0.to_d) { |budget| budget.calculator(today: today).required(allocated_balances[budget]) }
  end

  def progress_percentage
    return 0 unless pool.target_amount.to_f.positive?

    [(balance / pool.target_amount * 100).round, 100].min
  end

  # `to_d`, not `to_f`: nil-safe in exactly the same way (`nil.to_d` is 0, and account and
  # budget pools legitimately have no target) without routing a money value through binary
  # floating point. Same `0.to_d` reasoning as #free_amount for the overfunded branch.
  def remaining_amount
    [pool.target_amount.to_d - balance, 0.to_d].max
  end

  # A budget envelope whose rate period has ended still holds its leftover — the money is
  # physically there until a distribution moves it. We say so rather than rendering $0,
  # because `Σ pools == your bank balance` is the invariant everything rests on.
  #
  # Savings pools are excluded by TYPE, not by rule shape. A dateless goal is a rate rule on
  # a savings pool (see #dateless_goal?), so "has a rate rule whose period ended" would drain
  # every goal the user has — and #free_amount would hand the sweep a plausible figure to
  # take, because #required reads that rule's amount as a contribution rate while
  # #allocated_balances still clamps the reserve to it. Domain spec §7.2: savings accumulate
  # by definition, so they never sweep.
  #
  # Measured against the date the money ARRIVED, not against today. BudgetCalculator#period_end
  # answers "when does the period containing `today` end", so `period_end(today) < today` is
  # unreachable by construction — end-of-month is never before today, and #boundary_period_end
  # is the day before the next boundary, which is today at the earliest. Verified exhaustively:
  # every cadence x every anchor day x every day of a year x both bases, 15,330 combinations,
  # zero cases where it held. Asking it of the funding date instead is the same sentence about
  # the period that money actually belongs to, and it is the reachable one: $60 paid in on
  # Jul 12 sits in a period that ended Jul 23, and today is Aug 20.
  #
  # `all?`, so the LATEST period governs. An envelope mixing a per-paycheck rule and a monthly
  # one has two different period ends, and until both have rolled some rule still has a live
  # claim on the money. Sweeping at the earlier of the two would take money the monthly rule
  # expects to cover the rest of the month, and #required would then ask for the whole monthly
  # amount again — funding that rule twice in one month. The conservative direction is the
  # right one for a sweep: money staying put can never break the invariant, and never surprises
  # the user by disappearing.
  #
  # Memoised on `defined?` rather than `||=`, because false is the answer for most pools and
  # `||=` would re-run the whole thing every time it came back. Home asks this once per row and
  # #sweepable_amount asks it again, and the false path alone costs three aggregates plus a
  # paid-since-anchor SUM per dated rule.
  def period_closed?
    return @period_closed if defined?(@period_closed)

    @period_closed = compute_period_closed
  end

  # What the next distribution would take back. Never more than the balance, and never less
  # than zero: an overspent envelope has nothing to give, and its deficit is the buffer's
  # problem (spec §7.2) — a negative sweep would be the buffer paying the envelope on the way
  # out, money moving the wrong way through the ledger.
  #
  # `0.to_d` on the early return, not a bare `0`: that is the branch an entry-less envelope
  # takes, and this figure is summed and divided by the distribution. Mutating it to `0` fails
  # the type assertion, so it is the guard actually holding the line here.
  #
  # The subtraction is PARTIAL, not all-or-nothing. An envelope carrying a $500 rent rule and a
  # $100 gas rate rule is closed the moment its rate period ends, and it gives back only what
  # the rent is not holding — an earlier all-or-nothing gate on the rent left that $100 of
  # genuine leftover stranded in every period, forever, because a recurring rule is never
  # `fulfilled?`.
  #
  # The trailing `.to_d` on the clamp is belt to the braces on both operands: `[x, 0.to_d].max`
  # coerces only when the clamp FIRES, and this reader must hold its guarantee locally rather
  # than by inheriting one from #balance that a later edit could quietly withdraw.
  def sweepable_amount
    return 0.to_d unless period_closed?

    [(balance - anchored_reserve).to_d, 0.to_d].max.to_d
  end

  def contributions = movements_in_total + savings_entries_total

  def withdrawals = movements_out_total + expense_entries_total

  private

  # The body of #period_closed?, split out only so the memo above it stays one line of
  # bookkeeping rather than wrapping four guards. Named `compute_` rather than the near-
  # homograph `closed_period?` it used to be: a memo/body pair that governs money movement
  # cannot afford two names distinguishable only by word order.
  #
  # The marker means exactly what it says — this envelope's RATE period has ended. It carries
  # no opinion about the envelope's dated bills; #sweepable_amount subtracts what those hold.
  def compute_period_closed
    return false unless pool.pool_type_budget?

    rate_budgets = pool.budgets.reject { |budget| budget.anchor_date.present? }
    return false if rate_budgets.empty?
    return false if last_funded_on.nil?

    rate_budgets.all? { |budget| budget.calculator(today: last_funded_on).period_end < today }
  end

  # What an unpaid dated bill is already holding. #sweepable_amount is otherwise the whole
  # envelope, so a mixed envelope would sweep the rent to top up the buffer on the strength of
  # its gas rule alone.
  #
  # Reserved by ALLOCATION, not by the rule's amount: #allocated_balances is already this
  # class's single answer to which rules the money is covering, and it fills earliest-due
  # first, so an under-funded envelope reserves what the bill actually has rather than what it
  # wants. A second notion of reserve here would be a second answer to the same question, free
  # to disagree with #reserve and #free_amount.
  def anchored_reserve
    allocated_balances.sum(0.to_d) { |budget, allocated| live_anchored?(budget) ? allocated : 0.to_d }
  end

  # `fulfilled?` is BudgetCalculator's only "no longer live" signal and it is deliberately
  # narrow — only a one-time rule can ever be settled, because a recurring rule always has a
  # next occurrence to fund. A recurring dated bill therefore reserves in every period, which
  # is correct: the money is genuinely spoken for. What is no longer correct is letting that
  # stop the rest of the envelope from sweeping.
  def live_anchored?(budget) = budget.anchor_date.present? && !fulfilled?(budget)

  # One spelling of "settled", for the two readers that ask. #allocated_balances asks it to
  # decide whether the rule holds any of the balance; #live_anchored? asks it to decide whether
  # the rule's holding survives a sweep. A second spelling would let those two answers drift,
  # and they are the pair whose disagreement fix round 2 existed to close — so the memo goes
  # BEHIND the one spelling rather than beside it.
  #
  # Memoised because those two readers ask about the same rule on the same render, and
  # BudgetCalculator#fulfilled? does not memo its own #paid_since_anchor: each call is a fresh
  # calculator running a fresh SUM over the item's entries. Two SUMs per dated rule per pool,
  # on Home, which renders every pool the user has.
  #
  # `fetch` with a block, not `||=`. FALSE is the answer for every live rule — the common case
  # by far, and the one the memo most needs to hold — and `||=` re-runs on a false hit, which
  # is the same trap #period_closed? and #last_funded_on already dodge with `defined?`. A hash
  # keyed on the rule needs the key?-aware form instead.
  def fulfilled?(budget)
    @fulfilled ||= {}
    @fulfilled.fetch(budget) { @fulfilled[budget] = budget.calculator(today: today).fulfilled? }
  end

  # The last day money entered this pool — the period #period_closed? is actually asking about.
  #
  # The three money-IN terms of #balance, and only those: what was spent out of the envelope
  # says nothing about which period funded it. LAST rather than first, because the money sitting
  # here now belongs to the most recent funding — a stray $5 arriving today makes the envelope
  # current, which errs toward leaving money alone.
  #
  # `defined?` rather than `||=`: nil is the answer for a never-funded pool and the common one
  # (a fresh envelope is exactly the shape a sweep meets first), and `||=` would re-run all
  # three aggregates every time it came back.
  #
  # `.to_date` because both `date` columns are datetimes while every calculator here works in
  # whole days; TimeWithZone#to_date resolves in the request's zone, as DateContext expects.
  def last_funded_on
    return @last_funded_on if defined?(@last_funded_on)

    @last_funded_on = [
      scoped(pool.movements_in).maximum(:date),
      scoped(Entry.incomes.merge(entries_for_pool)).maximum(:date),
      scoped(Entry.savings.merge(entries_for_pool)).maximum(:date)
    ].compact.max&.to_date
  end

  # The sort key is a triple, not a bare due date. `sort_by` is not stable and `pool.budgets`
  # carries no ORDER BY, so two rules sharing a due date could swap fill order between calls —
  # the same pool reporting different #required figures on consecutive loads with no data
  # change. `-amount` breaks the tie toward the larger obligation (the bigger bill is the one
  # you can least afford to be short on); `id` makes even identical amounts deterministic.
  def budgets_by_due_date
    @budgets_by_due_date ||= pool.budgets.includes(:item, :pool).sort_by do |budget|
      [budget.calculator(today: today).due_date, -budget.amount, budget.id]
    end
  end

  # Entry.incomes / .expenses already join item: :category, so do not join again.
  # An entry's own pool_id overrides its category's, so both must be honoured —
  # otherwise Entry#pool is a column nothing reads.
  def income_entries_total
    scoped(Entry.incomes.merge(entries_for_pool)).sum(:amount)
  end

  def expense_entries_total
    scoped(Entry.expenses.merge(entries_for_pool)).sum(:amount)
  end

  # TODO(plan-3): delete once §6.1 step 5 converts savings-category entries to movements.
  # Becomes a no-op the moment that migration runs (Entry.savings is then empty), so the
  # removal is mechanical and cannot double-count during the cutover.
  def savings_entries_total
    scoped(Entry.savings.merge(entries_for_pool)).sum(:amount)
  end

  # One predicate rather than .or — Entry.incomes already carries the categories
  # join, and .or rejects relations whose joins differ structurally.
  def entries_for_pool
    Entry.where(
      "entries.pool_id = :id OR (entries.pool_id IS NULL AND categories.pool_id = :id)",
      id: pool.id
    )
  end

  def movements_in_total = scoped(pool.movements_in).sum(:amount)

  def movements_out_total = scoped(pool.movements_out).sum(:amount)

  def scoped(relation)
    @as_of ? relation.where(date: ..@as_of) : relation
  end
end
