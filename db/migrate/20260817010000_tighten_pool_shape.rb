# frozen_string_literal: true

# THE THREE POOL TIGHTENINGS THE BACKFILL UNBLOCKS (spec §7a, plan 3 task 6). Every one of them
# was written down as an obligation the day the column landed and deferred for the same reason:
# the database still held pre-cutover shapes that would have refused. `CutoverToEnvelopeBudgeting`
# houses every pool, dedupes every name and verifies both in raw SQL before it commits, so the
# three are now assertions about a database that already complies rather than changes to it.
#
# REVERSIBLE, as `change` — each of the three has an exact inverse (`change_column_default` is
# given both directions explicitly, an index and a check constraint drop by name). Rolling this
# back does NOT restore the rows it refuses; it restores the schema's permission to hold them,
# which is all a rollback can honestly promise. `spec/migrations/cutover_spec.rb` runs exactly
# that rollback to rebuild the world its subject migration was written for.
class TightenPoolShape < ActiveRecord::Migration[8.1]
  def change
    # `savings` WAS THE DEFAULT BECAUSE THE TABLE WAS `savings_pools` — every row in it was a
    # savings pool the day `pool_type` was added, so 2 was the only value that could not be wrong.
    # A pool is an envelope far more often than a goal now, spec §3's schema says `default: 1`,
    # and every path in the app writes the column explicitly (the form's select, the factories,
    # the cutover), so this default is only ever met by a raw INSERT that names no type — and the
    # ordinary pool this app makes is an envelope.
    change_column_default :pools, :pool_type, from: 2, to: 1

    # ONE NAME PER USER, CASE-INSENSITIVELY, AT THE DATABASE. `Pool` has validated this since Plan
    # 1 (`validates :name, uniqueness: { scope: :user_id, case_sensitive: false }`), and a
    # validation loses a race by construction: two requests that both read "no such name" both
    # write it. BudgetProposal's accept flow REUSES A POOL BY NAME — `Pool.find_by` on a
    # lower(name) match, then create if missing — so a duplicate is not a cosmetic annoyance
    # there, it is two envelopes splitting one lane's money with the picker showing one of them.
    #
    # Functional, not `[:user_id, :name]`: the model's rule is case-insensitive and an index on
    # the raw column would let "Groceries" and "groceries" both exist while the model refused
    # them, which is a guard that agrees with nothing.
    add_index :pools,
              "user_id, lower(name)",
              unique: true,
              name: "index_pools_on_user_id_and_lower_name"

    # EVERY POOL IS EITHER AN ACCOUNT OR LIVES IN ONE — spec §3.2's rule, at the database.
    #
    # NOT NULL CANNOT SAY THIS. An account's `account_id` is nil by the same rule that makes an
    # envelope's mandatory, so the column is nullable for one pool type and required for the other
    # two, and only a CHECK can hold both halves. Written as an equality between two booleans
    # rather than as an OR of two ANDs so that neither direction can be added without the other:
    # `(pool_type = 0) = (account_id IS NULL)` refuses an account that names a parent AND an
    # envelope or goal that names none.
    #
    # It cannot evaluate to NULL and pass by default — `pool_type` is NOT NULL and `IS NULL` never
    # returns NULL — so there is no third state for a row to hide in.
    #
    # WHAT IT DOES NOT SAY: that the named parent is an ACCOUNT of the SAME user. That is
    # `Pool#account_matches_pool_type`'s, and expressing it in SQL needs a subquery, which a CHECK
    # constraint may not contain. The cutover's `#house_the_pools` repairs exactly that shape and
    # its verifier refuses to commit while one survives.
    add_check_constraint :pools,
                         "(pool_type = 0) = (account_id IS NULL)",
                         name: "pools_account_matches_pool_type"
  end
end
