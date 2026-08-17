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
# WHAT IT ADDS THAT THE OLD DATABASE NEVER HELD. Exactly one thing: step 5b's zeroing movements,
# which open every budget envelope at $0 instead of at the whole of its category's spending history.
# The reasoning is on that method. Everything else here re-records a fact the database already held
# in a shape the new model can read.
#
# IDEMPOTENT. A second run finds no account to create, no pool to house, no cap to convert, no
# category to point, no savings entry to move and no envelope in deficit — and still verifies, which
# is what makes a re-run a usable audit of a database somebody else's script has since touched.
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
  SAVINGS_POOL = 2

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

  # THE TRANSACTION BOUNDARY IS THE WHOLE MIGRATION, NOT THE USER — and the earlier wording here
  # ("one transaction per user") was wrong about production, so it is corrected rather than quietly
  # deleted. `ActiveRecord::Migrator` already wraps the run in a JOINABLE transaction on PostgreSQL,
  # so this block joins it instead of opening one: no savepoint is taken, and a raise on user 3
  # rolls back users 1 and 2 with it.
  #
  # THAT IS THE BEHAVIOUR WE WANT, and it is stronger than the per-user guarantee the plan asked
  # for: the run is all-or-nothing. `requires_new: true` would buy per-user savepoints and, with
  # them, a 10,000-user database that is 6,000 migrated and 4,000 not — a state with no name, no
  # screen and no way back. It is deliberately not expressible.
  #
  # UNDER THE SPEC it is per-user after all, and for a reason that belongs to the test harness
  # rather than to this file: DatabaseCleaner opens its example transaction with `joinable: false`,
  # so this block DOES take a savepoint there and the sabotage examples can watch one user roll back
  # while the others stand. Same code, two boundaries, both correct.
  #
  # Either way the verification runs INSIDE the block, so a user whose figures do not reconcile is
  # never committed.
  def migrate_user(user_id, email)
    ActiveRecord::Base.transaction do
      # TAKEN BEFORE ANY WRITE, and it is the one figure this migration promises not to move. See
      # #savings_drift_failures.
      savings_before = pool_balances(user_id, SAVINGS_POOL)

      account_id = ensure_default_account(user_id)
      counts = { housed: house_the_pools(user_id, account_id) }
      counts[:caps], rules_before = convert_caps(user_id, account_id)
      # MEASURED, NOT ECHOED. The report used to print the cap count twice — "7 caps -> 7 envelope
      # rules" from one variable — which is a receipt that confirms itself. This side is read back
      # off the table, so the two halves of that sentence can disagree.
      counts[:rules] = pool_rule_count(user_id) - rules_before
      counts[:pointed] = point_remaining_categories(user_id, account_id)
      counts[:moved], counts[:deleted], savings_movements = convert_savings_entries(user_id, account_id)
      counts[:zeroed], zeroing_movements = zero_the_envelopes(user_id, account_id)

      pooled, bank = verify!(user_id, account_id, caps: counts[:caps], rules_before: rules_before,
                                                  savings_before: savings_before,
                                                  written: savings_movements + zeroing_movements)

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

  # STEP 2 — every non-account pool sits in an account OF THIS USER THAT IS REALLY AN ACCOUNT, and
  # all three clauses of that are load-bearing.
  #
  # "NOT NULL" IS NOT THE QUESTION, and asking only that was the bug. A pool whose `account_id`
  # points at an ENVELOPE, or at a stranger's account, has a non-null column and a house that cannot
  # hold it: `Pool#account_matches_pool_type` already refuses both ("must be an account", "must
  # belong to the same user"), so the row is invalid today, invisible to every screen that groups by
  # account, and — this is the part that matters — it would sail through the one migration able to
  # fix it and meet Task 6's tightening with no remedy left. Violators are re-housed in the default
  # account exactly as the null ones are.
  #
  # `pool_type: ACCOUNT_POOL` is excluded rather than filtered by `account_id` alone: an account's
  # own `account_id` is nil BY DEFINITION (the same validation refuses one), so housing it would be
  # the same error in the other direction.
  #
  # `NOT EXISTS` rather than `NOT IN`, because `account_id NOT IN (...)` is NULL for a null column
  # and NULL is not true — the account-less pools, which are the common case, would not have
  # matched at all.
  def house_the_pools(user_id, account_id)
    MigrationPool.where(user_id: user_id)
                 .where.not(pool_type: ACCOUNT_POOL)
                 .where(unhoused_predicate, uid: user_id, acct: ACCOUNT_POOL)
                 .update_all(account_id: account_id, updated_at: now)
  end

  # Shared by step 2 and the verifier, so "housed" cannot mean two things.
  def unhoused_predicate
    "NOT EXISTS (SELECT 1 FROM pools a WHERE a.id = pools.account_id " \
      "AND a.user_id = :uid AND a.pool_type = :acct)"
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
  #
  # RUNG 2 IS THE ONLY IRREVERSIBLE JUDGEMENT IN THIS MIGRATION, and it is called out rather than
  # left to be discovered. Every other step MOVES something: a cap becomes a rule, an entry becomes
  # a movement, a category gains a pool, and each of those is one row changing shape. This one
  # MERGES two things the user created separately — a category and a same-named envelope that had
  # nothing to do with each other until now — and afterwards there is no column recording that they
  # were ever apart. It fired once on the demo: the "Utilities" category's whole spending history
  # joined the "Utilities" envelope that was already funding its Electric Bill.
  #
  # It is done anyway, on `BudgetProposal::Envelope#existing`'s precedent, and that precedent is the
  # argument: the live accept flow makes exactly this judgement, in front of the user, with a
  # sentence explaining it — "This rule joins your existing Utilities envelope". An envelope already
  # called this IS this envelope. The alternative is a suffixed "Utilities 2" beside it, which is
  # not a smaller decision, only a quieter one, and it leaves the user with two envelopes for one
  # bill and a `UNIQUE (user_id, lower(name))` index (Task 6) that will not let them merge.
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
  # already counting it, not merely in the pool its category names. The SOURCE is #home_accounts'
  # answer for that destination; see there for why it is not the default account.
  #
  # TWO ENTRIES GET NO MOVEMENT, and both are conserving rather than lossy. An entry whose lane
  # resolves to an ACCOUNT is already sitting in its own buffer — its source and destination are
  # the same pool, which the `pool_movements_distinct_pools` constraint refuses and which would move
  # nothing anyway. An entry with a non-positive amount cannot exist through `Entry`'s validation and
  # would break the `pool_movements_positive_amount` constraint if it did. Neither omission touches
  # `Σ pools`: a movement's two halves cancel inside the user's own pool set by construction, so what
  # the movements decide is WHERE the money sits, never HOW MUCH there is.
  def convert_savings_entries(user_id, account_id)
    category_ids = MigrationCategory.where(user_id: user_id, category_type: SAVINGS_CATEGORY).pluck(:id)
    return [0, 0, []] if category_ids.empty?

    item_ids = MigrationItem.where(category_id: category_ids).pluck(:id)
    rows = savings_entry_rows(item_ids)
    homes = home_accounts(rows.map(&:last).compact.uniq)
    movements = rows.filter_map do |_id, amount, date, pool_id|
      movement_row(homes.fetch(pool_id, account_id), amount, date, pool_id)
    end

    written = movements.any? ? inserted_ids(movements) : []
    destroy_savings_records(rows.map(&:first), item_ids, category_ids)

    [movements.length, rows.length, written]
  end

  # THE ACCOUNT A POOL LIVES IN, and the one destination rule both movement-writing steps share.
  #
  # An envelope or a goal answers with the account holding it; an ACCOUNT answers with itself, since
  # it sits inside no other and stands in as its own — which is exactly `PoolMovement
  # #containing_account`, the reader `#crosses_accounts?` is built on. Written once here because
  # steps 5 and 5b were getting it right and wrong respectively: 5b was corrected to source a
  # zeroing movement from the envelope's own account, while 5 still hardcoded the DEFAULT account
  # and so wrote a cross-account transfer for any goal the user keeps somewhere else. Step 2 only
  # fills a NULL `account_id`, so a goal pre-housed in a second account is untouched by it and the
  # shape survives the migration.
  #
  # A cross-account movement is a BANK TRANSFER — spec §5.4 defers those, `#crosses_accounts?`
  # renders them with a callout, and the migration must not invent one that never happened. The
  # verifier checks this directly (#cross_account_failures) rather than trusting the two call sites
  # to keep agreeing.
  def home_accounts(pool_ids)
    return {} if pool_ids.empty?

    MigrationPool.where(id: pool_ids).pluck(:id, :account_id, :pool_type)
                 .to_h { |id, account_id, type| [id, type == ACCOUNT_POOL ? id : account_id] }
  end

  def inserted_ids(rows)
    MigrationMovement.insert_all!(rows, returning: %w[id]).rows.flatten
  end

  def savings_entry_rows(item_ids)
    return [] if item_ids.empty?

    MigrationEntry
      .where(item_id: item_ids)
      .joins("INNER JOIN items ON items.id = entries.item_id")
      .joins("INNER JOIN categories ON categories.id = items.category_id")
      .pluck(Arel.sql("entries.id, entries.amount, entries.date, COALESCE(entries.pool_id, categories.pool_id)"))
  end

  def movement_row(source_id, amount, date, pool_id)
    return nil if pool_id.blank? || source_id.blank? || pool_id == source_id || amount.blank? || amount <= 0

    { from_pool_id: source_id, to_pool_id: pool_id, amount: amount, date: date,
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

  # STEP 5b — BUDGET ENVELOPES OPEN AT ZERO, and this is the one step that writes a fact the old
  # database never held rather than re-recording one it did.
  #
  # WHY. An envelope created by step 3 has never been funded, and the moment its category is
  # re-pointed the WHOLE of that category's spending history resolves into it: the demo's Housing
  # envelope opened at −$3,182.00, Food & Dining at −$2,190.00. Every one of those figures is
  # technically true and practically a lie about the user's situation. It says "you are $754 in the
  # hole on utilities"; what actually happened is that they paid their utility bills out of the
  # buffer for years, before envelopes existed at all. A cutover that opens by accusing every user
  # of an overdraft they never had is a cutover that gets rolled back.
  #
  # WHAT IT RECORDS. One movement per overdrawn envelope, from the buffer, for exactly the deficit:
  # the retroactively-true aggregate fact that over those years this lane WAS funded with what it
  # spent. Afterwards the envelope holds $0 — a fresh start, which is what a cutover is — the buffer
  # holds the user's real position, and `Σ pools` is untouched, because both halves of a movement
  # sit inside the same pool set. Spec §7 defers "opening balances"; this is the one moment the
  # deferral has to resolve, because this migration is the only code that will ever see the data in
  # its pre-envelope shape.
  #
  # BUDGET POOLS ONLY. A savings pool's balance is real accumulated savings — the one number the old
  # app got right — and zeroing it would destroy it. #savings_drift_failures asserts those balances
  # do not move by so much as a cent across the whole migration.
  #
  # SHAPE-DRIVEN, NOT PROVENANCE-DRIVEN: any negative budget envelope is zeroed, whether step 3
  # created it or the user had it already. That is what makes the step idempotent by construction —
  # a second run finds nothing negative and writes nothing — rather than by remembering what it did.
  #
  # `kind` IS LEFT AT ITS DEFAULT (`transfer`), so these rows are invisible to a distribution's
  # replace-on-re-run, which deletes `allocation` and `sweep` only. A cutover artefact must not be
  # something next payday quietly deletes.
  #
  # `Σ pools` CANNOT SEE A MISTAKE HERE, which is why the deficit is measured with the same
  # expression the invariant is (see #balance_expression) and why the verifier gained a check of its
  # own: a movement of the wrong size still nets to zero, so it would leave the envelope wrong and
  # the invariant serene.
  # FROM THE ENVELOPE'S OWN ACCOUNT (#home_accounts), not from the user's default one. The ruling
  # this step implements says "from the buffer", and the buffer that historically paid a Health
  # Savings envelope's bills is Health Savings — so this is that instruction read literally rather
  # than a departure from it. It does not discriminate on the demo, where all eight overdrawn
  # envelopes sit in Checking, so the shape is planted in the spec instead.
  def zero_the_envelopes(user_id, account_id)
    deficits = pool_balances(user_id, BUDGET_POOL).select { |_id, balance| balance.negative? }
    return [0, []] if deficits.empty?

    homes = home_accounts(deficits.keys)
    rows = deficits.filter_map do |pool_id, balance|
      movement_row(homes.fetch(pool_id, account_id), -balance, now, pool_id)
    end

    [rows.length, inserted_ids(rows)]
  end

  # STEP 6 — eight checks, collected rather than short-circuited so a bad user is reported whole,
  # then raised as one failure inside the transaction.
  def verify!(user_id, account_id, caps:, rules_before:, savings_before:, written: [])
    pooled = pool_total(user_id)
    bank = bank_total(user_id)
    failures = structural_failures(user_id, account_id, caps, rules_before)
    failures.concat(envelope_failures(user_id))
    failures.concat(savings_drift_failures(user_id, savings_before))
    failures.concat(cross_account_failures(written))
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

  # STEP 5b's OWN CHECK, and it is not implied by the invariant: a zeroing movement of the wrong
  # size nets to zero like any other, so `Σ pools` would still equal the bank while the envelope it
  # was supposed to clear sat overdrawn.
  def envelope_failures(user_id)
    overdrawn = pool_balances(user_id, BUDGET_POOL).select { |_id, balance| balance.negative? }
    return [] if overdrawn.empty?

    ["#{overdrawn.size} budget envelopes are still negative (#{overdrawn.values.map(&:to_f).inspect})"]
  end

  # THE FIGURE THIS MIGRATION PROMISES NOT TO MOVE. A savings pool's balance is real accumulated
  # savings, and every step above is supposed to leave it exactly where it found it: converting an
  # entry to a movement replaces a `+amount` with an identical `+amount`, step 3 never re-points a
  # category away from a goal, step 4 seats pool-less categories in the ACCOUNT, and step 5b touches
  # budget pools only. Asserted rather than argued, cent for cent, against a snapshot taken before
  # the first write of the transaction.
  # A goal that VANISHED is drift too, and `after.reject` alone cannot see one — hence the union of
  # both key sets. Nothing here deletes a pool today; a step that started to would be reported as
  # `nil` rather than passing silently.
  def savings_drift_failures(user_id, before)
    after = pool_balances(user_id, SAVINGS_POOL)

    (before.keys | after.keys).filter_map do |pool_id|
      next if before[pool_id] == after[pool_id]

      "savings pool #{pool_id} moved #{before[pool_id]&.to_f.inspect} -> #{after[pool_id]&.to_f.inspect}"
    end
  end

  def unpooled_categories(user_id) = MigrationCategory.where(user_id: user_id, pool_id: nil).count

  # Step 2's own predicate, not a paraphrase of it: "has an account" and "is housed" have to be the
  # same question, or the step repairs one set and the verifier inspects another.
  def houseless_pools(user_id)
    MigrationPool.where(user_id: user_id)
                 .where.not(pool_type: ACCOUNT_POOL)
                 .where(unhoused_predicate, uid: user_id, acct: ACCOUNT_POOL)
                 .count
  end

  # NO MOVEMENT THIS MIGRATION WROTE MAY CROSS AN ACCOUNT BOUNDARY. `COALESCE(account_id, id)` is
  # `PoolMovement#containing_account` in SQL — an account stands in as its own — so this is
  # `#crosses_accounts?` asked of the rows just inserted.
  #
  # SCOPED TO THIS RUN'S ROWS, deliberately. A user may legitimately hold a cross-account movement:
  # the model supports one, `#must_not_cross_accounts` only refuses it on the `:reallocation`
  # context, and §5.4 calls the UI deferred rather than the record illegal. A blanket check would
  # make this migration refuse a database the app itself would accept.
  def cross_account_failures(written)
    return [] if written.empty?

    crossing = MigrationMovement
               .where(id: written)
               .joins("JOIN pools f ON f.id = pool_movements.from_pool_id")
               .joins("JOIN pools t ON t.id = pool_movements.to_pool_id")
               .where("COALESCE(f.account_id, f.id) <> COALESCE(t.account_id, t.id)")
               .count

    crossing.zero? ? [] : ["#{crossing} movements written by this migration cross accounts"]
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

  # THE BALANCE FORMULA, ONCE, PARAMETERISED BY WHICH POOLS IT IS ABOUT. `PoolCalculator#balance`'s
  # terms in SQL: entries reaching a pool through `COALESCE(entries.pool_id, categories.pool_id)`,
  # signed by category type, plus both movement directions.
  #
  # ONE EXPRESSION FOR TWO QUESTIONS, and that is the point of it being a method. `Σ pools` asks it
  # about every pool a user owns; #pool_balances asks it about one pool at a time, to find the
  # envelopes step 5b has to zero. Written twice, the sum the migration verifies and the deficit it
  # pays could drift apart — and the invariant would still hold while the individual envelopes were
  # wrong, which is the exact failure `Σ pools` is blind to (see the comment on #zero_the_envelopes).
  #
  # The savings arm is deliberately still here even though the check beside it asserts no savings
  # entry survives. It is the app's formula reproduced, not the post-migration formula assumed —
  # a savings entry the conversion missed must show up as MONEY, not merely as a count.
  #
  # `::numeric` on every money column, because `money` in Postgres is a fixed-scale type whose
  # arithmetic with integers is its own business; the comparison this migration turns on is
  # between two exact decimals or it is between two roundings.
  #
  # WHAT IT COSTS, MEASURED RATHER THAN GUESSED. Three correlated sub-selects, and #pool_balances
  # runs them once PER POOL — so the shape is roughly `users × pools × entries` with no index able
  # to collapse the `COALESCE(entries.pool_id, categories.pool_id)` join. On the demo (1 user, 22
  # pools, 184 entries) the whole migration takes ~0.17s and it is not worth a line of tuning.
  # BEFORE A LARGE-SCALE RUN, MEASURE IT on a restored copy: at ten thousand users with hundreds of
  # entries each this becomes the migration's whole runtime, and the fix (one grouped pass over
  # entries and movements, joined back to pools, exactly as `PoolBalanceLedger` does it for screens)
  # is a rewrite of this method rather than of its callers. Left unoptimised on purpose — the code
  # a migration is verified with should be the code that is easiest to read and hardest to get
  # wrong, and this one runs once.
  def balance_expression(pools)
    <<~SQL.squish
      COALESCE((SELECT SUM(CASE WHEN c.category_type = #{EXPENSE_CATEGORY}
                                THEN -e.amount::numeric ELSE e.amount::numeric END)
                  FROM entries e
                  JOIN items i ON i.id = e.item_id
                  JOIN categories c ON c.id = i.category_id
                 WHERE COALESCE(e.pool_id, c.pool_id) #{pools}), 0)
      + COALESCE((SELECT SUM(m.amount::numeric) FROM pool_movements m WHERE m.to_pool_id #{pools}), 0)
      - COALESCE((SELECT SUM(m.amount::numeric) FROM pool_movements m WHERE m.from_pool_id #{pools}), 0)
    SQL
  end

  # `Σ pools`, KEYED BY POOL MEMBERSHIP.
  def pool_total(user_id)
    decimal("SELECT #{balance_expression('IN (SELECT id FROM pools WHERE user_id = :uid)')}", user_id)
  end

  # EVERY POOL OF ONE TYPE, WITH ITS OWN BALANCE — the same expression, correlated to each row of
  # `pools` instead of to a set. Answers `{ pool_id => BigDecimal }`.
  def pool_balances(user_id, pool_type)
    rows = ActiveRecord::Base.connection.select_rows(
      ActiveRecord::Base.sanitize_sql_array(
        ["SELECT p.id, #{balance_expression('= p.id')} FROM pools p WHERE p.user_id = :uid AND p.pool_type = :type",
         { uid: user_id, type: pool_type }]
      )
    )
    rows.to_h { |id, balance| [id, BigDecimal(balance.to_s)] }
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
        "#{counts[:housed]} pools housed; #{counts[:caps]} caps -> #{counts[:rules]} envelope rules; " \
        "#{counts[:pointed]} categories -> buffer; " \
        "#{counts[:deleted]} savings entries -> #{counts[:moved]} movements; " \
        "#{counts[:zeroed]} envelopes zeroed; " \
        "Σ pools #{format('%.2f', pooled)} == bank truth #{format('%.2f', bank)}"
  end
end
