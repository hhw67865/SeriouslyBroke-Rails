# frozen_string_literal: true

# Computes a pool's balance and how that balance is spoken for by its rules.
# See docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md §2.2, §4.3
class PoolCalculator
  # Raised when a `net_of_sweep` calculator is asked what to sweep. See #initialize and
  # #refuse_when_net_of_sweep: the answer would be a second, smaller sweep, and a second sweep
  # is money moved twice. A named class rather than ArgumentError because Task 3 holds a plain
  # and a flagged calculator in the same method and may legitimately want to rescue-and-report
  # this rather than crash a confirm.
  class NetOfSweepError < StandardError; end

  # THE MOVEMENTS A SCREEN IS PROPOSING AND HAS NOT WRITTEN — one distribution's whole effect
  # on one pool, which is how the distribution screen asks "and what would this envelope be
  # asking for next period if I funded it $200 instead of $500".
  #
  # Three members rather than one signed number, because the ledger's two movements answer two
  # different questions here and a net figure can only answer the first:
  #
  #   #net is what the BALANCE does — the allocation in less the sweep out — and it is the only
  #   part #balance needs.
  #
  #   #funded_on is what the CLOCK does. #period_closed? measures a rate rule's period from the
  #   day the money arrived, and a projection whose money has no arrival date reads the pool's
  #   LAST real funding instead. On a never-funded envelope that is nil, so the period is not
  #   closed, so nothing is swept, so the projection reports a rate envelope funded $100 as
  #   asking $300 next period — when the truth is that its leftover is swept back and it asks
  #   for its full rate again either way. Measured on exactly that shape; see the spec example
  #   "says nothing about an envelope that is swept and topped back up".
  #
  # `funded.positive?` guards the date rather than `net`: a sweep bigger than the allocation is
  # still a funding event, and a $0 override is not one — AllocationCommitter writes no
  # allocation at all for it, so it must not make a closed rate period look live.
  Pending = Data.define(:funded, :swept, :on) do
    def self.none = new(funded: 0.to_d, swept: 0.to_d, on: nil)

    def net = funded - swept

    def funded_on = funded.positive? ? on : nil
  end

  attr_reader :pool, :today

  # `net_of_sweep:` answers a different question about the same pool: not "what is in this
  # envelope" but "what would be in it once the next distribution has taken back what belongs
  # to a period that is over". It is a property of the BALANCE, so every reader built on the
  # balance — #allocated_balances, #reserve, #free_amount, #required — inherits it unchanged.
  #
  # It exists because #required reads the live balance while the sweep is not materialised
  # until the distribution is confirmed, so a swept envelope's leftover is still sitting in it
  # when the proposal asks what it needs. Groceries holding $85 of last period's money against
  # a $400 rate rule asks for $315, the sweep then takes the $85 away, and the envelope starts
  # the period at $315 — short by exactly its own leftover, silently, every period.
  #
  # Default `false`, so every existing caller is untouched and this cannot change a number on
  # any screen that does not ask for it.
  #
  # NOT for the sweep itself, and this is ENFORCED rather than documented: #sweepable_amount
  # and #period_closed? RAISE NetOfSweepError when the flag is set. The sweep they name has
  # already been subtracted, so asking again re-derives a second, smaller one from what the
  # dated rules no longer hold — measured at $400 and then $100 on the same mixed envelope.
  # A comment is not a guard on a money path: the failure is not an exception but a silently
  # misplaced $100, and the caller most likely to make it is a committer holding a plain and a
  # flagged calculator in the same method. Ask a plain calculator what to sweep; ask this one
  # what to fund.
  # `pending:` is the SAME KIND of thing as `net_of_sweep:` and is deliberately built in the
  # same shape: an adjustment to the BALANCE, so every reader derived from the balance —
  # #allocated_balances, #reserve, #free_amount, #sweepable_amount, #required — inherits it
  # unchanged and no reader has to learn about it. See Pending for what it carries and why it
  # is a value rather than a number.
  #
  # It answers "what would this pool hold once the distribution now on screen had happened",
  # which is the question the override consequence asks: fund Rent $200 instead of $500 and the
  # envelope carries $300 less into the next period, so the next period's ask is larger.
  #
  # Default `Pending.none`, so every existing caller is untouched and this cannot change a
  # number on any screen that does not ask for it.
  # `terms:` IS THE SAME FIVE AGGREGATES, ALREADY RUN — a `{income:, savings:, expense:,
  # movements_in:, movements_out:}` hash from PoolBalanceLedger, which computes them for a whole
  # set of pools in five grouped queries instead of five per calculator. When it is present the
  # five `*_total` readers return the injected figures and NO aggregate runs here; when it is
  # absent this class queries exactly as it always has.
  #
  # It is a COST keyword and not a money one, which is the whole of why it is safe: the ledger
  # reproduces #income_entries_total's scoping and the other four's line for line, including the
  # entries-for-pool predicate and the `as_of` bound, so an injected calculator and a plain one
  # over the same pool are the same numbers. That is asserted in both directions — the default
  # pinned equal to today's figures, and a deliberately wrong term pinned as visibly MOVING the
  # balance, because a keyword that is inert when set is worth nothing.
  #
  # `nil` rather than an empty hash for "not batched": an empty hash is a ledger that answered
  # for a pool it does not know, and that must not read as "run your own queries" — it reads as
  # a KeyError instead (see #term).
  #
  # SAME `as_of` OR NOTHING. The ledger bounds its terms by `as_of` itself, so a caller handing
  # terms from one moment to a calculator asking about another gets a balance from neither. One
  # ledger per `as_of`; PoolBalanceLedger carries its own for exactly this reason.
  # rubocop:disable Metrics/ParameterLists -- the fifth keyword, and the disable is stated rather
  # than the limit raised for the whole app: Plan 2b's review already named this signature as a
  # class that has stopped being one idea (four orthogonal axes, now five), and a global Max of 6
  # would spread that permission to every other method instead of marking it here. `terms:` is
  # also the one axis that is not a QUESTION about the pool — as_of, today, net_of_sweep and
  # pending each change what is being asked, while this only changes who ran the query.
  def initialize(pool, as_of: nil, today: Date.current, net_of_sweep: false, pending: Pending.none, terms: nil)
    @pool = pool
    @as_of = as_of
    @today = today
    @net_of_sweep = net_of_sweep
    @pending = pending
    @terms = terms
  end
  # rubocop:enable Metrics/ParameterLists

  # Deliberately start-date-agnostic. The balance this replaces filtered entries to
  # `pool.start_date..`; a pool's balance is all the money in it, with no cutoff — the
  # movement ledger simply starts empty. `start_date` survives as a savings-goal display
  # attribute, not a balance filter. See the spec example that pins this.
  #
  # `.to_d` on the RESULT. Every `sum(:amount)` term here returns the Integer literal 0 when
  # its set is empty, and a pool holding nothing at all — a fresh envelope, the first shape a
  # sweep meets — made all five Integers, so #balance, #reserve, #free_amount and
  # PoolStatus#balance/#amount all changed TYPE on exactly the pools that are emptiest. Coerced
  # once here so every reader downstream inherits the guarantee, and INSIDE the memo so what is
  # stored is already a BigDecimal.
  #
  # SINCE #sweep_adjustment JOINED THIS SUM, THE COERCION NO LONGER FIRES. That method returns
  # a BigDecimal on both of its branches, so the whole expression is a BigDecimal before `.to_d`
  # is reached and dropping it now fails nothing (measured: 163 examples, 0 failures). It stays
  # because it is the thing that absorbs a regression one line down — make #sweep_adjustment
  # return a bare `0` and this method still answers in BigDecimal (0 failures), while dropping
  # BOTH takes out three type examples across PoolCalculator and PoolStatus. Stated rather than
  # left claiming a protection the measurement no longer shows.
  #
  # Memoised. These are five aggregates and almost every other reader in this class starts
  # here — #allocated_balances, #free_amount, #sweepable_amount, #progress_percentage and
  # #remaining_amount all ask — so a single render of a single pool ran them several times
  # over: measured at ten entry/movement aggregates for one closed envelope, now five.
  #
  # `||=`, matching #allocated_balances below, and NOT the `defined?` form. That form is not a
  # house style to be applied evenly: it is reserved in this class for the three readers whose
  # answer is legitimately falsy — #period_closed? (false for most pools), #last_funded_on (nil
  # for a never-funded one) and #fulfilled? (false for every live rule) — where `||=` really
  # would re-run on every hit. This reader cannot return nil or false. A zero balance is the
  # tempting counter-example and it is not one: `0`, and `BigDecimal("0")` with it, are TRUTHY
  # in Ruby, so `||=` memoises the entry-less envelope exactly as well as any other. Measured
  # both ways — three #balance calls on an entry-less pool cost five aggregates under either
  # form. Using `defined?` here would imply a falsy answer this method cannot produce.
  #
  # STALE AFTER A WRITE, deliberately and not newly. #allocated_balances, #period_closed?,
  # #last_funded_on, #budgets_by_due_date and #fulfilled? are already memoised and every one of
  # them derives from this number, so a calculator held across a movement or entry write has
  # been answering from a snapshot since long before this memo existed. This makes an existing
  # hazard honest rather than adding a new class of it. The rule it rests on, which Task 2 and
  # Task 3 carry: anything that writes movements builds fresh calculators afterward.
  def balance
    @balance ||= (income_entries_total + savings_entries_total + movements_in_total + @pending.net -
      movements_out_total - expense_entries_total - sweep_adjustment).to_d
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
    refuse_when_net_of_sweep(:period_closed?)
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
    refuse_when_net_of_sweep(:sweepable_amount)
    return 0.to_d unless period_closed?

    [(balance - anchored_reserve).to_d, 0.to_d].max.to_d
  end

  # `.to_d` ON THE SUM, and it is the type guarantee holding at the one place `terms:` could
  # otherwise break it. Both operands are `0` the Integer on an empty pool when this calculator
  # runs its own aggregates, and both are BigDecimal when a ledger hands them over — so without
  # this, these two readers changed SHAPE with which caller built the calculator, which is
  # exactly what "inert by default" is supposed to forbid. No rendered figure moved (nothing
  # divides by these), and a keyword whose inertness is true only of the figures is not inert.
  # Asserted by type on an empty pool down BOTH paths.
  def contributions = (movements_in_total + savings_entries_total).to_d

  def withdrawals = (movements_out_total + expense_entries_total).to_d

  # Income that landed in this pool inside `range` — the distribution screen's "income this
  # period", and the only part of #balance that screen can name separately.
  #
  # Here rather than in the presenter because "which entries belong to this pool" is one
  # question with one answer (#entries_for_pool: the entry's own pool_id, else its category's),
  # and a presenter rebuilding that predicate would be a second one — free to disagree with
  # the balance the same figure is subtracted from. Through #scoped for the same reason every
  # other entry reader is: an `as_of` calculator must not report income it has not reached yet.
  #
  # `.to_d` because an empty `sum(:amount)` is the Integer literal 0, and this is subtracted
  # from a BigDecimal available to produce the buffer line.
  def income_within(range)
    scoped(Entry.incomes.merge(entries_for_pool)).where(date: range).sum(:amount).to_d
  end

  private

  # The two readers that answer "what does the next distribution take back", refusing the one
  # calculator that cannot answer it. Both guards sit at the top of their PUBLIC method rather
  # than inside #compute_period_closed, because #sweepable_amount reaches #period_closed?
  # through the public door too and a guard one level down would fire twice with a message
  # naming the wrong reader.
  #
  # Raising is not defensive tidiness here. #sweepable_amount on a flagged calculator does not
  # return zero — it returns `balance − anchored_reserve` over an already-swept balance, which
  # on the mixed envelope is a plausible-looking $100. A plausible number is exactly what a
  # committer cannot detect.
  def refuse_when_net_of_sweep(reader)
    return unless @net_of_sweep

    raise NetOfSweepError,
          "##{reader} is meaningless on a net_of_sweep calculator: the sweep it names has " \
          "already been subtracted from the balance, so asking again derives a second one. " \
          "Build a plain PoolCalculator to ask what to sweep."
  end

  # What `net_of_sweep:` takes off the balance, and zero for every other calculator.
  #
  # Derived from a PLAIN calculator over the same pool rather than from `self`, and that is
  # not a stylistic choice: #sweepable_amount reads #balance (through #anchored_reserve), so
  # computing it on `self` would recurse until the stack ran out. The plain twin also keeps
  # one reader of the sweep — the figure subtracted here is the same figure the proposal
  # lists as `swept back from Groceries` and the same one AllocationCommitter writes as a
  # `sweep` movement, because all three are `sweepable_amount` on an unflagged calculator.
  #
  # Built inside #balance's memo, so it costs one extra pass over the pool's aggregates and
  # only on the calculators that asked for it.
  #
  # `pending:` IS PASSED THROUGH, and it has to be, on both of its members. The twin exists to
  # answer "what would the next distribution take back", and the next distribution takes it back
  # from the balance the pool will actually be holding — including whatever this screen is
  # proposing to put in, and measured from the day that money arrives. Dropped here, a
  # projection of next period's ask would sweep the OLD balance and then subtract it from the
  # new one: on a rate envelope funded $400 the twin would sweep $85 (last period's leftover)
  # instead of $400, and the projection would report the envelope already funded and asking for
  # nothing.
  #
  # `terms:` IS PASSED THROUGH FOR THE SAME REASON, and it is the difference between batching
  # this class and not batching it. The twin reads the SAME pool over the SAME ledger world — it
  # differs from `self` in nothing but the flag it drops — so injecting the figures already in
  # hand is not an optimisation of a different question, it is the same question asked twice.
  # Dropped here, every `net_of_sweep` calculator quietly runs its own five aggregates inside its
  # own balance, and those calculators are the majority on every screen this task measures: the
  # ask on Home, the ask in the fill, both asks behind a reallocation's damage. It would have
  # undone most of the saving while every figure still agreed, which is the shape a measurement
  # catches and a test does not.
  def sweep_adjustment
    return 0.to_d unless @net_of_sweep

    self.class.new(pool, as_of: @as_of, today: today, pending: @pending, terms: @terms).sweepable_amount
  end

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
      scoped(Entry.savings.merge(entries_for_pool)).maximum(:date),
      @pending.funded_on
    ].compact.max&.to_date
  end

  # The sort key is a triple, not a bare due date, and it is BudgetCalculator#due_order's — the
  # one place that rule lives, shared with PoolStatus#anchored_budgets and the three presenters
  # that name a rule. `sort_by` is not stable and `pool.budgets` carries no ORDER BY, so two
  # rules sharing a due date could otherwise swap fill order between calls: the same pool
  # reporting different #required figures on consecutive loads with no data change.
  def budgets_by_due_date
    @budgets_by_due_date ||= pool.budgets.includes(:item, :pool).sort_by do |budget|
      budget.calculator(today: today).due_order
    end
  end

  # THE FIVE AGGREGATES, EACH BEHIND THE SAME GATE. `term` returns the injected figure when this
  # calculator was handed a ledger's terms and otherwise runs the block, so the query and the
  # batched answer sit in one place per term and cannot describe different scopes.
  #
  # `fetch` without a default, deliberately: a terms hash missing a key is a ledger that does not
  # compute what this class needs, and the loud KeyError is the only honest answer. A `0.to_d`
  # default here would report an envelope holding nothing — a wrong number, silently, on the one
  # path this whole keyword exists to make cheaper.
  def term(name)
    return @terms.fetch(name) if @terms

    yield
  end

  # Entry.incomes / .expenses already join item: :category, so do not join again.
  # An entry's own pool_id overrides its category's, so both must be honoured —
  # otherwise Entry#pool is a column nothing reads.
  def income_entries_total
    term(:income) { scoped(Entry.incomes.merge(entries_for_pool)).sum(:amount) }
  end

  def expense_entries_total
    term(:expense) { scoped(Entry.expenses.merge(entries_for_pool)).sum(:amount) }
  end

  # TODO(plan-3): delete once §6.1 step 5 converts savings-category entries to movements.
  # Becomes a no-op the moment that migration runs (Entry.savings is then empty), so the
  # removal is mechanical and cannot double-count during the cutover.
  def savings_entries_total
    term(:savings) { scoped(Entry.savings.merge(entries_for_pool)).sum(:amount) }
  end

  # One predicate rather than .or — Entry.incomes already carries the categories
  # join, and .or rejects relations whose joins differ structurally.
  #
  # THE EXPRESSION IS PoolBalanceLedger's, NOT A SECOND SPELLING OF IT. This used to read
  # `entries.pool_id = :id OR (entries.pool_id IS NULL AND categories.pool_id = :id)`, which is
  # equivalent to the ledger's COALESCE on every arm — the entry's own pool where it has one, its
  # category's where it does not, and NEITHER matching when both are NULL — but equivalent by
  # argument rather than by construction. Two SQL forms of the rule the whole invariant rests on,
  # in two files, with nothing making them move together, is the two-readers defect this branch
  # has found in every task; the ledger's own header warns against it one layer down. Sharing the
  # literal makes the equivalence a fact of the source: there is one place to change, and a
  # change that breaks one path cannot leave the other reading the old rule.
  #
  # The constant lives on PoolBalanceLedger rather than here because that is the class that has
  # to GROUP BY it — the OR form cannot be grouped, so the COALESCE is the shape with the strictly
  # wider job, and it is the batched path that would otherwise be free to drift.
  def entries_for_pool
    Entry.where("#{PoolBalanceLedger::ENTRY_POOL_ID} = :id", id: pool.id)
  end

  def movements_in_total = term(:movements_in) { scoped(pool.movements_in).sum(:amount) }

  def movements_out_total = term(:movements_out) { scoped(pool.movements_out).sum(:amount) }

  def scoped(relation)
    @as_of ? relation.where(date: ..@as_of) : relation
  end
end
