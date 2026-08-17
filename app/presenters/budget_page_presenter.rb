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

  # §8's structural check, three lines: what the rules claim from a period, what the user says
  # they bring in, and the difference.
  #
  # `Budget.steady_need`, NOT a sum over #rules — even though #rules is already loaded and
  # preloaded, and this therefore costs a second pass over the same rows. The figure is read by
  # this page, by Home's standing band and (Task 9) by the sacrifice view, and the moment two of
  # them spell the sum themselves they are free to disagree about which rules count. One reader,
  # measured: see the query note in the task report.
  #
  # It counts POOL-MODE rules only, deliberately — a category cap is a spending limit, not a claim
  # on income. #caps_not_counted? below is what keeps that exclusion from reading as a bug.
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
  # Budget#steady_ask. `typical_income.present?` first: an undeclared income is not "covered", it
  # is unanswered, and the block says so rather than showing a button for a comparison nobody has
  # made.
  def underwater? = typical_income.present? && rules_need > typical_income

  # Whether the check has anything to check. Both halves are required: without a cadence
  # `rules_need` still answers (Budget#steady_ask treats the period as a month) but it answers
  # about a period the user has not agreed to, and printing "$1,668 a period" at someone who has
  # not said how long a period is states a figure with no unit.
  def declared? = user.typical_income.present? && user.period_cadence.present?

  # WHEN "$0.00 A PERIOD" NEEDS EXPLAINING. A user whose only rules are category caps — the shape
  # every pre-envelope user of this app has — reads `rules need $0.00` and trivially covered, and
  # that is CORRECT: no distribution fills a cap, so nothing yet claims their income. The envelope
  # rules that would are exactly what Tasks 6-7's suggestion engine exists to propose.
  #
  # Correct is not the same as legible, though. Zero printed above a page listing eight of the
  # user's own rules reads as a figure that failed to compute, so the block says in one sentence
  # which rules it is not counting and why. Gated on the zero, not merely on caps existing: beside
  # a real pool-mode figure the sentence would be a footnote about an exclusion nobody noticed.
  #
  # Off `#rules`, which is already loaded — `user.all_budgets` reaches both modes, so this asks no
  # new question of the database.
  def caps_not_counted? = rules_need.zero? && rules.any?(&:category_mode?)

  # §8'S BOTTOM HALF, straight from the engine and in the engine's order. Not re-sorted, not
  # filtered and not truncated here: `SuggestionEngine#ordered` sorts by [kind, per-period cost,
  # id] for reasons its own comments give (a $1,600 annual bill costs $61.54 a period and must not
  # outrank a $1,500 monthly one), and a second ordering on this side would be a screen deciding
  # to disagree with the reader it renders.
  #
  # THERE IS NO DISMISS AND NO CAP ON THE LIST (spec §8). Dismissal is state, and the state it
  # would hide is drift.
  def suggestions = @suggestions ||= SuggestionEngine.new(user: user, today: today).suggestions

  # THE MONTHLY CAP A RATE SUGGESTION'S CATEGORY ALREADY CARRIES, or nil.
  #
  # `Category.budgetable` — the rate detector's population — is "an expense category with no pool",
  # which says nothing about a cap, so five of the demo's rate suggestions are for categories the
  # user has already budgeted. The sentence must name the cap: a cap funds nothing
  # (`Budget.steady_need` counts pool-mode rules only, Task 4's ruling), so the suggestion is
  # correct — but printed silently beside a category the user capped last month it reads as the
  # app failing to notice.
  #
  # AND IT APPLIES TO A DATED BILL TOO, harder: accepting one RE-POINTS the category, and
  # `Category#destroy_budget_if_pool_linked` destroys the cap when it does. A sentence that did not
  # name the cap would let a click delete a rule the user wrote, silently.
  #
  # ONE QUERY FOR THE WHOLE PANEL rather than `category.budget` per row, and none at all when no
  # suggestion on screen would re-point anything. Keyed off `prefill[:category_id]`, which is
  # exactly the set of categories an acceptance would move — already in memory, so this asks the
  # database nothing it does not have to.
  def cap_for(suggestion) = caps_by_category_id[suggestion.prefill[:category_id]]

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

  # `user.budgets` and not a bare `Budget.where`, for the same reason every other read on this
  # presenter goes through the user: `has_many :budgets, through: :categories` walks the category
  # link, which is exactly and only the category-mode caps this asks about, and it cannot reach a
  # row the user does not own even if a `category_id` ever arrived from somewhere it should not.
  def caps_by_category_id
    @caps_by_category_id ||=
      begin
        ids = suggestions.filter_map { |suggestion| suggestion.prefill[:category_id] }
        ids.empty? ? {} : user.budgets.where(category_id: ids).index_by(&:category_id)
      end
  end

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
    @rules ||= user.all_budgets.includes(:item, category: :user, pool: [:user, :budgets, :account]).to_a
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
