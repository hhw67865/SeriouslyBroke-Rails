# frozen_string_literal: true

# WHEN EACH ACCOUNT LAST HANDED MONEY OUT THIS PERIOD, and the one question that reads off it:
# has a rule in this envelope moved since?
#
# SPEC §8'S ONE ROUGH EDGE, HANDLED WITH WORDING RATHER THAN ARCHITECTURE. Rule changes apply
# immediately — everything in this design is derived — so raising Groceries from $420 to $470 the
# day after a distribution flips the envelope from `on track` to `behind $50` with no money having
# moved and nothing having gone wrong. The row says which of the two it is:
# `behind $50.00 — you changed a rule here after distributing`.
#
# HERE RATHER THAN ON HomePresenter, and that is this fix round's own correction. The clause was
# threaded on Home only, so the Budget page — the screen where rules are actually EDITED, and
# therefore the screen where "you changed a rule here" is most nearly a caption for what the user
# just did — printed `behind $50.00` for the same envelope on the same afternoon. Two presenters
# need the answer, and the alternative to one reader is the 40 lines of period-bounded movement
# query copied into the second one, free to disagree about which distribution is "this period's".
#
# THE COPY SAYS "CHANGED A RULE HERE", NOT §8'S OWN "you raised this rule", AND THE NARROWING IS
# DELIBERATE: `updated_at` cannot support the stronger sentence, in two reachable shapes.
#
#   IT DOES NOT KNOW THE DIRECTION. A user who LOWERS a rule after distributing — Groceries from
#   $470 back to $420 on an envelope that is still behind against the new, smaller requirement —
#   moves this same timestamp, and "you raised this rule" would tell them they did the opposite of
#   what they did. `updated_at` is a fact about WHEN, and the amount before the edit is not on the
#   row to compare against; recovering it would mean the `effective_from` versioning §8 explicitly
#   declined. The honest verb is the one that covers both directions.
#
#   IT DOES NOT KNOW WHICH RULE. This asks `pool.budgets.any?`, so a pool carrying two rules fires
#   the clause when EITHER moved — and "this rule", printed on a POOL's row, points at whichever
#   one the reader happens to be looking at. "a rule here" says what is true: something in this
#   envelope changed after the money went out. Home's expanded row lists the rules; the Budget
#   page's group lists them by construction.
#
# A rule CREATED after the distribution answers true as well, and the wording covers that too: a
# new claim on an envelope already funded leaves it behind for the same reason an edited one does,
# and none of the three cases is a lie under this verb.
#
# DERIVED, NO NEW COLUMN. Two timestamps the app already keeps: the rule's `updated_at` against the
# newest `PoolMovement.distributed` row for this pool's account inside the current period.
#
# THE SIGNAL IS CLEAN, AND THAT WAS MEASURED RATHER THAN ASSUMED, because `touch: true` is
# everywhere on this schema and a cascade reaching `budgets` would make this fire on users who
# changed nothing. Every `touch: true` in app/models points AT a pool, a category, an item or a
# user — `Budget belongs_to :pool, touch: true` touches the POOL when a rule is saved, never the
# other way — and NO association anywhere declares `belongs_to :budget, touch: true`. The only
# writers of a `budgets` row in the whole app are BudgetsController#update and BudgetProposal's
# `budget.save`, which are the user editing a rule and the user accepting a suggestion. So
# `budgets.updated_at` moves when, and only when, the user changed the rule.
class DistributionClock
  attr_reader :user, :today, :account_ids

  # `account_ids` is handed in rather than queried, because both callers have already loaded the
  # accounts they render — Home for its buffer band, the Budget page through its rules' preload —
  # and a pluck here would be a query neither of them needs.
  def initialize(user:, account_ids:, today: Date.current)
    @user = user
    @today = today
    @account_ids = account_ids.uniq.compact
  end

  # `pool.budgets` is eager-loaded by both callers, so this asks the database nothing per row; the
  # movements are one query for the whole screen (see #latest).
  #
  # A pool with no account answers false through the missing key rather than through a guard: no
  # distribution has ever reached it, so nothing was handed out for a rule change to come after.
  def changed_after_distributing?(pool)
    distributed_at = latest[pool.account_id]

    distributed_at.present? && pool.budgets.any? { |budget| budget.updated_at > distributed_at }
  end

  private

  # ONE QUERY FOR THE WHOLE SCREEN rather than one per `behind` row, on the widest iteration in
  # the app, keyed by account id.
  #
  # BOTH ENDS OF THE MOVEMENT, because a distribution writes in both directions: allocations leave
  # the account for its envelopes and sweeps come back from them. Either is the distribution, so
  # either dates it; filtering on `from_pool_id` alone would miss a period whose split was pure
  # sweep, and on `to_pool_id` alone would miss the ordinary one.
  #
  # Bounded by `period_datetimes_containing`, which is the app's one reader of where a period
  # starts and ends and widens the last day to its own midnight — the same bound
  # AllocationCommitter uses to find the split it is replacing, so the screens and that write path
  # cannot disagree about which distribution is "this period's".
  #
  # `created_at` ON THE MOVEMENT, NOT `date`, AND THE DIFFERENCE IS THE WHOLE HONESTY OF THE
  # CLAUSE. `date` is the period day a distribution is FOR — AllocationCommitter writes every row
  # of a split with the same one, and the user may confirm it hours or days later; `created_at` is
  # the instant they pressed confirm. The sentence claims the rule was changed AFTER the money was
  # handed out, so it must compare against the moment the money moved. Compared against `date`,
  # every rule edited later on the period's opening day would be called changed-after-distributing
  # including the ones edited BEFORE the confirm — the app blaming a user for an edit it had
  # already taken into account. And `updated_at` is a timestamp while `date` is a period marker:
  # comparing them at all is a unit mismatch dressed as a comparison.
  #
  # `{}` on a user with no accounts rather than a query with an empty IN list: an empty set makes
  # the whole question moot, and #changed_after_distributing? reads a missing key as "no
  # distribution", which is the safe direction and the true one.
  def latest
    @latest ||= account_ids.empty? ? {} : fold(rows)
  end

  def rows
    within_period = PoolMovement.distributed.where(date: user.period_datetimes_containing(today))

    within_period.where(from_pool_id: account_ids)
      .or(within_period.where(to_pool_id: account_ids))
      .pluck(:from_pool_id, :to_pool_id, :created_at)
  end

  # Folded in Ruby rather than grouped in SQL because each row names TWO pools and only one of
  # them is the account — a `GROUP BY` would need the same two-branch decision written as a CASE
  # over both columns, and a period's distribution is a handful of rows.
  def fold(rows)
    ids = account_ids.to_set

    rows.each_with_object({}) do |(from_id, to_id, created_at), latest|
      [from_id, to_id].each do |id|
        next unless ids.include?(id)

        latest[id] = created_at if latest[id].nil? || latest[id] < created_at
      end
    end
  end
end
