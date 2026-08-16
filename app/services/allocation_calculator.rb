# frozen_string_literal: true

# What the next distribution would do to one account, and nothing else: this class WRITES
# NOTHING. It sweeps what belongs to a closed period, adds it to the account's unallocated
# cash, asks every envelope what it needs, and fills them top-down by priority until the
# money runs out. AllocationCommitter turns the answer into PoolMovement rows.
#
# STALE AFTER A WRITE, by construction and on purpose. Every figure here is memoised, and the
# PoolCalculators underneath memoise their balances — so a proposal held across a movement
# write keeps answering from the snapshot it was built on. That is right for a proposal, whose
# whole job is to describe one moment before anything moves, and it is the reason the committer
# must build FRESH calculators after it writes rather than reusing these. Do not hand a
# proposal's calculators to anything that writes.
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §5, §7.2
class AllocationCalculator
  # `short` rather than a stored field: it is `needed - funded` by definition, and a fourth
  # member would be a second place for the same number to be wrong.
  Row = Struct.new(:pool, :needed, :funded, keyword_init: true) do
    def short = needed - funded
  end

  # `user` is the ownership context the controller already holds; the arithmetic is entirely
  # `account`'s. Kept in the signature because every screen that builds one has a current_user
  # and an account, and a proposal that could be built for someone else's account is not a
  # shape worth making available.
  attr_reader :user, :account, :today

  def initialize(user:, account:, today: Date.current)
    @user = user
    @account = account
    @today = today
  end

  # What the next distribution takes back, keyed by the envelope it comes from.
  #
  # There is NO `period_closed?` filter here, deliberately. #sweepable_amount already returns
  # `0.to_d` unless the period is closed, so a second gate would be a second answer to the
  # same question, free to disagree with the amount actually being taken. `positive?` alone
  # keeps the zero rows out — including the closed-but-empty envelope and the overdrawn one,
  # neither of which has anything to give.
  #
  # Savings pools are absent because #sweepable_amount excludes them by pool TYPE (a dateless
  # goal is a rate rule on a savings pool, so eligibility by rule shape drains every goal the
  # user has). Nothing here re-states that rule; there is one place it lives.
  def sweeps
    @sweeps ||= envelopes.each_with_object({}) do |pool, swept|
      amount = calculator_for(pool).sweepable_amount
      swept[pool] = amount if amount.positive?
    end
  end

  def total_swept = sweeps.values.sum(0.to_d)

  # The account's unallocated cash PLUS the sweeps, and the addition is not double-counting.
  # Swept money is inside the account's *total* (`Σ pools`) but not inside its buffer: it is
  # sitting in an envelope, and the sweep is what moves it out. The account's own #balance
  # already excludes it, because funding the envelope was a movement out.
  #
  # Not clamped at zero. An overdrawn account genuinely has less than nothing to hand out,
  # and #fill's per-row clamp already refuses to fund from a negative pot — so the overdraft
  # survives into #leftover, where it is a fact the screen must state, rather than being
  # quietly rounded up to "nothing left".
  #
  # The trailing `.to_d` FIRES NO MUTATION today and is kept anyway, for the reason
  # PoolCalculator#free_amount keeps its own: both operands are already coerced at their own
  # source, and this is the figure every row's clamp is measured against — the one place the
  # type guarantee should hold locally rather than by inheriting one a later edit could
  # quietly withdraw. Stated rather than claimed as a protection it does not currently provide.
  def available
    @available ||= (account_calculator.balance + total_swept).to_d
  end

  # One row per envelope that asks for something, in the order the money reaches them.
  def rows
    @rows ||= fill
  end

  def total_allocated = rows.sum(0.to_d, &:funded)

  # What stays in the account buffer. Derived from #available rather than recomputed, so the
  # proposal cannot hand out more than it said it had.
  def leftover = available - total_allocated

  # Answers the question the distribution SCREEN branches on: does any envelope end this
  # distribution with less than it asked for? Read off the rows, never off
  # `total_allocated < Σ needed` — those disagree the moment a zero-need pool or a rejected
  # row enters the picture, and only the rows can say WHICH envelope is starved.
  def short? = rows.any? { |row| row.short.positive? }

  private

  # One read, one order, shared by the sweep and the fill so the two can never disagree about
  # which pools are in this account. `Pool.by_priority` is `[priority, name]` — priority alone
  # is not a total order, and a tie falling through to database order means random UUID bytes
  # deciding which envelope gets funded.
  def envelopes
    @envelopes ||= account.child_pools.by_priority.to_a
  end

  # Spends `remaining` down as it goes, so each envelope is funded out of what the ones above
  # it left behind — that IS the waterfall.
  #
  # Zero-need rows are rejected AFTER the fill, never before, exactly as HomePresenter#waterfall
  # does: rejecting first cannot change the arithmetic (a zero-need row funds zero and consumes
  # nothing) but it would put the two screens' row sets at risk of drifting apart, and a
  # "$0.00 of $0.00" line below the point the money ran out reads as money DENIED rather than
  # money not wanted.
  #
  # `[required, 0.to_d].max`, and it is not decoration. `clamp(0, negative)` raises
  # ArgumentError, and a negative ask is reachable: PoolCalculator#goal_required returns
  # `[rate, remaining].min`, so a savings goal carrying a rule with a negative amount asks for
  # a negative figure and this method takes the whole distribution screen down with a 500.
  # Measured, not assumed — `update_column(:amount, -150)` past the validation reproduces it,
  # and the example below pins it. Budget validates the sign, but a validation is an input
  # rule and this is a read path; #allocated_balances defends the same shape one level down
  # for the same reason. Clamping `needed` rather than only the bound also keeps the ROW
  # coherent: a zero ask is rejected below, where a negative one would have rendered
  # "-$150.00 needed" and made #short? read healthy.
  def fill
    remaining = available
    filled = envelopes.map do |pool|
      needed = [ask_calculator_for(pool).required, 0.to_d].max
      funded = remaining.clamp(0.to_d, needed)
      remaining -= funded
      Row.new(pool: pool, needed: needed, funded: funded)
    end
    filled.reject { |row| row.needed.zero? }
  end

  # The plain calculator: what this pool holds RIGHT NOW. The sweep is read from here.
  def calculator_for(pool) = (@calculators ||= {})[pool.id] ||= pool.calculator(today: today)

  # The post-sweep calculator: what this pool would need if its sweep had already happened.
  # The ask is read from here, and from here only.
  #
  # This is the whole reason `net_of_sweep:` exists. #required reads the live balance, and at
  # proposal time the leftover is still in the envelope — so a swept envelope would ask for its
  # rule LESS its own leftover, receive that, and start the period short by exactly the amount
  # the sweep took. Not recoverable by adding the sweep back onto #required afterwards: on a
  # mixed envelope, removing the swept money changes which rules #allocated_balances fills and
  # by how much, so only substituting the balance and re-reading gives the right answer.
  #
  # Unconditional, rather than only for pools that appear in #sweeps. A pool with nothing to
  # sweep subtracts `0.to_d` and this is provably the same object's answer as the plain
  # calculator's — so a conditional would buy a handful of queries at the price of a second
  # path through the money.
  def ask_calculator_for(pool)
    (@ask_calculators ||= {})[pool.id] ||= pool.calculator(today: today, net_of_sweep: true)
  end

  # The account is not one of its own envelopes, so it gets its own memo rather than a row.
  def account_calculator = @account_calculator ||= account.calculator(today: today)
end
