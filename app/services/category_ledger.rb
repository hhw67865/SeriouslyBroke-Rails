# frozen_string_literal: true

# ** WHICH CATEGORY AN EXPENSE DRAINS, AND ON WHAT DAY — THREE CONSTANTS AND NOTHING ELSE. **
#
# THIS CLASS WAS THE PURPOSE LEDGER (two-ledger spec §2): what each category HELD, and what was
# still AVAILABLE, read as batched grouped sums over `allocations`. Computed claims delete both
# halves of that sentence (computed-claims spec §5/§6). Nothing moves on the purpose side any more,
# so there is no holding to sum and no root to hold the remainder — a category's money is
# `Category#claim`, a function of its rules, and free money is `ClaimLedger#free`, which is
# `total − Σ claims`. `#available`, `#holding_of`, `#terms_for`, the four money terms, the funding
# date, `#for_as_of!` and every allocation query underneath them went with the table.
#
# WHAT SURVIVES IS THE ENTRY LANE, AND IT SURVIVES BECAUSE IT WAS NEVER ABOUT ALLOCATIONS. The
# question "which category does this expense drain, on which calendar day" is a fact about
# `entries.date`, `categories.funded_since` and the OWNER'S TIME ZONE, and it is exactly as true
# under computed claims as it was under moved money: `ClaimCalculator` reads a rule's spending
# through it, `ClaimLedger` batches the same expression, `SuggestionEngine`'s drift detector groups
# by it, `Entry.draining` narrows it to one category and `HomePresenter` reads its NULL answer.
#
# THE CLASS NAME IS KEPT RATHER THAN THE CONSTANTS MOVED, deliberately. Six files compose these by
# this name, the emitted SQL is character-for-character what `CategoriesHoldTheMoney#funded_gate`
# verified the two-ledger migration with, and a rename would put a diff over every one of those
# call sites in the commit that is already deleting a screen apiece. The name is now a lane rather
# than a ledger; that is what this header is for.
class CategoryLedger
  # THE CALENDAR DAY AN ENTRY FELL ON, IN THE OWNER'S ZONE — pulled out of ENTRY_CATEGORY_ID below
  # so that the day and the funding gate are ONE expression rather than two that happen to agree.
  # `ClaimCalculator`'s spending is grouped BY PERIOD (computed-claims spec §3.2), which needs the
  # day itself rather than the gate's verdict, and a second `AT TIME ZONE` pair written out in that
  # class is exactly the divergence this constant's own header warns about. Interpolated below, so
  # the emitted SQL is character-for-character what `CategoriesHoldTheMoney#funded_gate` verified the
  # migration with. `User#local_day` is its Ruby mirror.
  #
  # THE BOUNDARY IS THE USER'S DAY, AND THE TWO `AT TIME ZONE`s ARE WHY. `entries.date` is a
  # DATETIME and `categories.funded_since` is a DATE, and `ApplicationController` wraps every
  # request in `Time.use_zone(current_user.timezone)` — so an entry a Tokyo user files ON Aug 1 is
  # stored `2026-07-31 15:00:00`, nine hours before the UTC day it belongs to begins. Compared raw,
  # that entry is "before" a funding date it is actually on, and every east-of-UTC user's first day
  # of holding money would be read wrong. The first `AT TIME ZONE 'UTC'` reads the naive timestamp
  # as the UTC instant Rails wrote, the second renders it in the OWNER'S zone, and `::date` takes
  # the calendar day the user was living in.
  ENTRY_LOCAL_DAY = Arel.sql(<<~SQL.squish)
    (entries.date AT TIME ZONE 'UTC'
       AT TIME ZONE COALESCE(category_users.timezone, 'UTC'))::date
  SQL

  # WHICH CATEGORY AN EXPENSE DRAINS — the start-date rule (two-ledger spec §4). An expense counts
  # against its category from the category's `funded_since` onward, in the user's local day, and
  # against NOTHING (NULL) before that or when the category was never funded.
  #
  # ** WHAT THE NULL ANSWER MEANS NOW. ** It used to mean "drains AVAILABLE", a term this class
  # computed. Available is deleted with the movements (§5), so NULL now means what it always
  # physically meant and nothing more: this expense counts against no category's claim, so it comes
  # straight out of free money. `HomePresenter` reads exactly that arm for its unbudgeted spending.
  #
  # ARM 1 IS THE BELT AND `Entry.expenses` IS THE BRACES. Both consumers of this expression start
  # from an expense scope, so today an income entry never reaches this CASE at all — the arm is what
  # keeps the law true the moment a caller hands the expression a wider scope, which is a live risk
  # on a constant whose whole job is to be the app's ONE statement of which category an entry drains.
  #
  # THIS IS THE ONLY COMPARISON OF `funded_since` IN APP CODE. `Category#counts_spending_on?` is its
  # one Ruby mirror and says so.
  ENTRY_CATEGORY_ID = Arel.sql(<<~SQL.squish)
    CASE
      WHEN categories.category_type = #{Category.category_types[:income]} THEN NULL
      WHEN categories.funded_since IS NULL THEN NULL
      WHEN #{ENTRY_LOCAL_DAY}
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
end
