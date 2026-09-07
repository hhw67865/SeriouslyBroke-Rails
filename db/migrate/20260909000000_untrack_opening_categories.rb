# frozen_string_literal: true

# ** THE ONE ROW `AccountOpenings` ADOPTED AND DID NOT FINISH (account-openings §2, fix round 4). **
#
# `AccountOpenings#adopt_main_corrections` takes the `Opening Balance` category a user's OLD
# onboarding wrote and points its entry at their main account. It says nothing about
# `categories.tracked` — and a legacy row carries the column's default, which is `true`.
#
# ** WHAT A TRACKED OPENING CATEGORY DOES TO A SCREEN. ** `tracked` is the flag Reports sums its
# TRACKED bands by. An opening record is not income anybody received and not money anybody spent —
# it is what an account started with — so `Entry.earned` and `Entry.spendable` keep it out of every
# figure on that page. The BANDS beside those figures are narrowed by category
# (`Category.earned` / `Category.spendable`) for the UNTRACKED half only, on the reasoning that an
# opening category cannot be tracked: `Category#an_opening_category_is_never_tracked` forces the flag
# false on every save. That guard is a MODEL callback, and an adopted legacy row was never saved
# through the model — so exactly one population in the world could still appear in the tracked band,
# carrying a figure the total above it excludes. This closes it, in the only place a row that no code
# path will ever save again can be reached.
#
# ** IT IS ITS OWN MIGRATION RATHER THAN A LINE INSIDE THE OTHER ONE, and that is deliberate. **
# `AccountOpenings` has already run everywhere it is going to run, this machine's development
# database included. Editing a migration that has been applied changes nothing for anybody who has
# applied it, which is precisely the population that needs the fix.
#
# ** THE NAMES ARE LITERALS HERE, NOT `Category::OPENING_NAMES`. ** A migration is a statement about
# the rows as they were on the day it ran; if the constant is ever renamed, this file must go on
# meaning what it meant. The model reads the constant, and `spec/models/category_spec.rb` is where
# the two are held to the same spelling.
class UntrackOpeningCategories < ActiveRecord::Migration[8.1]
  OPENING_NAMES = ["opening balance", "opening shortfall"].freeze

  def up
    say_with_time("untracking every opening category") do
      receipt.each { |row| say("#{row['rows']} for user #{row['user_id']}", true) }

      execute(<<~SQL.squish)
        UPDATE categories SET tracked = false, updated_at = NOW()
         WHERE LOWER(name) IN ('opening balance', 'opening shortfall')
           AND tracked = true
      SQL
    end
  end

  # ** A NO-OP, AND IT SAYS SO RATHER THAN GUESSING. ** `tracked` has no memory: nothing records
  # which of these rows was true before this ran, and the only honest reversal would be to set every
  # opening category back to the column default — which would re-track the ones `AccountOpening`
  # deliberately wrote false, a state no user ever chose. `DropTheDistribution#down` states the same
  # law for the same reason: a data migration's reversal is a restore from backup.
  #
  # IT MUST NOT RAISE. `spec/support/schema_rewind.rb` runs the `down` of every registered migration
  # before each migration spec, and a raise here would take every one of them with it.
  def down
    say("tracked has no memory: nothing to restore, and re-tracking every opening category would " \
        "invent a state no user chose")
  end

  private

  # THE RECEIPT, READ BEFORE THE WRITE — after it, there is nothing left to count. Per user, because
  # "how many rows did this change" is a question a person asks about their own data, and a single
  # total across a restored production copy answers it for nobody.
  def receipt
    select_all(<<~SQL.squish)
      SELECT user_id, COUNT(*) AS rows
        FROM categories
       WHERE LOWER(name) IN ('opening balance', 'opening shortfall')
         AND tracked = true
       GROUP BY user_id
       ORDER BY user_id
    SQL
  end
end
