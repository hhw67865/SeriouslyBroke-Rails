# frozen_string_literal: true

# THE FIVE TERMS OF PoolCalculator#balance, FOR ANY NUMBER OF POOLS, IN FIVE QUERIES.
#
# Every PoolCalculator runs five aggregates of its own, and every screen here builds several
# DISTINCT calculators per pool — the plain one, the `net_of_sweep` one, the twin that one
# builds inside its own balance, a projected one per override. Measured at the end of Plan 2b:
# Home 407 queries, /distributions/new 574 with two edits, reallocation 269. The cost is
# structural rather than per-path, so this is the structural answer: ONE query per term for the
# whole set of pools a screen is about, handed to the calculators through `terms:`.
#
# It computes NOTHING of its own. Each term reproduces the scoping of the PoolCalculator method
# it replaces, line for line — the same three entry scopes, the same entries-for-pool predicate,
# the same two movement directions, the same `as_of` bound — because the only acceptable outcome
# of this class is that no figure anywhere moves. A second definition of "what is in this pool"
# would be exactly the two-readers defect this branch has found in every task.
#
# A SNAPSHOT, STALE AFTER A WRITE, on the same rule PoolCalculator#balance already carries: the
# terms are memoised at their FIRST READ, not at construction, and anything that writes movements
# or entries must build a fresh ledger afterwards.
#
# FIRST READ RATHER THAN CONSTRUCTION IS THIS CLASS'S OWN GUARANTEE, and #totals is the whole of
# it: every caller above is memoised, so a ledger handed out at construction time and read later
# would be the one figure in the app measured against a world that may since have been written to.
# Pinned by "reads the ledger at first use rather than at construction" in this class's spec — a
# movement written between `new` and the first read, and both the ledger and an AllocationCalculator
# built before it report the write.
#
# It is pinned HERE and not left to AllocationCommitter's re-run examples, which the review
# correctly noted would stay green against an eager ledger (the committer builds its proposal
# after the deletion, so its ordering never exercises this). Mutation-tested both ways: computing
# the terms in #initialize fails that example immediately, while building AllocationCalculator's
# ledger object eagerly does NOT — the guarantee is in #totals, not in that memo.
#
# See docs/superpowers/plans/2026-08-16-budget-page.md Task 1.
class PoolBalanceLedger
  # The five members of #terms_for, in the order they appear in PoolCalculator#balance. Named
  # once so a caller reading a term this class does not compute gets a KeyError rather than a
  # silent zero (see PoolCalculator#term).
  TERMS = [:income, :savings, :expense, :movements_in, :movements_out].freeze

  # WHICH POOL AN ENTRY REACHES — the one expression, shared with PoolCalculator#entries_for_pool
  # rather than restated there.
  #
  # The entry's own pool wins where it has one, and its category's pool answers where it does not;
  # an entry with neither reaches no pool, because `COALESCE(NULL, NULL) = :id` is NULL and NULL
  # is not true. That is the same rule the unbatched path used to spell as
  # `entries.pool_id = :id OR (entries.pool_id IS NULL AND categories.pool_id = :id)`, arm for
  # arm — and it is written this way round because a COALESCE can be GROUPED BY while an OR
  # cannot: the OR asks "does this row belong to THIS pool", this asks "which pool does this row
  # belong to", and only the second can answer for every pool in one pass.
  #
  # `Entry.incomes` and its two siblings already carry the `item: :category` join, so nothing is
  # joined twice — and it is an INNER join on both paths, which is what keeps them identical. A
  # LEFT JOIN here would let the batched path see item-less or category-less rows the per-pool
  # path (which merges these same scopes) never sees.
  ENTRY_POOL_ID = Arel.sql("COALESCE(entries.pool_id, categories.pool_id)")

  attr_reader :as_of

  # `pools` is the WHOLE set a screen is going to ask about, records rather than ids so callers
  # pass the collection they already hold. Unsaved pools are dropped rather than queried for: an
  # id-less pool matches no row, and `IN (NULL)` matches nothing in Postgres either — but a nil
  # in the list would then make #terms_for answer for every other unsaved pool as well.
  #
  # `as_of` is PoolCalculator's own, and it bounds all five terms exactly as #scoped does there.
  # It is part of the LEDGER rather than of a term because a calculator asking about an earlier
  # moment is asking about a different world: one ledger per `as_of`, never one shared across two.
  def initialize(pools, as_of: nil)
    @pool_ids = Array(pools).filter_map(&:id).uniq
    @known = @pool_ids.to_set
    @as_of = as_of
  end

  # The five terms for one pool, as `PoolCalculator.new(pool, terms:)` consumes them.
  #
  # `fetch` with a `0.to_d` default, and both halves are load-bearing. A grouped sum returns a
  # hash with NO KEY AT ALL for a pool that has no rows in that term — the emptiest pools, which
  # is the shape a fresh envelope and a brand-new account both take — so `[]` would hand back nil
  # and `balance` would raise on it. And the default is `0.to_d` rather than `0` because
  # PoolCalculator's whole type guarantee is that a money reader does not change shape with how
  # the pool is funded; an Integer here leaks into #balance, #reserve, #free_amount and
  # PoolStatus#amount on exactly the pools that hold nothing. Six Integer leaks on this branch so
  # far, every one of them at an empty set.
  #
  # `nil` FOR A POOL THIS LEDGER WAS NOT BUILT OVER, and never a set of zeros for it. That pool
  # is outside every grouped query here, so its terms are not missing — they were never asked
  # for, and the two are different facts. nil is what `PoolCalculator.new(terms: nil)` already
  # means: run your own five aggregates. The pool pays for itself and reports the same figures it
  # reports today, which is the only acceptable answer on a money screen; drift between a
  # caller's ledger set and its iteration costs queries and cannot cost accuracy.
  #
  # MEASURED, not defensive. HomePresenter#current_buffer_for is public and takes any account,
  # and spec/presenters/home_presenter_spec.rb's "is a decimal zero, not an integer, for a user
  # with nothing" asks it about an account created AFTER the presenter memoised its pool list —
  # a `let` referenced for the first time inside the example. Built to raise, this class took
  # that example down; the pool is a real pool with a real balance, and the ledger simply does
  # not know it.
  def terms_for(pool)
    return nil unless @known.include?(pool.id)

    TERMS.index_with { |term| totals(term).fetch(pool.id, 0.to_d) }
  end

  private

  # Memoised per term, and the win is ACROSS CALLS rather than across terms: #terms_for builds all
  # five for the pool it is asked about, so the first call pays for the whole set and every
  # #terms_for after it — one per pool, several per pool where a screen builds a plain and a
  # flagged calculator and a status — is free. Five queries for a screen, not five per calculator.
  #
  # `fetch` with a block rather than `||=`: a grouped sum over a term with no rows at all is `{}`,
  # which is falsy-adjacent enough to matter if this ever memoised on truthiness — `||=` would
  # re-run the query on every hit for exactly the emptiest ledger. (`{}` is truthy in Ruby today,
  # so this is the form that stays right rather than the form that fixes a live bug.)
  def totals(term)
    @totals ||= {}
    @totals.fetch(term) { @totals[term] = compute(term) }
  end

  def compute(term)
    case term
    when :income then entry_totals(Entry.incomes)
    when :savings then entry_totals(Entry.savings)
    when :expense then entry_totals(Entry.expenses)
    when :movements_in then movement_totals(:to_pool_id)
    when :movements_out then movement_totals(:from_pool_id)
    end
  end

  # One grouped SUM per entry kind. The WHERE and the GROUP BY are the same expression, so a row
  # can only be counted for a pool the predicate itself assigns it to — an entry whose category
  # belongs to somebody else's pool is outside the IN list and is not summed for anybody, which
  # is what an unbatched calculator does too (it filters on one pool id and sees nothing else).
  def entry_totals(scope)
    scoped(scope)
      .where("#{ENTRY_POOL_ID} IN (:ids)", ids: @pool_ids)
      .group(ENTRY_POOL_ID)
      .sum(:amount)
  end

  # `pool.movements_in` / `#movements_out` are `to_pool_id` / `from_pool_id` on PoolMovement and
  # carry no other condition, so the batched form is the same rows with the id read back out.
  def movement_totals(column)
    scoped(PoolMovement.where(column => @pool_ids)).group(column).sum(:amount)
  end

  # PoolCalculator#scoped, and deliberately the same expression: `date` is a datetime column on
  # both tables and the bound is inclusive, so a ledger and an unbatched calculator asked about
  # the same instant have to include the same rows.
  def scoped(relation)
    as_of ? relation.where(date: ..as_of) : relation
  end
end
