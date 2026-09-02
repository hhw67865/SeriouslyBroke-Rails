# frozen_string_literal: true

# WHEN THE USER LAST HANDED MONEY OUT THIS PERIOD, and the one question that reads off it: has a
# rule in this category moved since?
#
# SPEC §8'S ONE ROUGH EDGE, HANDLED WITH WORDING RATHER THAN ARCHITECTURE. Rule changes apply
# immediately — everything in this design is derived — so raising Groceries from $420 to $470 the
# day after a distribution flips the category from `on track` to `behind $50` with no money having
# moved and nothing having gone wrong. The row says which of the two it is:
# `behind $50.00 — you changed a rule here after distributing`.
#
# HERE RATHER THAN ON HomePresenter, and that is an earlier fix round's correction. The clause was
# threaded on Home only, so the Budget page — the screen where rules are actually EDITED, and
# therefore the screen where "you changed a rule here" is most nearly a caption for what the user
# just did — printed `behind $50.00` for the same rule on the same afternoon. Two presenters need
# the answer, and the alternative to one reader is the 40 lines of period-bounded query copied into
# the second one, free to disagree about which distribution is "this period's".
#
# THE COPY SAYS "CHANGED A RULE HERE", NOT §8'S OWN "you raised this rule", AND THE NARROWING IS
# DELIBERATE: `updated_at` cannot support the stronger sentence, in two reachable shapes.
#
#   IT DOES NOT KNOW THE DIRECTION. A user who LOWERS a rule after distributing — Groceries from
#   $470 back to $420 on a category that is still behind against the new, smaller requirement —
#   moves this same timestamp, and "you raised this rule" would tell them they did the opposite of
#   what they did. `updated_at` is a fact about WHEN, and the amount before the edit is not on the
#   row to compare against; recovering it would mean the `effective_from` versioning §8 explicitly
#   declined. The honest verb is the one that covers both directions.
#
#   IT DOES NOT KNOW WHICH RULE. This asks `holder.budgets.any?`, so a category carrying two rules
#   fires the clause when EITHER moved — and "this rule", printed on a row, points at whichever one
#   the reader happens to be looking at. "a rule here" says what is true: something here changed
#   after the money went out.
#
# A rule CREATED after the distribution answers true as well, and the wording covers that too: a new
# claim on a category already funded leaves it behind for the same reason an edited one does, and
# none of the three cases is a lie under this verb.
#
# DERIVED, NO NEW COLUMN. Two timestamps the app already keeps: the rule's `updated_at` against the
# newest `Allocation.distributed` row this user wrote inside the current period.
#
# ONE TIMESTAMP PER USER PER PERIOD, WHERE THE POOL ERA KEYED BY ACCOUNT (two-ledger spec §2). An
# allocation has no account — it moves money between the user's root and their categories, and the
# root is one — so there is one distribution per period and one moment it happened at. The
# per-account map is DELETED (Task 6) along with the `account_ids:` keyword that reached it.
#
# THE SIGNAL IS CLEAN, AND THAT WAS MEASURED RATHER THAN ASSUMED, because `touch: true` is
# everywhere on this schema and a cascade reaching `budgets` would make this fire on users who
# changed nothing. Every `touch: true` in app/models points AT a pool, a category, an item or a user
# — `Budget belongs_to :category, touch: true` touches the CATEGORY when a rule is saved, never the
# other way — and NO association anywhere declares `belongs_to :budget, touch: true`. So
# `budgets.updated_at` moves when, and only when, the user changed the rule.
class DistributionClock
  attr_reader :user, :today

  # `account_ids:` IS GONE (Task 6), and with it every line below the old `── THE POOL-ERA ARM`
  # marker: `#latest_by_account`, `#rows`, `#fold` and the `per_account?` switch. The keyword was a
  # transitional surface for the two screens that still handed this class a list of accounts and
  # asked it about a POOL — HomePresenter and CategoryBudgetPresenter — and both moved in this task.
  # There is ONE distribution per period per user now, because there is one root (two-ledger spec
  # §2), so there is one timestamp and no map to key it by.
  def initialize(user:, today: Date.current)
    @user = user
    @today = today
  end

  # `holder.budgets` is eager-loaded by every caller, so this asks the database nothing per row; the
  # timestamp is one query for the whole screen (see #latest_for_user).
  #
  # `holder` is a Category. Nothing here reads an account: there is one root, and every holder is
  # funded out of it.
  def changed_after_distributing?(holder)
    distributed_at = latest_for_user

    distributed_at.present? && holder.budgets.any? { |budget| budget.updated_at > distributed_at }
  end

  private

  # THE ONE QUERY: the newest moment this user's distribution wrote anything
  # inside this period.
  #
  # BOTH SIDES TESTED FOR THE OWNER, because either may be NULL: an allocation names only a
  # destination and a sweep names only a source, so a single-column match would miss a period whose
  # split was pure sweep, exactly as `from_pool_id` alone did on the pool side.
  #
  # Bounded by `period_datetimes_containing`, which is the app's one reader of where a period starts
  # and ends and widens the last day to its own midnight — the same bound
  # AllocationCommitter#previous_distribution uses to find the split it is replacing, so the screens
  # and that write path cannot disagree about which distribution is "this period's".
  #
  # `created_at`, NOT `date`, AND THE DIFFERENCE IS THE WHOLE HONESTY OF THE CLAUSE. `date` is the
  # period day a distribution is FOR — AllocationCommitter writes every row of a split with the same
  # one, and the user may confirm it hours or days later; `created_at` is the instant they pressed
  # confirm. The sentence claims the rule was changed AFTER the money was handed out, so it must
  # compare against the moment the money moved. And `updated_at` is a timestamp while `date` is a
  # period marker: comparing them at all is a unit mismatch dressed as a comparison.
  #
  # `defined?` rather than `||=`, because `nil` — no distribution this period — is the ordinary
  # answer and is exactly the one a truthiness memo would re-run for on every row of a screen.
  def latest_for_user
    return @latest_for_user if defined?(@latest_for_user)

    in_period = Allocation.distributed.where(date: user.period_datetimes_containing(today))
    mine = user.categories.select(:id)

    @latest_for_user =
      in_period.where(from_category_id: mine).or(in_period.where(to_category_id: mine)).maximum(:created_at)
  end
end
