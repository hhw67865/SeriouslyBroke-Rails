# frozen_string_literal: true

# THE DISTRIBUTION IS GONE (computed-claims spec §5/§6/§7). A category's money is a CLAIM computed
# from its rules, the calendar, its spending and dated adjustments — so the purpose side has no
# movement left to record, and the table that recorded them is dropped.
#
# WHAT THE THREE KINDS ON `allocations` MEANT, AND WHAT EACH ONE BECOMES:
#
#   * `allocation` and `sweep` were DISTRIBUTION MECHANICS — the split a distribution wrote and the
#     leftover it took back. Both are now COMPUTED every time a screen asks (`ClaimCalculator`), so
#     the rows are not converted into anything: they are deleted. Keeping them would be keeping a
#     second, stale answer to a question the app now derives.
#   * `transfer` was a HAND MOVE: money set aside into a goal, released back out of one, or shifted
#     from one category to another. That is §3.3's adjustment exactly — `(rule, date, signed amount)`
#     — so every transfer is CONVERTED, at its own date, signed by direction.
#
# ONE TRANSFER CAN BECOME TWO ADJUSTMENTS, and that is the "sign by direction" rule applied to each
# END rather than to the row. A set-aside is `(NULL -> category)` and yields one positive row; a
# release is `(category -> NULL)` and yields one negative row; a category-to-category reallocation
# has TWO category ends and yields both — the source's fund really did fall by $100 and the
# destination's really did rise by $100, and converting only one end would be recording half of a
# move the user made whole. NULL is AVAILABLE, which has no rule and needs no row: under the computed
# model free money is `total − Σ claims` and is never written down.
#
# WHICH RULE A CATEGORY'S ADJUSTMENT LANDS ON. The category's ITEM-LESS rule — the one whose spending
# lane is the whole category (§3.1's partition), which is the lane the money was set aside for. A
# category carrying several rules has at most one of those (`Budget#category_may_hold_one_item_less_
# rule`), and a category carrying none gets one MINTED: §3.2's "no rate is spelled as ZERO", the
# target-only shape Henry ruled on 2026-09-03. Every claim comes from a rule, so a goal fed only by
# hand has to BE a rule.
#
# THE MINTED RULE IS A SHAPE THE APP ITSELF COULD HAVE WRITTEN, and #verify_the_minted_rules asks
# that in SQL rather than believing it. `Budget`'s four relevant validations are restated there,
# frozen at this moment in the sequence, because a migration that reaches into today's model is a
# migration whose meaning changes when the model does. It matters beyond tidiness:
# `CadenceChange#apply` writes `Budget#amount` through `update!` with NO rescue, so a rule this file
# minted in a shape the model refuses would reach a user as a 500 the first time they changed their
# period — from a row they never wrote and cannot see.
#
# THE MINTED RULE IS BORN BEFORE THE MONEY IT HOLDS, and this is the one column here that is not a
# copy of something. `ClaimCalculator#accrual_start` is `max(funded_since, the rule's birthday)` — a
# rule cannot accrue before it existed — so a rule minted TODAY would walk no period that any of the
# set-asides it inherits is dated in, and a goal a user has been feeding since January would read
# $0.00 built up the morning after this runs. Its `created_at` is therefore the EARLIER of the
# category's `funded_since` (midnight UTC, which is on or before that day in every zone) and the
# first transfer being converted onto it, which makes `accrual_start` land on `funded_since` — the
# day the category started holding money, which is precisely the day the claim starts counting (§7:
# "rules and `funded_since` stay and become the accrual anchors").
#
# HISTORY IS CONVERTED AT ITS ORIGINAL DATE, EVEN WHERE THE WALK CANNOT SEE IT. A rate rule's walk is
# the CURRENT period only, so a set-aside from March converted onto one lands outside its countable
# span and moves no figure — which is the honest answer, because a rate rule is use-it-or-lose-it and
# a March set-aside is not September's money. `AdjustmentForm` is the ONE door that refuses a date
# outside the span, and it is a door a PERSON types at; this is the user's own history and is written
# straight to the table. #verify! counts any row that lands before its category's funding date and
# says so in the receipt rather than leaving the operator to find it.
#
# WHAT IS NOT VERIFIED HERE, AND WHY IT WOULD BE THE WRONG TEST. The purpose side is no longer a
# conserved partition (§2): `free = total − Σ claims` is a DEFINITION, and claims are derived, so
# there is no "Σ holdings unchanged" for this migration to pin. What must not move is the PHYSICAL
# invariant, `pot + Σ accounts == income − expenses`, and this file writes nothing to
# `account_movements`, `pools` or `entries` at all — so it is measured per user in raw SQL before the
# first statement and again after the last, and every user must reconcile to the same figure on both
# sides. A migration that cannot move a number is exactly the one that should be made to prove it.
#
# A RE-RUN ON A MIGRATED DATABASE RAISES, LOUDLY AND ON PURPOSE (fix round 1 — L3). `up` drops
# `allocations`, so running this file a second time without its `down` reaches `#unknown_kinds` —
# the first statement past `#ledgers` — and gets `PG::UndefinedTable` from Postgres itself. That is
# the right failure: the alternative is a `to_regclass` guard that turns a second run into a silent
# no-op, and a silent no-op is indistinguishable from a run that converted nothing because there was
# nothing to convert. An operator re-running this file is either resuming an aborted run (the whole
# `up` is one transaction, so there is nothing half-done to resume) or is on the wrong database, and
# both want a stack trace rather than a shrug.
#
# THE `down` IS FOR THE SCHEMA REWIND, NOT FOR PRODUCTION — `DropThePoolLayer#down`'s law, and this
# file inherits it for the same mechanical reason. `spec/support/schema_rewind.rb` runs
# `CategoriesHoldTheMoney#up`, whose whole subject is CREATING `allocations` and filling it, so a
# `down` here that raised would leave three migration specs unable to rewind to the world their own
# subjects were written for. It restores the SHAPE. The deleted rows are gone and the converted ones
# are adjustments now: a real reversal is a restore from backup, and the header of the block says so.
class DropTheDistribution < ActiveRecord::Migration[8.1]
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationCategory < ActiveRecord::Base
    self.table_name = "categories"
  end

  class MigrationBudget < ActiveRecord::Base
    self.table_name = "budgets"
  end

  class MigrationAdjustment < ActiveRecord::Base
    self.table_name = "adjustments"
  end

  class MigrationAllocation < ActiveRecord::Base
    self.table_name = "allocations"
  end

  LOCAL_CLASSES = [MigrationUser, MigrationCategory, MigrationBudget, MigrationAdjustment,
                   MigrationAllocation].freeze

  # The integers as the schema holds them at this moment in the sequence, written out rather than
  # read off the app's enums — `Allocation` and its `kind` enum are deleted in the same commit as
  # this file, and a migration whose meaning changes with a model is a migration that rewrites
  # history. `budgets.basis`' per-period member and `categories.category_type`'s expense member are
  # here for the same reason.
  TRANSFER = 0
  ALLOCATION = 1
  SWEEP = 2
  EXPENSE = 0
  ACCOUNT = 0
  INCOME = 1
  PER_PERIOD = 1

  # Refusing the INPUT — raised before the first write. `CategoriesHoldTheMoney`'s two classes, kept
  # apart for its reason: "is this database convertible" and "did the conversion go wrong" need
  # different work from whoever reads the message.
  class PreflightFailed < StandardError; end

  # Refusing its own OUTPUT — raised after the last write, inside the Migrator's transaction, so a
  # database whose physical ledger stopped reconciling is never committed.
  class VerificationFailed < StandardError; end

  # THE DROP IS LAST AND #verify! IS SECOND TO LAST, AND BOTH POSITIONS ARE LOAD-BEARING. #verify!
  # reads `allocations` — it proves the table is EMPTY, which is what makes "every row was either
  # converted or deliberately discarded" a measured fact rather than a sentence — so it cannot run
  # after the table is gone. And the whole of `up` is inside one transaction (the Migrator wraps it
  # on PostgreSQL, DDL included), so a raise from #verify! rolls the drop, the deletes and the
  # conversion back together. Adding `disable_ddl_transaction!` would turn #verify! from a refusal
  # into a report; nothing here needs a statement Postgres refuses inside a transaction, so this note
  # exists so that a future one has to argue with it first.
  def up
    LOCAL_CLASSES.each(&:reset_column_information)
    before = ledgers
    preflight!
    receipts = convert_the_transfers
    receipts[:discarded] = delete_the_distribution_rows
    verify!(before, receipts)
    drop_table :allocations
  end

  def down
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
    add_check_constraint :allocations, "from_category_id IS DISTINCT FROM to_category_id",
                         name: "allocations_distinct_sides"
  end

  private

  # -----------------------------------------------------------------------------------------------
  # The refusals
  # -----------------------------------------------------------------------------------------------

  def preflight!
    failures = unknown_kinds + unfundable_ends
    return if failures.empty?

    raise PreflightFailed, failures.join("; ")
  end

  # AN ALLOCATION WHOSE KIND THIS FILE DOES NOT KNOW. `kind` carries no CHECK — the three members
  # lived in the enum alone — so a fourth integer is a row the conversion would skip and the delete
  # would miss, and the drop would then take it away without a word. There is no honest guess to make
  # about which of the two lanes it belongs in.
  def unknown_kinds
    named(<<~SQL.squish, "allocation %<id>s has kind %<extra>s, which this migration does not know")
      SELECT a.id, a.kind::text AS extra, u.email
        FROM allocations a
        JOIN categories c ON c.id = COALESCE(a.to_category_id, a.from_category_id)
        JOIN users u ON u.id = c.user_id
       WHERE a.kind NOT IN (#{TRANSFER}, #{ALLOCATION}, #{SWEEP})
       ORDER BY u.email, a.id
    SQL
  end

  # A CATEGORY AT A TRANSFER'S END THAT CAN NEITHER LEND A RULE NOR BE GIVEN ONE. The set-aside has
  # to land on a rule (§3.3: "every adjustment targets a rule"), and the minted shape is legal only
  # where the CATEGORY names a target — §3.2's "a dateless target … accrues by its rate if it has
  # one, and otherwise only by positive adjustments". Without one there is no honest rule to write:
  # inventing a `target_amount` would be inventing the user's goal, and giving the rule a positive
  # amount would be inventing a standing contribution they never declared.
  #
  # A COUNT OF ITS TRANSFERS COMES WITH THE NAME, because the fix is a decision about money: an
  # operator either gives the category a target and re-runs, or accepts that those set-asides were
  # bookkeeping and deletes them. Both need to know how much is at stake.
  #
  # THE INCOME ARM IS HERE TOO, though `Allocation#sides_must_be_expense_categories_of_one_user`
  # refuses one today: `Category#category_type` is editable, and a category flipped to income after
  # its transfers were written is a shape the live app can still be holding.
  def unfundable_ends
    template = "%<extra>s cannot take its %<id>s converted set-asides: it has no rule covering " \
               "all its spending and no target to mint one against"
    named(<<~SQL.squish, template)
      WITH ends AS (
        SELECT to_category_id AS cid, COUNT(*) AS n FROM allocations
         WHERE kind = #{TRANSFER} AND to_category_id IS NOT NULL GROUP BY 1
        UNION ALL
        SELECT from_category_id, COUNT(*) FROM allocations
         WHERE kind = #{TRANSFER} AND from_category_id IS NOT NULL GROUP BY 1
      )
      SELECT SUM(ends.n)::text AS id, c.name AS extra, u.email
        FROM ends
        JOIN categories c ON c.id = ends.cid
        JOIN users u ON u.id = c.user_id
       WHERE NOT EXISTS (SELECT 1 FROM budgets b WHERE b.category_id = c.id AND b.item_id IS NULL)
         AND (c.category_type <> #{EXPENSE} OR c.target_amount IS NULL)
       GROUP BY c.name, u.email
       ORDER BY u.email, c.name
    SQL
  end

  # `%<extra>s` is optional in the template, so one helper serves an arm that names a second fact and
  # one that does not. `format` raises on a key the template never uses only under `%{}`; the
  # `%<name>s` spelling ignores the surplus.
  def named(sql, template)
    select_all(sql).map do |row|
      "#{row["email"]}: #{format(template, id: row["id"], extra: row["extra"])}"
    end
  end

  # -----------------------------------------------------------------------------------------------
  # The conversion
  # -----------------------------------------------------------------------------------------------

  # EVERY TRANSFER, IN ONE PASS, ORDERED BY DATE AND THEN BY ID. The order changes no figure — an
  # adjustment is a dated row and sums with its neighbours whatever order it was written in — and it
  # is fixed anyway so that two runs of this file against one backup produce byte-identical tables,
  # which is what makes a diff of the two a usable audit.
  #
  # THE RULES ARE RESOLVED FIRST, FOR THE WHOLE SET. Minting inside the row loop would ask
  # "does this category have an item-less rule yet" against a table this loop is writing to, and the
  # second transfer onto a freshly-minted goal would mint a SECOND rule — the exact shape
  # `Budget#category_may_hold_one_item_less_rule` refuses. One map, built once, is also what keeps
  # the mint count honest.
  def convert_the_transfers
    transfers = MigrationAllocation.where(kind: TRANSFER).order(:date, :id).to_a
    rule_of, minted = resolve_rules(transfers)

    rows = transfers.flat_map { |transfer| adjustment_rows(transfer, rule_of) }
    MigrationAdjustment.insert_all!(rows) if rows.any?
    MigrationAllocation.where(id: transfers.map(&:id)).delete_all if transfers.any?

    { transfers: transfers.length, adjustments: rows.length, minted: minted.length,
      per_user: tally(transfers, rows, minted) }
  end

  # THE PER-USER RECEIPT, TALLIED IN RUBY OVER THE ROWS THIS RUN ACTUALLY WROTE. An earlier draft
  # asked the database for it afterwards and had to identify "this run's writes" by their timestamp
  # — a mark that is right until two runs share a second, and one that cannot count the transfers at
  # all once they have been deleted. The objects are in hand here; counting them is exact.
  #
  # A TRANSFER'S OWNER IS READ OFF WHICHEVER END IT HAS, because `Allocation
  # #sides_must_be_expense_categories_of_one_user` makes both ends one user's wherever there are two.
  def tally(transfers, rows, minted)
    owner_of = owners(transfers.flat_map { |t| [t.to_category_id, t.from_category_id] }.compact)
    counts = Hash.new { |hash, email| hash[email] = { transfers: 0, adjustments: 0, minted: 0 } }
    transfers.each { |t| counts[owner_of[t.to_category_id || t.from_category_id]][:transfers] += 1 }
    rows.each { |row| counts[owner_of[rule_owner_category(row)]][:adjustments] += 1 }
    minted.each_key { |category_id| counts[owner_of[category_id]][:minted] += 1 }
    counts
  end

  def owners(category_ids)
    return {} if category_ids.empty?

    @owners ||= {}
    missing = category_ids.uniq - @owners.keys
    @owners.merge!(select_all(<<~SQL.squish).to_h { |row| [row["id"], row["email"]] }) if missing.any?
      SELECT c.id, u.email FROM categories c JOIN users u ON u.id = c.user_id
       WHERE c.id IN (#{missing.map { |id| connection.quote(id) }.join(", ")})
    SQL
    @owners
  end

  # An adjustment row's category, through the rule it was written onto — the reverse of the map the
  # rows were built from, so a row and its owner cannot come apart.
  def rule_owner_category(row)
    @category_of_rule ||= {}
    @category_of_rule[row[:rule_id]] ||= MigrationBudget.where(id: row[:rule_id]).pick(:category_id)
  end

  # ONE ROW PER CATEGORY END. `to_category_id` is money arriving and is POSITIVE; `from_category_id`
  # is money leaving and is NEGATIVE. A NULL end is AVAILABLE and contributes nothing — it has no
  # rule, and free money is computed rather than recorded.
  #
  # `date` IS COPIED VERBATIM, datetime to datetime, so the row lands in whatever period the user's
  # grid puts that instant in — §3.3's "period-cadence changes are free" is exactly the property that
  # makes copying the instant the right move rather than re-keying it to a period.
  #
  # ** AND THE AMOUNT NEEDS NO GUARD, WHICH IS A FACT ABOUT THE SCHEMA RATHER THAN AN ASSUMPTION
  # (fix round 1 — L2). ** `adjustments` carries `amount <> 0::money`
  # (`adjustments_non_zero_amount`), so a zero copied through here would be an unrescued
  # `StatementInvalid` in the middle of `insert_all!` — no receipt, no named row, just a raise.
  # It cannot happen: `allocations` has carried `amount > 0::money`
  # (`allocations_positive_amount`) since `588c15d`, so every row this loop reads is strictly
  # positive and `× ±1` keeps it non-zero. `drop_the_distribution_spec`'s "cannot be handed a
  # zero-amount transfer to convert" asserts the constraint rather than the reasoning, so dropping
  # it from under this file is a failing example rather than a 500 on somebody's restore.
  def adjustment_rows(transfer, rule_of)
    [[transfer.to_category_id, 1], [transfer.from_category_id, -1]].filter_map do |category_id, sign|
      next if category_id.nil?

      { id: SecureRandom.uuid, rule_id: rule_of.fetch(category_id), date: transfer.date,
        amount: transfer.amount.to_d * sign, created_at: now, updated_at: now }
    end
  end

  # THE ITEM-LESS RULE IF THERE IS ONE, ORDERED SO THAT A LEGACY DUPLICATE RESOLVES THE SAME WAY
  # TWICE. `category_may_hold_one_item_less_rule` is younger than the data it guards, so a real
  # database may hold two catch-all rules on one category — `SuggestionEngine#attributable_rate_rules`
  # keeps its own `rules.one?` guard for exactly that reason. The OLDEST is chosen because it is the
  # one whose accrual window reaches furthest back, so the set-asides being converted onto it are the
  # most likely to land inside a span the walk visits.
  #
  # `.reverse` IS WHAT MAKES "OLDEST" TRUE AND IT IS THE ONE LINE HERE THAT READS BACKWARDS. `to_h`
  # over an array of pairs keeps the LAST value for a repeated key, so ordering oldest-first and
  # reversing puts the oldest LAST and therefore in the map. Written this way rather than as a
  # descending `order` because the ORDER BY is what the comment above is about, and a reader should
  # meet "oldest first" in the query rather than have to invert a `DESC` in their head.
  def resolve_rules(transfers)
    category_ids = transfers.flat_map { |t| [t.to_category_id, t.from_category_id] }.compact.uniq
    existing = MigrationBudget.where(category_id: category_ids, item_id: nil)
                              .order(:created_at, :id).pluck(:category_id, :id).reverse.to_h
    minted = (category_ids - existing.keys).sort.to_h do |category_id|
      [category_id, mint_rule(category_id, transfers)]
    end

    [existing.merge(minted), minted]
  end

  # THE TARGET-ONLY SHAPE (§3.2, Henry's ruling of 2026-09-03): amount ZERO, no anchor, no interval,
  # per-period basis, no item. `Budget#set_aside_only?` is the predicate that permits the zero and it
  # names all three of those columns; `#shape_must_be_valid` is what forces the basis, since a
  # monthly-basis rule with neither an anchor nor an interval is refused outright.
  #
  # See the header for why `created_at` reaches back: `ClaimCalculator#accrual_start` is
  # `max(funded_since, the rule's birthday)`, and a rule born today holds none of the history being
  # converted onto it.
  def mint_rule(category_id, transfers)
    category = MigrationCategory.find(category_id)
    MigrationBudget.create!(
      id: SecureRandom.uuid, category_id: category_id, item_id: nil, amount: 0,
      basis: PER_PERIOD, anchor_date: nil, interval_months: nil,
      created_at: birthday_for(category, transfers), updated_at: now
    ).id
  end

  # MIDNIGHT UTC ON THE FUNDING DATE IS ON OR BEFORE THAT DAY IN EVERY ZONE — east of UTC it reads as
  # the same day and west of it as the day before — so `accrual_start` lands on `funded_since` itself
  # whichever way the owner's clock runs. A category with no funding date at all (nothing in the app
  # writes a rule onto one, but the column is nullable) falls back to the first transfer it is about
  # to inherit, which is the earliest day this rule could need to count from.
  def birthday_for(category, transfers)
    first_transfer = transfers.select { |t| [t.to_category_id, t.from_category_id].include?(category.id) }
                              .map(&:date).min
    funded = category.funded_since&.to_time(:utc)
    [funded, first_transfer].compact.min || now
  end

  # THE MECHANICS, DELETED RATHER THAN CONVERTED (§7): "existing `allocation`/`sweep` rows were
  # distribution mechanics — their effect is now computed". `delete_all` in one statement, and there
  # is no model left to run a callback on by the time this commit is finished.
  def delete_the_distribution_rows
    MigrationAllocation.where(kind: [ALLOCATION, SWEEP]).delete_all
  end

  # -----------------------------------------------------------------------------------------------
  # The verification, and the receipt
  # -----------------------------------------------------------------------------------------------

  def verify!(before, receipts)
    failures = drift(before) + surviving_allocations + malformed_minted_rules
    raise VerificationFailed, failures.join("; ") if failures.any?

    report(before, receipts)
  end

  # EVERY USER, ON BOTH SIDES, AND THE COMPARISON IS AGAINST THE PRE-CONVERSION FIGURE rather than
  # against bank truth alone — `DropThePoolLayer#verify!`'s reason: a change that moved money from one
  # term into the other by the same amount would satisfy "physical == bank" and still be wrong.
  def drift(before)
    after = ledgers
    before.flat_map do |id, was|
      now_figures = after[id]
      next ["#{was[:email]}: vanished from the users table"] if now_figures.nil?

      [:physical, :bank].filter_map do |side|
        "#{was[:email]}: #{side} was #{was[side].to_f}, is #{now_figures[side].to_f}" unless was[side] == now_figures[side]
      end
    end
  end

  # THE TABLE IS EMPTY BEFORE IT IS DROPPED, which is what makes "every row was either converted or
  # deliberately discarded" a fact rather than an intention. Without it a row this file's two lanes
  # both miss — a fourth kind slipped past #unknown_kinds, say — would leave with the table and
  # nobody would ever know it had been there.
  def surviving_allocations
    count = select_value("SELECT COUNT(*) FROM allocations").to_i
    count.zero? ? [] : ["#{count} allocations were neither converted nor discarded"]
  end

  # ** `Budget`'S VALIDATIONS, RESTATED IN SQL — CLAUSE FOR CLAUSE, AND NO CLAUSE MORE (fix round
  # 1 — M1). ** Every disjunct below names the model method it mirrors, and the SQL says what that
  # method says about an `amount = 0` rule and nothing else:
  #
  #   * `b.basis <> PER_PERIOD`, `b.anchor_date IS NOT NULL`, `b.interval_months IS NOT NULL` —
  #     `#shape_must_be_valid` (a per-period rule carries no anchor and no interval) closed against
  #     `#set_aside_only?` (a MONTHLY rule with neither is refused by that same method, so the
  #     dateless zero can only be per-period);
  #   * `c.target_amount IS NULL` — `#set_aside_only?`'s third clause, which is what makes
  #     `validates :amount … greater_than_or_equal_to: 0, if: :set_aside_only?` apply at all;
  #   * `c.category_type = INCOME` — `#category_must_be_an_expense`, which asks `category&.income?`
  #     rather than `!expense?` for the reason stated at the model: a third type added later is a
  #     decision somebody has to make, not one this clause makes silently;
  #   * the gated `EXISTS` — `#category_may_hold_one_item_less_rule`, INCLUDING ITS `return if
  #     item_id.present?`, which is the clause this verifier used to be missing.
  #
  # ** IT WAS STRICTER THAN THE MODEL AND THAT WAS A LIVE ABORT. ** The SQL flagged
  # `b.item_id IS NOT NULL` outright and applied the one-catch-all rule to item-BACKED rows too.
  # `#set_aside_only?` never reads `item_id`, so a per-period, amount-0, item-backed rule on a
  # category with a `target_amount` is a shape the app ACCEPTS — a goal whose flights line is fed by
  # hand — and a restore carrying one row of it aborted the whole migration on a verdict `Budget`
  # does not share. A verifier that refuses what the model accepts is not conservative; it is wrong
  # in the direction nobody can work around.
  #
  # WHAT IS DELIBERATELY NOT RESTATED: `#item_must_belong_to_category` and `#item_must_not_be_claimed`
  # are about which item a rule names, and this file mints only ITEM-LESS rules — so omitting them
  # leaves the verifier blind to a shape it cannot itself create, which is the safe direction. Being
  # STRICTER than `Budget` is the failure mode this method has already had once.
  #
  # WHY THEY ARE COPIED HERE RATHER THAN CALLED. `Budget.new(...).valid?` would make this migration's
  # verdict depend on the model as it stands whenever the file is next run, which is the hazard every
  # constant at the top of this class is written out to avoid — and it would also read `#set_aside_
  # only?`, a predicate that reaches for `categories.target_amount`, against a schema the rewind may
  # have moved. Copied, they are frozen at this moment in the sequence and the divergence is visible
  # in a diff of the two files rather than in a 500 a year from now.
  #
  # SCOPED BY `amount = 0`, WHICH IS THE ONLY MARK A MINTED RULE CARRIES. It is deliberately wider
  # than "the rules this run minted": a zero-amount rule written by any earlier run of this file, or
  # by the Budget page, is held to the same shape, and there is no id list to carry between two
  # methods for it to fall out of. That width is exactly why the clauses have to match `Budget`
  # exactly: they are asked of rows this file never wrote.
  def malformed_minted_rules
    named(<<~SQL.squish, "the target-only rule on %<extra>s is a shape the app would refuse (%<id>s)")
      SELECT b.id::text AS id, c.name AS extra, u.email
        FROM budgets b
        JOIN categories c ON c.id = b.category_id
        JOIN users u ON u.id = c.user_id
       WHERE b.amount = 0::money
         AND (b.basis <> #{PER_PERIOD}
           OR b.anchor_date IS NOT NULL
           OR b.interval_months IS NOT NULL
           OR c.target_amount IS NULL
           OR c.category_type = #{INCOME}
           OR (b.item_id IS NULL
               AND EXISTS (SELECT 1 FROM budgets o
                            WHERE o.category_id = b.category_id AND o.item_id IS NULL AND o.id <> b.id)))
       ORDER BY u.email, c.name
    SQL
  end

  # ONE LINE PER USER WHO HAD ANY OF THIS, plus the totals. A per-user receipt is what lets an
  # operator match this run against the screens afterwards; a total alone says only that something
  # happened.
  #
  # THE LAST CLAUSE IS THE ONE WORTH READING TWICE. A converted row dated before its category's
  # funding day falls outside every period `ClaimCalculator` walks, so it is written, correct, and
  # invisible — see the header for why it is converted anyway. It is counted here so that "invisible"
  # is something the operator was told rather than something they discover.
  def report(before, receipts)
    stranded = adjustments_before_their_funding_day
    receipts[:per_user].sort.each do |email, counts|
      say "#{email}: #{counts[:transfers]} transfers -> #{counts[:adjustments]} adjustments; " \
          "#{counts[:minted]} target-only rules minted"
    end
    say "#{receipts[:transfers]} transfers converted into #{receipts[:adjustments]} adjustments; " \
        "#{receipts[:minted]} rules minted; #{receipts[:discarded]} allocation/sweep rows discarded"
    say "#{stranded} converted rows are dated before their category started holding money and count nowhere" if stranded.positive?
    before.each_value { |was| say "#{was[:email]}: physical #{was[:physical].to_f} == bank #{was[:bank].to_f}, unchanged" }
  end

  # THE ROWS THIS RUN WROTE, marked by the one instant `#now` stamps every one of them with. It is a
  # count rather than a list because the fix is never per row: either the funding date is wrong or
  # the set-asides predate the category's own history, and both are answered once for the category.
  def adjustments_before_their_funding_day
    select_value(<<~SQL.squish).to_i
      SELECT COUNT(*)
        FROM adjustments a
        JOIN budgets b ON b.id = a.rule_id
        JOIN categories c ON c.id = b.category_id
        JOIN users u ON u.id = c.user_id
       WHERE a.created_at >= '#{now.utc.iso8601(6)}'
         AND c.funded_since IS NOT NULL
         AND (a.date AT TIME ZONE 'UTC' AT TIME ZONE COALESCE(u.timezone, 'UTC'))::date < c.funded_since
    SQL
  end

  # -----------------------------------------------------------------------------------------------
  # The physical invariant, before and after
  # -----------------------------------------------------------------------------------------------

  # `DropThePoolLayer#ledgers`, with the PURPOSE term dropped and for the reason the header gives:
  # after this migration there is no purpose-side partition to be a partition OF. Read straight from
  # the tables rather than through `AccountLedger`, on the cutover's rule — asking a reader to referee
  # a migration of its own tables means a wrong term answers wrong on both sides of the comparison.
  def ledgers
    select_all("SELECT id, email FROM users ORDER BY created_at, id").to_h do |row|
      [row["id"], { email: row["email"], physical: physical_total(row["id"]), bank: bank_total(row["id"]) }]
    end
  end

  # `pot + Σ accounts`. Every account movement has both ends inside the user's own accounts, so the
  # two sums cancel and this equals bank truth — which is the invariant, said as an expression rather
  # than asserted.
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

  # ONE INSTANT FOR THE WHOLE RUN, memoised: it stamps every row this file writes AND it is the mark
  # `#per_user` reads them back by, so two readings of the clock would leave the receipt counting a
  # subset of its own writes.
  def now = @now ||= Time.current
end
