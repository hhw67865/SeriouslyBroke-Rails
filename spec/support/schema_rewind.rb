# frozen_string_literal: true

require Rails.root.join("db/migrate/20260817010000_tighten_pool_shape")
require Rails.root.join("db/migrate/20260817020000_drop_cap_era_budget_columns")
require Rails.root.join("db/migrate/20260821000000_categories_hold_the_money")
require Rails.root.join("db/migrate/20260821010000_drop_the_pool_layer")
require Rails.root.join("db/migrate/20260903010000_drop_the_distribution")
require Rails.root.join("db/migrate/20260905010000_rules_own_the_budget")
require Rails.root.join("db/migrate/20260906000000_two_shapes")

# THE SCHEMA A MIGRATION WAS WRITTEN FOR, REBUILT FOR THE LENGTH OF A FILE.
#
# Every other spec in the project runs against the CURRENT schema, and for every other subject
# that is the right schema to run against. A spec whose subject is a MIGRATION is the exception: a
# migration is a statement about the schema at its own moment in the sequence, and plan 3 task 6
# added two tightenings AFTER `CutoverToEnvelopeBudgeting` by timestamp —
#
#   * `DropCapEraBudgetColumns` removes `budgets.category_id` and `budgets.prorated`, the two
#     columns the cutover moves a cap THROUGH (step 3 reads `category_id` to find the cap's owner
#     and nulls it as it re-points the rule at an envelope);
#   * `TightenPoolShape` adds `CHECK ((pool_type = 0) = (account_id IS NULL))`, which refuses the
#     account-less goal step 2 exists to house — past the model, so `validate: false` cannot plant
#     it either.
#
# A database migrating from before the cutover never meets this problem: it runs the cutover
# first, against a schema that still has both, and meets the tightenings afterwards. So the fix is
# on the SPEC's side, which is the same move `spec/migrations/cutover_spec.rb`'s planting helpers
# make for the same reason — the world a migration is written for is not the world it is tested
# from, and it is the TEST that travels. Teaching the migration to survive a later schema would be
# making it a different migration, one whose behaviour on a real legacy database nothing tests.
#
# `migrate(:down)` and back up, rather than hand-written DDL: it is the same code `db:rollback`
# runs, so a `down` that fails to restore what `up` removed fails HERE, in the file that depends
# on it, instead of in production. Both directions of every named migration are exercised on every
# run of every file that includes this.
#
# `before(:all)` deliberately, and it is the reason this is a shared context rather than a
# `let`: the schema is not per-example state, the example transactions roll back over it either
# way, and rebuilding it per example would be dozens of DDL round trips to make no difference.
#
# A THIRD MIGRATION JOINED THE LIST WITH THE TWO-LEDGER PLAN, and it is the reason the list is
# ordered rather than a set. `CategoriesHoldTheMoney` runs AFTER both tightenings by timestamp and
# it re-adds `budgets.category_id` — the very column `DropCapEraBudgetColumns` removed — so the two
# `down`s must meet in the right order or the second one adds a column the first has not yet
# dropped and Postgres refuses it. Newest first on the way down, oldest first on the way back up,
# which is exactly `db:rollback` followed by `db:migrate` and exactly what `#step_the_schema` does
# with `tightenings.reverse`.
#
# It also carries the second reason this file exists at all: a spec whose subject is the NEWEST
# migration runs against the world AFTER it, where its own `add_column` would meet its own columns.
# `two_ledger_spec` and `drop_the_pool_layer_spec` each include this context with `described_class`
# for exactly that.
#
# A FOURTH MIGRATION JOINED WITH THE DROP, and it is the one that makes the ORDER load-bearing for
# every file rather than for one: `DropThePoolLayer` deletes `budgets.pool_id`, `categories.pool_id`,
# `entries.pool_id` and the `pool_movements` TABLE NAME, which is the whole world the two older
# migration specs plant in. Its `down` has to run FIRST on the way down — before
# `CategoriesHoldTheMoney#down` takes `budgets.category_id` away from under the NOT NULL this one
# lifts — and LAST on the way back up.
#
#   include_context "with the schema its subject was written for",
#                   TightenPoolShape, DropCapEraBudgetColumns, CategoriesHoldTheMoney, DropThePoolLayer
#
# Named in the order they run FORWARD; the rewind reverses them itself.
#
# ** A FIFTH MIGRATION JOINED WITH THE COMPUTED CLAIMS, AND IT IS THE ONE EVERY OTHER FILE ON THE
# LIST NOW DEPENDS ON. ** `DropTheDistribution` (2026-09-03) DROPS the `allocations` table, and
# `allocations` is the table `CategoriesHoldTheMoney#up` creates and fills — so its `down` has to
# restore the table before that `up` can run, which puts it FIRST on the way down and LAST on the way
# back up. Every one of the three older migration specs therefore names it at the END of its own
# forward list:
#
#   include_context "with the schema its subject was written for",
#                   TightenPoolShape, DropCapEraBudgetColumns, CategoriesHoldTheMoney,
#                   DropThePoolLayer, DropTheDistribution
#
# ITS `down` RESTORES THE SHAPE AND NOT THE ROWS, on `DropThePoolLayer#down`'s law and for the same
# mechanical reason this paragraph exists: a `down` that raised — which is what a data migration's
# `down` would honestly be — would leave those three specs with no way to reach the world their own
# subjects were written for. The converted rows are adjustments now and the discarded ones are gone;
# a real reversal is a restore from backup, and the migration's own header says so.
#
# ** A SIXTH MIGRATION JOINED WITH THE RULE TYPES, AND IT IS NEWER THAN ALL FIVE (rules-own-the-budget
# §6). ** `RulesOwnTheBudget` (2026-09-05) DROPS `categories.target_amount`, and that column is read
# or written by TWO migrations already on this list — `CategoriesHoldTheMoney#up` fills it from a
# pool's own target and its `down` removes it, and `DropTheDistribution#up` reads it in both
# `#unfundable_ends` and `#malformed_minted_rules`. So its `down` (which re-adds the column and
# copies each building rule's figure back onto its category) has to run FIRST on the way down, before
# `CategoriesHoldTheMoney#down` can remove a column that is not there, and LAST on the way back up.
# Every one of the four older migration specs therefore names it at the END of its own forward list:
#
#   include_context "with the schema its subject was written for",
#                   TightenPoolShape, DropCapEraBudgetColumns, CategoriesHoldTheMoney,
#                   DropThePoolLayer, DropTheDistribution, RulesOwnTheBudget
#
# ** A SEVENTH JOINED WITH THE TWO SHAPES, AND IT IS NEWER THAN ALL SIX (two-shapes §6). **
# `TwoShapes` (2026-09-06) DROPS `budgets.carries_over` and `budgets.target_amount`, and BOTH are
# read or written by `RulesOwnTheBudget` — its `up` moves a category's figure onto the rule and sets
# the flag, and its `down` copies that figure back the other way. So this file's `down` (which
# re-adds the two columns and the CHECK) has to run FIRST on the way down, before `RulesOwnTheBudget`
# can write columns that are not there, and LAST on the way back up. Every one of the five older
# migration specs therefore names it at the END of its own forward list:
#
#   include_context "with the schema its subject was written for",
#                   TightenPoolShape, DropCapEraBudgetColumns, CategoriesHoldTheMoney,
#                   DropThePoolLayer, DropTheDistribution, RulesOwnTheBudget, TwoShapes
#
# ITS `down` RESTORES THE SHAPE AND NOT THE DATA — a rule this file converted stays a dated one-off,
# because the building shape has no code left to compute it. What the rewound specs need is the
# COLUMN, and the column is what they get; the rules they plant are their own, written after the
# rewind.
#
# ITS `down` DOES NOT TOUCH `budgets.carries_over`, `budgets.target_amount` OR `budgets.rule_type`,
# which is why `RulesOwnTheBudgetColumns` is NOT on this list: those columns belong to that file, no
# `down` here gives or takes them away, and adding it would put a `down` in the list that no `up` in
# the list depends on — the dead-entry shape the `CreateAdjustments` paragraph above rules out.
#
# ** `CreateAdjustments` (2026-09-03) IS DELIBERATELY NOT ON THAT LIST, AND THE MEASUREMENT IS WHY. **
# It is newer than the first four and older than the fifth, so the question is live in both
# directions; it is left out because it touches NOTHING any
# rewound migration gives or takes away. It adds a table of its own whose only foreign key is to
# `budgets.id`, and no `down` here drops `budgets` or its primary key — `CategoriesHoldTheMoney#down`
# removes `budgets.category_id`, which the adjustments table has never read. Measured by running all
# three migration files against the current schema with it left out: cutover 49, two_ledger 15,
# drop_the_pool_layer 18, every one green.
#
# Adding it anyway would cost every migration spec a create/drop cycle of a table nothing in them
# plants, and would leave a `down` in the list that no `up` in the list depends on — a dead entry
# that reads as a dependency. The rule this file follows is that a migration joins the list when a
# rewound `down` would collide with it, and this one does not.
RSpec.shared_context "with the schema its subject was written for" do |*tightenings|
  # rubocop:disable RSpec/BeforeAfterAll
  before(:all) { step_the_schema(:down, tightenings.reverse) }

  after(:all) { step_the_schema(:up, tightenings) }
  # rubocop:enable RSpec/BeforeAfterAll

  # `reset_column_information` on every model the DDL can touch, and it is not optional: the
  # columns come and go inside one process, and a `Budget` whose attribute set was cached before
  # the rewind has no `category_id=` for a fixture to call. `Category` joined the list with
  # `CategoriesHoldTheMoney`, which gives and takes away three of its columns.
  def step_the_schema(direction, migrations)
    migrations.each do |migration|
      instance = migration.new
      instance.suppress_messages { instance.migrate(direction) }
    end
    [Budget, Category, Entry, Pool].each(&:reset_column_information)
  end
end
