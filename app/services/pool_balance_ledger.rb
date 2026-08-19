# frozen_string_literal: true

# THE TERMS OF PoolCalculator#balance, FOR ANY NUMBER OF POOLS, IN ONE QUERY EACH.
#
# Every PoolCalculator runs four aggregates of its own, and every screen here builds several
# DISTINCT calculators per pool — the plain one, the `net_of_sweep` projection, the plain twin
# that projection builds to derive its sweep, a projected one per override. Measured at the end of Plan 2b:
# Home 407 queries, /distributions/new 574 with two edits, reallocation 269. The cost is
# structural rather than per-path, so this is the structural answer: ONE query per term for the
# whole set of pools a screen is about, handed to the calculators through `terms:`.
#
# It computes NOTHING of its own. Each term reproduces the scoping of the PoolCalculator method
# it replaces, line for line — the same two entry scopes, the same entries-for-pool predicate,
# the same two movement directions, the same `as_of` bound — because the only acceptable outcome
# of this class is that no figure anywhere moves. A second definition of "what is in this pool"
# would be exactly the two-readers defect this branch has found in every task.
#
# THE FIFTH TERM IS A DATE RATHER THAN AN AMOUNT, and it is here for the same measured reason the
# four money ones are. PoolCalculator#last_funded_on runs two MAX(date) aggregates — one entry,
# one movement — over EXACTLY the two money-IN scopes already batched above, and Task 3's fix
# round priced it: 24 of /budget's 50 queries and 48 of Home's, the single largest named residue
# on both. It reuses `grouped_entries` and `grouped_movements` verbatim rather than restating
# their WHERE and GROUP BY, so the batched MAX cannot see a row the batched SUM does not.
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
  # The four MONEY members of #terms_for, in the order they appear in PoolCalculator#balance.
  # Named once so a caller reading a term this class does not compute gets a KeyError rather than
  # a silent zero (see PoolCalculator#term).
  #
  # `:savings` IS GONE, AND IT WENT IN THE SAME COMMIT AS THE ENUM VALUE (plan 3, task 5). It summed
  # `Entry.savings` — entries in a savings-TYPE category — and a contribution is a `PoolMovement`
  # now, counted by `:movements_in` one term along. The cutover migration converted every savings
  # entry this app ever wrote, so the term read `0.to_d` for every pool of every user before it was
  # deleted, and the balance below is unchanged to the byte.
  MONEY_TERMS = [:income, :expense, :movements_in, :movements_out].freeze

  # The fifth, and it is SEPARATE from the four rather than appended to them because its EMPTY
  # ANSWER IS DIFFERENT IN KIND. A pool with no rows sums to `0.to_d` — it holds nothing — but it
  # was not funded on the zeroth of anything, and PoolCalculator#compute_period_closed reads
  # `last_funded_on.nil?` as its guard: any date at all here, epoch included, marks every fresh
  # envelope's rate period closed and hands it to the sweep. So this term defaults to nil and
  # cannot travel through the `fetch(pool.id, 0.to_d)` the four money terms share.
  FUNDED_ON = :last_funded_on

  # Every member of #terms_for, which is the hash PoolCalculator consumes whole.
  TERMS = [*MONEY_TERMS, FUNDED_ON].freeze

  # WHICH POOL AN ENTRY REACHES — the one expression, THE START-DATE RULE included
  # (main-account spec §3), shared with PoolCalculator#entries_for_pool rather than restated there.
  #
  # In order: the entry's own pool override; else its category's pool, but an envelope/goal only
  # from its start_date onward — earlier entries fall to the user's MAIN account
  # (users.default_account_id), because that is where history physically happened. Account pools
  # have no date gate, and a pool-less category still reaches no pool: NULL, never the
  # main-account fallback, which is reserved for history displaced by a start date.
  #
  # THE START DATE IS THE ENVELOPE'S, NOT THE CATEGORY'S CONNECTION DATE (ruled 2026-08-18).
  # Connecting an old category to a mid-life envelope counts its spending back to that date and no
  # further; before the rule, the re-point dragged the category's whole lifetime into a
  # never-funded envelope, which is the defect §1 opens with. It is a READ-side rule only — no row
  # is rewritten, and `Σ pools == bank truth` is untouched, because every displaced entry lands in
  # the main account rather than nowhere.
  #
  # The first two arms are the rule this used to be in full: the entry's own pool wins where it
  # has one, and an entry with neither pool nor category-pool reaches no pool, because
  # `COALESCE(NULL, NULL) = :id` is NULL and NULL is not true. That is the same rule the unbatched
  # path used to spell as
  # `entries.pool_id = :id OR (entries.pool_id IS NULL AND categories.pool_id = :id)`, arm for
  # arm — and it is written this way round because a COALESCE can be GROUPED BY while an OR
  # cannot: the OR asks "does this row belong to THIS pool", this asks "which pool does this row
  # belong to", and only the second can answer for every pool in one pass.
  #
  # `Entry.incomes` and its two siblings already carry the `item: :category` join, so nothing is
  # joined twice — and it is an INNER join on both paths, which is what keeps them identical. A
  # LEFT JOIN here would let the batched path see item-less or category-less rows the per-pool
  # path (which merges these same scopes) never sees.
  #
  # THE BOUNDARY IS THE USER'S DAY, AND THE TWO `AT TIME ZONE`s ARE WHY. `entries.date` is a
  # DATETIME column while `pools.start_date` is a DATE, and ApplicationController wraps every
  # request in `Time.use_zone(current_user.timezone)` — so an entry a Tokyo user files ON Aug 1 is
  # stored `2026-07-31 15:00:00`, nine hours before the UTC day it belongs to begins. Compared raw,
  # that entry is "before" a start date it is actually on, and every east-of-UTC user's first day of
  # an envelope would be exiled to main. The first `AT TIME ZONE 'UTC'` reads the naive timestamp as
  # the UTC instant Rails wrote, the second renders that instant in the OWNER'S zone, and `::date`
  # takes the calendar day the user was living in. `users.timezone` is nullable and validated
  # against `TZInfo::Timezone.all_identifiers`, which is the same IANA set Postgres knows, so the
  # COALESCE to 'UTC' covers the user who has not chosen one and nothing else can reach it.
  #
  # `Pool.pool_types[:account]` RATHER THAN THE LITERAL 0. The enum's numbering is a mapping this
  # codebase has renumbered before, and a bare 0 in a string of SQL is the one copy of it a rename
  # cannot reach.
  ENTRY_POOL_ID = Arel.sql(<<~SQL.squish)
    COALESCE(
      entries.pool_id,
      CASE
        WHEN categories.pool_id IS NULL THEN NULL
        WHEN category_pools.pool_type = #{Pool.pool_types[:account]} THEN categories.pool_id
        WHEN (entries.date AT TIME ZONE 'UTC' AT TIME ZONE COALESCE(category_users.timezone, 'UTC'))::date
             >= category_pools.start_date THEN categories.pool_id
        ELSE category_users.default_account_id
      END
    )
  SQL

  # The two joins ENTRY_POOL_ID now needs beside the `item: :category` join every caller
  # already carries. ALIASED — `Entry.in_pool_named` joins bare `pools` itself, and a second
  # bare `pools` would be ambiguous. Every consumer of the constant consumes these with it.
  #
  # LEFT on the pool and INNER on the user, and the asymmetry is the two columns' own: a category
  # with no pool is a shape the database still holds (the belongs_to is required at the model, not
  # below it), and an INNER join there would DROP its entries from the query entirely rather than
  # resolve them to NULL — the CASE's first arm exists to answer for exactly those rows and would
  # never be reached. `categories.user_id` is NOT NULL with a foreign key, so its join adds no row
  # and removes none; it is INNER so the expression cannot silently read a NULL default account
  # from a missing row instead of from a user who has not chosen one.
  ENTRY_POOL_JOINS = [
    "LEFT JOIN pools AS category_pools ON category_pools.id = categories.pool_id",
    "INNER JOIN users AS category_users ON category_users.id = categories.user_id"
  ].freeze

  # WHAT A SHARED LEDGER IS REFUSED FOR. Raised by #for_as_of! and named as a constant because a
  # `rescue` of it would be a caller deciding to read figures from a moment it did not ask about;
  # there is no such caller and there should not be one, but a bare RuntimeError could be swallowed
  # by a broad rescue without anyone noticing which rule had fired.
  class AsOfMismatch < StandardError; end

  attr_reader :as_of

  # `pools` is the WHOLE set a screen is going to ask about, records rather than ids so callers
  # pass the collection they already hold. Unsaved pools are dropped rather than queried for: an
  # id-less pool matches no row, and `IN (NULL)` matches nothing in Postgres either — but a nil
  # in the list would then make #terms_for answer for every other unsaved pool as well.
  #
  # `as_of` is PoolCalculator's own, and it bounds every term exactly as #scoped does there.
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
  # `[]` RATHER THAN `fetch` ON THE FIFTH, and that is the whole of the nil-vs-default discipline
  # this term needs: a pool absent from the grouped MAX hash has never been funded, and nil is the
  # answer PoolCalculator#last_funded_on already gives for it. The key is always PRESENT with a nil
  # value, which is what keeps PoolCalculator#term's `fetch`-without-default silent here (a missing
  # key is a ledger that does not compute what the calculator needs; a nil value is a real answer)
  # and what keeps #last_funded_on's `defined?` memo from re-running on it.
  def terms_for(pool)
    return nil unless @known.include?(pool.id)

    MONEY_TERMS.index_with { |term| totals(term).fetch(pool.id, 0.to_d) }
      .merge(FUNDED_ON => totals(FUNDED_ON)[pool.id])
  end

  # THIS LEDGER, IF IT IS ABOUT THE MOMENT THE CALLER IS ASKING ABOUT — the `as_of` half of
  # PoolCalculator's "SAME `as_of` OR NOTHING", turned from a sentence in a comment into a raise.
  #
  # Every consumer that accepts a ledger from somebody else calls this instead of trusting it:
  # AllocationCalculator#share_ledger and ReallocationPresenter#initialize today. It returns SELF
  # on a match so it reads as a checked handover (`@ledger = other.for_as_of!(nil)`) rather than
  # as a predicate somebody can forget to branch on — an `agrees_with?` returning a boolean is the
  # same guard with an ignorable answer.
  #
  # WHY IT MATTERS EVEN THOUGH IT CANNOT FIRE TODAY. Nothing on either injecting path has an
  # `as_of` at all — both consumers build unbounded ledgers, so both hand `nil` in — and that is
  # the reason to write it now rather than later: the mismatch it forbids is INVISIBLE when it
  # happens. A ledger bounded to Jul 31 answers with real, well-formed figures for a screen asking
  # about today; the balance is simply from a month ago, on every pool at once, and no reader
  # downstream has any way to tell. It is the one wrong answer this whole batching seam can
  # produce that would not look wrong.
  #
  # The message names both moments and the rule, because "one ledger per `as_of`" is the fact the
  # person reading the backtrace needs, not the two values on their own.
  def for_as_of!(wanted)
    return self if as_of == wanted

    raise AsOfMismatch,
          "this ledger is bounded at #{as_of.inspect} and the caller is asking about " \
          "#{wanted.inspect}: one ledger per `as_of`, never one shared across two"
  end

  private

  # Memoised per term, and the win is ACROSS CALLS rather than across terms: #terms_for builds all
  # five for the pool it is asked about, so the first call pays for the whole set and every
  # #terms_for after it — one per pool, several per pool where a screen builds a plain and a
  # flagged calculator and a status — is free. Four queries for a screen, not four per calculator.
  #
  # `fetch` with a block rather than `||=`: a grouped sum over a term with no rows at all is `{}`,
  # which is falsy-adjacent enough to matter if this ever memoised on truthiness — `||=` would
  # re-run the query on every hit for exactly the emptiest ledger. (`{}` is truthy in Ruby today,
  # so this is the form that stays right rather than the form that fixes a live bug.) The sixth
  # term needs that form for a second reason: it costs TWO queries, so a memo that missed on the
  # empty ledger would re-run both per pool — the exact cost this term exists to remove.
  def totals(term)
    @totals ||= {}
    @totals.fetch(term) { @totals[term] = compute(term) }
  end

  def compute(term)
    case term
    when :income then entry_totals(Entry.incomes)
    when :expense then entry_totals(Entry.expenses)
    when :movements_in then movement_totals(:to_pool_id)
    when :movements_out then movement_totals(:from_pool_id)
    when FUNDED_ON then funding_dates
    end
  end

  # THE LAST DAY MONEY ENTERED EACH POOL — the two money-IN scopes of PoolCalculator#balance and
  # only those, exactly as PoolCalculator#last_funded_on names them: what was spent out of an
  # envelope says nothing about which period funded it.
  #
  # THERE WERE THREE, AND THE SAVINGS LEG DIED WITH THE ENUM VALUE (plan 3, task 5) — a MAX(date)
  # over `Entry.savings`, which the cutover emptied. It cannot move a date it is dropped from: the
  # money it dated arrived as a `PoolMovement` and `#movement_maxima` already covers it.
  #
  # Two grouped queries for the whole set rather than two per pool, and the merge takes the
  # LATER of two dates for a pool that appears in both — which is the same `.compact.max`
  # the unbatched reader runs over its own two scalars, one level up. A pool present in neither
  # is absent from the result, and #terms_for reads that absence as nil.
  #
  # `date` is a datetime column, so `maximum` type-casts to a TimeWithZone here exactly as it does
  # unbatched; the `.to_date` that turns it into a whole day stays in PoolCalculator, where the
  # request's zone is the one that applies.
  def funding_dates
    [entry_maxima(Entry.incomes), movement_maxima]
      .reduce { |left, right| left.merge(right) { |_id, earlier, later| [earlier, later].max } }
  end

  # One grouped SUM per entry kind, over the shared grouped scope below.
  def entry_totals(scope) = grouped_entries(scope).sum(:amount)

  def entry_maxima(scope) = grouped_entries(scope).maximum(:date)

  # The WHERE and the GROUP BY are the same expression, so a row can only be counted for a pool
  # the predicate itself assigns it to — an entry whose category belongs to somebody else's pool
  # is outside the IN list and is not counted for anybody, which is what an unbatched calculator
  # does too (it filters on one pool id and sees nothing else).
  #
  # SHARED BY THE SUM AND THE MAX rather than written twice: the two aggregates answer about the
  # same rows by construction, so a term that moved would move both together instead of letting a
  # balance and its funding date describe different sets of entries.
  #
  # `ENTRY_POOL_JOINS` travels with the expression, here and in every other reader of it — the
  # start-date rule reads two tables the `item: :category` join does not reach. The movement lanes
  # take neither: a PoolMovement names its two pools outright and has no category to date-gate.
  def grouped_entries(scope)
    scoped(scope).joins(*ENTRY_POOL_JOINS)
      .where("#{ENTRY_POOL_ID} IN (:ids)", ids: @pool_ids).group(ENTRY_POOL_ID)
  end

  # `pool.movements_in` / `#movements_out` are `to_pool_id` / `from_pool_id` on PoolMovement and
  # carry no other condition, so the batched form is the same rows with the id read back out.
  def movement_totals(column) = grouped_movements(column).sum(:amount)

  # Movements IN only, because that is the direction that funds a pool.
  def movement_maxima = grouped_movements(:to_pool_id).maximum(:date)

  def grouped_movements(column)
    scoped(PoolMovement.where(column => @pool_ids)).group(column)
  end

  # PoolCalculator#scoped, and deliberately the same expression: `date` is a datetime column on
  # both tables and the bound is inclusive, so a ledger and an unbatched calculator asked about
  # the same instant have to include the same rows. It wraps the MAX(date)s too, because
  # #last_funded_on's three queries go through PoolCalculator#scoped today — an `as_of` calculator
  # must not report itself funded by money it has not reached yet.
  def scoped(relation)
    as_of ? relation.where(date: ..as_of) : relation
  end
end
