# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260821000000_categories_hold_the_money")

# THE MIGRATION THAT MOVES THE MONEY ONTO THE CATEGORIES (two-ledger spec §7), exercised in
# `spec/migrations/cutover_spec.rb`'s discipline: legacy shapes planted past today's model, every
# expected figure a planted literal, the invariant asked in raw SQL that shares nothing with the
# migration's own, and the verifier shown failing.
#
# WHY THE SCHEMA IS REWOUND FOR THE LENGTH OF THIS FILE. Unlike every other spec, this one's subject
# IS the newest migration, so the current schema is the world AFTER it — `add_column` would meet its
# own columns. The shared context runs this migration's `down` before the first example and its `up`
# after the last, which is also what proves the `down` correct; see `spec/support/schema_rewind.rb`.
#
# WHY EVERY EXAMPLE RE-RESETS COLUMN INFORMATION. The DDL runs INSIDE the example transaction, so
# `categories.funded_since` exists for the length of one example and is gone by the next — and an
# `ActiveRecord::Base` subclass that cached its attribute set on either side of that would write a
# column the database no longer has (or fail to read one it does). `#refresh_columns` runs at the
# top of every example, when the rewound schema is the truth, and again the moment `up` returns.
# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe CategoriesHoldTheMoney do
  # `DropThePoolLayer` JOINS THE REWIND (Task 8) AND IT IS NOT OPTIONAL: it deletes
  # `categories.pool_id`, `budgets.pool_id`, `entries.pool_id` and the `pool_movements` table name,
  # which are the whole world this migration converts. Named in the order the two run FORWARD; the
  # context reverses them itself, so the drop's `down` restores the pool era before this one's
  # `down` takes the two-ledger columns away.
  include_context "with the schema its subject was written for",
                  described_class,
                  DropThePoolLayer,
                  DropTheDistribution

  let(:migration) { described_class.new }
  let(:user) { create(:user, email: "ming@example.com") }
  let(:main) { create(:pool, :account, user: user, name: "Checking") }

  before do
    refresh_columns
    user.update!(default_account: main)
  end

  # ---------------------------------------------------------------------------------------------
  # Running it, and reading it back
  # ---------------------------------------------------------------------------------------------

  def refresh_columns = [Budget, Category, Entry, Pool].each(&:reset_column_information)

  def migrate!
    migration.suppress_messages { migration.up }
    refresh_columns
  end

  # THE MIGRATION'S OWN TABLE CLASS, borrowed rather than redeclared: `Allocation` does not exist
  # until task 2, and a second local class here would be a second opinion about the table's name.
  def allocations = described_class::MigrationAllocation

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
  # The planted worlds
  # ---------------------------------------------------------------------------------------------

  # THE POOL ERA IS PLANTED THROUGH THE MIGRATION'S OWN TABLE CLASSES, and after Task 8 that is the
  # only way left: `Pool`'s enum has one member, so `pool_type: 1` raises `ArgumentError` before any
  # `save(validate: false)` can help, `Category` and `Entry` have no `pool` association, and
  # `PoolMovement` is `AccountMovement` over a table that does not exist in the rewound schema. Same
  # move `cutover_spec` makes, borrowed rather than redeclared so nothing here is a second opinion
  # about a table's name.
  def pools = described_class::MigrationPool
  def movements = described_class::MigrationMovement
  def budgets = described_class::MigrationBudget

  def plant_pool(name:, pool_type:, start:, priority: 0, target: nil)
    pools.create!(
      user_id: user.id,
      name: name,
      pool_type: pool_type,
      account_id: main.id,
      start_date: start,
      priority: priority,
      target_amount: target,
      created_at: Time.current,
      updated_at: Time.current
    )
  end

  def envelope(name, start:, priority: 1, target: nil)
    plant_pool(name: name, pool_type: 1, start: start, priority: priority, target: target)
  end

  def goal(name, start:, target:)
    plant_pool(name: name, pool_type: 2, start: start, target: target)
  end

  # `update_column`, because `categories.pool_id` exists in the rewound schema but the model has no
  # association for it — the column is assignable, the writer is not.
  def category_in(pool, name, type: :expense)
    create(:category, type, user: user, name: name).tap do |category|
      category.update_column(:pool_id, pool.id) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def rule_on(pool, amount:)
    budgets.create!(
      pool_id: pool.id,
      amount: amount,
      basis: 1,
      interval_months: nil,
      created_at: Time.current,
      updated_at: Time.current
    )
  end

  def spend(category, amount, on: Date.current, pool: nil)
    create(:entry, item: create(:item, category: category), amount: amount, date: on).tap do |entry|
      entry.update_column(:pool_id, pool.id) if pool # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # The pool era's three movement kinds as integers, in a method rather than a constant: a constant
  # declared inside an example group leaks into the global namespace.
  def kind_number(name) = { transfer: 0, allocation: 1, sweep: 2 }.fetch(name)

  def move(from, to, amount, kind: :transfer, **attrs)
    movements.create!(
      from_pool_id: from.id,
      to_pool_id: to.id,
      amount: amount,
      date: attrs.fetch(:at, Time.zone.now),
      kind: kind_number(kind),
      source_entry_id: attrs[:source_entry]&.id,
      created_at: Time.current,
      updated_at: Time.current
    )
  end

  # ---------------------------------------------------------------------------------------------
  # BOTH LEDGERS, ASKED INDEPENDENTLY OF THE MIGRATION. The migration verifies itself in one
  # set-based statement per user; these ask the same questions a different way — the physical side
  # from `entries` alone with no pool named anywhere, the purpose side one category at a time,
  # summed in Ruby — so an error in either formula cannot answer wrong on both sides at once.
  # ---------------------------------------------------------------------------------------------

  def bank_truth
    sql_decimal(<<~SQL.squish)
      SELECT COALESCE(SUM(CASE WHEN c.category_type = 1 THEN e.amount::numeric
                               ELSE -e.amount::numeric END), 0)
      FROM entries e JOIN items i ON i.id = e.item_id JOIN categories c ON c.id = i.category_id
      WHERE c.user_id = '#{user.id}'
    SQL
  end

  # available + Σ category holdings, computed off the NEW tables only.
  def purpose_total = available + holdings.values.sum(0.to_d)

  # Income, minus the spending of categories that were not yet holding money on the day it
  # happened (the re-anchored start-date rule, §4), minus what has been allocated out of it.
  def available
    sql_decimal(<<~SQL.squish)
      SELECT COALESCE((SELECT SUM(e.amount::numeric) FROM entries e
                         JOIN items i ON i.id = e.item_id
                         JOIN categories c ON c.id = i.category_id
                        WHERE c.user_id = '#{user.id}' AND c.category_type = 1), 0)
           - COALESCE((SELECT SUM(e.amount::numeric) FROM entries e
                         JOIN items i ON i.id = e.item_id
                         JOIN categories c ON c.id = i.category_id
                        WHERE c.user_id = '#{user.id}' AND c.category_type <> 1
                          AND (c.funded_since IS NULL OR e.date < c.funded_since)), 0)
           - COALESCE((SELECT SUM(a.amount::numeric) FROM allocations a
                        WHERE a.from_category_id IS NULL
                          AND a.to_category_id IN (SELECT id FROM categories WHERE user_id = '#{user.id}')), 0)
           + COALESCE((SELECT SUM(a.amount::numeric) FROM allocations a
                        WHERE a.to_category_id IS NULL
                          AND a.from_category_id IN (SELECT id FROM categories WHERE user_id = '#{user.id}')), 0)
    SQL
  end

  # `{ category id => holdings }` — allocations in, minus allocations out, minus what the category
  # has spent since `funded_since`.
  def holdings
    rows = ActiveRecord::Base.connection.select_rows(<<~SQL.squish)
      SELECT c.id,
             COALESCE((SELECT SUM(a.amount::numeric) FROM allocations a WHERE a.to_category_id = c.id), 0)
           - COALESCE((SELECT SUM(a.amount::numeric) FROM allocations a WHERE a.from_category_id = c.id), 0)
           - COALESCE((SELECT SUM(e.amount::numeric) FROM entries e
                         JOIN items i ON i.id = e.item_id
                        WHERE i.category_id = c.id
                          AND c.funded_since IS NOT NULL AND e.date >= c.funded_since), 0)
      FROM categories c WHERE c.user_id = '#{user.id}' AND c.category_type <> 1
    SQL
    # rubocop:disable Style/HashTransformValues -- `rows` is an Array of pairs, not a Hash
    rows.to_h { |id, balance| [id, BigDecimal(balance.to_s)] }
    # rubocop:enable Style/HashTransformValues
  end

  def sql_decimal(sql) = BigDecimal(ActiveRecord::Base.connection.select_value(sql).to_s)

  # ---------------------------------------------------------------------------------------------
  # The fold
  # ---------------------------------------------------------------------------------------------

  it "folds an envelope into its one category and re-parents its rule", :aggregate_failures do
    food = envelope("Food", start: Date.new(2026, 8, 1), priority: 2)
    category = category_in(food, "Food")
    rule = rule_on(food, amount: 120)

    migrate!

    expect(category.reload.funded_since).to eq(Date.new(2026, 8, 1))
    expect(category.priority).to eq(2)
    expect(rule.reload.category_id).to eq(category.id)
  end

  it "turns a savings goal into a savings category carrying its holdings", :aggregate_failures do
    trip = goal("Trip", start: Date.new(2026, 6, 1), target: 900)
    move(main, trip, 250)

    migrate!

    saved = user.categories.find_by(name: "Trip")
    expect(saved).to have_attributes(target_amount: 900, tracked: false, funded_since: Date.new(2026, 6, 1))
    allocation = allocations.find_by(to_category_id: saved.id)
    expect(allocation.from_category_id).to be_nil # from AVAILABLE
    expect(allocation.amount).to eq(250)
    expect(movements.where(to_pool_id: trip.id)).to be_empty
  end

  # `kind` IS CARRIED VERBATIM, not defaulted. A distribution's replace-on-re-run deletes
  # `allocation` and `sweep` rows and leaves `transfer` alone, so a conversion that flattened the
  # column would either resurrect a swept envelope or make next payday delete a hand-made move.
  it "carries each movement's kind and date onto the allocation", :aggregate_failures do
    food = envelope("Food", start: Date.new(2026, 8, 1))
    category = category_in(food, "Food")
    moment = Time.zone.local(2026, 8, 14, 9)
    move(main, food, 200, kind: :allocation, at: moment)
    move(food, main, 30, kind: :sweep, at: moment)

    migrate!

    expect(allocations.where(to_category_id: category.id).pick(:kind, :date)).to eq([1, moment])
    expect(allocations.where(from_category_id: category.id).pick(:kind, :amount)).to eq([2, 30])
  end

  # `source_entry_id` IS WHAT MAKES A DISTRIBUTION REPLACEABLE — `AccountMovement.for_entry` finds a
  # movement by it, and the column is carried onto `allocations` with its own foreign key. A
  # conversion that dropped it would leave next payday unable to find what it wrote last time.
  it "carries a movement's source entry onto the allocation" do
    food = envelope("Food", start: Date.new(2026, 8, 1))
    category = category_in(food, "Food")
    source = spend(category, 45)
    move(main, food, 45, source_entry: source)

    migrate!

    expect(allocations.where(to_category_id: category.id).pick(:source_entry_id)).to eq(source.id)
  end

  it "keeps account↔account movements where they are" do
    ally = create(:pool, :account, user: user, name: "Ally")
    move(main, ally, 40)

    expect { migrate! }.not_to change(movements, :count)
  end

  # SPEC §2: "no paid from field on entries; the pot is where cash leaves." The column survives
  # until task 8's drop, so the migration empties it rather than leaving a lane two readers could
  # still disagree about.
  it "clears every paid-from override and counts them in the receipt", :aggregate_failures do
    food = envelope("Food", start: Date.new(2026, 8, 1))
    category = category_in(food, "Food")
    spend(category, 25, pool: food)
    spend(category, 15, pool: main)

    lines = receipts

    expect(Entry.where.not(pool_id: nil)).to be_empty
    expect(lines.join).to include("ming@example.com", "1 pools folded", "2 entry overrides cleared")
  end

  # ---------------------------------------------------------------------------------------------
  # The refusals — named before the first write
  # ---------------------------------------------------------------------------------------------

  it "refuses an envelope with two categories, naming it, and writes nothing", :aggregate_failures do
    food = envelope("Food", start: Date.current)
    category_in(food, "Groceries")
    category_in(food, "Restaurants")

    expect { migrate! }.to raise_error(described_class::PreflightFailed, /Food.*2 categories/)
    expect(allocations.count).to eq(0)
  end

  # THE OTHER ARM OF THE SAME REFUSAL, and it is not symmetrical with the one above: a SAVINGS pool
  # with no category is the ordinary shape (it gets one minted), a BUDGET pool with none is an
  # envelope whose spending lane nothing names, and there is nothing to fold it into.
  it "refuses an envelope with no category at all, before it re-parents a rule", :aggregate_failures do
    rule = rule_on(envelope("Food", start: Date.current), amount: 90)

    expect { migrate! }.to raise_error(described_class::PreflightFailed, /Food.*0 categories/)
    # THROUGH THE MIGRATION'S OWN TABLE CLASS, not `Budget`: `create_schema` runs before
    # `preflight!`, so the column exists in the database at the moment of the raise while the app
    # model — reset at the top of this example against the rewound schema — has never seen it.
    expect(budgets.find(rule.id).category_id).to be_nil
  end

  # ---------------------------------------------------------------------------------------------
  # The invariant
  # ---------------------------------------------------------------------------------------------

  # A $1,000 paycheck, $200 of it given a job, and $60 of that job spent — the four planted
  # literals below are that world read back through both partitions of spec §2.
  def plant_a_month(food)
    category = category_in(food, "Food")
    spend(category_in(main, "Pay", type: :income), 1000)
    spend(category, 60)
    move(main, food, 200, kind: :allocation)
    category
  end

  it "leaves both ledgers equal to bank truth", :aggregate_failures do
    category = plant_a_month(envelope("Food", start: Date.new(2026, 8, 1)))

    migrate!

    expect(purpose_total).to eq(bank_truth)
    expect(bank_truth).to eq(940)
    expect(holdings[category.id]).to eq(140) # 200 allocated in, 60 spent since it was funded
    expect(available).to eq(800) # 1000 in, 200 given a job
  end

  # SPENDING BEFORE `funded_since` DRAINS AVAILABLE, NOT THE CATEGORY (§4) — the pool table's
  # `start_date` arriving on the category as the same rule, which is the whole reason the column is
  # carried across rather than stamped `Date.current`.
  it "leaves pre-funding spending on available", :aggregate_failures do
    food = envelope("Food", start: Date.new(2026, 8, 1))
    category = category_in(food, "Food")
    pay = category_in(main, "Pay", type: :income)
    spend(pay, 500)
    spend(category, 70, on: Date.new(2026, 7, 20))

    migrate!

    expect(holdings[category.id]).to eq(0)
    expect(available).to eq(430)
    expect(purpose_total).to eq(bank_truth)
  end

  # ---------------------------------------------------------------------------------------------
  # THE VERIFIER, SHOWN FAILING. Every arm above describes a database the migration itself produced,
  # so none of them can fail on a run that worked; a verifier never seen refusing anything proves
  # nothing. The allocation planted here is the one breakage `Σ` is not blind to — money that has
  # left the user's own set of categories.
  # ---------------------------------------------------------------------------------------------

  describe "the verification, shown failing" do
    # $200 given a job, so a lost or miswritten allocation has a figure to be wrong about.
    def a_funded_envelope
      food = envelope("Food", start: Date.new(2026, 8, 1))
      category_in(food, "Food")
      move(main, food, 200, kind: :allocation)
      food
    end

    def funded_allocation = allocations.where.not(to_category_id: nil).sole

    it "catches money allocated out to a stranger's category" do
      a_funded_envelope
      held = capture
      migrate!

      expect { reverify(held, after: -> { allocate_away_to_a_stranger(user.categories.find_by(name: "Food")) }) }
        .to raise_error(described_class::VerificationFailed, /purpose ledger .* != bank truth/)
    end

    it "catches a movement that still names an envelope" do
      food = a_funded_envelope
      held = capture
      migrate!

      expect { reverify(held, after: -> { move(main, food, 5) }) }
        .to raise_error(described_class::VerificationFailed, /1 movements still name a pool that is not an account/)
    end

    # THE PHYSICAL PARTITION'S OWN ARM, and it is the one breakage the purpose side cannot see at
    # all: `allocations` never mentions an account, so money wired out of this user's pot into
    # somebody else's bank leaves `available + Σ holdings` perfectly intact while `pot + Σ accounts`
    # comes up short by exactly the amount. Both endpoints are accounts, so the structural arm does
    # not fire either — this figure is the only thing in the file that objects.
    it "catches money moved out to a stranger's account" do
      a_funded_envelope
      held = capture
      migrate!

      expect { reverify(held, after: -> { wire_money_to_a_strangers_account }) }
        .to raise_error(described_class::VerificationFailed, /physical ledger .* != bank truth/)
    end

    # THE TWO ARMS NO TOTAL CAN SEE, and this is the whole reason #holdings_failures exists. Both
    # breakages below leave `purpose == physical == bank truth` exactly true — a lost allocation
    # returns its amount to available, a miswritten one takes the difference out of available — so
    # an earlier verifier built only of the two sums passed both of them.
    it "catches an allocation that went missing in the conversion" do
      a_funded_envelope
      held = capture
      migrate!

      expect { reverify(held, after: -> { funded_allocation.delete }) }
        .to raise_error(described_class::VerificationFailed, /pool "Food".*held 200\.0.*holds 0\.0/)
    end

    it "catches an allocation written for the wrong amount" do
      a_funded_envelope
      held = capture
      migrate!

      expect { reverify(held, after: -> { funded_allocation.update!(amount: 500) }) }
        .to raise_error(described_class::VerificationFailed, /pool "Food".*held 200\.0.*holds 500\.0/)
    end
  end

  # The migration's own verifier, re-asked of a database somebody has since broken — the same move
  # `cutover_spec`'s `#verification_message` makes, and the only way to exercise arms that no
  # successful run can trip.
  # THE SNAPSHOT THE MIGRATION TAKES OF ITSELF, taken here by the same method and at the same
  # moment — before `up` — so a sabotage example holds the conversion to exactly the figure the
  # real run would have held it to.
  def capture = migration.send(:pool_holdings_before, user.id)

  def reverify(held, after:)
    pools = described_class::MigrationPool.where(user_id: user.id).where.not(pool_type: 0).to_a
    bank = bank_truth
    after.call
    reverify_now(pools, bank, held)
  end

  def reverify_now(pools, bank, held)
    user_row = described_class::MigrationUser.find(user.id)
    migration.send(:verify!, user_row, pools: pools, category_of: fold_map(pools), bank: bank, held: held)
  end

  def fold_map(pools) = pools.to_h { |pool| [pool.id, Category.find_by(pool_id: pool.id)&.id] }

  # OUT of this user's category and into somebody else's — the one shape `Σ` can see. An allocation
  # from AVAILABLE into a stranger's category is invisible to this user's arithmetic (neither side
  # is theirs), which is exactly why the sabotage has to name one of their own categories.
  # PAST THE MODEL — `AccountMovement#accounts_must_share_a_user` refuses this row and a database does
  # not, which is the same move `cutover_spec#steal_a_movement` makes for the same reason.
  def wire_money_to_a_strangers_account
    theirs = create(:pool, :account, user: create(:user), name: "Their Bank")
    movements.create!(
      from_pool_id: main.id,
      to_pool_id: theirs.id,
      amount: 75,
      date: Time.zone.now,
      kind: 0,
      created_at: Time.current,
      updated_at: Time.current
    )
  end

  def allocate_away_to_a_stranger(category)
    stranger = create(:category, :expense, user: create(:user), name: "Someone Else's Food")
    allocations.create!(from_category_id: category.id, to_category_id: stranger.id, amount: 50, date: Time.zone.now)
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
