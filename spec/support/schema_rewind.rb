# frozen_string_literal: true

require Rails.root.join("db/migrate/20260817010000_tighten_pool_shape")
require Rails.root.join("db/migrate/20260817020000_drop_cap_era_budget_columns")
require Rails.root.join("db/migrate/20260821000000_categories_hold_the_money")

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
# It also carries the second reason this file exists at all: `two_ledger_spec` is a spec whose
# subject is the NEWEST migration, so the current schema is the world AFTER it and `add_column`
# would meet its own columns. That spec includes this context with one name.
#
#   include_context "with the schema its subject was written for",
#                   TightenPoolShape, DropCapEraBudgetColumns, CategoriesHoldTheMoney
#
# Named in the order they run FORWARD; the rewind reverses them itself.
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
