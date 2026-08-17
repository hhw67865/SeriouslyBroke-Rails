# frozen_string_literal: true

class Budget < ApplicationRecord
  belongs_to :category, optional: true, touch: true
  belongs_to :pool, optional: true, touch: true
  belongs_to :item, optional: true

  enum :basis, { monthly: 0, per_period: 1 }, prefix: true

  # EVERY RULE A USER OWNS, IN ONE RELATION — the reader `User has_many :budgets, through:
  # :categories` cannot be. That association walks the category link only, so it reaches
  # category-mode rules and nothing else, and every pool-mode rule — which is every rule the
  # Budget page manages — is invisible to it. `current_user.budgets.find` therefore answered
  # RecordNotFound for rules the user plainly owns.
  #
  # Two `where`s OR-ed rather than a join, because a rule has exactly one owner (see
  # #exactly_one_owner) and the two owners live on different tables: a join would have to be
  # a LEFT OUTER pair and would then need a DISTINCT to undo itself. Sub-SELECTs keep it one
  # statement over the same `budgets` rows the association returns.
  #
  # Scoped by the OWNER's user, not by a `user_id` on this table — a budget carries no user
  # column, and inventing one would give the invariant two places to be wrong.
  scope :for_user,
        lambda { |user|
          where(category_id: user.categories.select(:id))
            .or(where(pool_id: user.pools.select(:id)))
        }

  # A rule that demands nothing is what deleting it is for, and a negative one is money
  # flowing the wrong way through the allocation waterfall — which `clamp` refuses outright.
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :interval_months, numericality: { greater_than: 0 }, allow_nil: true

  validate :exactly_one_owner
  validate :category_must_be_expense, if: :category_mode?
  validate :category_must_not_have_pool, if: :category_mode?
  validate :pool_must_not_be_an_account, if: :pool_mode?
  validate :shape_must_be_valid, if: :pool_mode?
  validate :item_must_belong_to_pool, if: :pool_mode?
  validate :item_must_not_be_claimed, if: :pool_mode?

  # An assigned-but-unsaved association has no foreign key yet, so consult the
  # target too — otherwise `Budget.new(pool: unsaved_pool)` reads as owner-less.
  def category_mode? = category_id.present? || category.present?
  def pool_mode? = pool_id.present? || pool.present?

  # nil-safe: an owner-less budget is exactly the state the form re-renders in
  # after a failed submission.
  def user = category&.user || pool&.user

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
  # A CATEGORY-MODE RULE IS MONTHLY, and it is answered before the interval branches. It is a
  # monthly spending cap that carries no interval at all — #shape_must_be_valid only runs in pool
  # mode — so the nil-interval branch would call every category cap a one-off.
  def cadence
    return :per_period if basis_per_period?
    return :monthly if category_mode?
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
  # POOL-MODE RULES ONLY. CATEGORY-MODE CAPS ARE EXCLUDED, and the boundary is the whole point of
  # the figure rather than an optimisation:
  #
  #   The structural check asks "does your income cover what your rules will CLAIM from it". The
  #   thing that claims money from a period's income is the fill, and the fill funds POOLS —
  #   AllocationCalculator never reads a category-mode budget, so no distribution has ever asked
  #   for a penny on account of one. A category cap is a SPENDING LIMIT on tracking, not a funding
  #   claim on income: cutting one frees no income, so it could not appear in §9's cut list even
  #   in principle, and counting one inflates "your rules need" by money that will never be asked
  #   for.
  #
  # Measured on the demo seeds, and the measurement corrected the estimate that prompted the
  # ruling — a "~$2,900 of caps" figure I reported was a MONTHLY total read as a per-period one,
  # which is the exact mixed-unit slip #steady_ask exists to prevent, made in prose instead of in
  # code. The real figures: of $4,125 a period, $1,523.08 was category caps, leaving $2,601.92.
  #
  # The DUPLICATION the ruling names is real and visible in that breakdown — a "Housing" cap of
  # $1,500 a month ($692.31 a period) sitting beside the $1,500 Rent rule that actually fills the
  # envelope, the same $692.31 counted twice; "Food & Dining" $600 a month over the top of
  # Groceries, Dining Out and Household Supplies. What is NOT true is that excluding caps makes
  # the demo comfortable: it still needs $2,601.92 against $2,400 of income. The overstatement was
  # $1,523.08 a period, not the whole gap.
  #
  # TASK 9 INHERITS THIS BOUNDARY: the sacrifice view's cut list is pool-mode rules and nothing
  # else, because the gap it is closing is this sum. It should not re-decide the question.
  #
  # ORPHAN POOL RULES STAY IN. A rule on an account-less pool is a real claim the user declared —
  # the fix is giving the pool an account, not pretending the claim away — which is the same line
  # 2b drew when orphans left the waterfall but stayed in HomePresenter#total_required.
  #
  # `for_user(user).where.not(pool_id: nil)` rather than a bare `where(pool_id: user.pools)`, so
  # ownership keeps being decided in exactly one place (#for_user) and this adds only the mode
  # filter on top of it.
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
  # `pool: :user` rather than a bare `:user`, because a budget has no user column — `Budget#user`
  # walks whichever owner the rule has, and in this relation that is always the pool.
  def self.steady_need(user, today: Date.current)
    for_user(user)
      .where.not(pool_id: nil)
      .includes(:item, pool: :user)
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

  def exactly_one_owner
    errors.add(:base, "must belong to either a category or a pool") if !category_mode? && !pool_mode?
    errors.add(:base, "cannot belong to both a category and a pool") if category_mode? && pool_mode?
  end

  def category_must_be_expense
    errors.add(:category, "must be an expense category") unless category&.expense?
  end

  def category_must_not_have_pool
    errors.add(:category, "cannot have a budget when linked to a savings pool") if category&.pool_id?
  end

  def pool_must_not_be_an_account
    errors.add(:pool, "cannot be an account") if pool&.pool_type_account?
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
