# frozen_string_literal: true

class Budget < ApplicationRecord
  # A RULE BELONGS TO THE THING THAT HOLDS THE MONEY (two-ledger spec §3): `budgets.category_id`
  # replaced `budgets.pool_id`, one category to one budget line, and Task 8 dropped the column the
  # pool arm read. `budgets.category_id` is NOT NULL at the database now.
  #
  # `optional: true` SURVIVES THE POOL IT WAS SHARED WITH, AND IT IS NOT AN OVERSIGHT. A required
  # `belongs_to` validates presence by READING the attribute, and `budgets.category_id` is younger
  # than `spec/migrations/two_ledger_spec.rb`, which plants rules through this model against a
  # schema rewound past the column (see `#category_column?`). Reading an attribute the database does
  # not have raises rather than rejecting, so the presence rule is stated by `#must_have_a_category`
  # below, behind the same gate every other reader of the column is behind.
  belongs_to :category, optional: true, touch: true
  belongs_to :item, optional: true

  # THE DATED, SIGNED DELTAS ON THIS RULE'S ACCRUAL (computed-claims spec §3.3). `dependent: :destroy`
  # because an adjustment is a delta on a schedule: with the rule gone there is no accrual for it to
  # be a delta ON, and a `+$500 into Vacation` left behind would be a claim with no arm to land on.
  #
  # `foreign_key: :rule_id` — the column is named for the app's word for a `budgets` row, and this is
  # the one place the two spellings meet (see the migration's header).
  has_many :adjustments, foreign_key: :rule_id, dependent: :destroy, inverse_of: :rule

  enum :basis, { monthly: 0, per_period: 1 }, prefix: true

  # EVERY RULE A USER OWNS, IN ONE RELATION — the reader `User has_many :budgets, through:
  # :categories` cannot be. That association walks the category link only, which after the cutover
  # reaches NOTHING at all, and every rule the Budget page manages is invisible to it.
  # `current_user.budgets.find` therefore answered RecordNotFound for rules the user plainly owns.
  #
  # THE CAP'S CATEGORY ARM WENT IN PLAN 3, AND THIS IS NOT IT COMING BACK. The scope was
  # `where(category_id: user.categories).or(where(pool_id: user.pools))` because a rule could be a
  # per-category CEILING on a pool-funded envelope; that shape is gone and its pins were withdrawn
  # with it. The arm that is left means the opposite thing — the category is the OWNER now, the
  # thing that holds the money — and it is reached by the same SQL only because the same column
  # happens to say who owns what.
  #
  # ONE LANE SINCE TASK 8, which dropped `budgets.pool_id`. The OR existed so a rule written through
  # the pool form and a rule written on a category were both found while the two lanes coexisted;
  # there is one lane, so the `.or` would now be a branch that can never match.
  #
  # Scoped by the OWNER's user, not by a `user_id` on this table — a budget carries no user
  # column, and inventing one would give the invariant two places to be wrong.
  scope :for_user, ->(user) { where(category_id: user.categories.select(:id)) }

  # A rule that demands nothing is what deleting it is for, and a negative one is money
  # flowing the wrong way through the allocation waterfall — which `clamp` refuses outright.
  #
  # ** ZERO IS LEGAL FOR EXACTLY ONE SHAPE (computed-claims spec §3.2, Henry's ruling of
  # 2026-09-03). ** "A dateless target … accrues by its rate if it has one, and OTHERWISE ONLY BY
  # POSITIVE ADJUSTMENTS" — a goal somebody feeds by hand and never on a schedule. Under the computed
  # model every claim comes from a rule (§3.3), so that goal has to BE a rule, and the only honest
  # way to say "no standing rate" is an amount of zero. See #set_aside_only? for the exact shape;
  # everywhere else "demands nothing" still means "delete it".
  validates :amount, presence: true
  validates :amount, numericality: { greater_than: 0 }, unless: :set_aside_only?
  validates :amount, numericality: { greater_than_or_equal_to: 0 }, if: :set_aside_only?
  validates :interval_months, numericality: { greater_than: 0 }, allow_nil: true

  validate :must_have_a_category
  validate :category_must_be_an_expense, if: :category_mode?
  validate :item_must_belong_to_category, if: :category_mode?
  validate :category_may_hold_one_item_less_rule, if: :category_mode?
  # UNGATED, BOTH OF THEM: `#shape_must_be_valid` is about the three columns that spell a cadence
  # and `#item_must_not_be_claimed` is about one item having one rule, so neither has ever needed
  # to know who owns the rule.
  validate :shape_must_be_valid
  validate :item_must_not_be_claimed

  # `#category_column?` FIRST, AND IT IS NOT DEFENSIVE. `budgets.category_id` is younger than
  # `spec/migrations/two_ledger_spec.rb`, which rewinds the schema past `CategoriesHoldTheMoney` —
  # whose whole subject is ADDING this column — for the length of the file. Reading an attribute the
  # database does not currently have raises NameError, and a predicate that raises is not an answer.
  # Asked once here and once in #user, which are the only two readers of the column outside a
  # validator gated on this method.
  #
  # `spec/seeds_spec.rb` USED TO BE THE SECOND SPEC ON THIS LIST and no longer rewinds anything
  # (Task 8): the seeds are category-native and cannot be replanted against a schema that has no
  # `funded_since` and no `allocations`.
  def category_mode? = category_column? && (category_id.present? || category.present?)

  # nil-safe: an owner-less budget is exactly the state the form re-renders in
  # after a failed submission, and a rewound schema has no `category_id` for a rule to carry.
  def user = category_mode? ? category&.user : nil

  # THE OWNER'S TODAY (fix round 2 — LOW-1), through the category that knows who the owner is.
  # `User#today` carries why this is not `Date.current`; `Category#today` carries the owner-less
  # fallback. What is left here is the CATEGORY-less arm, which is the same state `#user` above is
  # nil-safe for — a rule re-rendered from a failed form, which no calculator is built from.
  #
  # It is the default for the `today:` this class hands down, so two readers on one row cannot be
  # asked about two different days by the same caller.
  def today = category&.today || Date.current

  # WHAT THIS RULE CLAIMS FROM THE USER'S MONEY (computed-claims spec §3) — the ONE door onto the
  # claim, and the port of `Category#holding_calculator`'s role: `spending:` and `adjustments:` thread
  # straight through and DEFAULT TO NOTHING, which keeps this the unbatched single-rule door. Only the
  # callers that ITERATE rules build a `ClaimLedger` and let it inject the grouped rows.
  #
  # A SECOND CONSTRUCTION PATH IS HOW A KEYWORD ENDS UP HONOURED ON ONE SCREEN AND FORGOTTEN ON THE
  # NEXT, so nothing outside `ClaimLedger` calls `ClaimCalculator.new` itself.
  #
  # IT WAS NOT THE ONLY CALCULATOR ON THIS ROW UNTIL THE FIX WAVE. `#calculator` built a
  # `BudgetCalculator` — what the rule needed from the next DISTRIBUTION — and Task 4 was meant to
  # delete it along with the distribution. It survived on one branch of `#steady_ask` with a due date
  # the claims overrule; both are gone now (see `#one_off_steady_ask`).
  def claim_calculator(today: self.today, spending: nil, adjustments: nil)
    ClaimCalculator.new(self, today: today, spending: spending, adjustments: adjustments)
  end

  # ** WHICH OF §3'S THREE FORMULAS THIS RULE TAKES — `ClaimCalculator#shape`, AND THE ONLY DOOR ONTO
  # IT FROM OUTSIDE A CALCULATOR (fix wave — MED-2). ** The shape is read off `anchor_date` and the
  # CATEGORY's `target_amount`, and `SuggestionEngine#rate_shape?` held a second reading of it that
  # asked neither: `anchor_date.blank? && item_id.blank? && cadence.in?([:per_period, :monthly])`. It
  # is missing the target column, so every goal category's rule was a "rate rule" to the drift
  # detector — including the eight $0 rules Task 4's migration minted, which fired "your rule says
  # $0.00, you spend $X" at a fund the user feeds by hand, and a $50-a-period goal with heavy
  # spending, which was told to RAISE its contribution. One spelling, on the class that owns §3.
  #
  # IT COSTS NO QUERY WHERE THE OWNER IS LOADED: `#shape` reads two columns and the constructor's
  # `today:` default walks `category.user`, which every caller of this method already preloads.
  def claim_shape = claim_calculator.shape

  # HOW OFTEN THIS RULE COMES ROUND, as one symbol. `basis`, `interval_months` and `anchor_date`
  # are three columns whose COMBINATION is the shape (§3.1), and reading the shape off them takes
  # a four-branch cascade in an order that is a hazard in itself — so the cascade lives once,
  # here, and the two helpers that used to hold a copy each keep only their own words:
  # `HomeHelper#pool_rule_label` names a rule ("Every 6 months") and
  # `BudgetPageHelper#budget_rule_basis` says what an amount is per ("every 6 months").
  # Classification is the model's; wording is each screen's.
  #
  # `:every_n` names the shape without naming the number — the interval is on the record and each
  # caller interpolates its own, so this stays a fixed set of four rather than a symbol per N.
  #
  # `basis_per_period?` FIRST: a per-period rule carries no interval either, so testing the
  # interval first would call every rate rule a one-off.
  #
  # THE CATEGORY-CAP ARM IS GONE. A cap carried no interval at all (#shape_must_be_valid ran in
  # pool mode only), so it needed answering before the nil-interval branch could call it a one-off.
  # There is no cap to answer for now, and every rule reaching here has been through
  # #shape_must_be_valid — so a blank interval really does mean a one-time bill.
  def cadence
    return :per_period if basis_per_period?
    return :one_off if interval_months.blank?
    return :monthly if interval_months == 1

    :every_n
  end

  # PER-PERIOD STEADY-STATE COST OF THIS RULE — what it claims from a typical period, NOT what
  # it asks this period. That second question is `PoolCalculator#required` / `BudgetCalculator
  # #required`, and the two are deliberately different figures with deliberately different names:
  #
  #   #required   — this period's ask. Catch-up on a bill that slipped, zero on one already
  #                 funded, the whole remainder on one due before the next boundary. It moves
  #                 every time money is distributed.
  #   #steady_ask — the standing claim. What this rule costs a period FOREVER, assuming nothing
  #                 is behind and nothing is ahead. It moves only when the rule itself changes.
  #
  # §9's structural check ("your rules need $X a period / you typically bring in $Y") is a
  # question about the SHAPE of a budget, so it can only be asked of the steady figure. Asked of
  # #required it answers a different question in the same words: a catch-up period reads
  # underwater on a budget that fits fine, and the period right after a distribution reads fine
  # on a budget that does not fit at all.
  #
  # BUILT ON #cadence, not on a fifth reading of `basis`/`interval_months`/`anchor_date`. The
  # shape classification is that method's and the two helpers that used to hold a copy each were
  # collapsed into it one task ago; a private cascade here would reopen exactly that seam.
  #
  # `amount * 12 / (periods_per_year * interval)` rather than `amount / periods_in_interval`, and
  # the difference is not cosmetic: `periods_in_interval` for a monthly rule under a biweekly user
  # is 26/12 = 2.1666…, and an Integer spelling of it truncates to 2 — a monthly rule would ask
  # for half its amount every fortnight, 8% over the year. Dividing once, at the end, keeps the
  # fraction. `amount.to_d` first because an in-memory record assigned `amount: 260` holds an
  # Integer and `Integer * 12 / Integer` truncates the cents.
  #
  # `user` is the divisor's owner. The one-off branch reaches the rule's OWN owner through the
  # calculator instead (`BudgetCalculator#periods_until_due`); the two are the same record by
  # construction, since every caller reaches this through `Budget.for_user(user)`.
  #
  # `today:` is not in the plan's sketch and is needed: the one-off shape amortises over the
  # periods between NOW and its due date, so a caller with a fixed clock (every calculator in
  # this app takes one) must be able to hand its own down rather than have this reach for a clock
  # behind it. Unhanded, it reads the OWNER's day off the user it is already given (fix round 2 —
  # LOW-1), not the ambient one.
  #
  # THIS DIVIDES A MONTHLY RULE BY `periods_per_year` WHILE ITS PERIOD STILL ENDS ON THE CALENDAR
  # MONTH, and the divergence is deliberate (plan 2d decision 5, recorded here and in
  # `BudgetCalculator#period_end`). A $260-a-month rule under a biweekly cadence costs $120 a
  # period — always, in every month — because that is what a standing monthly rate means spread
  # over 26 periods. Its LIFECYCLE is a different question: the month is the span the user said
  # the money is for, so `period_end` closes it at month end and the sweep may not take the
  # envelope's leftover before then.
  #
  # Cost and lifecycle are not the same question, so one answer for both would be wrong for one of
  # them. Measured in both directions: costing by the calendar's boundaries made this rule answer
  # $130 in nine months of 2026 and $86.67 in the two holding a third boundary (see above), and
  # ending its period by `periods_per_year` instead would roll a monthly rule mid-month and fund it
  # twice inside one month.
  # `claim:` IS A SEAM AND NOT A SECOND DOOR (`ClaimCalculator#spending:`'s own reasoning). Only the
  # one-off branch reads it, and only `.steady_need` — which iterates a whole user's rules — hands
  # one in, off the `ClaimLedger` whose three grouped statements answer for every rule at once. Left
  # nil this method builds its own through `#claim_calculator`, so the single-rule door still works
  # unbatched.
  def steady_ask(user, today: user.today, claim: nil)
    case cadence
    when :per_period then amount.to_d
    when :one_off then one_off_steady_ask(today, claim)
    else (amount.to_d * 12 / (user.periods_per_year * (interval_months || 1))).round(2)
    end
  end

  # WHAT THIS USER'S FUNDING RULES CLAIM FROM ONE PERIOD — the single reader behind §9's
  # structural check, `BudgetPagePresenter#rules_need` and `HomePresenter#structurally_underwater?`
  # alike. Two screens asking the same question of two different sums is how one page tells a user
  # their budget fits while the other says it does not.
  #
  # THE EXCLUSION THIS FIGURE WAS BUILT AROUND IS NOW EMPTY, AND THAT IS THE HONEST THING TO SAY.
  # It used to read `for_user(user).where.not(pool_id: nil)`, and the `where.not` was the whole
  # argument: a category-mode cap is a SPENDING LIMIT on tracking, not a funding claim on income —
  # `AllocationCalculator` never read one, so no distribution ever asked for a penny on account of
  # one, and counting one would have inflated "your rules need" by money that will never be asked
  # for. On the pre-cutover demo that was $1,523.08 a period of double-counting, a "Housing" cap of
  # $1,500 a month sitting over the top of the $1,500 Rent rule that actually filled the envelope.
  #
  # Caps do not exist. `#for_user` is category-scoped by construction now, so the mode filter it used
  # to stack on top of it would be a `where.not` that can never exclude a row — a condition kept for
  # the sentence it lets a comment say, which is how dead filters survive. It is gone; the boundary
  # it drew survives as a fact about the data rather than a clause in a query.
  #
  # TASK 9 INHERITS THE SAME SUM: the sacrifice view's cut list is exactly the rules counted here,
  # because the gap it is closing is this figure. It should not re-derive the population.
  #
  # `sum(0.to_d)` with an explicit BigDecimal seed. An empty relation's `sum` is Integer `0`, and
  # this figure is compared against `typical_income` and subtracted from it — the seed keeps a
  # user with no rules at all on the same numeric type as one with them.
  #
  # ** IT ITERATES A `ClaimLedger` RATHER THAN A RELATION, AND THAT IS A COST DECISION (fix wave —
  # MED-3). ** `#steady_ask`'s one-off branch reads `ClaimCalculator#planned_this_period` now, and an
  # unbatched calculator runs a spending query and an adjustment query of its OWN — two statements
  # per one-off rule on a reader three screens call. `ClaimLedger` answers every rule's lanes in
  # three grouped statements whatever the count, and its `#rules` is this method's own population
  # spelled once (`for_user(user).includes(:item, category: :user)` — the same relation, the same
  # preloads, on the class that already owns it).
  #
  # THE PRELOAD ITSELF IS MEASURED, and the measurement corrected a claim this comment first made.
  # On the demo seeds it buys NOTHING on the FIGURE side: 22 rules cost 5 statements with it and 5
  # without, because only two of them are dated. It is kept because the shape differs even where the
  # figure does not — a budget has no user column, so `#user` walks the category, and without the
  # nested preload that is two un-preloaded queries per rule that reaches for a clock.
  #
  # PINNED, not asserted: `budget_steady_ask_spec`'s "costs the same number of queries for five
  # dated rules as for one" counts the statements, because a batching that quietly stops covering a
  # lane is invisible to every other example in that file.
  def self.steady_need(user, today: user.today, ledger: nil)
    ledger ||= ClaimLedger.new(user, today: today)

    ledger.rules.sum(0.to_d) { |budget| budget.steady_ask(user, today: today, claim: ledger.calculator_for(budget)) }
  end

  private

  # ** A ONE-TIME RULE HAS NO INTERVAL TO DIVIDE BY, so its steady claim is §3.2's CATCH-UP SHARE:
  # what is still missing, over the periods left to find it in. `ClaimCalculator#planned_this_period`
  # IS that figure and this branch reads nothing else (fix wave — MED-3). **
  #
  # ** IT WAS `BudgetCalculator`, AND THAT CLASS DIED HERE. ** Task 4 deleted the distribution it
  # belonged to; this one branch kept it alive, and with it a SECOND due date the claims overrule.
  # Two defects, both measured:
  #
  #   THE FULFILMENT LIE. `BudgetCalculator#fulfilled?` has no payment signal for an ITEM-LESS rule,
  #     so it fell back to "assume every bill was paid on time" — `today >= anchor_date`. An
  #     item-less one-off anchored Aug 1 with nothing spent was therefore priced at $0.00 a period by
  #     the structural check while its own row on the same page read `overdue · was Aug 1`. The
  #     computed model has the signal that class lacked (spending on the category, §3.2), so
  #     `#settled?` is a fact rather than an assumption — and it is inside `#planned_this_period`.
  #   THE FENCEPOST. `periods_until_due` counts from `today` and so misses the boundary today is
  #     standing on; `#periods_left` counts it, because §3.2's accrual lands IN FULL the day a period
  #     opens (spec §10.1 ruling 7). The two answered different numbers of periods for one bill.
  #
  # ** IT IS THE CATCH-UP FIGURE AND THEREFORE MOVES WITH WHAT IS ALREADY SAVED, which the old
  # reading did not. ** `amount / periods_until_due` re-asks for the WHOLE bill every period, so a
  # one-off half funded still reported the full per-period cost and the structural check counted
  # money the user had already set aside. The catch-up share reports what is left to find, and a
  # fund that is whole reports zero — the same zero the fulfilled gate used to produce, arrived at
  # from the fund rather than from the calendar.
  #
  # THE FLOOR AT ONE PERIOD SURVIVES INSIDE `#periods_left`, so a user with no declared cadence —
  # whose `period_boundaries` is empty — gets the whole remainder in one period rather than a
  # division by zero. Blunt, and it is the honest answer: without a period there is nothing to
  # spread over.
  def one_off_steady_ask(today, claim)
    (claim || claim_calculator(today: today)).planned_this_period
  end

  # A RULE BELONGS TO A CATEGORY, full stop (two-ledger spec §3). Its ancestor
  # `#must_have_an_owner` accepted a pool OR a category while both lanes existed, and
  # `#exactly_one_owner` before that refused a record naming both — three shapes of one rule, and
  # the last of them is the one the schema now enforces on its own with `NOT NULL`.
  #
  # BEHIND `#category_mode?` RATHER THAN `belongs_to … optional: false`, and the gate is the whole
  # reason this is a method: two specs plant rules through this model against a schema rewound past
  # the column (see `#category_column?`), and a presence rule that READS a missing attribute raises
  # instead of rejecting. A rewound rule is owner-less and nothing here pretends otherwise; it is
  # simply not asked, exactly as its three siblings are not.
  #
  # ON `:base` RATHER THAN `:category`: an owner-less rule is a fact about the whole record, not
  # about a control the form offers. `budgets/_form` renders `errors[:base]` in its own
  # notification, and the control it offers is a CATEGORY picker, so the sentence describes the
  # form the user is looking at.
  def must_have_a_category
    return unless category_column?

    errors.add(:base, "must belong to a category") unless category_mode?
  end

  # A RULE ON A CATEGORY THAT CANNOT HOLD MONEY AT ALL. Income lands in AVAILABLE and is allocated
  # out of it — an income
  # category holds nothing, ever — so a funding rule on one is a standing claim on money no
  # `Category#holder?` can ever be true of.
  #
  # IT CLOSES A PATH `BudgetProposal` ALREADY CLOSED FROM THE OTHER END, AND THE GAP BETWEEN THE TWO
  # IS THE WHOLE REASON THIS EXISTS. Accepting a rule stamps `funded_since`, and
  # `Category#only_expenses_hold_money` refuses that stamp on an income category — so `POST /budgets`
  # was answered. `PATCH /budgets/:id` is not: `#update` writes `budget.update(budget_params)`
  # directly, never through `BudgetProposal`, so re-parenting a rule onto the user's own income
  # category saved clean. The rule then counted into `Budget.steady_need` (measured: $500 a period
  # of a claim nothing can fill), rendered a group on the Budget page, and was UNFILLABLE FOREVER —
  # `Category.in_fill_order` is holders, so no distribution could ever reach it and no reorder could
  # include it. A validation is the right layer for that: it is a fact about the record, not about
  # which of two writers reached it.
  #
  # `income?` RATHER THAN `!expense?`, matching the enum's own two arms — a third type added later
  # is a decision somebody has to make about this rule rather than one this line makes silently by
  # refusing everything it does not recognise.
  def category_must_be_an_expense
    errors.add(:category, "must be an expense category") if category&.income?
  end

  # See docs/superpowers/specs/2026-08-14-envelope-budgeting-design.md §3.1
  def shape_must_be_valid
    if basis_per_period?
      errors.add(:basis, "per-period rules cannot have a due date or interval") if anchor_date.present? || interval_months.present?
      return
    end

    return if anchor_date.present?

    # Row 2 pins the anchorless monthly rate rule to a 1-month interval. Any
    # N > 1 is row 3, which requires an anchor — without one the calculator reads
    # the due date as the end of this month and demands N months of money now.
    if interval_months.blank?
      errors.add(:interval_months, "is required for a monthly rule with no due date")
    elsif interval_months != 1
      errors.add(:interval_months, "must be 1 for a monthly rule with no due date")
    end
  end

  def category_column? = has_attribute?(:category_id)

  # A dated bill anchors on an item, and that item has to be an item OF the category the rule funds
  # — an item from somewhere else would date a bill against money it never drains.
  #
  # Objects, not ids: under `build` nothing is persisted and `nil == nil` would wave every
  # item-less category through.
  def item_must_belong_to_category
    return if item.blank?

    errors.add(:item, "must belong to this category") unless item.category == category
  end

  # ** ONE CATEGORY, ONE BUDGET LINE (two-ledger spec §3), NOW THAT THE LINE IS A CLAIM (Henry's
  # ruling of 2026-09-03). ** An ITEM-LESS rule's spending lane is the WHOLE category — that is
  # computed-claims §3.2's own sentence, "an expense on the rule's item, or, for an item-less rule,
  # on the category" — and `Category#claim` is the SUM of its rules' claims. So two item-less rules
  # on one category each subtract the same entries: $250 of groceries comes off a $400 rate rule and
  # off a $75 one beside it, and the category reports $225 claimed when the honest figure is $475
  # less one $250. Neither rule is wrong on its own, which is what makes it invisible.
  #
  # ITEM-BACKED RULES STAY PER-ITEM and are untouched: their lanes are disjoint by construction, and
  # `#item_must_not_be_claimed` below already keeps two rules off one item. A category may therefore
  # carry one catch-all rule and as many dated bills as it has items, which is exactly the demo's
  # shape and Ming's.
  #
  # ON `:base`, with `#must_have_a_category`'s reasoning: it is a fact about the whole record rather
  # than about one control, and `budgets/_form` renders `errors[:base]` in its own notification. The
  # sentence names both ways out, because both are things the user can actually do on that form.
  #
  # `where.not(id: id)` for `#item_must_not_be_claimed`'s reason: it renders as `id IS NOT NULL` on
  # an unsaved record, so a new rule is compared against every persisted one, and an edit does not
  # collide with itself.
  def category_may_hold_one_item_less_rule
    return if item_id.present?
    return unless Budget.where(category_id: category_id, item_id: nil).where.not(id: id).exists?

    errors.add(
      :base,
      "this category already has a rule covering all of its spending — change that one instead, " \
      "or point this rule at a single item"
    )
  end

  # THE ONE SHAPE THAT MAY DEMAND NOTHING (computed-claims spec §3.2): a goal fed only by hand. The
  # CATEGORY names a figure to reach, the rule names no deadline and no interval to reach it by, and
  # so it has no schedule for a rate to be the rate OF — every penny it ever holds arrives as a
  # positive adjustment (§3.3's "set aside"). `ClaimCalculator` reads exactly this shape as a target
  # rule whose per-period accrual is its amount, so a zero amount accrues zero and the adjustments
  # are the whole of it.
  #
  # ALL THREE COLUMNS, AND THE THIRD IS NOT REDUNDANT: `#shape_must_be_valid` refuses a
  # monthly-basis rule with neither an anchor nor an interval, so "no anchor and no interval" is the
  # per-period shape — but stating it positively is what keeps this from silently widening if that
  # rule ever changes.
  #
  # BEHIND `#category_mode?`, like every other reader of the column: `categories.target_amount` and
  # `budgets.category_id` arrived in the same migration, so a schema rewound past it has neither and
  # this must not reach for either.
  def set_aside_only?
    return false unless category_mode?

    anchor_date.blank? && interval_months.blank? && category&.target_amount.present?
  end

  # `where.not(id: nil)` renders as `id IS NOT NULL`, so an unsaved budget still
  # compares against every persisted rule. An unsaved *item* has no id though,
  # and `item_id: nil` would match every item-less budget — bail rather than
  # invent a conflict.
  def item_must_not_be_claimed
    return if item&.id.blank?

    claimed = Budget.where(item_id: item.id).where.not(id: id).exists?
    errors.add(:item, "is already used by another rule") if claimed
  end
end
