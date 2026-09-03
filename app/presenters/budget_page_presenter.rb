# frozen_string_literal: true

# Everything the Budget page renders: every rule the user owns, grouped under the category it fills,
# in the order the money actually arrives. Read-only — the rule forms it links to own the writes.
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §8 and
# docs/superpowers/specs/2026-08-21-two-ledger-design.md §3
class BudgetPagePresenter
  # ONE RULE ON THE PAGE. `due_on` is nil for an anchorless rule and that nil is information, not
  # a gap: BudgetCalculator#due_date answers `period_end` for a rule with no anchor, which is a
  # real number for the maths and a lie on screen — "due Aug 31" printed against a rate rule that
  # is never due. The row prints a date only where one exists.
  #
  # `reason` IS GONE WITH THE ORPHANS (two-ledger spec §5, Task 5). It said WHY a rule was outside
  # the fill order, and the one reason left — a pool no account holds — is a fact about a layer that
  # no longer owns rules. A category-owned rule is always in the fill order; there is nothing left
  # for a row to have to excuse.
  #
  # ** THE CLAIM FIGURES RIDE ON THE ROW, FROM ONE LEDGER (computed-claims spec §3.3; Task 2). **
  # Every one of the figures comes off `ClaimLedger#calculator_for`, which the page builds ONCE over
  # the user's whole rule set — the row does not hold a calculator and the partial does not build
  # one. That is the same objection `Group#status` makes about the category header, said one level
  # down: a partial free to ask for a claim of its own is a screen that costs a walk per row and
  # can disagree with the figure the header above it printed.
  #
  # `shape` rather than two booleans, because §3.3 offers DIFFERENT WORDS per shape — a rate rule's
  # envelope is topped up or reduced for this period, an accruing rule's fund is set aside into,
  # taken back out of, or skipped — and `ClaimCalculator#shape` is the one place that classification
  # lives.
  #
  # `adjustments` is THIS PERIOD's rows in date order, which is what the row lists and what the
  # remove button deletes. The claim already counts them; they are listed so the figure above them
  # is explicable rather than merely asserted.
  Rule = Data.define(
    :budget, :due_on, :shape, :claim, :built_up, :planned_this_period, :accrued_this_period, :adjustments
  ) do
    def anchored? = due_on.present?

    def rate? = shape == :rate

    # ** WHETHER A SKIP IS OFFERABLE, AND IT IS THE ACCRUAL THAT DECIDES (fix round MED-2). ** A
    # skip means "accrue nothing this period", so the button has a job only while the period is
    # still accruing SOMETHING — and `accrued_this_period` is the post-adjustment figure
    # (`planned + Σ this period's deltas`) while `planned_this_period` is not. Read off the plan,
    # this offered a second skip on a period already skipped, whose −planned would have been a raid
    # on the fund's prior savings under a flash saying the period was skipped. `AdjustmentForm` is
    # the backstop for a submission that arrives anyway.
    def skippable? = !rate? && accrued_this_period.positive?
  end

  # ONE CATEGORY AND THE RULES THAT FILL IT. `status` is a HoldingStatus, so the group header speaks
  # the app's existing row vocabulary through `pool_status_label` rather than a second one of its
  # own, and its #balance is the category's holdings — the same object, so the header's state and
  # its figure cannot disagree, and the page does not build a second calculator to ask.
  #
  # THE MEMBER NAMES THE VOCABULARY READS ARE UNCHANGED, and deliberately so: `shared/_holding_status`
  # renders `HomePresenter::Row`, this and `CategoryBudgetPresenter` off ONE set of questions
  # (#status, #needs_attention?, #period_closed?, #changed_after_distributing?, #due_marker?,
  # #balance_clause?), and Home does not move onto categories until Task 6. Renaming the shared
  # partial is that task's; what this one owes is to keep answering.
  #
  # `changed_after_distributing` rides on the group rather than being asked in the partial, for the
  # same reason `status` does: it compares this category's rules against THIS period's latest
  # distribution, and which period that is depends on the presenter's `today`. It is the second
  # half of the row vocabulary — `period_closed?` is the first — and this page carries BOTH because
  # a suffix on Home and not here is two screens describing one envelope differently on the same
  # afternoon. That the Budget page is where rules are EDITED makes the clause more nearly a
  # caption for what the user just did here than anywhere else in the app.
  Group = Data.define(:category, :rules, :status, :changed_after_distributing) do
    delegate :balance, to: :status
    delegate :priority, to: :category

    # THE ROW VOCABULARY'S FOUR QUESTIONS, so this Data and `HomePresenter::Row` answer the same
    # set and `shared/_holding_status` can render either without asking which screen it is on. These
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
    # is a bill's shortfall rather than this category's money — `pool_balance_clause` owns which —
    # and never a date: every rule's own date is printed in the rows below this header, so a date up
    # here would be one of them repeated without saying which. The mirror of
    # `HomePresenter::Row#due_marker?`, where the screen is missing the opposite thing.
    def balance_clause? = true
    def due_marker? = false
  end

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

  # The top half of §8: categories in fill order, each carrying its rules in due order.
  #
  # `[priority, name]` is the in-memory twin of `Category.in_fill_order` and the same tie-break
  # HomePresenter#by_priority uses. Priority alone is not a total order, and a tie falling through
  # to database order is the defect Plan 1 shipped in its waterfall — heap order deciding who gets
  # funded first, so the same page reported a different order on consecutive loads with no data
  # change.
  #
  # HOLDER CATEGORIES THAT OWN A RULE — `Category.in_fill_order.with_a_rule`, and the population is
  # THE SAME SET `.apply_fill_order` REFUSES ANY OTHER LIST THAN. That agreement is the whole point
  # of stating it twice: the reorder endpoint compares the submitted ids against
  # `in_fill_order.with_a_rule`, so a page that drew a draggable card for anything else would offer
  # the user a control whose every use is refused — and the refusal it produced would say "that
  # order didn't match your categories" about the order the page itself had just rendered.
  #
  # THE `holder?` HALF IS THIS FIX ROUND'S CORRECTION (MED-1). It was `with_a_rule` alone, which is
  # wider by exactly the rules on categories that hold nothing: an expense category whose
  # `funded_since` is still NULL is not in `Category.in_fill_order`, so no distribution can ever
  # reach it and no reorder can ever include it — a group with a priority badge and two arrows,
  # unorderable forever. Those rules are not hidden; they go to #unfilled_rules, which says why.
  #
  # THE BANDS ARE GONE. `Band`/`#account_bands` split this list by the account that funded each
  # envelope, because priority was only ever compared inside an account; the waterfall now ranks
  # every holder against every other, so there is one list and one reorder scope.
  def category_groups
    @category_groups ||= grouped_categories.sort_by { |category| [category.priority, category.name] }
      .map { |category| build_group(category) }
  end

  # THE RULES NO GROUP CAN SHOW, each of which is a claim on income that no distribution will
  # reach. ONE SHAPE, and it is permanent rather than transitional: a rule on a category that is not
  # holding money yet (`funded_since` NULL). The second shape — a rule written before the cutover,
  # naming only a pool — is GONE with `budgets.pool_id` (Task 8): `budgets.category_id` is NOT NULL
  # and `Budget.for_user` is `where(category_id: user.categories.select(:id))`, one lane.
  #
  # THE SURVIVING SHAPE IS REACHED FROM THE CATEGORY FORM, which Task 7 made able to clear
  # `funded_since`, and it is narrower than it was: the final fix wave refuses that clear while the
  # category still holds money (`Category#money_may_not_be_stranded`), so a rule can land here only
  # on a category that has been emptied first — which is exactly the "I set this up by mistake"
  # flow, and exactly the user this band has something to tell.
  #
  # THIS IS THE ORPHAN BAND'S JOB, AND NOT ITS RETURN. The old one listed rules on account-less
  # pools — a setup problem inside a layer being deleted. This lists rules whose OWNER cannot hold
  # money yet, which is a fact about the purpose ledger and is exactly what `Budget.steady_need`
  # counts and the fill order cannot: a user whose structural check says $500 and whose fill order
  # shows nothing has to be told where the $500 went.
  #
  # Ordered by owner name then by the groups' own `#rule_order`, because `all_budgets` carries no
  # ORDER BY and a plain UPDATE relocates a row in the heap.
  def unfilled_rules
    @unfilled_rules ||= (rules - grouped_rules)
      .sort_by { |budget| [owner_name(budget), *rule_order(budget)] }
      .map { |budget| build_rule(budget) }
  end

  # The empty top half — a brand-new user's first sight of this page. Asked of every rule the user
  # has rather than of #category_groups, and the gap between the two is what #unfilled_rules is
  # about: a rule on a category that holds nothing is a rule the user HAS and no group can show, so
  # a screen that answered "no rules" off #category_groups would tell that user they have none while
  # the band below them lists one. The pool lane that used to be the second half of this gap is gone
  # (Task 8, `budgets.category_id` NOT NULL); the holder gap is not, and it is why this is asked of
  # `#rules`.
  def no_rules? = rules.empty?

  # §8's structural check, three lines: what the rules claim from a period, what the user says
  # they bring in, and the difference.
  #
  # `Budget.steady_need`, NOT a sum over #rules — even though #rules is already loaded and
  # preloaded, and this therefore costs a second pass over the same rows. The figure is read by
  # this page, by Home's standing band and by the sacrifice view, and the moment two of
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
  # Steady need against declared income, never `HomePresenter#remaining_plan` against it — see
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
  # THERE IS NO CAP ON THE LIST AND NOTHING IS TRUNCATED. There IS a dismiss now (Henry's ruling of
  # 2026-08-20, which reverses §8 on that one point) — but it is the USER's act, one row at a time,
  # and every hidden row is still listed at the panel's foot. Nothing this screen decides removes a
  # suggestion from the list.
  def suggestions = @suggestions ||= engine.suggestions

  # THE SUGGESTIONS THIS USER HAS PUT DOWN, each paired with the row that hides it — the panel's
  # foot section, and the answer to "where did it go" that keeps hiding from being deletion.
  #
  # Through the SAME engine instance as #suggestions, which is why that reader stopped building one
  # inline: the two lists are the two halves of one run of the detectors, and a second instance
  # would run them twice and could disagree with the first about what was found.
  def hidden_suggestions = @hidden_suggestions ||= engine.hidden

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

  # `#joined_pool` IS DELETED (two-ledger spec §5). It answered which envelope an acceptance would
  # JOIN rather than mint — two queries for the whole panel, and a whole paragraph about the two
  # ways to reuse one — and there is no envelope to join or mint. What accepting does now is stamp
  # `funded_since`, which the engine states on the suggestion itself (`detail[:starts_holding]`), so
  # the row needs nothing from this class to say it.

  private

  # ONE ENGINE FOR THE PAGE. #suggestions and #hidden_suggestions are its two answers about one
  # run of the four detectors, and it holds the dismissal lookup they are split by.
  def engine = @engine ||= SuggestionEngine.new(user: user, today: today)

  # EVERY RULE THE USER OWNS. `user.all_budgets` is `Budget.for_user`, the app's one answer to
  # which rules are a user's.
  #
  # `category: [:user, :budgets]` is the whole preload and it replaces four pool-shaped ones.
  # `:budgets` because `HoldingStatus` reads `category.budgets` for every anchored rule it ranks and
  # `DistributionClock#changed_after_distributing?` reads it again — without it every group header
  # is one SELECT per category, on the widest per-rule screen in the app. `:user` because
  # `Budget#user` walks the owner and `BudgetCalculator#periods_until_due` asks it for every dated
  # rule on the page; measured on the demo seeds in the pool era, eleven `SELECT users WHERE id = ?`
  # for one user.
  def rules
    @rules ||= user.all_budgets.includes(:item, category: [:user, :budgets]).to_a
  end

  # `Category#holder?` IN MEMORY — the Ruby twin of `Category.in_fill_order`'s `expenses.where.not
  # (funded_since: nil)`, asked of the categories the preload already loaded rather than through a
  # second query that could disagree with the one `.apply_fill_order` runs.
  def rules_by_category
    @rules_by_category ||= rules.select { |budget| budget.category&.holder? }.group_by(&:category_id)
  end

  def grouped_rules = @grouped_rules ||= rules_by_category.values.flatten

  def categories_by_id = @categories_by_id ||= rules.filter_map(&:category).index_by(&:id)

  def grouped_categories = rules_by_category.keys.map { |id| categories_by_id.fetch(id) }

  # THE OWNER'S NAME, category first and the pool behind it — `Budget#user`'s own order, and
  # `BudgetPageHelper#budget_rule_name`'s. `to_s` because a rule with neither owner is
  # `#must_have_an_owner`'s refusal rather than something to crash a sort over.
  def owner_name(budget) = budget.category&.name.to_s

  def build_group(category)
    Group.new(
      category: category,
      rules: rules_by_category.fetch(category.id).sort_by { |budget| rule_order(budget) }.map { |budget| build_rule(budget) },
      status: category.status(today: today, terms: ledger.terms_for(category)),
      changed_after_distributing: distribution_clock.changed_after_distributing?(category)
    )
  end

  # ONE CLOCK FOR THE WHOLE PAGE, and it is the ONLY ARM `DistributionClock` has. An allocation
  # names no account (it moves money between the user's root and their categories, and the root is
  # one), so there is one distribution per period and one moment it happened at: one query for the
  # screen, O(1) in groups, and no `account_ids:` to thread. The pool era's per-account map and the
  # `account_ids:` keyword that reached it were deleted in Task 6 with their last caller
  # (`HomePresenter`), so this is no longer "the first caller to take" a second arm — there is no
  # second arm.
  #
  # `category.budgets` is in memory already (`#rules` preloads it), so this asks the database
  # nothing per row.
  def distribution_clock
    @distribution_clock ||= DistributionClock.new(user: user, today: today)
  end

  def build_rule(budget)
    calculator = claim_ledger.calculator_for(budget)

    Rule.new(
      budget: budget,
      due_on: due_on_for(budget),
      shape: calculator.shape,
      claim: calculator.claim,
      built_up: calculator.built_up,
      planned_this_period: calculator.planned_this_period,
      accrued_this_period: calculator.accrued_this_period,
      adjustments: adjustments_this_period.fetch(budget.id, [])
    )
  end

  # ONE CLAIM LEDGER FOR THE WHOLE PAGE (computed-claims spec §3.3) — three statements for the
  # user's entire rule set, where a calculator per row would be two per rule. It is built over
  # `Budget.for_user`, which is every rule this page can render including the ones in
  # #unfilled_rules, so `#calculator_for` never has to be guarded against a row it does not know.
  #
  # LAZY, as `#ledger` is and for the same reason: this page writes nothing, so there is no deletion
  # for a snapshot to fall the wrong side of.
  #
  # PINNED, not asserted: `budget_page_presenter_spec`'s "costs the same number of statements for
  # five rules as for one" counts them, because a row that quietly grew a calculator of its own is
  # invisible to every other example in that file.
  def claim_ledger = @claim_ledger ||= ClaimLedger.new(user, today: today)

  # THIS PERIOD'S DELTAS, BY RULE — one statement for the page, and the rows themselves rather than
  # a sum, because the row lists each one with its date and a remove button.
  #
  # ONE DAY OF SLACK ON EITHER SIDE, THEN FILTERED IN RUBY, which is `ClaimLedger#window`'s idiom
  # for the same reason: the bound is a UTC instant and the day it protects is the OWNER's, so the
  # query is deliberately wide and `Adjustment#local_day` — the app's one re-zoning — decides
  # membership. A bare timestamp range would drop a Tokyo evening's top-up from its own period.
  #
  # THE PRELOAD IS WHAT KEEPS `#local_day` FREE. It walks `rule → category → user` for the zone, so
  # without it the filter above and the date the row prints are two lookups per delta — the very
  # per-row cost `#claim_ledger` exists to avoid, arriving through the back door.
  def adjustments_this_period
    @adjustments_this_period ||= begin
      period = user.period_containing(today)
      Adjustment.where(rule_id: rules.map(&:id))
        .includes(rule: { category: :user })
        .dated_within((period.first - 1).beginning_of_day..(period.last + 1).end_of_day)
        .order(:date, :created_at)
        .select { |adjustment| period.cover?(adjustment.local_day) }
        .group_by(&:rule_id)
    end
  end

  # THROUGH THE CALCULATOR, NEVER THE RAW ANCHOR. A recurring bill's `anchor_date` is its FIRST
  # occurrence — the demo's car insurance anchors in March and is due every six months — so
  # printing the column would show a date years in the past as the next thing to pay.
  def due_on_for(budget) = budget.anchor_date.presence && due_date_for(budget)

  def due_date_for(budget) = (@due_dates ||= {})[budget] ||= calculator_for(budget).due_date

  # BudgetCalculator#due_order, never a `[due_date, -amount, id]` of our own: that key decides
  # which rule a category row names, which one `allocated_balances` fills first and therefore which
  # one slips — and it lives in exactly one place.
  #
  # The already-computed due date is handed in rather than left for the key to ask again, because
  # #due_date re-runs #paid_since_anchor's SUM on every call and this page sorts every rule the
  # user has.
  def rule_order(budget) = calculator_for(budget).due_order(due_date_for(budget))

  # Keyed by the record rather than by id, as HomePresenter does: an unsaved rule has no id, and
  # nil as a cache key would hand every such rule the first one's calculator.
  def calculator_for(budget) = (@calculators ||= {})[budget] ||= budget.calculator(today: today)

  # ONE LEDGER FOR THE WHOLE PAGE, over exactly the categories the groups render — grouped queries
  # for the set instead of five aggregates per category per status. A category in #unfilled_rules is
  # not in it and needs no term: it holds nothing by definition, which is why its rule is in that
  # list rather than in a group.
  #
  # Lazy, like Home's. This page writes nothing, so there is no deletion for a snapshot to fall
  # the wrong side of; the laziness only keeps a presenter that is built and never rendered free.
  #
  # `user:` is passed so a page whose groups are empty still names an owner — `CategoryLedger`
  # raises `NoSingleOwner` rather than guessing, and a brand-new user's page has no categories at
  # all to read one off.
  def ledger = @ledger ||= CategoryLedger.new(grouped_categories, user: user)
end
