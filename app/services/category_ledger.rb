# frozen_string_literal: true

# THE PURPOSE LEDGER, READ (two-ledger spec §2): what each category holds, and what is still
# available. `PoolBalanceLedger`'s shape, re-anchored on the thing that holds the money.
#
# It is the same class in every structural respect and deliberately so — batched grouped sums, one
# query per term for the WHOLE set a screen is about, terms memoised at their FIRST READ rather
# than at construction, `as_of` part of the ledger rather than of a term, `#for_as_of!` refusing a
# handover across two moments. Every one of those decisions was paid for on the pool side (the
# measurements are in that class's own comments) and none of them are re-derived here.
#
# WHAT IS GENUINELY DIFFERENT, and it is two things:
#
#   1. THE FIFTH TERM'S SIBLING IS A SCALAR ABOUT THE USER. `#available` is the root of the purpose
#      ledger — money with no job yet — and it belongs to the USER, not to any category in the set.
#      A screen asking about three of a user's categories still has to be told the same available
#      as a screen asking about thirty, or `available + Σ holdings` stops being a partition of one
#      total and the invariant in §2 becomes untestable. So it is computed over the whole user and
#      the ledger refuses to answer at all when it cannot name exactly one.
#
#   2. THERE IS NO PER-CATEGORY FALLBACK READER. `PoolBalanceLedger#terms_for` answers nil for a
#      pool outside its set because `PoolCalculator.new(pool, terms: nil)` will happily run its own
#      five aggregates. Nothing does that for a category, so #holding_of RAISES on a category this
#      ledger was not built over rather than handing back a zero that reads exactly like an
#      envelope somebody has spent flat.
#
# A SNAPSHOT, STALE AFTER A WRITE, on `PoolBalanceLedger`'s rule: anything that writes entries or
# allocations must build a fresh ledger afterwards.
class CategoryLedger
  # The four MONEY members of #terms_for, in the order `PoolCalculator#balance` reads them — the
  # same four names, so a calculator can consume either ledger's hash. `:income` is always ZERO
  # here and it is in the list anyway: the KEY has to be present or `PoolCalculator#term`'s
  # `fetch`-without-default raises on a hash that simply does not compute what it needs, and a
  # missing key and a zero are different facts.
  MONEY_TERMS = [:income, :expense, :movements_in, :movements_out].freeze

  # The fifth, separate from the four because its EMPTY ANSWER IS DIFFERENT IN KIND — a category
  # with no allocations holds nothing, but it was not funded on the zeroth of anything, and every
  # reader of this term guards on `nil?`. It defaults to nil and cannot travel through the
  # `fetch(id, 0.to_d)` the four money terms share.
  FUNDED_ON = :last_funded_on

  TERMS = [*MONEY_TERMS, FUNDED_ON].freeze

  # WHICH CATEGORY AN EXPENSE DRAINS — the start-date rule re-anchored (spec §4). An expense
  # drains its category from the category's funded_since onward (the user's local day, exactly
  # as PoolBalanceLedger did it), and drains AVAILABLE (NULL) before that or when the category
  # was never funded. Income never drains a category: it lands in available.
  #
  # THE BOUNDARY IS THE USER'S DAY, AND THE TWO `AT TIME ZONE`s ARE WHY. `entries.date` is a
  # DATETIME and `categories.funded_since` is a DATE, and `ApplicationController` wraps every
  # request in `Time.use_zone(current_user.timezone)` — so an entry a Tokyo user files ON Aug 1 is
  # stored `2026-07-31 15:00:00`, nine hours before the UTC day it belongs to begins. Compared raw,
  # that entry is "before" a funding date it is actually on, and every east-of-UTC user's first day
  # of holding money would drain available instead. The first `AT TIME ZONE 'UTC'` reads the naive
  # timestamp as the UTC instant Rails wrote, the second renders it in the OWNER'S zone, and
  # `::date` takes the calendar day the user was living in.
  #
  # THIS IS THE ONLY COMPARISON OF `funded_since` IN APP CODE. `Category#counts_spending_on?` is
  # its one Ruby mirror and says so; the day-boundary spelling here is character-for-character the
  # one `CategoriesHoldTheMoney#funded_gate` verified the migration with, so a divergence between
  # them is a bug in one of the two rather than a difference of opinion.
  ENTRY_CATEGORY_ID = Arel.sql(<<~SQL.squish)
    CASE
      WHEN categories.category_type = #{Category.category_types[:income]} THEN NULL
      WHEN categories.funded_since IS NULL THEN NULL
      WHEN (entries.date AT TIME ZONE 'UTC'
              AT TIME ZONE COALESCE(category_users.timezone, 'UTC'))::date
           >= categories.funded_since THEN categories.id
      ELSE NULL
    END
  SQL

  # The one join ENTRY_CATEGORY_ID needs beside the `item: :category` join `Entry.expenses` and its
  # siblings already carry. ALIASED, because a bare `users` could collide with a caller's own join.
  #
  # INNER, because `categories.user_id` is NOT NULL with a foreign key: the join adds no row and
  # removes none, and INNER is what keeps the expression from silently reading a NULL timezone out
  # of a missing row instead of out of a user who has not chosen one.
  ENTRY_CATEGORY_JOINS = [
    "INNER JOIN users AS category_users ON category_users.id = categories.user_id"
  ].freeze

  # `PoolBalanceLedger::AsOfMismatch`, for its reasons: a `rescue` of this would be a caller
  # deciding to read figures from a moment it did not ask about.
  class AsOfMismatch < StandardError; end

  # A HOLDING ASKED OF A LEDGER THAT WAS NEVER BUILT OVER THE CATEGORY. Zero would be a wrong money
  # figure that looks exactly like a right one — an envelope spent flat — and there is no
  # per-category fallback reader to defer to, so this is a raise rather than a default.
  class UnknownCategory < StandardError; end

  # WHOSE AVAILABLE? Raised when the ledger cannot name exactly one user: an empty set with no
  # `user:` given, a set spanning two users, or a `user:` that does not own every category handed
  # in. Not defensive — a user with income and no expense categories has a real, non-zero available,
  # so an empty ledger answering `0` would be wrong on exactly the screens a new user sees first.
  class NoSingleOwner < StandardError; end

  attr_reader :as_of

  # `categories` is the WHOLE set a screen is going to ask about, RECORDS rather than ids — the
  # owner has to be readable off them, and callers pass the collection they already hold. Unsaved
  # categories are dropped rather than queried for.
  #
  # `user:` IS OPTIONAL AND IS ABOUT #available ALONE. Handed one, the ledger checks the set against
  # it and uses it; handed none, it reads the owner off the categories. The keyword exists for the
  # one shape the categories cannot answer for — a user whose expense categories are an EMPTY set,
  # which is every user on their first day.
  def initialize(categories, as_of: nil, user: nil)
    @categories = Array(categories).select(&:id)
    @category_ids = @categories.map(&:id).uniq
    @known = @category_ids.to_set
    @as_of = as_of
    @named_user = user
  end

  # The five terms for one category, as a calculator consumes them. nil for a category this ledger
  # was not built over — never a set of zeros, which would be an answer to a question nobody asked.
  def terms_for(category)
    return nil unless @known.include?(category.id)

    MONEY_TERMS.index_with { |term| totals(term).fetch(category.id, 0.to_d) }
      .merge(FUNDED_ON => totals(FUNDED_ON)[category.id])
  end

  # WHAT THIS CATEGORY HOLDS: what was allocated in, less what was allocated out, less the spending
  # it counts (§2). The convenience over #terms_for, and the figure `available + Σ holdings` is
  # summed from.
  def holding_of(category)
    terms = terms_for(category)
    raise UnknownCategory, "#{category.name} is not in this ledger's set of categories" if terms.nil?

    terms[:movements_in] - terms[:movements_out] - terms[:expense]
  end

  # MONEY WITH NO JOB YET — the root of the purpose ledger (§2), and a fact about the USER rather
  # than about this ledger's set.
  #
  # Income, less the spending that drains no category (an unfunded category's, and a funded one's
  # own history from before it was funded), less what has been allocated out of the root, plus what
  # has been allocated back into it. Every allocation with both ends inside one user contributes to
  # exactly one of those last two terms or to neither — a category-to-category hand move touches
  # neither, which is what makes "allocating money moves nothing" true on this side too.
  def available
    income_total - unfunded_spending - allocated_out + allocated_in
  end

  # THIS LEDGER, IF IT IS ABOUT THE MOMENT THE CALLER IS ASKING ABOUT — `PoolBalanceLedger
  # #for_as_of!` verbatim in intent. It returns SELF on a match so it reads as a checked handover
  # rather than as a predicate somebody can forget to branch on.
  def for_as_of!(wanted)
    return self if as_of == wanted

    raise AsOfMismatch,
          "this ledger is bounded at #{as_of.inspect} and the caller is asking about " \
          "#{wanted.inspect}: one ledger per `as_of`, never one shared across two"
  end

  # The one user this ledger's available belongs to. Memoised with `defined?` rather than `||=`
  # because the answer is a record that never changes — but the RAISE must not be swallowed into a
  # second, different message on a second read.
  #
  # THE MEMO IS `@user` AND THE CONSTRUCTOR'S ARGUMENT IS `@named_user`, which is not a stylistic
  # choice: `Naming/MemoizedInstanceVariableName` requires the memo of #user to be `@user`, and an
  # `@user` also assigned in #initialize makes `defined?` true from birth — so this method returned
  # the constructor's nil forever and every entry term read `nil.id`. (`rubocop -A` made exactly
  # that rename on the first draft of this file; the specs caught it, which is why they are re-run
  # after every autocorrect.)
  def user
    return @user if defined?(@user)

    @user = resolve_owner
  end

  private

  def resolve_owner
    owners = @categories.map(&:user).uniq
    return owner_named(owners) if @named_user

    raise NoSingleOwner, no_single_owner_message(owners) unless owners.size == 1

    owners.first
  end

  # A `user:` that does not own the whole set is refused rather than trusted: available would be
  # computed over one user while the holdings it is added to belong to another, and the sum would
  # be a number no ledger anywhere is a partition of.
  def owner_named(owners)
    strangers = owners.reject { |owner| owner == @named_user }
    return @named_user if strangers.empty?

    raise NoSingleOwner,
          "this ledger was told it belongs to #{@named_user.email} but holds categories of " \
          "#{strangers.map(&:email).join(", ")}"
  end

  def no_single_owner_message(owners)
    return "available is a figure about one user, and this ledger has no categories to read one off" if owners.empty?

    "available is a figure about one user, and this ledger spans #{owners.size}: " \
      "#{owners.map(&:email).join(", ")}"
  end

  # Memoised per term, and the win is ACROSS CALLS rather than across terms — #terms_for builds all
  # five for the category it is asked about, so the first call pays for the whole set and every one
  # after it is free. `fetch` with a block rather than `||=`, because a grouped sum over a term with
  # no rows at all is `{}` and a truthiness memo would re-run it every time.
  def totals(term)
    @totals ||= {}
    @totals.fetch(term) { @totals[term] = compute(term) }
  end

  def compute(term)
    case term
    # NO QUERY, AND NO ROWS TO RUN ONE OVER: income never lands in a category (ENTRY_CATEGORY_ID's
    # first arm sends every income entry to available), so the term is an empty hash and every
    # category reads its `fetch` default of `0.to_d` out of it.
    when :income then {}
    when :expense then grouped_entries.sum(:amount)
    when :movements_in then grouped_allocations(:to_category_id).sum(:amount)
    when :movements_out then grouped_allocations(:from_category_id).sum(:amount)
    when FUNDED_ON then grouped_allocations(:to_category_id).maximum(:date)
    end
  end

  # The WHERE and the GROUP BY are the same expression, so a row can only be counted for the
  # category the rule itself assigns it to — an entry whose category is somebody else's is outside
  # the IN list and is counted for nobody.
  def grouped_entries
    scoped(Entry.expenses).joins(*ENTRY_CATEGORY_JOINS)
      .where("#{ENTRY_CATEGORY_ID} IN (:ids)", ids: @category_ids).group(ENTRY_CATEGORY_ID)
  end

  # MONEY IN IS `to_category_id` AND THE FUNDING DATE IS ITS MAX, on `PoolBalanceLedger`'s reason:
  # what was spent out of a category says nothing about which period funded it. The two aggregates
  # share this scope rather than restating its WHERE, so the batched MAX cannot see a row the
  # batched SUM does not.
  def grouped_allocations(column)
    scoped(Allocation.where(column => @category_ids)).group(column)
  end

  # ALL OF THIS USER'S INCOME, whatever category it names — income lands in available, full stop.
  def income_total = scoped(user_entries(Entry.incomes)).sum(:amount).to_d

  # THE SPENDING THAT DRAINS NO CATEGORY, which is the same rule ENTRY_CATEGORY_ID states, read for
  # its NULL answer instead of for its id one. Over the whole user rather than over this ledger's
  # set, because available is the user's root: a category left out of the set still drains it.
  def unfunded_spending
    scoped(user_entries(Entry.expenses)).joins(*ENTRY_CATEGORY_JOINS)
      .where("#{ENTRY_CATEGORY_ID} IS NULL").sum(:amount).to_d
  end

  def allocated_out = root_allocations(:from_category_id, :to_category_id).sum(:amount).to_d

  def allocated_in = root_allocations(:to_category_id, :from_category_id).sum(:amount).to_d

  # An allocation with the ROOT on one side and one of this user's categories on the other. Both
  # halves are load-bearing: the NULL side is what makes it available's business at all, and the
  # user side is what keeps one user's root from being drained by a row naming somebody else's
  # category (a shape `Allocation` refuses, and one this figure must not depend on it refusing).
  def root_allocations(root_side, category_side)
    scoped(Allocation.where(root_side => nil, category_side => user.categories.select(:id)))
  end

  def user_entries(scope) = scope.where(categories: { user_id: user.id })

  # `PoolBalanceLedger#scoped`, and deliberately the same expression: `date` is a datetime column
  # on both tables here too, and the bound is inclusive.
  def scoped(relation)
    as_of ? relation.where(date: ..as_of) : relation
  end
end
