# frozen_string_literal: true

# Everything the Budget page renders: every rule the user owns, grouped under the pool it fills,
# in the order the money actually arrives. Read-only — the rule forms it links to own the writes.
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §8
class BudgetPagePresenter
  # ONE RULE ON THE PAGE. `due_on` is nil for an anchorless rule and that nil is information, not
  # a gap: BudgetCalculator#due_date answers `period_end` for a rule with no anchor, which is a
  # real number for the maths and a lie on screen — "due Aug 31" printed against a rate rule that
  # is never due. The row prints a date only where one exists.
  #
  # `reason` is nil for a rule in the fill order and a symbol for one outside it (see
  # #orphan_reason). It travels on the rule rather than on the section so the row can say WHY it
  # is not in the main list — the two orphan kinds are different problems with different fixes.
  Rule = Data.define(:budget, :due_on, :reason) do
    def anchored? = due_on.present?
  end

  # ONE POOL AND THE RULES THAT FILL IT. `status` is a PoolStatus, so the group header speaks the
  # app's existing row vocabulary through `pool_status_label` rather than a second one of its own,
  # and its #balance is the pool's balance — the same object, so the header's state and its figure
  # cannot disagree, and the page does not build a second calculator to ask.
  Group = Data.define(:pool, :rules, :status) do
    delegate :balance, to: :status
    delegate :priority, to: :pool
  end

  attr_reader :user, :today

  def initialize(user:, today: Date.current)
    @user = user
    @today = today
  end

  # The top half of §8: pools in fill order, each carrying its rules in due order.
  #
  # `[priority, name]` is the in-memory twin of `Pool.by_priority` and the same tie-break
  # HomePresenter#by_priority uses. Priority alone is not a total order, and a tie falling through
  # to database order is the defect Plan 1 shipped in its waterfall — heap order deciding who gets
  # funded first, so the same page reported a different order on consecutive loads with no data
  # change.
  #
  # Only pools that OWN a rule are groups, and only pools with an account. A pool with no rule has
  # nothing to show on a page about rules, and an account-less pool can be funded by no
  # distribution at all — its rules are named in #orphan_rules with the step that fixes them.
  def pool_groups
    @pool_groups ||= grouped_pools.sort_by { |pool| [pool.priority, pool.name] }.map { |pool| build_group(pool) }
  end

  # THE RULES NO DISTRIBUTION CAN REACH, each saying which of the two reasons it is.
  #
  # A category-mode rule funds a category rather than an envelope, so no pool ever fills it; an
  # account-less pool has no account whose money could arrive. Both are setup states with a
  # different fix, which is why the reason rides on the row.
  #
  # Ordered by owner name and then by the same #due_order the groups use, because this is a
  # rendered list and `all_budgets` carries no ORDER BY: without a key its order is whatever
  # Postgres hands back, and a plain UPDATE relocates a row in the heap. Every rule here is
  # persisted (see #rules), so `due_order`'s id tie-break cannot meet an unsaved record.
  def orphan_rules
    @orphan_rules ||= rules.filter_map { |budget| build_orphan(budget) }
      .sort_by { |rule| [owner_name(rule.budget), *rule_order(rule.budget)] }
  end

  # The empty top half — a brand-new user's first sight of this page. Asked of every rule the user
  # has rather than of #pool_groups: a user whose only rules are orphans has rules, and telling
  # them they have none above a list of their own rules is a screen contradicting itself.
  def no_rules? = rules.empty?

  private

  # THE ONE READER FOR BOTH RULE MODES. `user.all_budgets` reaches category-mode and pool-mode
  # rules alike; `user.budgets` walks the category link only and would render this page's main
  # list empty.
  #
  # `pool: :budgets` is preloaded because PoolStatus reads `pool.budgets` for every anchored rule
  # it ranks — without it every group header is one SELECT per pool, on the widest per-rule screen
  # in the app.
  #
  # `:user` on both owners because `Budget#user` walks whichever one the rule has, and
  # BudgetCalculator#periods_until_due asks it for every dated rule on the page. Measured on the
  # demo seeds: eleven `SELECT users WHERE id = ?` for one user, and the page's whole cost fell
  # from 37 queries to 26 when they were preloaded.
  def rules
    @rules ||= user.all_budgets.includes(:item, category: :user, pool: [:user, :budgets]).to_a
  end

  def rules_by_pool
    @rules_by_pool ||= rules.select { |budget| budget.pool&.account_id }.group_by(&:pool_id)
  end

  def pools_by_id = @pools_by_id ||= rules.filter_map(&:pool).index_by(&:id)

  def grouped_pools = rules_by_pool.keys.map { |id| pools_by_id.fetch(id) }

  def build_group(pool)
    Group.new(
      pool: pool,
      rules: rules_by_pool.fetch(pool.id).sort_by { |budget| rule_order(budget) }.map { |budget| build_rule(budget) },
      status: pool.status(today: today, terms: ledger.terms_for(pool))
    )
  end

  def build_orphan(budget)
    reason = orphan_reason(budget)

    build_rule(budget, reason) if reason
  end

  # `:category` before `:no_account`, and the order is not arbitrary: Budget#exactly_one_owner
  # means a rule has one owner or the other, so a category-mode rule has no pool to ask about an
  # account. Testing the pool first would call `.account_id` on nil.
  def orphan_reason(budget)
    return :category if budget.category.present?

    :no_account if budget.pool && budget.pool.account_id.nil?
  end

  def build_rule(budget, reason = nil)
    Rule.new(budget: budget, due_on: due_on_for(budget), reason: reason)
  end

  # THROUGH THE CALCULATOR, NEVER THE RAW ANCHOR. A recurring bill's `anchor_date` is its FIRST
  # occurrence — the demo's car insurance anchors in March and is due every six months — so
  # printing the column would show a date years in the past as the next thing to pay.
  def due_on_for(budget) = budget.anchor_date.presence && due_date_for(budget)

  def due_date_for(budget) = (@due_dates ||= {})[budget] ||= calculator_for(budget).due_date

  # BudgetCalculator#due_order, never a `[due_date, -amount, id]` of our own: that key decides
  # which rule a pool row names, which one `allocated_balances` fills first and therefore which
  # one slips — and it lives in exactly one place.
  #
  # The already-computed due date is handed in rather than left for the key to ask again, because
  # #due_date re-runs #paid_since_anchor's SUM on every call and this page sorts every rule the
  # user has.
  def rule_order(budget) = calculator_for(budget).due_order(due_date_for(budget))

  # Keyed by the record rather than by id, as HomePresenter does: an unsaved rule has no id, and
  # nil as a cache key would hand every such rule the first one's calculator.
  def calculator_for(budget) = (@calculators ||= {})[budget] ||= budget.calculator(today: today)

  def owner_name(budget) = budget.pool&.name || budget.category&.name.to_s

  # ONE LEDGER FOR THE WHOLE PAGE, over every pool that owns a rule — five grouped queries for the
  # set instead of five aggregates per pool per status. Orphan pools are in it too: they cost the
  # ledger nothing extra (the queries are grouped over the whole set) and a pool that is uncovered
  # would quietly fall back to five queries of its own.
  #
  # Lazy, like Home's. This page writes nothing, so there is no deletion for a snapshot to fall
  # the wrong side of; the laziness only keeps a presenter that is built and never rendered free.
  def ledger = @ledger ||= PoolBalanceLedger.new(pools_by_id.values)
end
