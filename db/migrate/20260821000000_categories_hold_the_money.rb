# frozen_string_literal: true

# CATEGORIES HOLD THE MONEY (two-ledger spec §7). Adds the purpose ledger's tables and backfills
# them from the pool layer WITHOUT dropping anything — old readers keep working until Task 8's
# drop. Per user, all-or-nothing under the Migrator's transaction; refuses shapes it will not
# guess at (a budget pool with 0 or 2+ categories) by NAMING them before the first write.
#
# IT INHERITS THE CUTOVER'S TWO RULES AND ADDS NOTHING TO THEM. Every write goes through a
# migration-local `ActiveRecord::Base` subclass carrying nothing but a table name, and through
# `update_all` / `update_columns` / `insert_all!` / `delete_all`, so no validation and no callback
# fires — `Category#destroy_budget_if_pool_linked` is gone, but `Category`'s required
# `belongs_to :pool`, `#pool_must_be_reachable` and `Budget#must_belong_to_a_pool` are all live
# today and all of them would refuse a row this migration legitimately writes on its way to a
# schema where they no longer apply. Task 8 deletes them; until then they are simply not consulted.
#
# WHAT IT ADDS THAT THE OLD DATABASE NEVER HELD: nothing. Every allocation is a `pool_movements`
# row re-keyed from pools to categories, every `funded_since` is a pool's `start_date`, every
# target and priority is the pool's own. The one DELETION is `entries.pool_id` — spec §2 rules the
# paid-from lane out of existence ("the pot is where cash leaves"), so the override is cleared
# rather than left for two readers to disagree over. It is counted and printed per user, because it
# is the only figure here that moves money on the PHYSICAL side and no receipt should hide that.
#
# WHAT IT REFUSES BEFORE IT WRITES ANY DATA. A budget pool whose category count is not exactly one:
# with two, there is no answer to "which category is this envelope" that is not a guess about the
# user's money; with none, there is no lane to fold the envelope into at all. A SAVINGS pool with
# none is the ordinary shape and gets a category minted for it; a savings pool with two is refused
# on the same reasoning as the envelope. Named with the owner's email and the pool's id, once,
# across every user, before the loop starts — the run is all-or-nothing, so a refusal discovered
# late costs the same rollback and names none of the rows responsible.
#
# NOT IDEMPOTENT, AND DELIBERATELY UNLIKE THE CUTOVER. This migration's first act is DDL, so a
# second run fails on `add_column` before it can consider re-converting anything. The audit
# property the cutover bought with idempotence is bought here by #verify!, which is re-callable on
# its own against a live database (see `spec/migrations/two_ledger_spec.rb`'s sabotage block).
#
# THE `down` IS FOR THE SCHEMA REWIND, NOT FOR PRODUCTION. See the comment on it.
class CategoriesHoldTheMoney < ActiveRecord::Migration[8.1]
  class MigrationPool < ActiveRecord::Base
    self.table_name = "pools"
  end

  class MigrationCategory < ActiveRecord::Base
    self.table_name = "categories"
  end

  class MigrationBudget < ActiveRecord::Base
    self.table_name = "budgets"
  end

  class MigrationMovement < ActiveRecord::Base
    self.table_name = "pool_movements"
  end

  class MigrationAllocation < ActiveRecord::Base
    self.table_name = "allocations"
  end

  class MigrationEntry < ActiveRecord::Base
    self.table_name = "entries"
  end

  class MigrationItem < ActiveRecord::Base
    self.table_name = "items"
  end

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  LOCAL_CLASSES = [MigrationPool, MigrationCategory, MigrationBudget, MigrationMovement,
                   MigrationAllocation, MigrationEntry, MigrationItem, MigrationUser].freeze

  # The integers as the schema holds them TODAY, written out rather than read off the app's enums:
  # `Pool`'s budget and savings members die in Task 8, and a migration whose meaning changes when
  # they do is a migration that rewrites history.
  ACCOUNT = 0
  BUDGET = 1
  SAVINGS = 2
  EXPENSE = 0
  INCOME = 1

  # Refusing the INPUT — raised before the first write, outside every transaction.
  class PreflightFailed < StandardError; end

  # Refusing its own OUTPUT — raised inside the user's transaction, so a user whose two ledgers do
  # not reconcile is never committed. Two classes rather than one message a `case` has to parse:
  # "is this database convertible yet" and "did the conversion go wrong" need different work.
  class VerificationFailed < StandardError; end

  def up
    create_schema
    preflight!
    MigrationUser.order(:created_at, :id).each { |user| convert(user) }
  end

  def down
    drop_table :allocations
    remove_reference :budgets, :category, foreign_key: true, type: :uuid
    remove_column :categories, :funded_since
    remove_column :categories, :target_amount
    remove_column :categories, :priority
    # The backfilled data is not reversed: categories minted for savings pools stay (harmless),
    # and the allocations they held are gone with the table. Down exists for the schema rewind
    # only — a real reversal is a restore.
  end

  private

  def create_schema
    add_column :categories, :funded_since, :date
    add_column :categories, :target_amount, :money, scale: 2
    add_column :categories, :priority, :integer, null: false, default: 0
    add_reference :budgets, :category, type: :uuid, foreign_key: true, index: true

    create_allocations
    # THE LOCAL CLASSES LEARN THE NEW SHAPE HERE, and it is not optional under the spec: the DDL
    # above and the reads below happen in ONE process, and a class that cached `categories`'
    # attribute set before this line has no `funded_since=` for #fold to call.
    LOCAL_CLASSES.each(&:reset_column_information)
  end

  # ONE TABLE FOR BOTH DIRECTIONS AND FOR THE ROOT. A NULL side is AVAILABLE — the purpose
  # ledger's pot — so funding a category is (NULL → category), spending it back down to no
  # particular job is (category → NULL), and moving money between two jobs is (category →
  # category). The alternative, a nullable `category_id` plus a sign, makes "which way did this
  # go" a second question with a second answer.
  #
  # `IS DISTINCT FROM` rather than `<>`: `NULL <> NULL` is NULL, which a CHECK constraint passes,
  # so the plain inequality would wave through the one row with no meaning at all — available to
  # available.
  def create_allocations
    create_table :allocations, id: :uuid do |t|
      t.uuid :from_category_id   # NULL = available
      t.uuid :to_category_id     # NULL = available
      t.money :amount, scale: 2, null: false
      t.datetime :date, null: false
      t.integer :kind, null: false, default: 0
      t.uuid :source_entry_id
      t.timestamps
    end
    add_foreign_key :allocations, :categories, column: :from_category_id
    add_foreign_key :allocations, :categories, column: :to_category_id
    add_foreign_key :allocations, :entries, column: :source_entry_id
    add_index :allocations, :from_category_id
    add_index :allocations, :to_category_id
    add_index :allocations, :source_entry_id
    add_index :allocations, :date
    add_check_constraint :allocations, "amount > 0::money", name: "allocations_positive_amount"
    add_check_constraint :allocations,
                         "from_category_id IS DISTINCT FROM to_category_id",
                         name: "allocations_distinct_sides"
  end

  # NAMES every budget pool whose category count is not exactly 1. Savings pools may have 0
  # (they get a minted category) or 1; 2+ is refused for both types.
  def preflight!
    rows = select_all(<<~SQL.squish)
      SELECT p.id, p.name, p.pool_type, u.email, COUNT(c.id) AS categories
      FROM pools p
      JOIN users u ON u.id = p.user_id
      LEFT JOIN categories c ON c.pool_id = p.id
      WHERE p.pool_type <> #{ACCOUNT}
      GROUP BY p.id, p.name, p.pool_type, u.email
      HAVING (p.pool_type = #{BUDGET} AND COUNT(c.id) <> 1) OR COUNT(c.id) > 1
      ORDER BY u.email, p.name
    SQL
    return if rows.empty?

    raise PreflightFailed, rows.map { |r|
      "#{r['email']}: pool #{r['name']} (#{r['id']}) has #{r['categories']} categories"
    }.join("; ")
  end

  # THE TRANSACTION BOUNDARY IS THE WHOLE MIGRATION, NOT THE USER, in production: the Migrator
  # already wraps the run in a JOINABLE transaction on PostgreSQL, so this block joins it rather
  # than opening one, no savepoint is taken, and a raise on user 3 rolls back users 1 and 2 with
  # it. That is the behaviour we want — a half-converted database has no name, no screen and no way
  # back. Under the spec, DatabaseCleaner's example transaction is `joinable: false`, so this DOES
  # take a savepoint there and the sabotage arms can watch one user roll back. Same code, two
  # boundaries, both correct.
  def convert(user)
    ActiveRecord::Base.transaction do
      # TAKEN BEFORE ANY WRITE. Nothing here is supposed to move it, and #verify! says so rather
      # than assuming it: the override-clearing step touches `entries`, which is the one table both
      # ledgers are read from.
      bank = bank_total(user.id)

      pools = MigrationPool.where(user_id: user.id).where.not(pool_type: ACCOUNT).order(:created_at, :id).to_a
      category_of = pools.to_h { |pool| [pool.id, fold(pool, user)] }
      moved = convert_movements(user, category_of)
      nulled = clear_paid_from_overrides(user)

      verify!(user, pools: pools, category_of: category_of, bank: bank)
      say "#{user.email}: #{pools.length} pools folded; #{moved} movements -> allocations; " \
          "#{nulled} entry overrides cleared; purpose == physical == bank truth #{format('%.2f', bank)}"
    end
  end

  # One pool → its category (existing for budget pools; minted for savings pools without one), and
  # the pool's three funding facts land on it: `start_date` becomes `funded_since` (§4 — Ming's
  # healed Food & Grocery stays healed), `target_amount` and `priority` are carried verbatim.
  def fold(pool, user)
    category = MigrationCategory.find_by(pool_id: pool.id) || mint_category(pool, user)
    category.update_columns(funded_since: pool.start_date, target_amount: pool.target_amount,
                            priority: pool.priority, updated_at: now)
    MigrationBudget.where(pool_id: pool.id).update_all(category_id: category.id, updated_at: now)
    category.id
  end

  # A SAVINGS GOAL THAT NEVER HAD A SPENDING LANE gets one, because a category is the only thing
  # that can hold money now. `tracked: false` keeps it off the tracked-spending screens, which is
  # what a goal has always been; EXPENSE because the savings category type died at the cutover and
  # only expense categories hold money (§3).
  #
  # `pool_id` IS THE USER'S MAIN ACCOUNT, which is the seat every pool-less category got at the
  # cutover and the only one `Category#pool_must_be_reachable` accepts. The column is deleted in
  # Task 8; the fallback to the goal's own account exists so that a user with no flagged default
  # still gets a NOT-NULL value rather than a row the current model cannot save — `TightenPoolShape`
  # guarantees a non-account pool has an `account_id`, so the fallback cannot itself be NULL.
  def mint_category(pool, user)
    MigrationCategory.create!(
      user_id: user.id, name: unique_category_name(user.id, pool.name), category_type: EXPENSE,
      pool_id: user.default_account_id || pool.account_id, tracked: false,
      created_at: now, updated_at: now
    )
  end

  # Suffixed on `Category`'s own rule — per user, case-insensitive — because a goal's name is not
  # reserved against the category table and "Trip" the goal may meet "Trip" the category that has
  # nothing to do with it. Nothing is merged on a name match here: the cutover's rung 2 merged a
  # cap into a same-named envelope because the live accept flow does exactly that in front of the
  # user, and no flow anywhere merges a category into another category.
  def unique_category_name(user_id, base)
    taken = MigrationCategory.where(user_id: user_id).pluck(:name).map(&:downcase).to_set
    return base unless taken.include?(base.downcase)

    suffix = 2
    suffix += 1 while taken.include?("#{base} #{suffix}".downcase)
    "#{base} #{suffix}"
  end

  # Every movement with a non-account endpoint becomes an allocation: an account endpoint maps
  # to NULL (available), a pool endpoint to its category. Account↔account rows stay — those are
  # the physical ledger's own writer (§2) and this migration does not touch them.
  #
  # THE MAPPING IS DONE IN RUBY, NOT IN THE `INSERT ... SELECT` it looks like it wants to be, and
  # the reason is a join: resolving a pool to its category in SQL means `LEFT JOIN categories ON
  # pool_id`, which MULTIPLIES the row for an ACCOUNT endpoint — accounts carry many categories —
  # and would write one allocation per category of the account. `category_of` already holds the
  # answer, minted rows included, and it holds exactly one per pool by construction.
  #
  # `kind` IS CARRIED VERBATIM. A distribution's replace-on-re-run deletes `allocation` and `sweep`
  # rows and leaves `transfer` alone, so flattening the column would either resurrect a swept
  # envelope or hand next payday a hand-made move to delete. `source_entry_id` likewise: a movement
  # that was minted from an entry stays traceable to it.
  #
  # BOTH ENDPOINTS MUST BELONG TO THIS USER. A movement whose ends straddle two users is not
  # converted here and not converted by the other user's pass either — #verify!'s structural arm
  # names it rather than this step guessing which side's category should receive the money.
  def convert_movements(user, category_of)
    rows = movement_rows(user.id)
    return 0 if rows.empty?

    MigrationAllocation.insert_all!(rows.map { |row| allocation_row(row, category_of) })
    MigrationMovement.where(id: rows.map(&:first)).delete_all
    rows.length
  end

  def movement_rows(user_id)
    MigrationMovement
      .joins("JOIN pools f ON f.id = pool_movements.from_pool_id")
      .joins("JOIN pools t ON t.id = pool_movements.to_pool_id")
      .where("f.user_id = :uid AND t.user_id = :uid", uid: user_id)
      .where("f.pool_type <> :acct OR t.pool_type <> :acct", acct: ACCOUNT)
      .order(Arel.sql("pool_movements.date, pool_movements.id"))
      .pluck(Arel.sql(<<~SQL.squish))
        pool_movements.id, pool_movements.from_pool_id, pool_movements.to_pool_id,
        pool_movements.amount, pool_movements.date, pool_movements.kind,
        pool_movements.source_entry_id
      SQL
  end

  def allocation_row(row, category_of)
    _id, from_pool_id, to_pool_id, amount, date, kind, source_entry_id = row

    { from_category_id: category_of[from_pool_id], to_category_id: category_of[to_pool_id],
      amount: amount, date: date, kind: kind, source_entry_id: source_entry_id,
      created_at: now, updated_at: now }
  end

  # SPEC §2: "No 'paid from' field on entries; the pot is where cash leaves." The column survives
  # until Task 8's drop, so it is emptied here rather than left holding an override the purpose
  # ledger has no term for. Scoped through the user's own CATEGORIES rather than through their
  # pools, so an override pointing at a stranger's pool is cleared too.
  def clear_paid_from_overrides(user)
    MigrationEntry
      .where.not(pool_id: nil)
      .where(item_id: MigrationItem.where(category_id: MigrationCategory.where(user_id: user.id).select(:id))
                                   .select(:id))
      .update_all(pool_id: nil, updated_at: now)
  end

  # SIX ARMS, COLLECTED RATHER THAN SHORT-CIRCUITED so a bad user is reported whole, then raised as
  # one failure inside the user's transaction.
  #
  # THE TWO LEDGERS ARE ASKED SEPARATELY AND KEYED DIFFERENTLY, which is the whole point. The
  # physical side is `income − expenses` over the user's own entries with no pool and no category
  # holding named anywhere; the purpose side is `available + Σ holdings`, every term of which is
  # read from `allocations` and `categories.funded_since`. They share the entries table and nothing
  # else, so they can only agree if every allocation this migration wrote lands on a category of
  # THIS user — money allocated out to a stranger's category leaves one side short and the other
  # untouched. That is the one arithmetic breakage `Σ` is not blind to; the structural arms below
  # cover what it is.
  def verify!(user, pools:, category_of:, bank:)
    failures = fold_failures(pools, category_of)
    failures.concat(structural_failures(user.id))
    physical = bank_total(user.id)
    purpose = purpose_total(user.id)
    failures << "bank truth moved #{physical.to_f} != #{bank.to_f}" unless physical == bank
    failures << "purpose ledger #{purpose.to_f} != bank truth #{physical.to_f}" unless purpose == physical

    raise VerificationFailed, "#{user.email} (#{user.id}): #{failures.join('; ')}" if failures.any?
  end

  # THE FOLD, RE-READ FROM THE DATABASE rather than trusted from the loop that wrote it — a `fold`
  # that returned an id without writing a column would leave every arithmetic arm below serene,
  # because an unfunded category holds nothing and spends nothing on the purpose side either way.
  def fold_failures(pools, category_of)
    pools.filter_map do |pool|
      category_id = category_of[pool.id]
      category = category_id && MigrationCategory.find_by(id: category_id)
      next if category &&
              category.funded_since == pool.start_date &&
              category.target_amount == pool.target_amount &&
              category.priority == pool.priority

      "pool #{pool.name.inspect} (#{pool.id}) did not fold onto category #{category_id.inspect}"
    end
  end

  def structural_failures(user_id)
    stranded = stranded_movements(user_id)
    ruleless = ruleless_rules(user_id)

    failures = []
    failures << "#{stranded} movements still name a pool that is not an account" if stranded.positive?
    failures << "#{ruleless} rules on this user's envelopes still have no category" if ruleless.positive?
    failures
  end

  # NOT A PARAPHRASE OF #movement_rows' PREDICATE — deliberately wider. The conversion takes only
  # the movements whose two ends belong to the SAME user; this asks about every movement with a
  # non-account end that touches this user at all, so a cross-user leftover is named here rather
  # than silently outliving the run.
  def stranded_movements(user_id)
    MigrationMovement
      .joins("JOIN pools f ON f.id = pool_movements.from_pool_id")
      .joins("JOIN pools t ON t.id = pool_movements.to_pool_id")
      .where("f.user_id = :uid OR t.user_id = :uid", uid: user_id)
      .where("f.pool_type <> :acct OR t.pool_type <> :acct", acct: ACCOUNT)
      .count
  end

  def ruleless_rules(user_id)
    MigrationBudget
      .where(pool_id: MigrationPool.where(user_id: user_id).where.not(pool_type: ACCOUNT).select(:id))
      .where(category_id: nil)
      .count
  end

  # THE PHYSICAL LEDGER'S TOTAL — money in from the world minus money out to it, over the entries of
  # the user's own categories, with no pool and no allocation named anywhere in the statement.
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

  # THE PURPOSE LEDGER'S TOTAL — `available + Σ category holdings`, spec §2's right-hand partition,
  # every term of it read from the tables this migration just wrote.
  #
  #   available = income − spending that predates its category's funding − Σ allocations out of
  #               available + Σ allocations back into it
  #   holdings  = Σ allocations into the user's categories − Σ allocations out of them − spending
  #               on or after `funded_since`
  #
  # `e.date >= c.funded_since` IS THE START-DATE RULE (§4), inherited from the pool table's
  # `start_date` and re-anchored on the column #fold just filled: spending before a category was
  # funded drains AVAILABLE, not the category. The two arms partition the user's expenses exactly,
  # so a wrong `funded_since` moves money between the two terms and cannot change their sum — which
  # is why #fold_failures exists and this does not stand in for it.
  def purpose_total(user_id)
    decimal(<<~SQL.squish, user_id)
      WITH mine AS (SELECT id, funded_since FROM categories WHERE user_id = :uid),
           spend AS (
             SELECT COALESCE(SUM(CASE WHEN m.funded_since IS NOT NULL AND e.date >= m.funded_since
                                      THEN 0 ELSE e.amount::numeric END), 0) AS unfunded,
                    COALESCE(SUM(CASE WHEN m.funded_since IS NOT NULL AND e.date >= m.funded_since
                                      THEN e.amount::numeric ELSE 0 END), 0) AS funded
               FROM entries e
               JOIN items i ON i.id = e.item_id
               JOIN categories c ON c.id = i.category_id
               JOIN mine m ON m.id = c.id
              WHERE c.category_type <> #{INCOME}),
           earned AS (
             SELECT COALESCE(SUM(e.amount::numeric), 0) AS total
               FROM entries e
               JOIN items i ON i.id = e.item_id
               JOIN categories c ON c.id = i.category_id
              WHERE c.user_id = :uid AND c.category_type = #{INCOME}),
           moved AS (
             SELECT COALESCE(SUM(CASE WHEN a.to_category_id IN (SELECT id FROM mine)
                                      THEN a.amount::numeric ELSE 0 END), 0) AS into_mine,
                    COALESCE(SUM(CASE WHEN a.from_category_id IN (SELECT id FROM mine)
                                      THEN a.amount::numeric ELSE 0 END), 0) AS out_of_mine,
                    COALESCE(SUM(CASE WHEN a.from_category_id IS NULL
                                       AND a.to_category_id IN (SELECT id FROM mine)
                                      THEN a.amount::numeric ELSE 0 END), 0) AS from_available,
                    COALESCE(SUM(CASE WHEN a.to_category_id IS NULL
                                       AND a.from_category_id IN (SELECT id FROM mine)
                                      THEN a.amount::numeric ELSE 0 END), 0) AS to_available
               FROM allocations a)
      SELECT (earned.total - spend.unfunded - moved.from_available + moved.to_available)
           + (moved.into_mine - moved.out_of_mine - spend.funded)
        FROM earned, spend, moved
    SQL
  end

  # `BigDecimal(...to_s)` rather than the adapter's cast: `select_value` hands back a String for
  # some numeric results and a BigDecimal for others depending on the OID it lands on, and a money
  # comparison must not depend on which.
  def decimal(sql, user_id)
    BigDecimal(ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array([sql, { uid: user_id }])
    ).to_s)
  end

  def now = Time.current
end
