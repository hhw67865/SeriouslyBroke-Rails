# frozen_string_literal: true

# THE CAP'S LAST TWO COLUMNS (spec §7a, plan 3 task 6). `budgets.category_id` was how a rule found
# its owner when a rule WAS a monthly cap on a category; `budgets.prorated` spread that cap across
# the days of the month to print an "expected by today" line. A rule is owned by a POOL now
# (§6.1), plan 3 task 3 deleted the Ruby on both sides — the association, the permitted parameter,
# the pace arithmetic and the form's switch — and `CutoverToEnvelopeBudgeting` nulled
# `category_id` on every surviving row and verified that it had. Two columns nothing reads and
# nothing may write.
#
# ORDERED AFTER THE CUTOVER BY TIMESTAMP, AND THAT IS LOAD-BEARING. The cutover reads and writes
# both columns — it moves each cap onto its envelope in place — so a database migrating from
# before it runs the cutover first, against a schema that still has them, and meets this drop
# afterwards. Nothing in the cutover is made conditional on the columns' existence: a migration is
# a statement about the schema at ITS OWN moment in the sequence, and teaching it to survive a
# later schema would be teaching it to be a different migration.
#
# The one file that has to know is `spec/migrations/cutover_spec.rb`, which runs against the
# CURRENT schema rather than the historical one. It rolls this migration back for the duration of
# the file — see its `#rewind_the_schema_to_the_cutover` — which is also what proves the `down`
# below correct.
#
# EXPLICIT `up`/`down` rather than `change`: the inverse has to restore the index and the foreign
# key as well as the columns, and spelling it out is cheaper to read (and to trust) than
# remembering which `remove_reference` options survive inversion.
class DropCapEraBudgetColumns < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :budgets, :categories
    # The index goes with the column; Postgres drops `index_budgets_on_category_id` itself.
    remove_column :budgets, :category_id
    remove_column :budgets, :prorated
  end

  def down
    add_column :budgets, :category_id, :uuid
    add_index :budgets, :category_id
    add_foreign_key :budgets, :categories
    add_column :budgets, :prorated, :boolean, default: false, null: false
  end
end
