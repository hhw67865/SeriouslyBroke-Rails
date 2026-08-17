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
  #
  # `changed_after_distributing` rides on the group rather than being asked in the partial, for the
  # same reason `status` does: it compares this pool's rules against THIS period's latest
  # distribution, and which period that is depends on the presenter's `today`. It is the second
  # half of the row vocabulary — `period_closed?` is the first — and this page carries BOTH because
  # a suffix on Home and not here is two screens describing one envelope differently on the same
  # afternoon. That the Budget page is where rules are EDITED makes the clause more nearly a
  # caption for what the user just did here than anywhere else in the app.
  Group = Data.define(:pool, :rules, :status, :changed_after_distributing) do
    delegate :balance, to: :status
    delegate :priority, to: :pool

    # THE ROW VOCABULARY'S FOUR QUESTIONS, so this Data and `HomePresenter::Row` answer the same
    # set and `shared/_pool_status` can render either without asking which screen it is on. These
    # two rode straight off `status` in the partial before; through the group they are the group's,
    # which is what stops a caller threading one suffix and forgetting the other (see
    # HomePresenter::Row's header for the two times that happened).
    delegate :needs_attention?, :period_closed?, to: :status

    # A PREDICATE, matching `Rule#anchored?` above and the two neighbours the partial reads beside
    # it — `status.needs_attention?` and `status.period_closed?`. The header prints
    # `period_closed?` and this one on adjacent lines, and one of the two answering without a `?`
    # reads as a different kind of thing.
    def changed_after_distributing? = changed_after_distributing

    # THE CLAUSE THIS SCREEN ADDS AFTER THE STATE. `· holds $X` on the three states whose figure
    # is a bill's shortfall rather than this pool's money — `pool_balance_clause` owns which — and
    # never a date: every rule's own date is printed in the rows below this header, so a date up
    # here would be one of them repeated without saying which. The mirror of
    # `HomePresenter::Row#due_marker?`, where the screen is missing the opposite thing.
    def balance_clause? = true
    def due_marker? = false
  end

  # ONE ACCOUNT AND ITS POOLS IN FILL ORDER. The page's main list is banded by account rather
  # than flat, and Task 5 is why: priority is only ever compared within an account (the fill is
  # per-account), so a flat list interleaved by `[priority, name]` across two accounts would
  # offer the user a drag between rows whose relative order decides nothing. The band is the
  # scope of one reorder — what is inside it is exactly what `PATCH /budget/reorder` rewrites.
  Band = Data.define(:account, :groups)

  attr_reader :user, :today

  # THE RECORD THE DECLARATION FORM EDITS, which is `user` on every path but one.
  #
  # A refused declaration leaves the rejected values and the errors on the in-memory user, and the
  # form must keep both — otherwise a validation failure silently throws away what was typed. But
  # the FIGURES must not read them: the row was not written, so a block computed from those values
  # would print "$2,400.00 a period" at a user whose income the database still holds as nil, under
  # a message saying the save failed. Measured in the browser, not reasoned about.
  #
  # Hence two objects on that one path: `user` for what is true, `declaration` for what was typed.
  # See BudgetPageController#update.
  attr_reader :declaration

  def initialize(user:, today: Date.current, declaration: nil)
    @user = user
    @today = today
    @declaration = declaration || user
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

  # #pool_groups banded by the account that funds them, accounts in their own `[priority, name]`
  # order. `group_by` preserves insertion order, so each band's groups arrive already in fill
  # order — there is no second sort here to disagree with #pool_groups' one.
  #
  # Every group has an account by construction (#rules_by_pool selects on `pool.account_id`), so
  # there is no nil band to render and no pool falls out of the page by being banded.
  def account_bands
    @account_bands ||= pool_groups.group_by { |group| group.pool.account }
      .sort_by { |account, _groups| [account.priority, account.name] }
      .map { |account, groups| Band.new(account: account, groups: groups) }
  end

  # THE RULES NO DISTRIBUTION CAN REACH, each saying why.
  #
  # ONE REASON NOW: an account-less pool has no account whose money could arrive. The other was a
  # category-mode rule, which funded a category rather than an envelope so no pool ever filled it —
  # a shape deleted in plan 3, task 3. The reason still rides on the row rather than on the section,
  # because it is the row that has to say what the fix is.
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

  # §8's structural check, three lines: what the rules claim from a period, what the user says
  # they bring in, and the difference.
  #
  # `Budget.steady_need`, NOT a sum over #rules — even though #rules is already loaded and
  # preloaded, and this therefore costs a second pass over the same rows. The figure is read by
  # this page, by Home's standing band and (Task 9) by the sacrifice view, and the moment two of
  # them spell the sum themselves they are free to disagree about which rules count. One reader,
  # measured: see the query note in the task report.
  #
  def rules_need = @rules_need ||= Budget.steady_need(user, today: today)

  # NIL, NOT ZERO, for a user who has not declared one. Zero is a claim — "you bring in nothing"
  # — and it would make every user with a single rule read as underwater on a screen they have
  # not yet told anything. The block renders its invitation off this nil.
  #
  # `.to_d` because the comparison and the subtraction below both meet `rules_need`, which is
  # always BigDecimal. The `money` column casts, but an in-memory user assigned
  # `typical_income: 2400` holds the Integer.
  def typical_income = user.typical_income&.to_d

  # What is left after every rule is funded — the third line of §8, and the buffer's own source.
  # Nil wherever #typical_income is, because there is nothing to subtract from.
  def leftover = typical_income && (typical_income - rules_need)

  # §9's gate, and the ONE state the sacrifice button renders in.
  #
  # Steady need against declared income, never `HomePresenter#total_required` against it — see
  # Budget#steady_ask.
  #
  # `declared?` AND NOT `typical_income.present?`, WHICH IS THIS FIX ROUND'S CORRECTION. The gate
  # used to ask only about the income, and it was unreachable in the wrong state only because the
  # view happens to nest this inside `if declared?` — a layout fact protecting a money comparison,
  # which is not a gate at all. A user with an income and NO CADENCE reaches `rules_need` through
  # `Budget#steady_ask`, which treats the period as a calendar month: comparing a monthly need
  # against an income whose period nobody has declared is two units in one `>`, and it decides
  # whether the app offers to cut the user's budget. Closed at the reader, so no second caller can
  # inherit the view's accident.
  #
  # THE APP NOW SPELLS THE SAME COMPARISON THREE TIMES AND ALL THREE AGREE — this,
  # `HomePresenter#structurally_underwater?` and `SacrificePresenter#gap` — each gated on a
  # declaration that includes the cadence. An undeclared income is not "covered", it is unanswered,
  # and the block says so rather than showing a button for a comparison nobody has made.
  def underwater? = declared? && rules_need > typical_income

  # Whether the check has anything to check. Both halves are required: without a cadence
  # `rules_need` still answers (Budget#steady_ask treats the period as a month) but it answers
  # about a period the user has not agreed to, and printing "$1,668 a period" at someone who has
  # not said how long a period is states a figure with no unit.
  def declared? = user.typical_income.present? && user.period_cadence.present?

  # §8'S BOTTOM HALF, straight from the engine and in the engine's order. Not re-sorted, not
  # filtered and not truncated here: `SuggestionEngine#ordered` sorts by [kind, per-period cost,
  # id] for reasons its own comments give (a $1,600 annual bill costs $61.54 a period and must not
  # outrank a $1,500 monthly one), and a second ordering on this side would be a screen deciding
  # to disagree with the reader it renders.
  #
  # THERE IS NO DISMISS AND NO CAP ON THE LIST (spec §8). Dismissal is state, and the state it
  # would hide is drift.
  def suggestions = @suggestions ||= SuggestionEngine.new(user: user, today: today).suggestions

  # THE PANEL'S INDEX AND ITS HEADINGS, from one grouping so the counts cannot disagree with the
  # runs they point at.
  #
  # `group_by` and NOT a sort: `SuggestionEngine#ordered` already sorts by `[kind, per-period cost,
  # id]`, so the kinds arrive in the engine's rank order and each run is contiguous by
  # construction. Re-sorting here would be this page deciding to disagree with the reader it
  # renders — the same objection #suggestions' own comment makes — and grouping a list that is
  # already grouped is free.
  #
  # It hides nothing, which is the whole constraint (§8 forbids truncation and dismissal alike).
  # Every suggestion the engine returned is in exactly one group and every group is rendered in
  # full; the index above them is navigation, not a filter.
  def suggestions_by_kind = @suggestions_by_kind ||= suggestions.group_by(&:kind)

  # THE NAME OF THE ENVELOPE THIS ACCEPTANCE WOULD JOIN, or nil if it would make a new one — the
  # difference between "joins your existing Utilities envelope" and "puts all Utilities spending in
  # a new Utilities envelope", which are two different acts and must not share a sentence.
  #
  # TWO WAYS TO JOIN ONE, and they are the two `BudgetProposal#find_or_create_envelope` reuses on:
  #
  #   1. the category already points at an envelope — the engine says so itself, with `pool_id`,
  #      and it is the state the SECOND bill in a category is in once the first was accepted;
  #   2. the user already has a budget pool by the proposed name. The engine names a proposal after
  #      the CATEGORY and cannot see pools it did not propose, so this one is only visible here —
  #      and on the demo seeds it is the ordinary case, not the edge one.
  #
  # Two queries for the whole panel, and neither is per row.
  # NIL FOR THE TWO KINDS THAT PROPOSE NOTHING, and the guard is explicit rather than left to a
  # `&.`: drift and a dead rule are about a rule that already has an envelope, so their payloads
  # carry neither half and asking this of them is a question with no answer.
  def joined_envelope_name(suggestion)
    prefill = suggestion.prefill
    return reused_envelope_names[prefill[:pool_id]] if prefill.key?(:pool_id)
    return nil unless prefill.key?(:pool)

    existing_envelope_names[prefill[:pool][:name].to_s.downcase]
  end

  private

  def reused_envelope_names
    @reused_envelope_names ||=
      begin
        ids = suggestions.filter_map { |suggestion| suggestion.prefill[:pool_id] }
        ids.empty? ? {} : user.pools.where(id: ids).pluck(:id, :name).to_h
      end
  end

  # Every envelope the user already has, keyed by its lower-cased name — the same
  # case-insensitivity `Pool`'s uniqueness validation and `BudgetProposal`'s lookup use, so the
  # sentence and the write cannot disagree about whether a name is taken.
  def existing_envelope_names
    @existing_envelope_names ||=
      if suggestions.any? { |suggestion| suggestion.prefill.key?(:pool) }
        user.pools.budget_pools.pluck(:name).index_by(&:downcase)
      else
        {}
      end
  end

  # EVERY RULE THE USER OWNS. `user.all_budgets` is `Budget.for_user`, the app's one answer to
  # which rules are a user's.
  #
  # `pool: :budgets` is preloaded because PoolStatus reads `pool.budgets` for every anchored rule
  # it ranks — without it every group header is one SELECT per pool, on the widest per-rule screen
  # in the app.
  #
  # `pool: :user` because `Budget#user` walks the pool and BudgetCalculator#periods_until_due asks
  # it for every dated rule on the page. Measured on the demo seeds: eleven
  # `SELECT users WHERE id = ?` for one user, and the page's whole cost fell from 37 queries to 26
  # when they were preloaded. (`category: :user` rode alongside while a rule could be category-owned
  # and is dropped with that mode — it now preloads a link that is nil on every row.)
  def rules
    @rules ||= user.all_budgets.includes(:item, pool: [:user, :budgets, :account]).to_a
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
      status: pool.status(today: today, terms: ledger.terms_for(pool)),
      changed_after_distributing: distribution_clock.changed_after_distributing?(pool)
    )
  end

  # ONE CLOCK FOR THE WHOLE PAGE, over exactly the accounts the groups sit in — one movement query
  # for the screen rather than one per group. `pool.account_id` is in memory already (`#rules`
  # preloads `pool: [..., :account]`), and `#changed_after_distributing?` reads `pool.budgets`,
  # which the same preload loaded.
  #
  # Off `grouped_pools` rather than `user.pools.accounts`: an account holding no rule-carrying
  # envelope has no group on this page, so widening the query to it would fetch a distribution
  # nothing renders.
  #
  # MEASURED ON THE DEMO SEEDS, because a per-group query on the widest per-rule screen in the app
  # is exactly the shape this page has been bitten by before: the whole page costs 31 statements
  # without the clause and 32 with it. One query for thirteen groups, O(1) in groups.
  def distribution_clock
    @distribution_clock ||=
      DistributionClock.new(user: user, account_ids: grouped_pools.map(&:account_id), today: today)
  end

  def build_orphan(budget)
    reason = orphan_reason(budget)

    build_rule(budget, reason) if reason
  end

  # `budget.pool &&` is kept though every rule the page loads is pool-owned: `#rules` is
  # `Budget.for_user`, which is pool-scoped, but an unsaved rule assigned no pool would reach here
  # through a future caller and `.account_id` on nil is a 500 on a money screen.
  def orphan_reason(budget)
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

  def owner_name(budget) = budget.pool&.name.to_s

  # ONE LEDGER FOR THE WHOLE PAGE, over every pool that owns a rule — five grouped queries for the
  # set instead of five aggregates per pool per status. Orphan pools are in it too: they cost the
  # ledger nothing extra (the queries are grouped over the whole set) and a pool that is uncovered
  # would quietly fall back to five queries of its own.
  #
  # Lazy, like Home's. This page writes nothing, so there is no deletion for a snapshot to fall
  # the wrong side of; the laziness only keeps a presenter that is built and never rendered free.
  def ledger = @ledger ||= PoolBalanceLedger.new(pools_by_id.values)
end
