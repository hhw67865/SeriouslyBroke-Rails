# frozen_string_literal: true

# EVERY FUND BECOMES A DATED RULE, AND TWO COLUMNS GO (two-shapes spec §6, Henry's ruling of
# 2026-09-05: "I thought build up / reset isn't a thing anymore since nothing really is holding the
# money any more, right? Build up is just a higher target on a timeline longer than a period").
#
# ---------------------------------------------------------------------------------------------
# WHAT MOVES
# ---------------------------------------------------------------------------------------------
#
# A rule with `carries over` set was the BUILDING shape: the §3.2 walk with no due date to spread
# itself over, accruing its own rate every period, capped where it named a figure and unbounded
# where it did not. §2 retires it. What a fund is now is a DATED ONE-OFF whose `amount` IS its
# target — "$10,000 by next September" — which is a shape the model, the claim formulas and the
# screens all already had. So each such rule is rewritten:
#
#     amount           := the target it was building toward
#     basis            := monthly
#     interval_months  := NULL          (a one-off; it does not roll)
#     anchor_date      := THE DAY IT WOULD HAVE REACHED THAT TARGET AT ITS CURRENT RATE
#
# ** THE DATE IS DERIVED SO THAT THE CLAIM DOES NOT MOVE, and that is the whole care of this file. **
# Walk `ceil((target − built up) ÷ rate)` periods forward from the period containing the OWNER's
# today, on the OWNER's grid, and take the LAST DAY of the period you land in. The catch-up formula
# then re-plans `remaining ÷ periods left` every period against exactly that horizon — and on a rule
# that has been accruing a constant rate with nothing spent and nothing adjusted, that quotient IS
# the rate, period after period. The fund the user was looking at yesterday is the fund they see
# today; only the sentence under it changes.
#
# WHERE ROUNDING MOVES A CENT it is named in the receipt rather than hidden: `ceil` can only place
# the date at or beyond the true crossing, and `(gap ÷ periods left).round(2)` on a horizon that is
# not a whole multiple of the rate asks a few cents less per period than the rate did. The receipt
# prints the old rate beside the new date for every rule, so an owner can correct either on the
# Budget page.
#
# ** A HAND-FED FUND GETS ONE YEAR. ** `amount = 0` was how "this goal has no standing rate — I feed
# it by hand" was spelled, and zero has no crossing date to derive: the fund would reach its target
# never. One year from the owner's today is a horizon, stated rather than inferred, and it is on the
# receipt for the owner to move. It is also the only choice that keeps such a rule VALID: `Budget`
# validates `amount > 0` on every shape from this commit, and the rewrite gives the rule its target
# as its amount — so the rule that demanded nothing now demands its whole goal by a date.
#
# ** AN UNCAPPED FUND IS REFUSED BY NAME. ** `carries over` with no target was "grow for ever", and
# there is no target for the new `amount` to be and no crossing date to derive. Inventing either
# would be inventing the user's goal. The preflight names the owner, the category and the rule id,
# and the run writes nothing. (None exist on dev — receipt in the task report.)
#
# ---------------------------------------------------------------------------------------------
# ** WHY THE PRE-CONVERSION BUILT-UP IS WALKED HERE RATHER THAN READ OFF `ClaimCalculator`. **
# ---------------------------------------------------------------------------------------------
#
# It cannot be read off it. `ClaimCalculator#shape` is `anchor_date.present? ? :dated : :rate` from
# this commit — the building arm is deleted in the same change this file's `up` is the data half of
# — so a pre-conversion fund reads as a RATE rule there and `#built_up` answers ZERO. Measured: the
# $150-a-period, $1,200-target fixture in `spec/migrations/two_shapes_spec.rb` would derive
# `ceil(1200 ÷ 150)` = 8 periods instead of 6, and land its anchor two periods late with the claim
# $300 lower than the day before.
#
# So the retired formula is restated here, once, and frozen: `DropTheDistribution`'s law — a
# migration whose meaning changes when a model does is a migration that rewrites history. What is
# NOT restated is anything still alive: the period grid is `User#period_boundaries` /
# `#period_containing` through the model (nothing is planted through it), the spending lane is the
# same `Entry.draining` / `Entry.on_unruled_items` composition `ClaimCalculator#query_spending`
# makes, and the adjustments are the rule's own association.
#
# ---------------------------------------------------------------------------------------------
# A RE-RUN RAISES, LOUDLY AND ON PURPOSE
# ---------------------------------------------------------------------------------------------
#
# `up` drops both columns, so a second run without the `down` meets `PG::UndefinedColumn` on the
# preflight's first statement. `RulesOwnTheBudget`'s ruling, inherited: a guard that turned a second
# run into a silent no-op would be indistinguishable from a run that moved nothing because there was
# nothing to move. The whole of `up` is one transaction (the Migrator wraps it on PostgreSQL, DDL
# included), so there is never anything half-done to resume.
#
# ---------------------------------------------------------------------------------------------
# THE `down` RESTORES THE SHAPE AND NOT THE DATA
# ---------------------------------------------------------------------------------------------
#
# The two columns and the CHECK come back; every rule this file converted STAYS a dated one-off with
# its target as its amount. That is the honest inverse: the building shape has no code left to
# compute it, so a `down` that re-flagged those rows would leave a database whose rules no formula
# in the app can read. `spec/support/schema_rewind.rb` names this file last, so the six older
# migration specs travel back through it to reach the world their own subjects were written for —
# what they need from this `down` is the SHAPE (`RulesOwnTheBudget#down` copies a rule's target back
# onto its category and cannot run against a table that has no such column), and the shape is what
# they get.
class TwoShapes < ActiveRecord::Migration[8.1]
  # The integers as the schema holds them at THIS moment in the sequence, written out rather than
  # read off the app's enums — `DropTheDistribution`'s law again.
  MONTHLY = 0 # budgets.basis
  ACCOUNT = 0 # pools.pool_type
  INCOME = 1 # categories.category_type

  # Ten years of weekly periods, `ClaimCalculator::PERIOD_WALK_LIMIT` verbatim: the same stop, so a
  # fund funded in 2010 is walked here exactly as far as the app walked it yesterday.
  PERIOD_WALK_LIMIT = 520

  # A HORIZON FOR A FUND WITH NO RATE TO CROSS ONE — see the header. A year from the owner's today,
  # to the DAY rather than to a period boundary: it is a horizon this file states rather than one it
  # derived, and rounding it onto the grid would dress a stated figure as a computed one.
  HAND_FED_HORIZON = 1.year

  # Refusing the INPUT — raised before the first write.
  class PreflightFailed < StandardError; end

  # Refusing its own OUTPUT — raised after the last write and before the drop, inside the Migrator's
  # transaction, so a database whose rules stopped being shapes the app accepts is never committed.
  class VerificationFailed < StandardError; end

  def up
    before = ledgers
    preflight!
    receipts = convert_the_funds
    verify!(before, receipts)
    drop_the_columns
  end

  # SHAPE ONLY (see the header). A converted rule stays a dated one-off.
  def down
    add_column :budgets, :carries_over, :boolean, null: false, default: false
    add_column :budgets, :target_amount, :money, scale: 2
    add_check_constraint :budgets, "target_amount > 0::money", name: "budgets_positive_target_amount"
  end

  private

  # -----------------------------------------------------------------------------------------------
  # The refusal
  # -----------------------------------------------------------------------------------------------

  # ** THE ONE ARM, AND IT RUNS BEFORE THE FIRST WRITE. ** A fund with no ceiling has no figure to
  # become its amount and no day to be due on, and both ways out — name the goal, or delete the rule
  # — are decisions about the user's money. Named by OWNER, CATEGORY and RULE ID, because "give it a
  # target" is not actionable without all three.
  def preflight!
    failures = uncapped_funds
    return if failures.empty?

    raise PreflightFailed, failures.join("; ")
  end

  def uncapped_funds
    template = "the fund on %<extra>s (%<id>s) names no target, so it has no figure to be due and " \
               "no day to be due on — give it a target or delete it"
    named(<<~SQL.squish, template)
      SELECT b.id::text AS id, c.name AS extra, u.email
        FROM budgets b
        JOIN categories c ON c.id = b.category_id
        JOIN users u ON u.id = c.user_id
       WHERE b.carries_over
         AND b.target_amount IS NULL
       ORDER BY u.email, c.name
    SQL
  end

  # `%<extra>s` is optional in the template, so one helper serves an arm that names a second fact and
  # one that does not — `RulesOwnTheBudget#named`, and `format` ignores a surplus key under the
  # `%<name>s` spelling where `%{}` would raise.
  def named(sql, template)
    select_all(sql).map do |row|
      "#{row["email"]}: #{format(template, id: row["id"], extra: row["extra"])}"
    end
  end

  # -----------------------------------------------------------------------------------------------
  # The conversion
  # -----------------------------------------------------------------------------------------------

  # ONE RULE AT A TIME, because the derived date is a walk over the OWNER's period grid and there is
  # no SQL that knows what a fortnight is for this user. The write is one UPDATE per rule; the whole
  # of `up` is one transaction, so a raise anywhere takes every one of them back.
  #
  # Returns the receipt lines, grouped by owner email: name · old rate · new date.
  def convert_the_funds
    Budget.reset_column_information

    funds.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |rule, receipts|
      owner = rule.category.user
      anchor = anchor_for(rule, owner)
      receipts[owner.email] << line_for(rule, anchor)
      write_the_shape(rule, anchor)
    end
  end

  # THE FUNDS, WITH EVERY RECORD THE WALK READS ALREADY LOADED: the owner (the grid and the
  # timezone), the category (`funded_since`, and the spending lane), the item (which lane), and the
  # adjustments. Ordered so two runs against one backup produce the same receipt.
  def funds
    Budget.where(carries_over: true)
      .includes(:item, :adjustments, category: :user)
      .order(:created_at, :id)
      .to_a
  end

  def write_the_shape(rule, anchor)
    execute(ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, { id: rule.id, anchor: anchor, now: now }]))
      UPDATE budgets
         SET amount = target_amount,
             basis = #{MONTHLY},
             interval_months = NULL,
             anchor_date = :anchor,
             updated_at = :now
       WHERE id = :id
    SQL
  end

  # ** THE DAY THIS FUND WOULD HAVE REACHED ITS TARGET AT ITS CURRENT RATE. ** `ceil` periods forward
  # from the period containing the owner's today, and the LAST DAY of the period landed in — because
  # §3.2's accrual lands IN FULL the day a period opens, so the money is whole from that period's
  # open and the honest deadline is its close.
  #
  # A GAP ALREADY CLOSED WALKS ZERO PERIODS and is due at the end of THIS period, which is the true
  # sentence about a fund that has reached its figure: the money is there, and there is nothing left
  # to save.
  #
  # A RATE OF ZERO CROSSES NOTHING — see `HAND_FED_HORIZON`.
  def anchor_for(rule, owner)
    today = owner.today
    rate = rule.amount.to_d
    return today + HAND_FED_HORIZON unless rate.positive?

    gap = rule.target_amount.to_d - built_up(rule, owner, today)
    periods_out = gap.positive? ? (gap / rate).ceil : 0
    period_after(owner, owner.period_containing(today), periods_out).last
  end

  def period_after(owner, period, steps)
    steps.times { period = owner.period_containing(period.last + 1) }
    period
  end

  # ---------------------------------------------------------------------------------------------
  # ** THE RETIRED BUILDING WALK, FROZEN (see the header for why it cannot be `ClaimCalculator`'s). **
  #
  #   planned(P) = min(rate, target − built up)          — its own rate, capped by what is missing
  #   built up   = max( min(built up + planned + Σ adj(P), target) − spent(P), 0 )
  #
  # Period by period, from the period containing the accrual start through the period containing the
  # owner's today. The order inside a period is §3.2's own: the period opens and its whole accrual
  # lands, the adjustments dated in it apply, the total is capped at the target, and only then does
  # the period's spending come out.
  # ---------------------------------------------------------------------------------------------
  def built_up(rule, owner, today)
    spending = spending_rows(rule)
    adjustments = rule.adjustments.map { |adjustment| [adjustment.local_day, adjustment.amount.to_d] }
    target = rule.target_amount.to_d
    rate = rule.amount.to_d

    walk_periods(owner, accrual_start(rule, owner, today), today).reduce(0.to_d) do |built, period|
      gap = target - built
      planned = gap.positive? ? [rate, gap].min : 0.to_d
      accrued = [built + planned + within(adjustments, period), target].min
      [accrued - within(spending, period), 0.to_d].max
    end
  end

  def walk_periods(owner, from, today)
    visited = []
    cursor = owner.period_containing(from)
    while cursor.first <= today && visited.size < PERIOD_WALK_LIMIT
      visited << cursor
      cursor = owner.period_containing(cursor.last + 1)
    end
    visited
  end

  # `ClaimCalculator#accrual_start`, verbatim: the later of the day the category started holding
  # money and the day the rule itself was written, in the OWNER's zone. A rule cannot accrue before
  # it existed.
  def accrual_start(rule, owner, today)
    born = rule.created_at.present? ? owner.local_day(rule.created_at) : nil
    [rule.category.funded_since, born].compact.max || today
  end

  def within(rows, period)
    rows.sum(0.to_d) { |day, amount| period.cover?(day) ? amount : 0.to_d }
  end

  # THE LANE A FULFILMENT ARRIVES ON — the rule's own item where it names one, everything else in the
  # category where it does not. The SAME composition `ClaimCalculator#query_spending` makes, of the
  # SAME model scopes: `Entry.draining` carries the funded-since gate and the owner's calendar day,
  # and `Entry.on_unruled_items` is §3.1's partition. Neither is restated here — only composed — so
  # this cannot read a different set of rows than the app read yesterday.
  def spending_rows(rule)
    scope = Entry.expenses.merge(Entry.draining(rule.category))
    scope = if rule.item_id.present?
              scope.where(item_id: rule.item_id)
            else
              scope.merge(Entry.on_unruled_items)
            end
    scope.pluck(CategoryLedger::ENTRY_LOCAL_DAY, :amount)
  end

  # -----------------------------------------------------------------------------------------------
  # The verification, and the receipt
  # -----------------------------------------------------------------------------------------------

  def verify!(before, receipts)
    failures = drift(before) + funds_left_behind + malformed_rules
    raise VerificationFailed, failures.join("; ") if failures.any?

    report(before, receipts)
  end

  # EVERY USER, ON BOTH SIDES, AND THE COMPARISON IS AGAINST THE PRE-MIGRATION FIGURE rather than
  # against bank truth alone — `DropThePoolLayer#verify!`'s reason: a change that moved money from
  # one term into the other by the same amount would satisfy "physical == bank" and still be wrong.
  # This file writes no entry, no account movement and no pool at all, and a migration that cannot
  # move a number is exactly the one that should be made to prove it.
  def drift(before)
    after = ledgers
    before.flat_map do |id, was|
      now_figures = after[id]
      next ["#{was[:email]}: vanished from the users table"] if now_figures.nil?

      [:physical, :bank].filter_map do |side|
        next if was[side] == now_figures[side]

        "#{was[:email]}: #{side} was #{was[side].to_f}, is #{now_figures[side].to_f}"
      end
    end
  end

  # ** EVERY FUND IS A DATED ONE-OFF, ASKED WHILE THE COLUMN IS STILL THERE TO ASK. ** The columns go
  # in the next statement, so a fund the loop skipped would leave with them and nobody would ever
  # know it had been one. The comparison is on the FIGURE as well as on the shape, so a rewrite that
  # landed the wrong amount is caught by the same clause as one that landed none.
  def funds_left_behind
    template = "%<extra>s's fund (%<id>s) is not a dated one-off carrying its target"
    named(<<~SQL.squish, template)
      SELECT b.id::text AS id, c.name AS extra, u.email
        FROM budgets b
        JOIN categories c ON c.id = b.category_id
        JOIN users u ON u.id = c.user_id
       WHERE b.carries_over
         AND NOT (b.anchor_date IS NOT NULL
                  AND b.interval_months IS NULL
                  AND b.basis = #{MONTHLY}
                  AND b.amount = b.target_amount)
       ORDER BY u.email, c.name
    SQL
  end

  # ** `Budget`'s SURVIVING VALIDATIONS, RESTATED IN SQL — CLAUSE FOR CLAUSE, AND NO CLAUSE MORE. **
  # Every disjunct names the model method it mirrors:
  #
  #   * `amount <= 0` — `validates :amount, numericality: { greater_than: 0 }`, which is
  #     UNCONDITIONAL from this commit and is the rule the hand-fed fund's rewrite has to satisfy;
  #   * the two basis clauses — `#shape_must_be_valid`, both branches: a per-period rule carries
  #     neither anchor nor interval, and an anchorless MONTHLY rule needs an interval of exactly 1;
  #   * `interval_months <= 0` — `validates :interval_months, numericality: { greater_than: 0 }`.
  #
  # ** SCOPED TO THE POPULATION THIS FILE IS ANSWERABLE FOR, WHICH IS NOT EVERY ROW IN THE TABLE. **
  # `DropTheDistribution#malformed_minted_rules` learned this from the other side: a verifier
  # stricter than the model aborted a whole migration over a row the app accepts, and being wrong in
  # that direction is the one nobody can work around. The scope is the rules this run WROTE.
  def malformed_rules
    named(<<~SQL.squish, "the rule on %<extra>s is a shape the app would refuse (%<id>s)")
      SELECT b.id::text AS id, c.name AS extra, u.email
        FROM budgets b
        JOIN categories c ON c.id = b.category_id
        JOIN users u ON u.id = c.user_id
       WHERE b.carries_over
         AND (b.amount <= 0::money
           OR (b.basis <> #{MONTHLY} AND (b.anchor_date IS NOT NULL OR b.interval_months IS NOT NULL))
           OR (b.basis = #{MONTHLY} AND b.anchor_date IS NULL
               AND (b.interval_months IS NULL OR b.interval_months <> 1))
           OR b.interval_months <= 0)
       ORDER BY u.email, c.name
    SQL
  end

  # ** ONE LINE PER FUND, UNDER ONE LINE PER OWNER, plus the totals and the invariant. ** The OLD
  # RATE is on every line and it is the point of the receipt: the date this file derived is a
  # consequence of that rate, so an owner who disagrees with the date has the number it came from in
  # front of them — and where rounding moved a cent (see the header) the two figures are what says
  # so.
  def report(before, receipts)
    receipts.keys.sort.each do |email|
      say "#{email}: #{count(receipts[email].size, 'fund')} became #{became(receipts[email].size)}"
      receipts[email].each { |line| say line, true }
    end
    say "#{count(receipts.values.sum(&:size), 'fund')} converted in total across " \
        "#{count(receipts.size, 'owner')}"
    before.each_value { |was| say "#{was[:email]}: physical #{was[:physical].to_f} == bank #{was[:bank].to_f}, unchanged" }
  end

  def line_for(rule, anchor)
    name = rule.item&.name || rule.category.name
    "#{name} · was #{money(rule.amount)} a period · now #{money(rule.target_amount)} by #{anchor}"
  end

  def money(amount) = format("$%.2f", amount.to_d)

  # PLURALS ON BOTH HALVES OF THE SENTENCE, because a receipt is read by a person: "1 fund became
  # dated rules" is the kind of line that makes a reader wonder what else the file is careless about
  # — `RulesOwnTheBudget#report`'s own note, and the verb needs the same care the noun does.
  def became(number) = number == 1 ? "a dated rule" : "dated rules"

  def count(number, noun) = "#{number} #{noun.pluralize(number)}"

  def drop_the_columns
    remove_check_constraint :budgets, name: "budgets_positive_target_amount"
    remove_column :budgets, :target_amount
    remove_column :budgets, :carries_over
    Budget.reset_column_information
  end

  # -----------------------------------------------------------------------------------------------
  # The physical invariant, before and after
  # -----------------------------------------------------------------------------------------------

  # `RulesOwnTheBudget#ledgers`, verbatim and for its reason: read straight from the tables rather
  # than through `AccountLedger`, because asking a reader to referee a migration of its own tables
  # means a wrong term answers wrong on both sides of the comparison.
  def ledgers
    select_all("SELECT id, email FROM users ORDER BY created_at, id").to_h do |row|
      [row["id"], { email: row["email"], physical: physical_total(row["id"]), bank: bank_total(row["id"]) }]
    end
  end

  def physical_total(user_id)
    decimal(<<~SQL.squish, user_id)
      SELECT COALESCE((SELECT SUM(CASE WHEN c.category_type = #{INCOME}
                                       THEN e.amount::numeric ELSE -e.amount::numeric END)
                         FROM entries e
                         JOIN items i ON i.id = e.item_id
                         JOIN categories c ON c.id = i.category_id
                        WHERE c.user_id = :uid), 0)
           + COALESCE((SELECT SUM(m.amount::numeric) FROM account_movements m
                        WHERE m.to_pool_id IN (SELECT id FROM pools
                                                WHERE user_id = :uid AND pool_type = #{ACCOUNT})), 0)
           - COALESCE((SELECT SUM(m.amount::numeric) FROM account_movements m
                        WHERE m.from_pool_id IN (SELECT id FROM pools
                                                  WHERE user_id = :uid AND pool_type = #{ACCOUNT})), 0)
    SQL
  end

  def bank_total(user_id)
    decimal(<<~SQL.squish, user_id)
      SELECT COALESCE(SUM(CASE WHEN c.category_type = #{INCOME}
                               THEN e.amount::numeric ELSE -e.amount::numeric END), 0)
        FROM entries e
        JOIN items i ON i.id = e.item_id
        JOIN categories c ON c.id = i.category_id
       WHERE c.user_id = :uid
    SQL
  end

  # `BigDecimal(...to_s)` rather than the adapter's cast, for `CategoriesHoldTheMoney#decimal`'s
  # reason: `select_value` hands back a String for some numeric results and a BigDecimal for others
  # depending on the OID, and a money comparison must not depend on which.
  def decimal(sql, user_id)
    BigDecimal(select_value(ActiveRecord::Base.sanitize_sql_array([sql, { uid: user_id }])).to_s)
  end

  # ONE INSTANT FOR THE WHOLE RUN, memoised: it stamps every row this file writes, so two readings of
  # the clock would leave one statement's rows dated after another's for no reason a reader could
  # explain.
  def now = @now ||= Time.current
end
