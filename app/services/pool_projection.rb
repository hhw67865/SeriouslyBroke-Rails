# frozen_string_literal: true

# WHAT A POOL WOULD HOLD IF SOMETHING THAT HAS NOT HAPPENED YET HAD HAPPENED. PoolCalculator
# answers about the ledger as it stands — five aggregates and the rules they are spoken for by —
# and it now answers only that. The two questions a screen asks about a ledger it has not written
# live here: the sweep the next distribution would take back (`net_of_sweep:`), and the movements
# the distribution or reallocation now on screen is proposing (`pending:`).
#
# See docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md §2.2, §4.3
#
# IT WRAPS A PLAIN CALCULATOR rather than reimplementing one, and delegates everything it does not
# refuse. Both projections are adjustments to the BALANCE, so every reader derived from the balance
# — #allocated_balances, #reserve, #free_amount, #required — inherits them unchanged and no reader
# has to learn about them. Delegating through #method_missing is that sentence written as code, and
# it is what makes the inheritance FUTURE-PROOF IN ONE DIRECTION: a reader added to PoolCalculator
# tomorrow is projected the day it is written, because the object it is delegated to was constructed
# with the adjustment already in it and there is no path here to an unadjusted balance.
#
# THE OTHER DIRECTION IS NOT FREE, AND SAYING SO IS THE POINT. The REFUSAL is an enumerated list —
# PoolCalculator::SWEEP_READERS — and a second reader that names the sweep would be delegated
# straight past it, answering with the plausible phantom figure the guard exists to prevent. The
# adjustment needs no list; the refusal cannot do without one. What the list buys is that it is ONE
# list, read by #method_missing here and named beside the two readers there, so adding a third
# forces the question rather than answering it wrongly by default.
#
# (An enumerated `delegate :balance, :required, …` would not be silently wrong — PoolProjection does
# not inherit from PoolCalculator, so an unlisted reader raises NoMethodError. Loud and pointless
# rather than dangerous. The argument for delegating everything is the one above, not a hazard.)
#
# THE SPLIT ITSELF is plan 2d decision 4. PoolCalculator carried four keyword axes, a bespoke error
# class guarding one combination, and a recursive twin of itself inside its own balance memo; the
# ledger question (`as_of:`) and the clock (`today:`) stayed there because they are questions about
# what IS, while these two are questions about what WOULD BE.
class PoolProjection
  # Raised when a `net_of_sweep` projection is asked what to sweep. See #refuse_when_net_of_sweep:
  # the answer would be a second, smaller sweep, and a second sweep is money moved twice. A named
  # class rather than ArgumentError because AllocationCommitter holds a plain calculator and a
  # projection in the same method and may legitimately want to rescue-and-report this rather than
  # crash a confirm.
  #
  # It travels with the refusal rather than staying behind on PoolCalculator, which no longer has
  # anything to refuse. `PoolCalculator::NetOfSweepError` is kept there as an ALIAS of this class,
  # because the constant is a public name that existing rescues and examples use — see the comment
  # on it.
  class NetOfSweepError < StandardError; end

  # THE MOVEMENTS A SCREEN IS PROPOSING AND HAS NOT WRITTEN — one distribution's whole effect
  # on one pool, which is how the distribution screen asks "and what would this envelope be
  # asking for next period if I funded it $200 instead of $500".
  #
  # Three members rather than one signed number, because the ledger's two movements answer two
  # different questions here and a net figure can only answer the first:
  #
  #   #net is what the BALANCE does — the allocation in less the sweep out — and it is the only
  #   part PoolCalculator#balance needs.
  #
  #   #funded_on is what the CLOCK does. PoolCalculator#period_closed? measures a rate rule's
  #   period from the day the money arrived, and a projection whose money has no arrival date
  #   reads the pool's LAST real funding instead. On a never-funded envelope that is nil, so the
  #   period is not closed, so nothing is swept, so the projection reports a rate envelope funded
  #   $100 as asking $300 next period — when the truth is that its leftover is swept back and it
  #   asks for its full rate again either way. Measured on exactly that shape; see the spec
  #   example "says nothing about an envelope that is swept and topped back up".
  #
  # `funded.positive?` guards the date rather than `net`: a sweep bigger than the allocation is
  # still a funding event, and a $0 override is not one — AllocationCommitter writes no
  # allocation at all for it, so it must not make a closed rate period look live.
  Pending = Data.define(:funded, :swept, :on) do
    def self.none = new(funded: 0.to_d, swept: 0.to_d, on: nil)

    def net = funded - swept

    def funded_on = funded.positive? ? on : nil

    # WHAT THE CALCULATOR IS HANDED, and it is deliberately narrower than what this class holds:
    # the two members #balance and #last_funded_on actually read, with no opinion about which of
    # them was a funding and which a sweep. The ledger does not need to know that a screen is
    # proposing anything; it needs a figure and a date.
    def to_adjustment = PoolCalculator::Adjustment.new(net: net, funded_on: funded_on)

    # Whether this pending changes an answer at all, asked in terms of the two members that
    # reach the calculator rather than of the three that are typed in. `Pending.new(funded: 100,
    # swept: 100, on: today)` moves no balance and still reopens a rate period, so a `net`-only
    # test would call it inert and lose the date.
    def projecting? = !net.zero? || !funded_on.nil?
  end

  # THE ONE DOOR, and the reason it is a factory rather than a constructor: a projection with
  # nothing to project IS the plain calculator, and handing back the calculator itself keeps every
  # caller that asks no projected question on exactly the object it has always had — no wrapper, no
  # #method_missing hop, and `PoolStatus` over an inert `pending:` unchanged down to its class.
  #
  # Pool#calculator delegates its whole signature here, so this is also the answer to "where do the
  # projection keywords live now": in one place, called from the one place a calculator is built
  # from a pool.
  def self.for(pool, net_of_sweep: false, pending: Pending.none, **ledger)
    return PoolCalculator.new(pool, **ledger) unless net_of_sweep || pending.projecting?

    new(pool, net_of_sweep: net_of_sweep, pending: pending, **ledger)
  end

  # `net_of_sweep:` answers a different question about the same pool: not "what is in this
  # envelope" but "what would be in it once the next distribution has taken back what belongs
  # to a period that is over".
  #
  # It exists because #required reads the live balance while the sweep is not materialised
  # until the distribution is confirmed, so a swept envelope's leftover is still sitting in it
  # when the proposal asks what it needs. Groceries holding $85 of last period's money against
  # a $400 rate rule asks for $315, the sweep then takes the $85 away, and the envelope starts
  # the period at $315 — short by exactly its own leftover, silently, every period.
  #
  # Default `false`, so a projection asked only about `pending:` is untouched by it.
  #
  # NOT for the sweep itself, and this is ENFORCED rather than documented: #sweepable_amount
  # and #period_closed? RAISE NetOfSweepError when the flag is set. The sweep they name has
  # already been subtracted, so asking again re-derives a second, smaller one from what the
  # dated rules no longer hold — measured at $400 and then $100 on the same mixed envelope.
  # A comment is not a guard on a money path: the failure is not an exception but a silently
  # misplaced $100, and the caller most likely to make it is a committer holding a plain and a
  # flagged calculator in the same method. Ask a plain calculator what to sweep; ask this one
  # what to fund.
  #
  # `pending:` is the SAME KIND of thing and is deliberately built in the same shape — see Pending
  # for what it carries and why it is a value rather than a number. It answers "what would this
  # pool hold once the distribution now on screen had happened", which is the question the override
  # consequence asks: fund Rent $200 instead of $500 and the envelope carries $300 less into the
  # next period, so the next period's ask is larger.
  #
  # `**ledger` IS THE CALCULATOR'S OWN SIGNATURE, PASSED THROUGH UNREAD — `as_of:`, `today:` and
  # `terms:`. A splat rather than three keywords, and that is a guard rather than brevity: the twin
  # below has to be built over the SAME ledger world as the projection, and every keyword written
  # out by hand there is a keyword a later edit can forget. `terms:` was exactly that bug waiting
  # to happen (see #twin), and with a splat there is nothing to forget — the twin and the projected
  # calculator take the same hash, or neither is built at all.
  def initialize(pool, net_of_sweep: false, pending: Pending.none, **ledger)
    @pool = pool
    @net_of_sweep = net_of_sweep
    @pending = pending
    @ledger = ledger
  end

  # THE ONE DELEGATION PATH, AND THE ONE PLACE THE SWEEP IS REFUSED. Every reader of the projected
  # pool arrives here — #balance, #required, #free_amount, #allocated_balances and the rest answer
  # over the projected balance, and the ones that name the sweep are refused first.
  #
  # WHY REFUSE HERE RATHER THAN IN TWO NAMED METHODS. Two overrides would have covered exactly
  # today's two readers, and a third sweep reader added to PoolCalculator later would have been
  # delegated straight past them: `#sweepable_amount` on a projected balance does not return zero,
  # it returns `balance − anchored_reserve` over an already-swept balance, which on the mixed
  # envelope is a plausible-looking $100 — and a plausible number is exactly what a committer cannot
  # detect. One list, consulted on every delegated call, is the version of that guard that a future
  # reader cannot walk around; PoolCalculator names the same constant beside the two readers, so
  # writing a third puts the question in front of the person writing it.
  #
  # THE GUARD SITS ON THE PROJECTION and the calculator underneath carries none. That is stronger
  # than the pair of guards it replaces: those sat at the top of two public methods precisely
  # because #sweepable_amount reaches #period_closed? through the public door and a guard one level
  # down would fire twice with a message naming the wrong reader. The inner calculator is a plain
  # one, so its own #sweepable_amount → #period_closed? call cannot reach a guard at all, and the
  # message can only ever name the reader the caller actually asked for.
  #
  # WHAT THIS REPRODUCES FROM `delegate_missing_to`, which it replaced when the guard needed a place
  # to stand: public methods only (so the calculator's privates stay private, exactly as before),
  # and an unknown name falling through to a NoMethodError naming this class rather than being
  # swallowed.
  #
  # WHAT IT IMPROVES: the oracle is the CLASS, not the instance, so #respond_to? answers without
  # building anything. `delegate_missing_to`'s `calculator.respond_to?` would have run the twin's
  # five aggregates to answer a question about a method table. The two oracles cannot disagree —
  # PoolCalculator defines no #method_missing of its own, so what it responds to IS what it defines.
  def method_missing(name, *, &)
    refuse_when_net_of_sweep(name) if PoolCalculator::SWEEP_READERS.include?(name)
    return super unless PoolCalculator.public_method_defined?(name)

    calculator.public_send(name, *, &)
  end

  def respond_to_missing?(name, include_private = false)
    PoolCalculator.public_method_defined?(name) || super
  end

  private

  # THE PROJECTED CALCULATOR, built at FIRST READ and not in #initialize, and that is the same
  # staleness rule everything else on these screens obeys: /distributions/new renders inside a
  # transaction that has just DELETED this period's split, and a calculator built before that
  # deletion would answer about a world the screen is not showing. Nothing here touches the
  # database until a reader asks — construction is four ivars.
  #
  # "FIRST READ" MEANS THE FIRST DELEGATED READER OF ANY KIND, WHICH IS WIDER THAN WHAT IT REPLACED,
  # and the difference is stated rather than glossed. The sweep used to be derived inside
  # PoolCalculator#balance's memo, so the twin's five aggregates ran at the first BALANCE read and
  # `calculator.today` cost nothing; here the adjustment is a constructor argument, so the first
  # delegated call — money or not — builds the twin. #respond_to? is deliberately outside that (see
  # #respond_to_missing?), which was the sharpest edge of it.
  #
  # KEPT THAT WAY ON PURPOSE. Making the adjustment lazy — an object the calculator consults at
  # balance time — would narrow the window back and would trade a guarantee held BY CONSTRUCTION for
  # one held by a memo: as a constructor argument the adjustment is applied exactly once, before the
  # calculator can answer anything, and there is no reachable state in which a balance has been read
  # with the adjustment half-applied. That property is worth more than the window, because the
  # window is only reachable by reading a non-money reader off a projection BEFORE any money reader
  # and ACROSS a write — and nothing in app/ reads a non-money reader off one at all (grepped:
  # `#pool` and `#today` are never asked of a calculator anywhere in the app; every caller asks
  # #balance, #required, #free_amount or #allocated_balances first). Measured: all six screens'
  # query counts unchanged.
  #
  # `||=` and not the `defined?` form: this is an object, never nil or false. The `defined?` form
  # is reserved for readers whose answer is legitimately falsy (see PoolCalculator#period_closed?).
  def calculator = @calculator ||= PoolCalculator.new(@pool, **@ledger, adjustment: adjustment)

  # WHAT THE BALANCE IS MOVED BY, and the one place the two projections meet. `pending` on its own
  # travels straight through; with `net_of_sweep` the twin's sweep is taken off the same figure,
  # because the two are one arithmetic question — what does this pool hold once both the movements
  # on screen and the movements the confirm will write have happened.
  #
  # `#with(net:)` rather than a second Adjustment written out: the DATE is the pending's own and is
  # not touched by a sweep. Money leaving an envelope is not a funding event, so a projection that
  # sweeps $85 out of Groceries must not report Groceries as funded today — the pool's rate period
  # would then read as live from a date the ledger never had.
  #
  # Computed inside #calculator's memo, so it costs one extra pass over the pool's aggregates and
  # only on the projections that asked for a sweep.
  def adjustment
    return @pending.to_adjustment unless @net_of_sweep

    @pending.to_adjustment.with(net: @pending.net - twin.sweepable_amount)
  end

  # THE PLAIN TWIN, over the same pool, differing from the projection in nothing but the sweep it
  # drops. Derived from a plain calculator rather than from the projected one, and that is not a
  # stylistic choice: #sweepable_amount reads #balance (through #anchored_reserve), so computing it
  # over the projected balance would be the balance defined in terms of itself. The twin also keeps
  # ONE reader of the sweep — the figure subtracted here is the same figure the proposal lists as
  # `swept back from Groceries` and the same one AllocationCommitter writes as a `sweep` movement,
  # because all three are #sweepable_amount on a plain calculator.
  #
  # `@pending` IS PASSED THROUGH, and it has to be, on both of its members. The twin exists to
  # answer "what would the next distribution take back", and the next distribution takes it back
  # from the balance the pool will actually be holding — including whatever this screen is
  # proposing to put in, and measured from the day that money arrives. Dropped here, a projection
  # of next period's ask would sweep the OLD balance and then subtract it from the new one: on a
  # rate envelope funded $400 the twin would sweep $85 (last period's leftover) instead of $400,
  # and the projection would report the envelope already funded and asking for nothing.
  #
  # `@ledger` IS PASSED THROUGH FOR THE SAME REASON, and it is the difference between batching this
  # class and not batching it. The twin reads the SAME pool over the SAME ledger world, so injecting
  # the `terms:` already in hand is not an optimisation of a different question, it is the same
  # question asked twice. Dropped here, every `net_of_sweep` projection quietly runs its own five
  # aggregates inside its own balance, and those are the majority on every screen the plan measures:
  # the ask on Home, the ask in the fill, both asks behind a reallocation's damage. It would have
  # undone most of the saving while every figure still agreed, which is the shape a measurement
  # catches and a test does not — so `spec/services/pool_balance_ledger_spec.rb` counts the SUMs
  # this line is responsible for (10 unbatched, none batched) rather than trusting the figures.
  def twin = PoolCalculator.new(@pool, **@ledger, adjustment: @pending.to_adjustment)

  def refuse_when_net_of_sweep(reader)
    return unless @net_of_sweep

    raise NetOfSweepError,
          "##{reader} is meaningless on a net_of_sweep calculator: the sweep it names has " \
          "already been subtracted from the balance, so asking again derives a second one. " \
          "Build a plain PoolCalculator to ask what to sweep."
  end
end
