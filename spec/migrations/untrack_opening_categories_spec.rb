# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260909000000_untrack_opening_categories")

# ** ONE COLUMN ON ONE POPULATION (account-openings §2, fix round 4). **
#
# `AccountOpenings#adopt_main_corrections` adopts the `Opening Balance` category a user's OLD
# onboarding wrote — by raw SQL, because the row predates every guard the model now carries — and
# says nothing about `categories.tracked`. A legacy row therefore survives adoption carrying the
# column's default, `true`, and `Category#an_opening_category_is_never_tracked` never sees it: that
# guard is a `before_validation`, and nothing will ever save this row through the model again.
#
# ** WHY THAT MATTERS ON A SCREEN. ** Reports sums its TRACKED bands by that flag while
# `Entry.earned` and `Entry.spendable` keep opening entries out of every FIGURE on the page. A
# tracked opening category is therefore a row in a band with a figure the total above it excludes —
# the one thing a reader cannot reconcile, and the exact hole `Category`'s own guard exists to close
# for every row the model does touch.
#
# THE FIXTURES ARE PLANTED BY SQL, and that is the whole point of them: the model REFUSES both
# reserved names to anybody but `AccountOpening` (`#opening_names_are_reserved`) and forces `tracked`
# false on the ones it allows, so a factory cannot produce the row this migration is about. Only the
# old world could, and the old world is gone.
RSpec.describe UntrackOpeningCategories do
  include_context "with the schema its subject was written for", described_class

  let(:migration) { described_class.new }
  let(:connection) { ActiveRecord::Base.connection }
  let(:user) { create(:user, timezone: "UTC") }

  def migrate! = migration.suppress_messages { migration.up }

  def rewind! = migration.suppress_messages { migration.down }

  # A LEGACY ROW EXACTLY AS `OpeningBalancesController` LEFT IT: the reserved name, income-typed, and
  # `tracked` at the column's default. `INSERT` rather than `create!` because every guard that would
  # stop this today is a model guard, and this row was written before any of them existed.
  def plant_a_legacy_category(name, tracked: true)
    connection.select_value(
      ActiveRecord::Base.sanitize_sql_array(
        [
          "INSERT INTO categories (id, name, category_type, tracked, priority, user_id, created_at, updated_at) " \
          "VALUES (gen_random_uuid(), ?, 1, ?, 0, ?, NOW(), NOW()) RETURNING id",
          name,
          tracked,
          user.id
        ]
      )
    )
  end

  def tracked?(id) = connection.select_value("SELECT tracked FROM categories WHERE id = '#{id}'")

  it "untracks a legacy opening category", :aggregate_failures do
    id = plant_a_legacy_category(Category::OPENING_BALANCE_NAME)
    expect(tracked?(id)).to be(true)

    migrate!

    expect(tracked?(id)).to be(false)
  end

  # BOTH NAMES, because the expense twin is written by exactly the same door and reaches exactly the
  # same band on the other tab.
  it "untracks a legacy shortfall category too" do
    id = plant_a_legacy_category(Category::OPENING_SHORTFALL_NAME)

    migrate!

    expect(tracked?(id)).to be(false)
  end

  # CASE-INSENSITIVE, matching the scope that reads these names and the validation beside it: a user
  # who typed "opening balance" into the ordinary categories screen years ago owns the same row.
  it "untracks a name typed in another case" do
    id = plant_a_legacy_category("opening balance")

    migrate!

    expect(tracked?(id)).to be(false)
  end

  # ** THE OTHER DIRECTION, AND IT IS THE ONE THAT KEEPS A BLANKET `UPDATE` HONEST. ** Every other
  # category in the database is somebody's own decision about what counts toward a period's figures,
  # and this migration must not touch one of them.
  it "leaves every ordinary category alone", :aggregate_failures do
    tracked = create(:category, :expense, user: user, name: "Groceries")
    untracked = create(:category, :income, user: user, name: "Gifts", tracked: false)

    migrate!

    expect(tracked.reload.tracked).to be(true)
    expect(untracked.reload.tracked).to be(false)
  end

  # IDEMPOTENT, which is what `AND tracked = true` buys: the rows `AccountOpening` wrote are already
  # false, so a second run of this migration meets nothing and writes nothing.
  it "leaves an opening category that is already untracked untouched", :aggregate_failures do
    id = plant_a_legacy_category(Category::OPENING_BALANCE_NAME, tracked: false)

    expect { migrate! }.not_to(change { connection.select_value("SELECT MAX(updated_at) FROM categories") })
    expect(tracked?(id)).to be(false)
  end

  # ** THE ROUND TRIP, WHICH FOR A DATA MIGRATION IS A STATEMENT RATHER THAN A RESTORE. ** `tracked`
  # has no memory: nothing records which of these rows was true before, and re-tracking every opening
  # category on the way down would invent a state no user chose. What `down` owes the rewind other
  # migration specs depend on is that it does not RAISE, and that `up` after it is unchanged.
  it "reverses to nothing, twice over", :aggregate_failures do
    id = plant_a_legacy_category(Category::OPENING_BALANCE_NAME)
    migrate!

    expect { rewind! }.not_to raise_error
    expect(tracked?(id)).to be(false)

    migrate!
    expect(tracked?(id)).to be(false)
  end
end
