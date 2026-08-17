# frozen_string_literal: true

# THE CUTOVER. Every user's data moves into the envelope model here, and this is the only
# migration in the four-plan conversion that REWRITES existing rows rather than adding beside
# them. Read the two rules below before changing a line of it.
#
# RULE ONE — NO APP MODEL IS REFERENCED, ANYWHERE. Every write goes through a migration-local
# `ActiveRecord::Base` subclass with nothing on it but a table name, and through `update_all` /
# `insert_all!` / `delete_all`, which run no validations and fire no callbacks. This is not
# hygiene; it is the difference between this migration working and it deleting data:
# `Category#destroy_budget_if_pool_linked` destroys a category's cap THE MOMENT a `pool_id` is
# assigned to it. Through `Category`, step 4 below would silently destroy every cap that step 3
# had not yet converted. Local classes also mean next year's validations — `pool` required on
# Category (Task 3), an account required on every non-account pool (Task 6), a UNIQUE index on
# pool names (Task 6) — cannot retroactively refuse a row this migration legitimately wrote on
# its way to satisfying them.
#
# RULE TWO — ENVELOPES BEFORE RE-POINTING. Spec §6.1 lists "point every category at the account"
# as step 2 and "convert the caps" as step 4. In that order the caps are gone before step 4 runs
# (rule one's callback), which §7a names "the step that loses data". The order here is inverted:
# a capped category gets its envelope, its rule and its re-point as one act (step 3), and only
# the categories that still have no pool afterwards go to the account (step 4).
#
# WHAT IT VERIFIES, AND WHY NOT WITH THE APP'S READERS. After each user, the migration re-derives
# the invariant the app is about to display — `Σ pools == the bank's balance` — in raw SQL, from
# `entries` alone. Asking `PoolCalculator` would be asking the readers being migrated to referee
# their own migration: a balance formula with a wrong term would answer wrong on both sides of
# the comparison and the check would pass. The two sides here are keyed differently on purpose —
# one sums by POOL MEMBERSHIP (`COALESCE(entries.pool_id, categories.pool_id)`, plus both
# movement directions), the other by CATEGORY OWNERSHIP (`categories.user_id`) — so they can only
# agree if every entry actually reaches a pool of the user who owns it.
#
# IDEMPOTENT. A second run finds no account to create, no pool to house, no cap to convert, no
# category to point and no savings entry to move — and still verifies, which is what makes a
# re-run a usable audit of a database somebody else's script has since touched.
class CutoverToEnvelopeBudgeting < ActiveRecord::Migration[8.1]
  # Raised inside the user's transaction, so a user is either wholly migrated or wholly untouched.
  class VerificationFailed < StandardError; end

  # The integers as the schema holds them TODAY. Written out rather than read off the app's enums
  # for rule one's reason: `Category`'s `savings: 2` is deleted in Task 5, and a migration whose
  # meaning changes when that happens is a migration that rewrites history.
  EXPENSE_CATEGORY = 0
  INCOME_CATEGORY = 1
  SAVINGS_CATEGORY = 2

  ACCOUNT_POOL = 0
  BUDGET_POOL = 1

  MONTHLY_BASIS = 0
  TRANSFER_KIND = 0

  DEFAULT_ACCOUNT_NAME = "Checking"

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationPool < ActiveRecord::Base
    self.table_name = "pools"
  end

  class MigrationCategory < ActiveRecord::Base
    self.table_name = "categories"
  end

  class MigrationItem < ActiveRecord::Base
    self.table_name = "items"
  end

  class MigrationEntry < ActiveRecord::Base
    self.table_name = "entries"
  end

  class MigrationBudget < ActiveRecord::Base
    self.table_name = "budgets"
  end

  class MigrationMovement < ActiveRecord::Base
    self.table_name = "pool_movements"
  end

  def up
    MigrationUser.order(:created_at, :id).pluck(:id, :email).each do |user_id, email|
      migrate_user(user_id, email)
    end
  end

  # There is no down. The savings entries are deleted, their categories and items with them, and
  # a cap that has become a funding rule cannot be told apart from a funding rule somebody wrote
  # by hand afterwards. Restoring this state means restoring a backup.
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # ONE TRANSACTION PER USER, and the verification is INSIDE it: a user whose figures do not
  # reconcile is rolled back to the shape they arrived in, and the raise stops the run before the
  # next user is touched.
  def migrate_user(user_id, email)
    ActiveRecord::Base.transaction do
      account_id = ensure_default_account(user_id)
      counts = { housed: house_account_less_pools(user_id, account_id) }
      counts[:caps], rules_before = convert_caps(user_id, account_id)
      counts[:pointed] = point_remaining_categories(user_id, account_id)
      counts[:moved], counts[:deleted] = convert_savings_entries(user_id, account_id)

      pooled, bank = verify!(user_id, account_id, caps: counts[:caps], rules_before: rules_before)

      report(email, account_id, counts, pooled, bank)
    end
  end

  # STEP 1 — the account every other step points at.
  #
  # The flagged default is honoured only if it is really an account of THIS user: a
  # `default_account_id` naming an envelope (or a pool since deleted — the column nullifies on
  # delete, but a hand-edited row need not) would seat every category in something that cannot
  # act as a buffer.
  def ensure_default_account(user_id)
    flagged = MigrationUser.where(id: user_id).pick(:default_account_id)
    return flagged if flagged && account?(user_id, flagged)

    account_id = first_account(user_id) || create_default_account(user_id)
    MigrationUser.where(id: user_id).update_all(default_account_id: account_id, updated_at: now)
    account_id
  end

  def account?(user_id, pool_id)
    MigrationPool.where(id: pool_id, user_id: user_id, pool_type: ACCOUNT_POOL).exists?
  end

  def first_account(user_id)
    MigrationPool.where(user_id: user_id, pool_type: ACCOUNT_POOL).order(:created_at, :id).pick(:id)
  end

  def create_default_account(user_id)
    insert_pool(user_id, name: unique_pool_name(user_id, DEFAULT_ACCOUNT_NAME), pool_type: ACCOUNT_POOL,
                         account_id: nil)
  end

  # STEP 2 — every non-account pool sits in an account. `pool_type: ACCOUNT_POOL` is excluded
  # rather than filtered by `account_id` alone: an account's own `account_id` is nil BY
  # DEFINITION (`Pool#account_matches_pool_type` refuses one), so housing it would be the same
  # error in the other direction.
  def house_account_less_pools(user_id, account_id)
    MigrationPool.where(user_id: user_id, account_id: nil)
                 .where.not(pool_type: ACCOUNT_POOL)
                 .update_all(account_id: account_id, updated_at: now)
  end

  # STEP 3 — ENVELOPES FIRST. Each category-mode cap becomes a monthly funding rule on an
  # envelope named for its category, and the category is re-pointed at that envelope in the same
  # breath.
  #
  # The cap row is UPDATED IN PLACE rather than inserted-and-deleted. Inserting a twin and
  # nulling the original's `category_id` would leave a budget row owned by nothing at all —
  # `Budget#exactly_one_owner` calls that invalid, no screen can reach it, and every rule total in
  # the app would count it. One row in, one row out, same id.
  #
  # Returns the cap count and the pool-mode rule count taken BEFORE any of them moved, which is
  # what lets the verification compare two figures measured from the database rather than
  # comparing a loop counter to itself.
  def convert_caps(user_id, account_id)
    rules_before = pool_rule_count(user_id)
    caps = MigrationBudget.where(category_id: MigrationCategory.where(user_id: user_id).select(:id))
                          .order(:created_at, :id)
                          .pluck(:id, :category_id)

    caps.each do |budget_id, category_id|
      pool_id = envelope_for(user_id, category_id, account_id)
      MigrationBudget.where(id: budget_id).update_all(
        pool_id: pool_id, category_id: nil, interval_months: 1, basis: MONTHLY_BASIS,
        anchor_date: nil, item_id: nil, prorated: false, updated_at: now
      )
      MigrationCategory.where(id: category_id).update_all(pool_id: pool_id, updated_at: now)
    end

    [caps.length, rules_before]
  end

  # WHERE A CAP'S MONEY GOES, and the ladder is `BudgetProposal::Envelope#existing`'s, rung for
  # rung, because that flow answers the same question live and the two must not disagree:
  #
  #   1. The category's OWN pool, if it has one that is not an account. Unreachable from the app
  #      (the callback in rule one destroys a cap the moment a pool is assigned) but reachable in
  #      a database, and a link the user made deliberately outranks a name.
  #   2. An envelope of this user already called this. A second pool by the same name would break
  #      `Pool`'s case-insensitive uniqueness and, in Task 6, a UNIQUE index. Narrowed to BUDGET
  #      pools on that flow's reasoning: hanging a category's spending on a savings goal that
  #      merely shares its name is worse than a suffix.
  #   3. A new envelope, suffixed if any pool of this user — of any type — already holds the name.
  def envelope_for(user_id, category_id, account_id)
    name, pool_id = MigrationCategory.where(id: category_id).pick(:name, :pool_id)

    return pool_id if pool_id && !account?(user_id, pool_id)

    reusable = MigrationPool.where(user_id: user_id, pool_type: BUDGET_POOL)
                            .where("LOWER(name) = LOWER(?)", name)
                            .order(:created_at, :id)
                            .pick(:id)
    return reusable if reusable

    insert_pool(user_id, name: unique_pool_name(user_id, name), pool_type: BUDGET_POOL, account_id: account_id)
  end

  # STEP 4 — everything still unpooled lands in the buffer. Income categories MUST name an
  # account (`Category#income_must_land_in_an_account`); the expense ones become the
  # buffer-funded shape Home already renders as "spent straight from the account".
  def point_remaining_categories(user_id, account_id)
    MigrationCategory.where(user_id: user_id, pool_id: nil).update_all(pool_id: account_id, updated_at: now)
  end

  # STEP 5 — a savings entry was never money crossing the user's boundary. It was "I moved my own
  # money" wearing the wrong record type, and it is re-recorded as what it was: a transfer out of
  # the buffer and into the goal. The entry is then DELETED — keeping both would double-count the
  # moment anything summed entries and movements together, which is exactly what `#balance` does.
  #
  # The destination is `COALESCE(entries.pool_id, categories.pool_id)` — the same lane every
  # balance in the app resolves an entry through — so the money lands in the pool that was
  # already counting it, not merely in the pool its category names.
  #
  # TWO ENTRIES GET NO MOVEMENT, and both are conserving rather than lossy. An entry whose lane
  # resolves to the DEFAULT ACCOUNT ITSELF would be a movement from a pool to itself, which the
  # `pool_movements_distinct_pools` constraint refuses and which would move nothing anyway. An
  # entry with a non-positive amount cannot exist through `Entry`'s validation and would break the
  # `pool_movements_positive_amount` constraint if it did. Neither omission touches `Σ pools`: a
  # movement's two halves cancel inside the user's own pool set by construction, so what the
  # movements decide is WHERE the money sits, never HOW MUCH there is.
  def convert_savings_entries(user_id, account_id)
    category_ids = MigrationCategory.where(user_id: user_id, category_type: SAVINGS_CATEGORY).pluck(:id)
    return [0, 0] if category_ids.empty?

    item_ids = MigrationItem.where(category_id: category_ids).pluck(:id)
    rows = savings_entry_rows(item_ids)
    movements = rows.filter_map { |_id, amount, date, pool_id| movement_row(account_id, amount, date, pool_id) }

    MigrationMovement.insert_all!(movements) if movements.any?
    destroy_savings_records(rows.map(&:first), item_ids, category_ids)

    [movements.length, rows.length]
  end

  def savings_entry_rows(item_ids)
    return [] if item_ids.empty?

    MigrationEntry
      .where(item_id: item_ids)
      .joins("INNER JOIN items ON items.id = entries.item_id")
      .joins("INNER JOIN categories ON categories.id = items.category_id")
      .pluck(Arel.sql("entries.id, entries.amount, entries.date, COALESCE(entries.pool_id, categories.pool_id)"))
  end

  def movement_row(account_id, amount, date, pool_id)
    return nil if pool_id.blank? || pool_id == account_id || amount.blank? || amount <= 0

    { from_pool_id: account_id, to_pool_id: pool_id, amount: amount, date: date,
      source_entry_id: nil, kind: TRANSFER_KIND, created_at: now, updated_at: now }
  end

  # The two nullifications are foreign keys, not tidiness: `pool_movements.source_entry_id` and
  # `budgets.item_id` both reference rows about to be deleted, and neither key cascades. Legacy
  # data holds no such row today — movements arrived with Plan 1 — so this is the cost of the
  # migration surviving a database that has been running the new code for a week.
  def destroy_savings_records(entry_ids, item_ids, category_ids)
    MigrationMovement.where(source_entry_id: entry_ids).update_all(source_entry_id: nil, updated_at: now)
    MigrationEntry.where(id: entry_ids).delete_all
    MigrationBudget.where(item_id: item_ids).update_all(item_id: nil, updated_at: now)
    MigrationItem.where(id: item_ids).delete_all
    MigrationCategory.where(id: category_ids).delete_all
  end

  # STEP 6 — six checks, collected rather than short-circuited so a bad user is reported whole,
  # then raised as one failure inside the transaction.
  def verify!(user_id, account_id, caps:, rules_before:)
    pooled = pool_total(user_id)
    bank = bank_total(user_id)
    failures = structural_failures(user_id, account_id, caps, rules_before)
    failures << "Σ pools #{pooled.to_f} != bank truth #{bank.to_f}" unless pooled == bank

    raise VerificationFailed, "user #{user_id}: #{failures.join('; ')}" if failures.any?

    [pooled, bank]
  end

  def structural_failures(user_id, account_id, caps, rules_before)
    unpooled = unpooled_categories(user_id)
    houseless = houseless_pools(user_id)

    failures = []
    failures << "default account #{account_id.inspect} is not an account of this user" unless
      MigrationUser.where(id: user_id).pick(:default_account_id) == account_id && account?(user_id, account_id)
    failures << "#{unpooled} categories still have no pool" if unpooled.positive?
    failures << "#{houseless} non-account pools still have no account" if houseless.positive?
    failures.concat(rule_failures(user_id, caps, rules_before))
    failures.concat(savings_failures(user_id))
    failures
  end

  def unpooled_categories(user_id) = MigrationCategory.where(user_id: user_id, pool_id: nil).count

  def houseless_pools(user_id)
    MigrationPool.where(user_id: user_id, account_id: nil).where.not(pool_type: ACCOUNT_POOL).count
  end

  # BOTH SIDES MEASURED FROM THE DATABASE. `caps` is the count of category-mode rows read before
  # any of them moved and `rules_before` the pool-mode count at the same instant, so this compares
  # what the table says now against what it said then — not a loop counter against itself, which
  # would be true however many rules the loop had dropped on the floor.
  def rule_failures(user_id, caps, rules_before)
    grew_by = pool_rule_count(user_id) - rules_before
    remaining = MigrationBudget.where(category_id: MigrationCategory.where(user_id: user_id).select(:id)).count

    failures = []
    failures << "#{grew_by} envelope rules created for #{caps} caps" unless grew_by == caps
    failures << "#{remaining} category-mode caps survived" unless remaining.zero?
    failures
  end

  def savings_failures(user_id)
    categories = MigrationCategory.where(user_id: user_id, category_type: SAVINGS_CATEGORY).count
    entries = MigrationEntry.where(item_id: MigrationItem.where(category_id: MigrationCategory
      .where(user_id: user_id, category_type: SAVINGS_CATEGORY).select(:id)).select(:id)).count

    failures = []
    failures << "#{categories} savings categories survived" unless categories.zero?
    failures << "#{entries} savings entries survived" unless entries.zero?
    failures
  end

  def pool_rule_count(user_id)
    MigrationBudget.where(pool_id: MigrationPool.where(user_id: user_id).select(:id)).count
  end

  # `Σ pools`, KEYED BY POOL MEMBERSHIP. The five terms of `PoolCalculator#balance` summed over
  # every pool this user owns, in one statement: entries reaching a pool through
  # `COALESCE(entries.pool_id, categories.pool_id)`, signed by category type, plus both movement
  # directions.
  #
  # The savings arm is deliberately still here even though the check beside it asserts no savings
  # entry survives. It is the app's formula reproduced, not the post-migration formula assumed —
  # a savings entry the conversion missed must show up as MONEY, not merely as a count.
  #
  # `::numeric` on every money column, because `money` in Postgres is a fixed-scale type whose
  # arithmetic with integers is its own business; the comparison this migration turns on is
  # between two exact decimals or it is between two roundings.
  def pool_total(user_id)
    decimal(<<~SQL.squish, user_id)
      SELECT
        COALESCE((SELECT SUM(CASE WHEN c.category_type = #{EXPENSE_CATEGORY}
                                  THEN -e.amount::numeric ELSE e.amount::numeric END)
                    FROM entries e
                    JOIN items i ON i.id = e.item_id
                    JOIN categories c ON c.id = i.category_id
                   WHERE COALESCE(e.pool_id, c.pool_id) IN (SELECT id FROM pools WHERE user_id = :uid)), 0)
      + COALESCE((SELECT SUM(m.amount::numeric) FROM pool_movements m
                   WHERE m.to_pool_id IN (SELECT id FROM pools WHERE user_id = :uid)), 0)
      - COALESCE((SELECT SUM(m.amount::numeric) FROM pool_movements m
                   WHERE m.from_pool_id IN (SELECT id FROM pools WHERE user_id = :uid)), 0)
    SQL
  end

  # THE BANK'S OWN ANSWER, KEYED BY CATEGORY OWNERSHIP — money in from the world minus money out
  # to it, over the entries of the user's own categories, with no pool named anywhere in the
  # statement. It shares no join, no predicate and no grouping with the sum above, which is the
  # whole point: two queries that reached the same rows the same way would agree about a database
  # in which every category had lost its pool.
  def bank_total(user_id)
    decimal(<<~SQL.squish, user_id)
      SELECT COALESCE(SUM(CASE WHEN c.category_type = #{INCOME_CATEGORY}
                               THEN e.amount::numeric ELSE -e.amount::numeric END), 0)
        FROM entries e
        JOIN items i ON i.id = e.item_id
        JOIN categories c ON c.id = i.category_id
       WHERE c.user_id = :uid
         AND c.category_type IN (#{EXPENSE_CATEGORY}, #{INCOME_CATEGORY})
    SQL
  end

  # `BigDecimal(...to_s)` rather than the adapter's cast: `select_value` hands back a String for
  # some numeric results and a BigDecimal for others depending on the OID it lands on, and a
  # money comparison must not depend on which.
  def decimal(sql, user_id)
    BigDecimal(ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array([sql, { uid: user_id }])
    ).to_s)
  end

  def insert_pool(user_id, name:, pool_type:, account_id:)
    MigrationPool.insert!(
      { user_id: user_id, name: name, pool_type: pool_type, account_id: account_id,
        priority: next_priority(user_id), start_date: Date.current, target_amount: nil,
        created_at: now, updated_at: now },
      returning: %w[id]
    ).first["id"]
  end

  # AFTER everything the user already ordered, never at 0. `priority` is the fill order the
  # distribution waterfall pays in, and a converted cap arriving at the front of it would quietly
  # outrank rules the user placed by hand — 0 is also the column default, so every converted
  # envelope would tie with every other and the order would fall through to the name.
  def next_priority(user_id) = (MigrationPool.where(user_id: user_id).maximum(:priority) || -1) + 1

  # Suffixed against pools of EVERY type, because `Pool`'s uniqueness is per user and
  # case-insensitive with no regard for type — and Task 6's UNIQUE index will be too.
  def unique_pool_name(user_id, base)
    taken = MigrationPool.where(user_id: user_id).pluck(:name).map(&:downcase).to_set
    return base unless taken.include?(base.downcase)

    suffix = 2
    suffix += 1 while taken.include?("#{base} #{suffix}".downcase)
    "#{base} #{suffix}"
  end

  def now = Time.current

  def report(email, account_id, counts, pooled, bank)
    say "#{email}: buffer #{MigrationPool.where(id: account_id).pick(:name)}; " \
        "#{counts[:housed]} pools housed; #{counts[:caps]} caps -> #{counts[:caps]} envelope rules; " \
        "#{counts[:pointed]} categories -> buffer; " \
        "#{counts[:deleted]} savings entries -> #{counts[:moved]} movements; " \
        "Σ pools #{format('%.2f', pooled)} == bank truth #{format('%.2f', bank)}"
  end
end
