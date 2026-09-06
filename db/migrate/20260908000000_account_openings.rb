# frozen_string_literal: true

# ** TWO COLUMNS, AND BETWEEN THEM THEY ARE "THE OPENING RECORD" (account-openings spec §2). **
#
# The old onboarding asked two questions — fund each account with a movement (step 2), then correct
# main with one entry (step 3) — and neither answer was addressable afterwards. The new question is
# asked once per account, "what's in it right now", and its answer has to be FINDABLE later, because
# correcting a balance REWRITES that account's own opening record rather than writing a second one.
#
#   `pools.opened_on`             — the day this account said what it holds. NULL means it has not
#                                   said yet, which is the whole of `HomePresenter#awaiting_opening?`.
#   `entries.opening_account_id`  — which account's opening this entry IS.
#
# ** WHY `opened_on` EXISTS AT ALL, WHEN THE ENTRY WOULD SEEM TO BE THE RECORD. ** Two reasons, and
# either alone is enough:
#
#   * ZERO IS A REAL ANSWER. "What's in it right now" is $0.00 for an account a user has opened and
#     not yet moved money into, and `Entry` validates `amount > 0` — so an opening of zero has NO
#     entry to be, and an account that stated zero would otherwise be indistinguishable from one that
#     never answered. Onboarding would never complete for that user.
#   * THE OPENING DAY MUST NOT DRIFT. Spec §2: "The record's date stays the opening day." The day is
#     `the day before the user's earliest non-opening entry, else today`, which MOVES as the user
#     records older history — so it is computed once, at the first save, and read from this column
#     forever after. Recomputing it on every correction would walk the record backwards through the
#     user's history a day at a time.
#
# ** WHY THE ENTRY CARRIES THE ACCOUNT AND NOT THE OTHER WAY ROUND. ** A user has ONE `Opening
# Balance` category (and, when an account is stated below what the app has tracked, one `Opening
# Shortfall`), so the category cannot say which account an entry is the opening of — every account's
# opening lives in the same one. The unique index is the "never a second entry" half of §2 made
# structural: a correction that failed to find the existing row would be refused by the database
# rather than quietly leaving two.
#
# ** THE MOVEMENT NEEDS NO MARKER OF ITS OWN. ** A non-main account's opening is an entry PLUS one
# transfer, and the transfer already has the link this app uses for exactly that pairing:
# `account_movements.source_entry_id`, which `Entry#route_income_to!` writes and `Entry#routed_account`
# reads. The opening movement is the one whose `source_entry` is the opening entry — which survives
# a rename, a date change, and (the shape a structural "the movement dated the opening day from main
# to this account" match would get wrong) a user's own transfer made on the very same day, since a
# user's transfer names no source entry.
#
# `entries.opening_account_id` IS NOT `entries.pool_id` COMING BACK (two-ledger §5 dropped that one).
# That column said WHERE AN ENTRY LANDED — a lane the ledger read for every entry the user owned.
# This one says an entry IS an account's opening, is NULL on every ordinary entry, and no balance
# reader looks at it: `AccountLedger` is untouched by this migration and by the spec (§4).
class AccountOpenings < ActiveRecord::Migration[8.1]
  def up
    add_column :pools, :opened_on, :date

    add_column :entries, :opening_account_id, :uuid
    add_foreign_key :entries, :pools, column: :opening_account_id
    add_index :entries, :opening_account_id, unique: true

    backfill_the_old_onboarding
  end

  # ** WHAT THE OLD ONBOARDING ALREADY ANSWERED IS NOT ASKED AGAIN. ** Without this, every account in
  # the database reads `opened_on IS NULL` — "has never said what it holds" — and a user who finished
  # the old two-step setup years ago opens Home to a card asking for all of it again, with their
  # accounts pulled out of the money row's "Elsewhere" tile and the accounts line while they wait.
  # The old steps map onto the new record exactly:
  #
  #   STEP 3 (the one-time main correction) → MAIN's opening record. Its entry is adopted outright:
  #     `opening_account_id` points it at main, so the next **Edit balance** REWRITES that row rather
  #     than writing a second one (§2: "never a second entry"). The record's date is the entry's own,
  #     which is where the opening-day rule already put it.
  #   STEP 2 (one movement from main per account) → EVERY OTHER FUNDED ACCOUNT's opening record. The
  #     movement stays exactly where it is: it is a flow like any other, and the account's first
  #     correction subtracts it and writes the opening entry it never had — which is the
  #     pre-existing-account case §2 already describes.
  #
  # AN ACCOUNT NOTHING HAS EVER MOVED INTO KEEPS ITS NULL, because that user genuinely never answered
  # for it — it was sitting on onboarding step 2's card when this shipped, and it gets a row in the
  # new card instead. Same for a main account whose correction was never recorded.
  def backfill_the_old_onboarding
    say_with_time("adopting each user's opening-balance entry as their main account's record") do
      adopt_main_corrections
    end

    say_with_time("marking every account a movement has funded as having answered") do
      execute(<<~SQL.squish)
        UPDATE pools p
           SET opened_on = m.first_day
          FROM (SELECT to_pool_id, MIN(date)::date AS first_day FROM account_movements GROUP BY to_pool_id) m
         WHERE p.id = m.to_pool_id
           AND p.opened_on IS NULL
           AND p.id NOT IN (SELECT default_account_id FROM users WHERE default_account_id IS NOT NULL)
      SQL
    end
  end

  # `DISTINCT ON (u.id) … ORDER BY u.id, e.date` takes ONE entry per user — the earliest — because
  # `entries.opening_account_id` is unique and the old category could hold more than one row (nothing
  # stopped a user adding entries to it through the ordinary screens).
  def adopt_main_corrections
    rows = select_all(<<~SQL.squish)
      SELECT DISTINCT ON (u.id) u.default_account_id AS account_id, e.id AS entry_id, e.date::date AS day
        FROM users u
        JOIN categories c ON c.user_id = u.id AND LOWER(c.name) = 'opening balance'
        JOIN items i ON i.category_id = c.id
        JOIN entries e ON e.item_id = i.id
       WHERE u.default_account_id IS NOT NULL
       ORDER BY u.id, e.date ASC
    SQL

    rows.each do |row|
      execute(sanitize_sql(["UPDATE entries SET opening_account_id = ? WHERE id = ?", row["account_id"], row["entry_id"]]))
      execute(sanitize_sql(["UPDATE pools SET opened_on = ? WHERE id = ? AND opened_on IS NULL", row["day"], row["account_id"]]))
    end
  end

  def sanitize_sql(statement) = ActiveRecord::Base.sanitize_sql_array(statement)

  def down
    remove_index :entries, :opening_account_id
    remove_foreign_key :entries, :pools, column: :opening_account_id
    remove_column :entries, :opening_account_id

    remove_column :pools, :opened_on
  end
end
