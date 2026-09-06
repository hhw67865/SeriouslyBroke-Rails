# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260908000000_account_openings")

# ** TWO COLUMNS AND A DATA BACKFILL (account-openings spec §2, fix round — MED-3). **
#
# `AFundKeepsUnspent`'s discipline asked of a migration that converts rows: the two columns exist
# with the shape the model relies on, and — the half that needs a spec rather than a reading — the
# OLD onboarding's answers are carried onto the new record instead of being asked for again.
#
# ** WHY THE BACKFILL IS THE SUBJECT. ** Without it every account in the database reads `opened_on
# IS NULL` on the morning this deploys, which is "has never said what it holds": a household that
# finished the old two-step setup years ago opens Home to a card asking for every account again,
# with their money pulled out of the "Elsewhere" tile and the accounts line while they answer. The
# old steps map onto the new record exactly, and each mapping is one example below.
#
# ** WHY THE SCHEMA IS REWOUND FOR THE LENGTH OF THIS FILE. ** Its subject is the newest migration,
# so the current schema is the world AFTER it and the `up` under test would meet its own columns
# (`PG::DuplicateColumn`). The shared context runs the `down` before the first example and the `up`
# after the last, which is also what proves the `down` correct — and it is why every example calls
# `migrate!` for itself rather than assuming the columns are there.
#
# ** THE FIXTURES ARE THE OLD WORLD'S OWN SHAPE, WRITTEN BY THE APP'S OWN MODELS. ** `AccountOpening`
# cannot plant anything here — it writes `entries.opening_account_id`, the column this migration adds
# — so what these examples plant is what the DELETED controllers wrote: an "Opening Balance" category
# with one entry for `OpeningBalancesController`'s step 3, and a movement from main for
# `AccountFundingsController`'s step 2.
RSpec.describe AccountOpenings do
  include_context "with the schema its subject was written for", described_class

  let(:migration) { described_class.new }
  let(:connection) { ActiveRecord::Base.connection }
  let(:user) { create(:user, timezone: "UTC") }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }

  def refresh_columns = [Budget, Category, Entry, Pool, Adjustment].each(&:reset_column_information)

  def migrate!
    migration.suppress_messages { migration.up }
    refresh_columns
  end

  def rewind!
    migration.suppress_messages { migration.down }
    refresh_columns
  end

  # ONBOARDING STEP 3'S ANSWER, AS `OpeningBalancesController` WROTE IT: one auto-created category
  # named "Opening Balance", one item, one ordinary entry dated before the user's history.
  def plant_a_correction(amount: 1_000, on: Date.new(2026, 8, 20))
    category = user.categories.find_by(name: Category::OPENING_BALANCE_NAME) ||
               create(:category, :income, user: user, name: Category::OPENING_BALANCE_NAME, tracked: false)
    item = category.items.find_by(name: "Initial balance") || create(:item, category: category, name: "Initial balance")
    create(:entry, item: item, amount: amount, date: on)
  end

  # ONBOARDING STEP 2'S ANSWER: the ONE movement from main that gave an account its real balance.
  def plant_a_funding(account, amount: 500, on: Date.new(2026, 8, 25))
    create(:account_movement, from_pool: checking, to_pool: account, amount: amount, date: on, kind: :transfer)
  end

  # `Date.parse` ON THE WAY OUT: `select_value` hands back whatever the adapter read, which for a
  # `date` column asked this way is the string Postgres printed. Read as SQL rather than through
  # `Pool` deliberately — the column comes and goes inside this file, and the model's attribute set
  # is only correct between a `reset_column_information` and the next DDL.
  def opened_on(account)
    value = connection.select_value("SELECT opened_on FROM pools WHERE id = '#{account.id}'")

    value && Date.parse(value.to_s)
  end

  def adopted_entry_id
    connection.select_value("SELECT id FROM entries WHERE opening_account_id = '#{checking.id}'")
  end

  it "does not have the columns before it runs", :aggregate_failures do
    expect(connection.column_exists?(:pools, :opened_on)).to be(false)
    expect(connection.column_exists?(:entries, :opening_account_id)).to be(false)
    # AND THE OLD WORLD IS STILL PLANTABLE, which is what every example below depends on.
    expect(plant_a_correction).to be_persisted
  end

  it "adds both columns, and at most one opening entry per account", :aggregate_failures do
    migrate!

    expect(connection.column_exists?(:pools, :opened_on)).to be(true)
    expect(connection.column_exists?(:entries, :opening_account_id)).to be(true)
    index = connection.indexes(:entries).find { |i| i.columns == ["opening_account_id"] }
    expect(index.unique).to be(true)
  end

  # ** STEP 3 → MAIN'S RECORD. ** The entry is ADOPTED rather than copied: `opening_account_id`
  # points it at main, so the next **Edit balance** rewrites that row instead of writing a second
  # one, and `opened_on` takes the date the entry already carried (the opening-day rule had already
  # backdated it there).
  it "adopts a user's opening-balance entry as their main account's record", :aggregate_failures do
    entry = plant_a_correction(amount: 1_000, on: Date.new(2026, 8, 20))

    migrate!

    expect(adopted_entry_id).to eq(entry.id)
    expect(opened_on(checking)).to eq(Date.new(2026, 8, 20))
  end

  # ** THE TIEBREAK (fix round — LOW-2). ** Nothing stopped a user adding a second entry to that
  # category through the ordinary screens, and `entries.opening_account_id` is unique — so exactly
  # one row may be adopted. Two entries on the SAME DAY leave `DISTINCT ON` free to pick either, and
  # Postgres may pick differently on a re-run or a differently-planned scan; `ORDER BY … e.date,
  # e.id` makes the choice total. Re-derived: two $500 entries dated 2026-08-20, so the date cannot
  # decide, and the row adopted is the one with the lower id — asserted against the pair rather than
  # against a literal, because uuids are minted per run.
  it "adopts exactly one row when two entries share the earliest day", :aggregate_failures do
    first = plant_a_correction(amount: 500, on: Date.new(2026, 8, 20))
    second = plant_a_correction(amount: 500, on: Date.new(2026, 8, 20))

    migrate!

    expect(adopted_entry_id).to eq([first, second].map(&:id).min)
    expect(connection.select_value("SELECT COUNT(*) FROM entries WHERE opening_account_id IS NOT NULL")).to eq(1)
  end

  # THE EARLIEST ENTRY WINS when the dates DO decide, which is the ordinary shape: the correction is
  # backdated before all history and anything else in that category came later.
  it "adopts the earliest entry when the dates differ" do
    earliest = plant_a_correction(amount: 1_000, on: Date.new(2026, 8, 20))
    plant_a_correction(amount: 25, on: Date.new(2026, 9, 1))

    migrate!

    expect(adopted_entry_id).to eq(earliest.id)
  end

  # ** STEP 2 → EVERY OTHER FUNDED ACCOUNT. ** The movement STAYS where it is — it is a flow like any
  # other, and the account's first correction subtracts it and writes the opening entry it never had
  # (§2's pre-existing-account case). What the account gets here is the date it was funded on.
  it "marks an account a movement has funded as having answered", :aggregate_failures do
    ally = create(:pool, :account, user: user, name: "Ally")
    movement = plant_a_funding(ally, amount: 500, on: Date.new(2026, 8, 25))

    migrate!

    expect(opened_on(ally)).to eq(Date.new(2026, 8, 25))
    expect(AccountMovement.where(id: movement.id).count).to eq(1)
    expect(connection.select_value("SELECT COUNT(*) FROM entries WHERE opening_account_id IS NOT NULL")).to eq(0)
  end

  # THE OTHER DIRECTION, AND IT IS THE ONE THAT KEEPS THE BACKFILL HONEST: an account nothing has ever
  # moved into is an account sitting on the old step-2 card at the moment this deploys. It has not
  # answered, so it keeps its NULL and gets a row in the new card.
  it "leaves an account nothing has moved into unanswered" do
    fresh = create(:pool, :account, user: user, name: "Fresh")

    migrate!

    expect(opened_on(fresh)).to be_nil
  end

  # MAIN WITHOUT ITS CORRECTION IS ALSO UNANSWERED — the old step 3 was still open for that user, and
  # incoming movements do not answer for main (it is excluded from the second statement by name).
  it "leaves a main account with no correction unanswered", :aggregate_failures do
    ally = create(:pool, :account, user: user, name: "Ally")
    create(:account_movement, from_pool: ally, to_pool: checking, amount: 200, date: Date.new(2026, 8, 25), kind: :transfer)

    migrate!

    expect(opened_on(checking)).to be_nil
    expect(adopted_entry_id).to be_nil
  end

  # A USER WITH NO MAIN ACCOUNT HAS NOTHING TO ADOPT ONTO. `users.default_account_id` nullifies when
  # the main account is deleted, and the adoption's own `WHERE u.default_account_id IS NOT NULL` is
  # what keeps this from writing a NULL into a unique index or guessing at an account.
  it "adopts nothing for a user with no main account", :aggregate_failures do
    plant_a_correction
    user.update!(default_account: nil)

    migrate!

    expect(connection.select_value("SELECT COUNT(*) FROM entries WHERE opening_account_id IS NOT NULL")).to eq(0)
    expect(opened_on(checking)).to be_nil
  end

  # ONE USER'S ANSWER IS NOT ANOTHER'S. The adoption is `DISTINCT ON (u.id)`, so two households with
  # the same category name each get their own row on their own main account.
  it "keeps two households' records apart", :aggregate_failures do
    mine = plant_a_correction(amount: 1_000, on: Date.new(2026, 8, 20))
    neighbour = create(:user, timezone: "UTC")
    their_checking = create(:pool, :account, user: neighbour, name: "Checking")
    their_category = create(:category, :income, user: neighbour, name: Category::OPENING_BALANCE_NAME, tracked: false)
    theirs = create(:entry, item: create(:item, category: their_category, name: "Initial balance"), amount: 90, date: Date.new(2026, 7, 1))

    migrate!

    expect(adopted_entry_id).to eq(mine.id)
    expect(connection.select_value("SELECT opening_account_id FROM entries WHERE id = '#{theirs.id}'"))
      .to eq(their_checking.id)
  end

  # ** THE `pool_type = 0` ARM IS DOCUMENTATION UNTIL THE SCHEMA ALLOWS ANOTHER KIND (fix round —
  # LOW-3), AND THIS EXAMPLE SAYS SO RATHER THAN PRETENDING TO PIN IT. ** `pools_are_accounts` is a
  # live CHECK constraint, so a non-account pool cannot be planted here even deliberately — the
  # condition cannot currently exclude a row. What it does is state which rows this statement is
  # ABOUT, so a later pool type does not silently inherit a column that means "this ACCOUNT has said
  # what it holds". The half that IS pinnable is that every account it does meet is answered.
  it "answers every funded account it meets", :aggregate_failures do
    ally = create(:pool, :account, user: user, name: "Ally")
    hysa = create(:pool, :account, user: user, name: "HYSA")
    plant_a_funding(ally, amount: 500, on: Date.new(2026, 8, 25))
    plant_a_funding(hysa, amount: 200, on: Date.new(2026, 8, 26))

    migrate!

    expect(opened_on(ally)).to eq(Date.new(2026, 8, 25))
    expect(opened_on(hysa)).to eq(Date.new(2026, 8, 26))
  end

  # ** THE ROUND TRIP, WHICH IS WHAT THE REWIND EVERY OTHER MIGRATION SPEC DEPENDS ON IS MADE OF. **
  # `down` removes both columns outright, which is a true reversal of the SHAPE: what the backfill
  # wrote lives only in those columns, so taking them away leaves exactly the rows the database held
  # before — the adopted entry is an ordinary entry again and the funded account is a funded account
  # again. Running `up` a second time re-derives the same answers from the same rows.
  it "removes both columns on the way down and re-derives on the way back up", :aggregate_failures do
    entry = plant_a_correction(amount: 1_000, on: Date.new(2026, 8, 20))
    migrate!

    rewind!
    expect(connection.column_exists?(:pools, :opened_on)).to be(false)
    expect(connection.column_exists?(:entries, :opening_account_id)).to be(false)
    expect(Entry.where(id: entry.id).count).to eq(1)

    migrate!
    expect(adopted_entry_id).to eq(entry.id)
    expect(opened_on(checking)).to eq(Date.new(2026, 8, 20))
  end
end
