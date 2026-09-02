# frozen_string_literal: true

# THE DROP (two-ledger spec §5). `CategoriesHoldTheMoney` built the purpose ledger beside the pool
# layer and left the pool layer standing so the old readers kept working; this deletes it. What
# survives is `pools` AS ACCOUNTS ONLY — spec §5's "pools survives ONLY as accounts" — and
# `pool_movements` under the name it has always meant: `account_movements`, a transfer between two
# of a user's own bank accounts.
#
# WHAT GOES, IN ONE LIST, BECAUSE THE ORDER BELOW IS ABOUT FOREIGN KEYS RATHER THAN ABOUT MEANING:
#
#   * `categories.pool_id`, `entries.pool_id`, `budgets.pool_id` — the three references INTO the
#     layer. A category holds its own money (§2), an entry's "paid from" override is ruled out of
#     existence (§2, and Task 1 already cleared every one of them), and a rule belongs to the
#     category it funds (§3).
#   * every non-account POOL ROW — the envelopes and goals Task 1 folded onto categories.
#   * `pools.account_id` and the CHECK that paired it with `pool_type`, replaced by the flat
#     `pools_are_accounts`. Nesting is what `account_id` expressed and there is nothing left to nest.
#   * `pools.start_date`, `pools.target_amount`, `pools.priority` — an envelope's three columns.
#     `target_amount`'s "buffer marker" was a parked question and the ruling is that it is dropped:
#     an account mirrors a bank statement and has nothing to aim at.
#   * `pool_movements.kind`'s allocation and sweep members, by CHECK. A distribution writes
#     `allocations` now; what is left on this table is the transfer it was always named for.
#
# WHAT IT REFUSES BEFORE IT WRITES ANYTHING. Four shapes, each named with the owner's email, because
# the run is all-or-nothing and a refusal discovered halfway costs the same rollback while naming
# none of the rows responsible: a movement with a non-account end (the row the delete below would
# have to break a foreign key to remove), a movement that is not a transfer, a rule with no category
# to own it (`category_id` becomes NOT NULL), and a user whose main account is not an account.
#
# HOW IT VERIFIES ITSELF, AND WHAT IT DELIBERATELY DOES NOT DO. Spec §2's two partitions are
# measured per user in raw SQL BEFORE the first statement and again after the last, and every user
# must reconcile to the same figure on both sides. It does NOT re-derive Task 1's pool -> category
# mapping to check the fold: a savings pool's category was MINTED by that migration and carries no
# link back to the pool it came from, so matching by id reports a false alarm on exactly the rows
# that were converted most carefully. The invariant is the acceptance test the spec names, and it is
# the one asked here.
#
# IT ASSUMES NOTHING ABOUT `funded_since` BEYOND ITS PRESENCE. `Category#funding_start_is_not_in_the_
# future` is a validation younger than the data, so a category with a future funding start may exist
# and is none of this migration's business: no arm below compares that column to today, and
# #purpose_total's two spending arms partition the same expenses either way.
#
# THE `down` IS FOR THE SCHEMA REWIND, NOT FOR PRODUCTION — it restores the SHAPE so
# `spec/migrations/cutover_spec.rb` and `spec/migrations/two_ledger_spec.rb` can plant the world
# their subjects were written for. The deleted rows are gone; a real reversal is a restore.
class DropThePoolLayer < ActiveRecord::Migration[8.1]
  # Refusing the INPUT — raised before the first write.
  class PreflightFailed < StandardError; end

  # Refusing its own OUTPUT — raised after the last, inside the Migrator's transaction, so a
  # database whose two ledgers stopped reconciling is never committed. `CategoriesHoldTheMoney`'s
  # two classes, kept apart for its reason: "is this database droppable" and "did the drop go
  # wrong" need different work from whoever reads the message.
  class VerificationFailed < StandardError; end

  # The integers as the schema holds them at this moment in the sequence, written out rather than
  # read off the app's enums — `Pool`'s budget and savings members are deleted in the same commit as
  # this file, and a migration whose meaning changes with a model is a migration that rewrites
  # history.
  ACCOUNT = 0
  INCOME = 1
  TRANSFER = 0

  def up
    before = ledgers
    preflight!
    drop_the_references
    delete_the_non_account_pools
    narrow_the_pools_table
    rename_the_movements
    tighten_the_rules
    verify!(before)
  end

  # The mirror image, shape only. `account_movements` goes back to `pool_movements` FIRST, because
  # the columns restored after it are what a rewound spec plants against, and every restoration is
  # nullable so it lands on rows that have long since stopped carrying a value.
  def down
    remove_check_constraint :pools, name: "pools_are_accounts"
    change_column_null :budgets, :category_id, true
    restore_the_movements
    restore_the_pools_table
    restore_the_references
  end

  private

  # ---------------------------------------------------------------------------------------------
  # The refusals
  # ---------------------------------------------------------------------------------------------

  def preflight!
    failures = stranded_movements + undistributed_kinds + ownerless_rules + misfiled_mains
    return if failures.empty?

    raise PreflightFailed, failures.join("; ")
  end

  # A MOVEMENT WITH A NON-ACCOUNT END. Task 1 converted every one of these into an `allocation` and
  # deleted the row, so on a migrated database there are none — and this is the arm that says so
  # rather than assuming it. Left standing, the DELETE below would have to break a foreign key to
  # remove the pool on the other end of it, and the physical ledger has been silently skipping the
  # row all along (`AccountLedger#account_movements` joins both ends to accounts).
  def stranded_movements
    named(<<~SQL.squish, "movement %<id>s has an end that is not an account")
      SELECT m.id, u.email
        FROM pool_movements m
        JOIN pools f ON f.id = m.from_pool_id
        JOIN pools t ON t.id = m.to_pool_id
        JOIN users u ON u.id = f.user_id
       WHERE f.pool_type <> #{ACCOUNT} OR t.pool_type <> #{ACCOUNT}
       ORDER BY u.email, m.id
    SQL
  end

  # A MOVEMENT THAT IS NOT A TRANSFER. `allocation` and `sweep` were how a distribution marked its
  # own rows so it could replace them; a distribution writes `allocations` now and marks them there
  # (`Allocation.distributed`). A leftover would be refused by the CHECK a few lines below with no
  # owner named, so it is named here instead.
  def undistributed_kinds
    named(<<~SQL.squish, "movement %<id>s is not a transfer")
      SELECT m.id, u.email
        FROM pool_movements m
        JOIN pools f ON f.id = m.from_pool_id
        JOIN users u ON u.id = f.user_id
       WHERE m.kind <> #{TRANSFER}
       ORDER BY u.email, m.id
    SQL
  end

  # A RULE WITH NO CATEGORY. `budgets.category_id` becomes NOT NULL, and Task 1 wrote one onto every
  # rule it found — so a rule without one is a rule written since, through a form that no longer
  # exists, and guessing an owner for it is guessing about the user's money.
  def ownerless_rules
    named(<<~SQL.squish, "rule %<id>s has no category")
      SELECT b.id, COALESCE(u.email, '(no owner at all)') AS email
        FROM budgets b
        LEFT JOIN pools p ON p.id = b.pool_id
        LEFT JOIN users u ON u.id = p.user_id
       WHERE b.category_id IS NULL
       ORDER BY email, b.id
    SQL
  end

  # A MAIN ACCOUNT THAT IS NOT AN ACCOUNT. `users.default_account_id` carries `ON DELETE SET NULL`,
  # so the DELETE below would quietly un-name such a user's main account and take the pot with it —
  # every balance on Home reading zero with nothing to explain it.
  def misfiled_mains
    named(<<~SQL.squish, "main account %<id>s is not an account")
      SELECT p.id, u.email
        FROM users u
        JOIN pools p ON p.id = u.default_account_id
       WHERE p.pool_type <> #{ACCOUNT}
       ORDER BY u.email
    SQL
  end

  def named(sql, template)
    select_all(sql).map { |row| "#{row["email"]}: #{format(template, id: row["id"])}" }
  end

  # ---------------------------------------------------------------------------------------------
  # The drop itself
  # ---------------------------------------------------------------------------------------------

  # THE THREE REFERENCES GO FIRST, and the order is the whole reason this is a method of its own:
  # every one of them is a foreign key INTO `pools`, so the rows cannot be deleted while they stand.
  # `remove_column` takes the key and the index with it.
  def drop_the_references
    remove_column :budgets, :pool_id
    remove_column :categories, :pool_id
    remove_column :entries, :pool_id
  end

  # `delete_all`, not `destroy_all`: there is no model left to run callbacks on by the time this
  # commit is finished, and `Pool`'s destroy callbacks are the envelope re-pointing machinery this
  # migration exists to delete.
  def delete_the_non_account_pools
    say_with_time "deleting the envelopes and goals" do
      execute("DELETE FROM pools WHERE pool_type <> #{ACCOUNT}")
    end
  end

  # `account_id` TAKES ITS CHECK WITH IT — Postgres drops a constraint that depends on a dropped
  # column — so the flat replacement is added afterwards rather than swapped in place. It says the
  # same thing the pair said for an account and nothing at all for anything else, because there is
  # nothing else.
  #
  # THE COLUMN DEFAULT MOVES WITH THE CHECK, and it is not cosmetic. `TightenPoolShape` set it to
  # `budget` because an envelope was the ordinary pool this app made; a raw INSERT naming no type
  # would now write a 1 straight into a constraint that refuses it, and `Pool.new` would come back
  # from the database already invalid.
  def narrow_the_pools_table
    remove_column :pools, :account_id
    remove_column :pools, :start_date
    remove_column :pools, :target_amount
    remove_column :pools, :priority
    change_column_default :pools, :pool_type, from: 1, to: ACCOUNT
    add_check_constraint :pools, "pool_type = #{ACCOUNT}", name: "pools_are_accounts"
  end

  # The two check constraints are re-made rather than renamed: `rename_table` renames a table's
  # indexes by convention and leaves its constraints alone, so `pool_movements_distinct_pools` would
  # outlive the word "pool" everywhere else.
  def rename_the_movements
    remove_check_constraint :pool_movements, name: "pool_movements_positive_amount"
    remove_check_constraint :pool_movements, name: "pool_movements_distinct_pools"
    rename_table :pool_movements, :account_movements
    add_check_constraint :account_movements, "amount > 0::money", name: "account_movements_positive_amount"
    add_check_constraint :account_movements, "from_pool_id <> to_pool_id", name: "account_movements_distinct_accounts"
    add_check_constraint :account_movements, "kind = #{TRANSFER}", name: "account_movements_are_transfers"
  end

  def tighten_the_rules
    change_column_null :budgets, :category_id, false
  end

  def restore_the_movements
    remove_check_constraint :account_movements, name: "account_movements_are_transfers"
    remove_check_constraint :account_movements, name: "account_movements_positive_amount"
    remove_check_constraint :account_movements, name: "account_movements_distinct_accounts"
    rename_table :account_movements, :pool_movements
    add_check_constraint :pool_movements, "amount > 0::money", name: "pool_movements_positive_amount"
    add_check_constraint :pool_movements, "from_pool_id <> to_pool_id", name: "pool_movements_distinct_pools"
  end

  def restore_the_pools_table
    change_column_default :pools, :pool_type, from: ACCOUNT, to: 1
    add_column :pools, :account_id, :uuid
    add_column :pools, :start_date, :date
    add_column :pools, :target_amount, :money, scale: 2
    add_column :pools, :priority, :integer, null: false, default: 0
    add_index :pools, :account_id
    add_index :pools, [:user_id, :priority]
    add_foreign_key :pools, :pools, column: :account_id
    add_check_constraint :pools,
                         "(pool_type = #{ACCOUNT}) = (account_id IS NULL)",
                         name: "pools_account_matches_pool_type"
  end

  def restore_the_references
    add_column :entries, :pool_id, :uuid
    add_index :entries, :pool_id
    add_foreign_key :entries, :pools
    add_column :categories, :pool_id, :uuid
    add_index :categories, :pool_id
    add_foreign_key :categories, :pools
    add_column :budgets, :pool_id, :uuid
    add_index :budgets, :pool_id
    add_foreign_key :budgets, :pools
  end

  # ---------------------------------------------------------------------------------------------
  # The invariant, before and after
  # ---------------------------------------------------------------------------------------------

  # SPEC §2'S TWO PARTITIONS PER USER, plus bank truth as the figure both must equal. Read straight
  # from the tables rather than through `AccountLedger` and `CategoryLedger`, on the cutover's rule:
  # asking the readers to referee a migration of their own tables means a wrong term answers wrong on
  # both sides of the comparison.
  def ledgers(movements: "pool_movements")
    select_all("SELECT id, email FROM users ORDER BY created_at, id").to_h do |row|
      [
        row["id"],
        {
          email: row["email"],
          purpose: purpose_total(row["id"]),
          physical: physical_total(row["id"], movements),
          bank: bank_total(row["id"])
        }
      ]
    end
  end

  # EVERY USER, ON BOTH SIDES, AND THE COMPARISON IS AGAINST THE PRE-DROP FIGURE rather than against
  # bank truth alone: a drop that moved money from one partition into the other by the same amount
  # would satisfy "purpose == physical" and still be wrong.
  def verify!(before)
    after = ledgers(movements: "account_movements")
    failures = before.flat_map { |id, was| drift(was, after[id]) } + surviving_pools
    raise VerificationFailed, failures.join("; ") if failures.any?

    before.each_value { |was| say "#{was[:email]}: purpose #{was[:purpose].to_f} == physical #{was[:physical].to_f} == bank #{was[:bank].to_f}, unchanged" }
  end

  def drift(was, now)
    return ["#{was[:email]}: vanished from the users table"] if now.nil?

    [:purpose, :physical, :bank].filter_map do |side|
      "#{was[:email]}: #{side} was #{was[side].to_f}, is #{now[side].to_f}" unless was[side] == now[side]
    end
  end

  def surviving_pools
    count = select_value("SELECT COUNT(*) FROM pools WHERE pool_type <> #{ACCOUNT}").to_i
    count.zero? ? [] : ["#{count} pools that are not accounts survived the drop"]
  end

  # `CategoriesHoldTheMoney#purpose_total`, unchanged and deliberately so: it names no pool at all,
  # which is precisely why it reads the same on both sides of a migration that deletes them. See
  # that method for why the funded/unfunded gate carries no `AT TIME ZONE` — the two arms partition
  # one set of expenses and are added together here, so the boundary is inert.
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

  # `pot + Σ accounts`. The movement table is named by the caller because this figure is asked on
  # both sides of the rename and there is one expression for it, not two that agree today.
  def physical_total(user_id, movements)
    decimal(<<~SQL.squish, user_id)
      SELECT COALESCE((SELECT SUM(CASE WHEN c.category_type = #{INCOME}
                                       THEN e.amount::numeric ELSE -e.amount::numeric END)
                         FROM entries e
                         JOIN items i ON i.id = e.item_id
                         JOIN categories c ON c.id = i.category_id
                        WHERE c.user_id = :uid), 0)
           + COALESCE((SELECT SUM(m.amount::numeric) FROM #{movements} m
                        WHERE m.to_pool_id IN (SELECT id FROM pools
                                                WHERE user_id = :uid AND pool_type = #{ACCOUNT})), 0)
           - COALESCE((SELECT SUM(m.amount::numeric) FROM #{movements} m
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
end
