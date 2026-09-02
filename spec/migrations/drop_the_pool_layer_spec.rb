# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260821010000_drop_the_pool_layer")

# THE DROP (two-ledger spec §5), exercised in `spec/migrations/cutover_spec.rb`'s discipline: the
# pool-era world planted past today's model, every expected figure a planted literal, the invariant
# asked in raw SQL that shares nothing with the migration's own, and the verifier shown failing.
#
# WHY THE SCHEMA IS REWOUND FOR THE LENGTH OF THIS FILE. This spec's subject is the NEWEST
# migration, so the current schema is the world AFTER it — `remove_column` would meet columns that
# are already gone. The shared context runs the `down` before the first example and the `up` after
# the last, which is also what proves the `down` correct.
#
# WHY EVERY POOL IS PLANTED IN SQL. `Pool`'s enum has one member after this commit, and an enum
# raises `ArgumentError` on a value it does not know — so `pool_type: 1` cannot be assigned through
# the model at all, not even with `save!(validate: false)`. Planting in SQL is the only spelling
# that survives the model this migration exists to shrink, and it is the same move cutover_spec
# makes with the migration's own table classes.
#
# WHY EVERY EXAMPLE RE-RESETS COLUMN INFORMATION: the DDL runs INSIDE the example transaction, so
# `pools.start_date` exists for the length of one example and is gone by the next.
RSpec.describe DropThePoolLayer do
  include_context "with the schema its subject was written for", described_class

  let(:migration) { described_class.new }
  let(:user) { create(:user, email: "ming@example.com", timezone: "UTC") }
  let(:main) { create(:pool, :account, user: user, name: "Checking") }

  before do
    refresh_columns
    user.update!(default_account: main)
  end

  def refresh_columns = [Budget, Category, Entry, Pool].each(&:reset_column_information)

  def migrate!
    migration.suppress_messages { migration.up }
    refresh_columns
  end

  # The `say` lines, captured rather than suppressed — a per-user receipt nobody reads is a receipt
  # that can quietly stop counting.
  def receipts
    lines = []
    allow(migration).to receive(:write) { |text| lines << text }
    migration.up
    refresh_columns
    lines
  end

  # ---------------------------------------------------------------------------------------------
  # Planting the pool era
  # ---------------------------------------------------------------------------------------------

  delegate :connection, to: :"ActiveRecord::Base"

  def sql(statement, **binds)
    connection.execute(ActiveRecord::Base.sanitize_sql_array([statement, binds]))
  end

  def sql_value(statement, **binds)
    connection.select_value(ActiveRecord::Base.sanitize_sql_array([statement, binds]))
  end

  def sql_decimal(statement, **binds) = BigDecimal(sql_value(statement, **binds).to_s)

  # A leftover envelope or goal: the row `CategoriesHoldTheMoney` folded onto a category and left
  # standing. `pool_type` 1 is an envelope, 2 a goal — spelled as integers because the enum that
  # named them is being deleted in this same commit.
  def plant_pool(name:, pool_type: 1, target: nil, start: Date.new(2026, 1, 1), priority: 0)
    id = SecureRandom.uuid
    sql(<<~SQL.squish, id: id, uid: user.id, name: name, type: pool_type, t: target, s: start, p: priority)
      INSERT INTO pools (id, user_id, name, pool_type, account_id, target_amount, start_date,
                         priority, created_at, updated_at)
      VALUES (:id, :uid, :name, :type, '#{main.id}', :t, :s, :p, NOW(), NOW())
    SQL
    id
  end

  def plant_movement(from:, to:, amount: 120, kind: 0, at: Time.zone.local(2026, 8, 1, 9))
    id = SecureRandom.uuid
    sql(<<~SQL.squish, id: id, from: from, to: to, amount: amount, kind: kind, at: at)
      INSERT INTO pool_movements (id, from_pool_id, to_pool_id, amount, kind, date, created_at, updated_at)
      VALUES (:id, :from, :to, :amount, :kind, :at, NOW(), NOW())
    SQL
    id
  end

  def second_account = create(:pool, :account, user: user, name: "Ally")

  def category(name, funded_since: nil, type: :expense)
    create(:category, type, user: user, name: name, funded_since: funded_since)
  end

  # PAST THE MODEL, deliberately: `Category#funding_start_is_not_in_the_future` is younger than the
  # rows it governs, so a future funding start is a shape the database may already hold and the
  # migration must not assume away. The validation is the app's rule, not the data's.
  def category_funded_from(name, day)
    category(name).tap { |record| record.update_column(:funded_since, day) } # rubocop:disable Rails/SkipsModelValidations
  end

  def spend(cat, amount, on: Date.new(2026, 8, 10))
    create(:entry, item: create(:item, category: cat), amount: amount, date: on)
  end

  def allocate(to:, amount:, on: Date.new(2026, 8, 5))
    create(:allocation, to_category: to, from_category: nil, amount: amount, date: on)
  end

  # ---------------------------------------------------------------------------------------------
  # BOTH LEDGERS, ASKED INDEPENDENTLY OF THE MIGRATION — the physical side from `entries` and the
  # movement table alone, the purpose side one category at a time and summed in Ruby, so an error
  # in either formula cannot answer wrong on both sides at once.
  # ---------------------------------------------------------------------------------------------

  def bank_truth
    sql_decimal(<<~SQL.squish, uid: user.id)
      SELECT COALESCE(SUM(CASE WHEN c.category_type = 1 THEN e.amount::numeric
                               ELSE -e.amount::numeric END), 0)
      FROM entries e JOIN items i ON i.id = e.item_id JOIN categories c ON c.id = i.category_id
      WHERE c.user_id = :uid
    SQL
  end

  def purpose_total = available + holdings.values.sum(0.to_d)

  def available
    sql_decimal(<<~SQL.squish, uid: user.id)
      SELECT COALESCE((SELECT SUM(e.amount::numeric) FROM entries e
                         JOIN items i ON i.id = e.item_id
                         JOIN categories c ON c.id = i.category_id
                        WHERE c.user_id = :uid AND c.category_type = 1), 0)
           - COALESCE((SELECT SUM(e.amount::numeric) FROM entries e
                         JOIN items i ON i.id = e.item_id
                         JOIN categories c ON c.id = i.category_id
                        WHERE c.user_id = :uid AND c.category_type <> 1
                          AND (c.funded_since IS NULL OR e.date < c.funded_since)), 0)
           - COALESCE((SELECT SUM(a.amount::numeric) FROM allocations a
                        WHERE a.from_category_id IS NULL
                          AND a.to_category_id IN (SELECT id FROM categories WHERE user_id = :uid)), 0)
           + COALESCE((SELECT SUM(a.amount::numeric) FROM allocations a
                        WHERE a.to_category_id IS NULL
                          AND a.from_category_id IN (SELECT id FROM categories WHERE user_id = :uid)), 0)
    SQL
  end

  def holdings
    rows = connection.select_rows(ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, { uid: user.id }]))
      SELECT c.id,
             COALESCE((SELECT SUM(a.amount::numeric) FROM allocations a WHERE a.to_category_id = c.id), 0)
           - COALESCE((SELECT SUM(a.amount::numeric) FROM allocations a WHERE a.from_category_id = c.id), 0)
           - COALESCE((SELECT SUM(e.amount::numeric) FROM entries e
                         JOIN items i ON i.id = e.item_id
                        WHERE i.category_id = c.id
                          AND c.funded_since IS NOT NULL AND e.date >= c.funded_since), 0)
      FROM categories c WHERE c.user_id = :uid AND c.category_type <> 1
    SQL
    # rubocop:disable Style/HashTransformValues -- `rows` is an Array of pairs, not a Hash
    rows.to_h { |id, balance| [id, BigDecimal(balance.to_s)] }
    # rubocop:enable Style/HashTransformValues
  end

  # `pot + Σ accounts`, over whichever name the movement table is currently wearing.
  def physical_total(movements)
    sql_decimal(<<~SQL.squish, uid: user.id)
      SELECT COALESCE((SELECT SUM(CASE WHEN c.category_type = 1 THEN e.amount::numeric
                                       ELSE -e.amount::numeric END)
                         FROM entries e
                         JOIN items i ON i.id = e.item_id
                         JOIN categories c ON c.id = i.category_id
                        WHERE c.user_id = :uid), 0)
           + COALESCE((SELECT SUM(m.amount::numeric) FROM #{movements} m
                        WHERE m.to_pool_id IN (SELECT id FROM pools WHERE user_id = :uid AND pool_type = 0)), 0)
           - COALESCE((SELECT SUM(m.amount::numeric) FROM #{movements} m
                        WHERE m.from_pool_id IN (SELECT id FROM pools WHERE user_id = :uid AND pool_type = 0)), 0)
    SQL
  end

  def column?(table, name) = connection.column_exists?(table, name)

  # THE WORLD `CategoriesHoldTheMoney` LEAVES BEHIND, and the one this migration is aimed at: the
  # money already on the categories, the envelope and goal ROWS still standing with categories
  # pointing at them, and the only movements left are account to account.
  #
  # PLANTED LITERALS, and the two figures they make:
  #   income 3,000; spending 400 in a funded category and 90 in one that has never held money.
  #   bank truth  = 3,000 − 400 − 90            = 2,510
  #   available   = 3,000 − 90 − 600 allocated  = 2,310
  #   Groceries   = 600 allocated − 400 spent   =   200
  #   purpose     = 2,310 + 200                 = 2,510
  # The 750 moved Checking → Ally nets to zero across the two accounts, so it moves neither.
  def plant_the_migrated_world
    groceries = category("Groceries", funded_since: Date.new(2026, 8, 1))
    sql("UPDATE categories SET pool_id = :p WHERE id = :c", p: plant_pool(name: "Groceries pool"), c: groceries.id)
    plant_pool(name: "Trip", pool_type: 2, target: 900)
    plant_movement(from: main.id, to: second_account.id, amount: 750)
    spend(category("Salary", type: :income), 3_000, on: Date.new(2026, 8, 2))
    spend(groceries, 400)
    spend(category("Coffee"), 90)
    allocate(to: groceries, amount: 600)
    groceries
  end

  # ---------------------------------------------------------------------------------------------
  # The rows, the columns and the rename
  # ---------------------------------------------------------------------------------------------

  it "deletes every pool that is not an account and leaves the accounts standing", :aggregate_failures do
    plant_the_migrated_world

    migrate!

    expect(sql_value("SELECT COUNT(*) FROM pools WHERE pool_type <> 0").to_i).to eq(0)
    expect(user.pools.reload.pluck(:name)).to contain_exactly("Checking", "Ally")
  end

  it "takes the envelope's own columns off the pools table", :aggregate_failures do
    migrate!

    expect(column?(:pools, :account_id)).to be(false)
    expect(column?(:pools, :start_date)).to be(false)
    expect(column?(:pools, :target_amount)).to be(false)
    expect(column?(:pools, :priority)).to be(false)
  end

  it "drops the three references into the layer", :aggregate_failures do
    migrate!

    expect(column?(:categories, :pool_id)).to be(false)
    expect(column?(:entries, :pool_id)).to be(false)
    expect(column?(:budgets, :pool_id)).to be(false)
  end

  it "renames pool_movements to account_movements, carrying its rows across", :aggregate_failures do
    plant_the_migrated_world

    migrate!

    expect(connection.table_exists?(:pool_movements)).to be(false)
    expect(sql_decimal("SELECT SUM(amount::numeric) FROM account_movements")).to eq(750)
  end

  # PAST THE MODEL, which is the point of a CHECK: `Pool`'s enum refuses a non-account in Ruby and
  # this refuses one written by a console, an import or a raw INSERT.
  it "refuses a pool that is not an account, past the model" do
    migrate!

    expect { sql(<<~SQL.squish, uid: user.id) }.to raise_error(ActiveRecord::StatementInvalid, /pools_are_accounts/)
      INSERT INTO pools (id, user_id, name, pool_type, created_at, updated_at)
      VALUES ('#{SecureRandom.uuid}', :uid, 'Smuggled', 1, NOW(), NOW())
    SQL
  end

  it "refuses a movement that is not a transfer, past the model" do
    plant_the_migrated_world
    migrate!
    statement = <<~SQL.squish
      INSERT INTO account_movements (id, from_pool_id, to_pool_id, amount, kind, date, created_at, updated_at)
      VALUES ('#{SecureRandom.uuid}', :from, :to, 10, 1, NOW(), NOW(), NOW())
    SQL

    expect { sql(statement, from: main.id, to: user.pools.find_by(name: "Ally").id) }
      .to raise_error(ActiveRecord::StatementInvalid, /account_movements_are_transfers/)
  end

  it "makes a rule's category required" do
    migrate!

    expect(connection.columns(:budgets).find { |column| column.name == "category_id" }.null).to be(false)
  end

  # ---------------------------------------------------------------------------------------------
  # The invariant, before and after
  # ---------------------------------------------------------------------------------------------

  it "leaves both partitions of spec §2 exactly where they were", :aggregate_failures do
    plant_the_migrated_world
    expect([bank_truth, purpose_total, physical_total("pool_movements")])
      .to eq([BigDecimal("2510"), BigDecimal("2510"), BigDecimal("2510")])

    migrate!

    expect([bank_truth, purpose_total, physical_total("account_movements")])
      .to eq([BigDecimal("2510"), BigDecimal("2510"), BigDecimal("2510")])
  end

  # A FUNDING START IN THE FUTURE IS A SHAPE THE DATA MAY ALREADY HOLD — `Category#funding_start_is_
  # not_in_the_future` is a validation younger than the rows it governs — so no arm of this
  # migration may compare that column to today. Planted at a fixed literal rather than off
  # `Date.current` so the example means the same thing on every day it runs.
  it "tolerates a category whose funding start has not arrived yet", :aggregate_failures do
    plant_the_migrated_world
    later = category_funded_from("Car", Date.new(2099, 1, 1))
    allocate(to: later, amount: 100)
    before = [bank_truth, purpose_total]

    migrate!

    expect(before).to eq([BigDecimal("2510"), BigDecimal("2510")])
    expect([bank_truth, purpose_total]).to eq(before)
  end

  it "prints a per-user receipt naming both partitions" do
    plant_the_migrated_world

    expect(receipts).to include(a_string_matching(/ming@example\.com: purpose 2510\.0 == physical 2510\.0/))
  end

  # ---------------------------------------------------------------------------------------------
  # What it refuses before it writes
  # ---------------------------------------------------------------------------------------------

  it "refuses a movement with an end that is not an account, naming it" do
    envelope = plant_pool(name: "Groceries pool")
    plant_movement(from: main.id, to: envelope)

    expect { migration.suppress_messages { migration.up } }
      .to raise_error(described_class::PreflightFailed, /ming@example\.com: movement .* is not an account/)
  end

  it "refuses a movement that is not a transfer, naming it" do
    plant_movement(from: main.id, to: second_account.id, amount: 50, kind: 2)

    expect { migration.suppress_messages { migration.up } }
      .to raise_error(described_class::PreflightFailed, /ming@example\.com: movement .* is not a transfer/)
  end

  it "refuses a rule with no category, naming it" do
    envelope = plant_pool(name: "Groceries pool")
    sql(<<~SQL.squish, p: envelope)
      INSERT INTO budgets (id, pool_id, amount, basis, interval_months, created_at, updated_at)
      VALUES ('#{SecureRandom.uuid}', :p, 100, 0, 1, NOW(), NOW())
    SQL

    expect { migration.suppress_messages { migration.up } }
      .to raise_error(described_class::PreflightFailed, /ming@example\.com: rule .* has no category/)
  end

  it "refuses a main account that is not an account, naming it" do
    sql("UPDATE users SET default_account_id = :p WHERE id = :u", p: plant_pool(name: "Trip", pool_type: 2), u: user.id)

    expect { migration.suppress_messages { migration.up } }
      .to raise_error(described_class::PreflightFailed, /ming@example\.com: main account .* is not an account/)
  end

  it "refuses nothing on the world Task 1 leaves behind" do
    plant_the_migrated_world

    expect { migrate! }.not_to raise_error
  end

  # ---------------------------------------------------------------------------------------------
  # Refusing its own output
  # ---------------------------------------------------------------------------------------------

  # THE SABOTAGE IS REAL WORK, NOT A STUBBED FIGURE, and it is the ONE failure mode `#purpose_total`
  # has: money allocated OUT of this user's category and INTO a stranger's. Every other allocation
  # term cancels between the two arms — deleting an allocation, for instance, moves exactly as much
  # back into available as it takes out of holdings, which is why that is not a sabotage at all —
  # so the cross-user row is what a wrong drop would have to look like to move one partition and
  # leave the other standing. Written in SQL because `Allocation` refuses it in Ruby.
  it "refuses to commit when a partition moves under it" do
    groceries = plant_the_migrated_world
    stranger = create(:category, :expense, user: create(:user, email: "other@example.com"), name: "Theirs")
    allow(migration).to receive(:rename_the_movements).and_wrap_original do |original, *args|
      allocate_away_to(groceries, stranger)
      original.call(*args)
    end

    expect { migration.suppress_messages { migration.up } }
      .to raise_error(described_class::VerificationFailed, /ming@example\.com: purpose was 2510\.0, is 1910\.0/)
  end

  def allocate_away_to(mine, theirs)
    sql(<<~SQL.squish, from: mine.id, to: theirs.id)
      INSERT INTO allocations (id, from_category_id, to_category_id, amount, date, kind, created_at, updated_at)
      VALUES ('#{SecureRandom.uuid}', :from, :to, 600, NOW(), 0, NOW(), NOW())
    SQL
  end
end
