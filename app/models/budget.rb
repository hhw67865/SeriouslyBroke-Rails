# frozen_string_literal: true

class Budget < ApplicationRecord
  # A RULE BELONGS TO THE THING THAT HOLDS THE MONEY (two-ledger spec §3): `budgets.category_id`
  # replaces `budgets.pool_id`, one category to one budget line, and Task 1's migration has already
  # written a `category_id` onto every rule in the database.
  #
  # `optional: true` ON BOTH SIDES FOR THE LENGTH OF THIS BRANCH, and `#must_have_an_owner` below is
  # what makes "a rule has an owner" true. It is NOT the cap this column used to carry (plan 3
  # deleted that, and it was a per-category CEILING on a pool-funded envelope — two owners with two
  # different meanings). A category-owned rule here IS the funding rule; the pool arm is the same
  # rule pointing at the layer that is being deleted, and Task 8 removes it along with the column.
  belongs_to :category, optional: true, touch: true
  belongs_to :pool, optional: true, touch: true
  belongs_to :item, optional: true

  enum :basis, { monthly: 0, per_period: 1 }, prefix: true

  # EVERY RULE A USER OWNS, IN ONE RELATION — the reader `User has_many :budgets, through:
  # :categories` cannot be. That association walks the category link only, which after the cutover
  # reaches NOTHING at all, and every rule the Budget page manages is invisible to it.
  # `current_user.budgets.find` therefore answered RecordNotFound for rules the user plainly owns.
  #
  # THE CAP'S CATEGORY ARM WENT IN PLAN 3, AND THE ARM BELOW IS NOT IT COMING BACK. This scope used
  # to be `where(category_id: user.categories).or(where(pool_id: user.pools))` because a rule could
  # be a per-category CEILING on a pool-funded envelope; that shape is gone and its pins were
  # withdrawn with it. The category arm that reappears below means the opposite thing — the category
  # is the OWNER now, the thing that holds the money — and it is reached by the same SQL only
  # because the same column happens to say who owns what.
  #
  # Scoped by the OWNER's user, not by a `user_id` on this table — a budget carries no user
  # column, and inventing one would give the invariant two places to be wrong.
  #
  # BOTH LANES, FOR THE LENGTH OF THE BRANCH AND NO LONGER. Task 1's migration wrote a
  # `category_id` onto every rule it found and LEFT `pool_id` standing, so on real data the two
  # arms answer with the same rows and the OR is redundant. It is not redundant on the way there:
  # a rule written today through the pool form has no category yet, and a rule Task 7 writes on a
  # category has no pool — and a screen that lost either would show a user a Budget page missing
  # their own rules. Task 8 drops `budgets.pool_id` and this narrows to the category arm alone.
  #
  # An OR over one table, so a rule carrying BOTH columns (which is every migrated rule) is
  # returned once, not twice.
  scope :for_user,
        lambda { |user|
          where(pool_id: user.pools.select(:id)).or(where(category_id: user.categories.select(:id)))
        }

  # A rule that demands nothing is what deleting it is for, and a negative one is money
  # flowing the wrong way through the allocation waterfall — which `clamp` refuses outright.
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :interval_months, numericality: { greater_than: 0 }, allow_nil: true

  validate :must_have_an_owner
  validate :pool_must_not_be_an_account, if: :pool_mode?
  validate :item_must_belong_to_pool, if: :pool_mode?
  validate :category_must_be_an_expense, if: :category_mode?
  validate :item_must_belong_to_category, if: :category_mode?
  # UNGATED, BOTH OF THEM, and they were gated on `pool_mode?` only because a pool was the only
  # owner a rule could have. Neither reads a pool: `#shape_must_be_valid` is about the three
  # columns that spell a cadence, and `#item_must_not_be_claimed` is about one item having one
  # rule. A category-owned rule that skipped them would be the second definition of a rule's shape.
  validate :shape_must_be_valid
  validate :item_must_not_be_claimed

  # An assigned-but-unsaved association has no foreign key yet, so consult the
  # target too — otherwise `Budget.new(pool: unsaved_pool)` reads as owner-less.
  def pool_mode? = pool_id.present? || pool.present?

  # `#category_column?` FIRST, AND IT IS NOT DEFENSIVE. `budgets.category_id` is younger than two
  # specs that plant rules through this model: `spec/migrations/two_ledger_spec.rb` rewinds the
  # schema past `CategoriesHoldTheMoney` — whose whole subject is ADDING this column — and
  # `DropCapEraBudgetColumns` took it away before that. Reading an attribute the database does not
  # currently have raises NameError, and a predicate that raises is not an answer. Asked once here
  # and once in #user, which are the only two readers of the column outside a validator gated on
  # this method.
  def category_mode? = category_column? && (category_id.present? || category.present?)

  # nil-safe: an owner-less budget is exactly the state the form re-renders in
  # after a failed submission.
  #
  # THE CATEGORY ANSWERS FIRST, because it is the owner that survives: every migrated rule carries
  # both columns and they name the same user, so the order cannot change an answer today — and when
  # Task 8 drops `pool_id`, the arm that is left is already the one being read.
  def user = (category_mode? && category&.user) || pool&.user

  def calculator(today: Date.current)
    BudgetCalculator.new(self, today: today)
  end

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
  # this app takes one) must be able to hand its own down rather than have this reach for
  # `Date.current` behind it.
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
  def steady_ask(user, today: Date.current)
    case cadence
    when :per_period then amount.to_d
    when :one_off then one_off_steady_ask(today)
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
  # Caps do not exist. `#for_user` is pool-scoped by construction now, so the mode filter it used to
  # stack on top of it would be a `where.not` that can never exclude a row — a condition kept for
  # the sentence it lets a comment say, which is how dead filters survive. It is gone; the boundary
  # it drew survives as a fact about the data rather than a clause in a query.
  #
  # TASK 9 INHERITS THE SAME SUM: the sacrifice view's cut list is exactly the rules counted here,
  # because the gap it is closing is this figure. It should not re-derive the population.
  #
  # ORPHAN POOL RULES STAY IN. A rule on an account-less pool is a real claim the user declared —
  # the fix is giving the pool an account, not pretending the claim away — which is the same line
  # 2b drew when orphans left the waterfall but stayed in HomePresenter#total_required.
  #
  # `sum(0.to_d)` with an explicit BigDecimal seed. An empty relation's `sum` is Integer `0`, and
  # this figure is compared against `typical_income` and subtracted from it — the seed keeps a
  # user with no pool rules at all on the same numeric type as one with them.
  #
  # THE PRELOAD IS MEASURED, and the measurement corrected a claim this comment first made. On the
  # demo seeds it buys NOTHING: 22 rules cost 5 statements with it and 5 without, because only two
  # of them are dated and each dated rule is what reaches off the `budgets` row at all. It is kept
  # because the shape differs even where the figure does not — `#steady_ask`'s one-off branch
  # builds a BudgetCalculator, which asks `budget.user` for the period boundaries and `budget.item`
  # for what has been paid, both on other tables. Planted 20 further dated rules and rolled back:
  # 42 rules cost 45 statements un-preloaded and still 5 with the preload. O(1) against O(n) in
  # dated rules, on a reader three screens call.
  #
  # BOTH OWNER LANES ARE PRELOADED, because a budget has no user column and `#user` walks whichever
  # owner the rule has — THE CATEGORY FIRST (see #user), then the pool.
  #
  # `category: :user` IS NOT SPECULATIVE AND IT IS NOT TASK 7'S (fix round 2). Task 1's migration
  # wrote a `category_id` onto EVERY rule in the database, so every migrated dated rule takes the
  # category arm of `#user` — and without this preload that is two un-preloaded queries per rule,
  # the category and then its user, measured live under query logging. The first draft of this
  # comment claimed the pool arm answered first and deferred the fix; both halves were wrong, and
  # `#user`'s own comment two screens up said so in capitals at the time.
  #
  # PINNED, not asserted: `budget_steady_ask_spec`'s "costs the same number of queries for five
  # migrated dated rules as for one" plants the migrated shape (both columns set) and counts the
  # statements, because a preload that quietly stops covering a lane is invisible to every other
  # example in that file.
  def self.steady_need(user, today: Date.current)
    for_user(user)
      .includes(:item, pool: :user, category: :user)
      .sum(0.to_d) { |budget| budget.steady_ask(user, today: today) }
  end

  private

  # A ONE-TIME RULE HAS NO INTERVAL TO DIVIDE BY, so its steady claim is what saving for it costs
  # between now and the day it is due — the same divisor `BudgetCalculator#required` uses, taken
  # from the same place so the two cannot disagree about how many periods are left.
  #
  # ZERO ONCE FULFILLED: a settled bill claims nothing from any future period, and telling a user
  # their rules need money for a bill they have already paid would put the structural check
  # permanently and unfixably underwater. This is `BudgetCalculator#shortfall`'s own fulfilled
  # gate, said again at the only other place that asks a one-off rule for a figure.
  #
  # `periods_until_due` floors at 1, so a user with no declared cadence — whose
  # `period_boundaries` is empty — gets the whole amount in one period rather than a division by
  # zero. Blunt, and it is the honest answer: without a period there is nothing to spread over.
  def one_off_steady_ask(today)
    calc = calculator(today: today)
    return 0.to_d if calc.fulfilled?

    (amount.to_d / calc.periods_until_due).round(2)
  end

  # AN OWNER, AND IT IS A POOL OR A CATEGORY — the one line that makes "a rule has an owner" true
  # while both associations are `optional: true`.
  #
  # IT DOES NOT REFUSE "BOTH", and its ancestor `#exactly_one_owner` did. That version was policing
  # two owners with two different MEANINGS (a pool that funds the rule, or a category the rule
  # capped), so a record naming both was incoherent. These two name the same thing — the owner of
  # the rule — one layer apart, and Task 1's migration deliberately wrote both columns onto every
  # rule in the database. Refusing the pair would refuse every migrated rule. Task 8 drops
  # `budgets.pool_id` and this becomes "a rule belongs to a category", full stop.
  #
  # THE MESSAGE NAMES THE CATEGORY, and that is about the screen rather than the schema:
  # `budgets/_form` is the only form that can submit an owner-less rule, it renders `errors[:base]`
  # in its own notification, and the control it offers is a CATEGORY picker (two-ledger spec §3,
  # Task 5) — so the sentence the user reads describes the form they are looking at. It said "must
  # belong to a pool" while the picker offered pools, and the pool the sentence pointed at is the
  # layer being deleted.
  #
  # ON `:base` RATHER THAN `:category` for that reason: an owner-less rule is a fact about the whole
  # record, not about a control the form offers.
  def must_have_an_owner
    errors.add(:base, "must belong to a category") unless pool_mode? || category_mode?
  end

  def pool_must_not_be_an_account
    errors.add(:pool, "cannot be an account") if pool&.pool_type_account?
  end

  # THE DIRECT ANALOGUE OF #pool_must_not_be_an_account, ONE LAYER IN (two-ledger spec §2/§3). That
  # one refuses a rule on the thing money physically sits in; this refuses a rule on a category that
  # cannot hold money at all. Income lands in AVAILABLE and is allocated out of it — an income
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

  def item_must_belong_to_pool
    return if item.blank?

    # Objects, not ids: under `build` the pool is unsaved and `pool_id` is nil, so
    # an id comparison equates every pool-less category with this pool and rejects
    # the items that genuinely belong to it.
    errors.add(:item, "must belong to a category in this pool") unless item.category&.pool == pool
  end

  def category_column? = has_attribute?(:category_id)

  # THE CATEGORY-MODE TWIN OF #item_must_belong_to_pool, and the same rule one layer in: a dated
  # bill anchors on an item, and that item has to be an item OF the category the rule funds — an
  # item from somewhere else would date a bill against money it never drains.
  #
  # Objects, not ids, for #item_must_belong_to_pool's own reason: under `build` nothing is
  # persisted and `nil == nil` would wave every item-less category through.
  def item_must_belong_to_category
    return if item.blank?

    errors.add(:item, "must belong to this category") unless item.category == category
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
