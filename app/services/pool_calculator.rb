# frozen_string_literal: true

# Computes a pool's balance and how that balance is spoken for by its rules.
# See docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md §2.2, §4.3
#
# THE LEDGER AS IT STANDS, AND ONLY THAT. Plan 2d decision 4 moved the two questions about a ledger
# nobody has written yet — the coming sweep, and the movements a screen is proposing — out to
# PoolProjection, which wraps one of these and owns the adjustment arithmetic, the twin it needs and
# the refusal that guards it. What stayed is what this class can answer from rows that exist:
# `as_of:` (a ledger question — which rows had happened by then), `today:` (the clock every
# calculator shares) and `terms:` (the same aggregates, run by somebody else).
class PoolCalculator
  # THE REFUSAL'S OTHER NAME. The class itself now lives on PoolProjection — the object that raises
  # it — and this is an ALIAS of that one class, not a second error. It stays because the constant
  # is a PUBLIC name: `rescue PoolCalculator::NetOfSweepError` is what AllocationCommitter's comment
  # names and what pool_calculator_spec asserts in both directions, and `raise`/`rescue` compare by
  # object identity, so the two names cannot come to mean different things.
  #
  # IT IS ALSO THE ONE LOAD-TIME REFERENCE BETWEEN THESE TWO CLASSES, and it runs in this direction
  # ONLY. PoolProjection names PoolCalculator inside method bodies alone (`.for`, #calculator, #twin,
  # Pending#to_adjustment), so loading this file loads that one and stops. Adding a load-time
  # reference the other way — `adjustment: PoolCalculator::Adjustment.none` as a default in
  # PoolProjection's signature is the tempting one — closes the cycle, and it fails in the ugliest
  # available way: this class object exists by then but Adjustment below does not, so it is a
  # NameError on boot rather than a circular-require warning.
  NetOfSweepError = PoolProjection::NetOfSweepError

  # THE READERS THAT NAME THE SWEEP, in one list because two classes have to agree about them.
  # #sweepable_amount and #period_closed? below answer "what does the next distribution take back",
  # which is the one question a net_of_sweep projection cannot answer — its sweep has already been
  # subtracted, so asking again derives a second, smaller one. PoolProjection refuses every
  # delegated call whose name is in here (see PoolProjection#method_missing).
  #
  # A CONSTANT RATHER THAN TWO OVERRIDES THERE, and this is the whole of what it buys: a third
  # reader of the sweep added to this class later is delegated straight past a pair of hand-written
  # overrides and answers with a plausible phantom figure. It cannot walk past a list — but only if
  # whoever writes it knows the list exists, which is why the list is named HERE, beside the readers
  # it is about, and not only in the class that consults it.
  SWEEP_READERS = [:sweepable_amount, :period_closed?].freeze

  # THE PROJECTION SEAM, and the whole of what this class knows about projections: a figure the
  # balance treats as already moved, and the day that money arrived. PoolProjection computes both
  # and hands them over; see PoolProjection::Pending, where the reasoning about what they MEAN
  # lives. Nothing here asks what they describe — an adjustment is arithmetic, and this class does
  # not need to know that a screen is proposing anything.
  #
  # TWO MEMBERS RATHER THAN ONE SIGNED NUMBER, and they are read by two different readers for two
  # different reasons: #net is what the BALANCE does, #funded_on is what the CLOCK does (see
  # #last_funded_on). A projection that moved money with no arrival date and a projection that
  # moved none are not the same question, and one number cannot tell them apart.
  #
  # `.none` carries `0.to_d` rather than a bare `0` because #balance sums it with five aggregate
  # terms, and this class's type guarantee is that a money reader never changes shape with how a
  # pool is funded — see #balance.
  Adjustment = Data.define(:net, :funded_on) do
    def self.none = new(net: 0.to_d, funded_on: nil)
  end

  attr_reader :pool, :today

  # `adjustment:` IS A PROJECTION'S ARITHMETIC, ALREADY DONE — see Adjustment above and
  # PoolProjection for who computes it. It is applied in exactly two places (#balance and
  # #last_funded_on) and inherited everywhere else, because every other reader here is derived from
  # those: #allocated_balances, #reserve, #free_amount, #sweepable_amount, #required and
  # #period_closed? all read one of them and none of them has to learn about projections.
  #
  # Default `Adjustment.none`, so a calculator built without one is the ledger as it stands and no
  # figure on a screen that asks no projected question can move.
  #
  # `terms:` IS THE SAME AGGREGATES, ALREADY RUN — a `{income:, savings:, expense:, movements_in:,
  # movements_out:, last_funded_on:}` hash from PoolBalanceLedger, which computes them for a whole
  # set of pools in one grouped query per term instead of that many per calculator. When it is
  # present the five `*_total` readers and #funded_at return the injected values and NO aggregate
  # runs here; when it is absent this class queries exactly as it always has.
  #
  # It is a COST keyword and not a money one, which is the whole of why it is safe: the ledger
  # reproduces #income_entries_total's scoping and the other four's line for line, including the
  # entries-for-pool predicate and the `as_of` bound, so an injected calculator and a plain one
  # over the same pool are the same numbers. That is asserted in both directions — the default
  # pinned equal to today's figures, and a deliberately wrong term pinned as visibly MOVING the
  # balance, because a keyword that is inert when set is worth nothing.
  #
  # The sixth member is a DATE and not money, and it carries the same both-direction pin one
  # question further along: a wrong-on-purpose `last_funded_on` must visibly move #period_closed?,
  # because that is the reader it exists for and a date nothing consumes would be a no-op nobody
  # could see.
  #
  # `nil` rather than an empty hash for "not batched": an empty hash is a ledger that answered
  # for a pool it does not know, and that must not read as "run your own queries" — it reads as
  # a KeyError instead (see #term).
  #
  # SAME `as_of` OR NOTHING. The ledger bounds its terms by `as_of` itself, so a caller handing
  # terms from one moment to a calculator asking about another gets a balance from neither. One
  # ledger per `as_of`; PoolBalanceLedger carries its own for exactly this reason.
  #
  # THE `rubocop:disable Metrics/ParameterLists` THAT USED TO SIT HERE IS GONE, and that is the
  # visible half of what decision 4 was for. It read: "the fifth keyword, and the disable is stated
  # rather than the limit raised for the whole app: Plan 2b's review already named this signature as
  # a class that has stopped being one idea (four orthogonal axes, now five)". The two axes that
  # made it four have moved to PoolProjection, so the list is back under the limit on its own and
  # there is nothing left to grant permission for. `terms:` remains the one axis that is not a
  # QUESTION about the pool — `as_of` and `today` change what is being asked, while this only
  # changes who ran the query.
  def initialize(pool, as_of: nil, today: Date.current, adjustment: Adjustment.none, terms: nil)
    @pool = pool
    @as_of = as_of
    @today = today
    @adjustment = adjustment
    @terms = terms
  end

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
  # SINCE AN ADJUSTMENT JOINED THIS SUM, THE COERCION NO LONGER FIRES. `Adjustment.none` carries
  # `0.to_d` and every projected one is BigDecimal arithmetic over it, so the whole expression is a
  # BigDecimal before `.to_d` is reached and dropping it now fails nothing. RE-MEASURED after the
  # projection split, over pool_calculator_spec + pool_status_spec (107 examples): `.to_d` dropped,
  # 0 failures; `Adjustment.none` carrying a bare `0` instead, 0 failures; BOTH dropped, exactly
  # THREE failures — the type examples at pool_calculator_spec:253 and pool_status_spec:639,651.
  # It stays because it is the thing that absorbs a regression one line up, and the three failures
  # are what says the pair is doing the work rather than either one alone.
  #
  # (The same sentence used to name #sweep_adjustment, which was the BigDecimal operand before
  # decision 4 moved the sweep to PoolProjection. The guarantee did not move: what enters this sum
  # from outside the five aggregates is still a BigDecimal by construction, and it is still the
  # only operand that is.)
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
    @balance ||= (income_entries_total + savings_entries_total + movements_in_total + @adjustment.net -
      movements_out_total - expense_entries_total).to_d
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

  # A rule's amount is per-period or per-month depending on its basis, and Budget blesses both
  # shapes without an anchor. Summing them raw mixes units: a $600-a-month rule would ask $600
  # every fortnight, more than twice the rate the user set, funding a four-month goal in under
  # two. Normalise to a per-period figure before adding.
  #
  # `Budget#steady_ask`, NOT a normalisation of this file's own. It used to divide by the
  # boundaries falling inside the CALENDAR MONTH, and that made a standing rate depend on which
  # month you asked in: measured on a $260-a-month rule under the demo's biweekly cadence, it
  # answered $130 in nine months of 2026 and $86.67 in March and August, the two months holding a
  # third boundary. A 50% swing in a savings goal's contribution with no data change, and neither
  # figure is the rate the user set — $260 a month is $120 a period, always, because 26 periods a
  # year is what biweekly means. `steady_ask` says $120 in every month.
  #
  # Two answers to "what does a monthly rule claim per period" is the exact defect this branch
  # polices hardest, and the second answer was about to become load-bearing: Task 6 makes
  # `steady_ask` the baseline the drift detector compares against, so the app would have held both
  # figures on one page. Collapsed here rather than there, while only dateless goals read it.
  #
  # THE OLD COMMENT'S TWO GUARANTEES BOTH SURVIVE, more strongly than before:
  #   - "the whole month, not what is left of it" — `steady_ask` never looks at the calendar for
  #     an anchorless rule at all, so the ask cannot get lumpier as the month wears on.
  #   - the no-cadence fallback — `User#periods_per_year` answers 12 for an undeclared user, so a
  #     monthly rule still passes through at its full amount instead of dividing by zero.
  #
  # Only two shapes reach here: #dateless_goal? requires every rule on the pool to be anchorless,
  # and Budget#shape_must_be_valid pins an anchorless rule to per-period or to a 1-month
  # interval. `steady_ask` answers both directly (`:per_period` passes the amount through), so
  # this delegates whole rather than branching first.
  def per_period_rate(budget) = budget.steady_ask(pool.user, today: today)

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
  # `all?`, so the LATEST period governs. An envelope mixing a per-period rule and a monthly
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
  # THE REFUSAL THAT USED TO OPEN THIS METHOD IS NOW PoolProjection'S, on the object that has a
  # sweep to be wrong about. This calculator answers the question honestly for every caller,
  # because a calculator whose balance has had a sweep taken off it is no longer one of these —
  # it is a PoolProjection, and that is where the guard sits. Same public surface: the two readers
  # still raise NetOfSweepError when asked of a `net_of_sweep` object, which is what
  # `pool.calculator(net_of_sweep: true)` hands back.
  #
  # THIS AND #sweepable_amount ARE SWEEP_READERS, and a THIRD reader that answers "what would the
  # next distribution take back" belongs in that constant on the day it is written. Delegation
  # projects a new reader automatically; it does not refuse one automatically.
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
  # whole days; TimeWithZone#to_date resolves in the request's zone, as DateContext expects. It
  # stays HERE, on the calculator, rather than moving into the ledger with the query: the ledger
  # is built once per screen while the zone that matters is the request's, and a date resolved at
  # ledger-construction time would be one step further from it for no gain.
  #
  # The ADJUSTMENT'S date is added AFTER the batched value and never travels through the ledger. It
  # is a property of what THIS calculator is projecting — one screen's unwritten distribution —
  # while the ledger describes rows that exist; folding it in would make one shared ledger answer
  # differently for two calculators over the same pool.
  #
  # `.compact.max` and not `@adjustment.funded_on || funded_at`: a projection dated today over a
  # pool funded yesterday and one over a pool funded next month are different worlds, and LAST is
  # the rule (see above). Both are nil on a never-funded pool with nothing projected into it, and
  # that nil is the answer the `defined?` memo exists to hold.
  def last_funded_on
    return @last_funded_on if defined?(@last_funded_on)

    @last_funded_on = [funded_at, @adjustment.funded_on].compact.max&.to_date
  end

  # THE THREE MAX(date)s, BEHIND THE SAME GATE AS THE FIVE SUMS. Injected when a ledger ran them
  # for the whole pool set — 24 of /budget's 50 queries and 48 of Home's, measured — and run here
  # when it did not, over exactly the three money-IN scopes of #balance.
  #
  # The pre-`to_date` maximum rather than the finished answer, because that is what the ledger can
  # honestly compute: a TimeWithZone or nil, the same shape `maximum(:date)` returns below. Nil
  # travels through `term` untouched — `@terms.fetch` finds the key and returns its nil value
  # rather than yielding — which is what keeps #last_funded_on's `defined?` memo from re-running
  # three aggregates on the never-funded envelope this whole reader exists to answer nil for.
  def funded_at
    term(PoolBalanceLedger::FUNDED_ON) do
      [
        scoped(pool.movements_in).maximum(:date),
        scoped(Entry.incomes.merge(entries_for_pool)).maximum(:date),
        scoped(Entry.savings.merge(entries_for_pool)).maximum(:date)
      ].compact.max
    end
  end

  # The sort key is a triple, not a bare due date, and it is BudgetCalculator#due_order's — the
  # one place that rule lives, shared with PoolStatus#anchored_budgets and the three presenters
  # that name a rule. `sort_by` is not stable and `pool.budgets` carries no ORDER BY, so two
  # rules sharing a due date could otherwise swap fill order between calls: the same pool
  # reporting different #required figures on consecutive loads with no data change.
  def budgets_by_due_date
    @budgets_by_due_date ||= rules.sort_by { |budget| budget.calculator(today: today).due_order }
  end

  # THE POOL'S RULES, READ OFF THE ASSOCIATION — the same `pool.budgets` #dateless_goal?,
  # #goal_required and #compute_period_closed already enumerate, and that consistency is the point
  # rather than a side effect.
  #
  # This used to be `pool.budgets.includes(:item, :pool)`, which is a NEW RELATION and therefore a
  # fresh SELECT every time, whatever the caller had already loaded. It defeated every eager load
  # in the app — HomePresenter and ReallocationPresenter both preload `:budgets` — and it cost up
  # to THREE queries per calculator that reached it (the budgets, the items, the pools) on top of
  # the association load its three siblings above trigger anyway. Plan 2c priced it at 38 of
  # Home's 100 queries; measured again as the only change in the tree, this one line took Home
  # from 100 to 61, /budget from 45 to 41 and /pool_movements/new from 63 to 25, with every
  # rendered figure and the whole stripped page text byte-identical on all seven screens.
  #
  # It also left this class disagreeing with itself. The three readers above see the association's
  # loaded target and this one saw a fresh SELECT, so on a pool whose rules had been written to
  # since the association loaded, #period_closed? and #allocated_balances were answering about
  # DIFFERENT SETS OF RULES on the same object. Reading the association here removes that split:
  # there is now one answer to "which rules does this pool have", and the staleness rule is the
  # one PoolCalculator already carries and callers already obey (see #balance's STALE AFTER A
  # WRITE note) — anything that writes builds fresh objects afterward, the pool included.
  #
  # THE PRELOADER RATHER THAN `includes`, and it is what keeps the N+1 away without re-querying:
  # given records whose association is already loaded it runs NOTHING (measured: 0 queries when
  # the caller preloaded `budgets: :item`), and given records without it, one query for the whole
  # set. `includes` cannot do that here, because a relation with `includes` on it is a second read
  # of the rows by construction.
  #
  # IT IS INERT ON THE DEMO SEEDS AND IS KEPT ANYWAY, stated because a line that fires on nothing
  # measurable is one somebody will delete. Removing it moves no figure and no query count on any
  # of the seven screens measured — two of the demo's fifteen rules carry an item, and both of
  # those items are loaded by another reader on the same page. It is the guarantee the old
  # `includes(:item)` carried, and the shape that needs it is a pool with SEVERAL item-bearing
  # dated rules: measured on one built for the purpose, six such rules cost 1 item load with this
  # line and 6 without it (21 queries against 26). BudgetCalculator#fulfilled? and #overdue? read
  # `budget.item` for every dated rule, so the cost is per rule, on the reader #required calls.
  #
  # `:pool` STAYS IN THE LIST even though the association's automatic `inverse_of` already hands
  # each rule back the very pool it came from — measured at 0 queries either way. It costs nothing
  # to keep and it is the one thing standing between BudgetCalculator#user (`category&.user ||
  # pool&.user`) and a lookup per rule if that inverse is ever lost.
  #
  # UNMEMOISED BECAUSE IT HAS ONE MEMOISED CALLER. Re-running the Preloader is a no-op, but the
  # `to_a` dup is per call — memoise here before adding a second caller.
  def rules
    budgets = pool.budgets.to_a
    ActiveRecord::Associations::Preloader.new(records: budgets, associations: [:item, :pool]).call
    budgets
  end

  # EVERY AGGREGATE, EACH BEHIND THE SAME GATE. `term` returns the injected value when this
  # calculator was handed a ledger's terms and otherwise runs the block, so the query and the
  # batched answer sit in one place per term and cannot describe different scopes.
  #
  # `fetch` without a default, deliberately: a terms hash missing a key is a ledger that does not
  # compute what this class needs, and the loud KeyError is the only honest answer. A `0.to_d`
  # default here would report an envelope holding nothing — a wrong number, silently, on the one
  # path this whole keyword exists to make cheaper.
  #
  # `fetch` IS ALSO WHAT MAKES THE SIXTH TERM'S NIL SAFE, and it is key-aware rather than
  # truthiness-aware — which is the whole distinction. `last_funded_on` is legitimately nil for a
  # never-funded pool, so the tempting `@terms[name] || yield` would read that real answer as a
  # miss and run the three MAX(date)s anyway, on exactly the emptiest pools this term exists to
  # answer cheaply: the same falsy-answer trap #period_closed?, #last_funded_on and #fulfilled?
  # each dodge one level up with `defined?` and keyed `fetch`. Mutation-tested — `|| yield` here
  # leaves a batched calculator running three maxima of its own, and the ledger spec's
  # "runs three grouped maxima where per-pool calculators run three each" says so.
  #
  # (`fetch(name) { yield }` would be safe on nil and is still not used: the block would swallow
  # the missing-key case that must raise.)
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
