# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260903010000_drop_the_distribution")

# THE DISTRIBUTION'S DELETION (computed-claims spec §5/§6/§7), exercised in
# `spec/migrations/drop_the_pool_layer_spec.rb`'s discipline: the world planted past today's model,
# every expected figure a planted literal, the physical invariant asked in raw SQL that shares
# nothing with the migration's own, and the verifier shown failing.
#
# WHY THE SCHEMA IS REWOUND FOR THE LENGTH OF THIS FILE. This spec's subject is the newest
# migration, so the current schema is the world AFTER it — `allocations` does not exist and
# `drop_table` would meet nothing. The shared context runs the `down` before the first example and
# the `up` after the last, which is also what proves the `down` correct.
#
# ** WHY EVERY ALLOCATION IS PLANTED IN SQL. ** `Allocation`, its factory and `Category
# #allocations_in`/`#allocations_out` are all deleted in the same commit as this file — there is no
# model left to plant one through, not even with `save!(validate: false)`. Planting in SQL is the
# only spelling that survives the deletion this migration exists to make possible, and it is the
# same move `drop_the_pool_layer_spec` makes with `pools` for the same reason.
#
# WHAT IS NOT ASSERTED HERE, AND WHY IT WOULD BE THE WRONG TEST. There is no "Σ holdings unchanged"
# to pin: §2 says the purpose side stops being a conserved partition the moment claims are derived,
# so the acceptance test is the PHYSICAL invariant (`pot + Σ accounts == income − expenses`) plus a
# row-by-row account of where every allocation went. Both are here.
RSpec.describe DropTheDistribution do
  include_context "with the schema its subject was written for", described_class

  let(:migration) { described_class.new }
  let(:user) do
    create(
      :user,
      email: "ming@example.com",
      timezone: "UTC",
      period_cadence: :monthly,
      period_anchor_date: Date.new(2026, 1, 1)
    )
  end
  let(:main) { create(:pool, :account, user: user, name: "Checking") }

  before do
    refresh_columns
    user.update!(default_account: main)
  end

  def refresh_columns = [Budget, Category, Entry, Pool, Adjustment].each(&:reset_column_information)

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

  delegate :connection, to: :"ActiveRecord::Base"

  def sql(statement, **binds)
    connection.execute(ActiveRecord::Base.sanitize_sql_array([statement, binds]))
  end

  def sql_value(statement, **binds)
    connection.select_value(ActiveRecord::Base.sanitize_sql_array([statement, binds]))
  end

  def sql_decimal(statement, **binds) = BigDecimal(sql_value(statement, **binds).to_s)

  # ---------------------------------------------------------------------------------------------
  # Planting the distribution era
  # ---------------------------------------------------------------------------------------------

  # `kind` 0 is a transfer (a hand move), 1 an allocation and 2 a sweep — spelled as integers
  # because the enum that named them is being deleted in this same commit.
  def plant_allocation(amount:, on:, to: nil, from: nil, kind: 0)
    id = SecureRandom.uuid
    sql(<<~SQL.squish, id: id, from: from&.id, to: to&.id, amount: amount, kind: kind, on: on)
      INSERT INTO allocations (id, from_category_id, to_category_id, amount, kind, date,
                               created_at, updated_at)
      VALUES (:id, :from, :to, :amount, :kind, :on, NOW(), NOW())
    SQL
    id
  end

  def category(name, funded_since: nil, target: nil, type: :expense)
    create(:category, type, user: user, name: name, funded_since: funded_since, target_amount: target)
  end

  def spend(cat, amount, on:)
    create(:entry, item: create(:item, category: cat), amount: amount, date: on)
  end

  def adjustments_on(rule) = Adjustment.where(rule_id: rule.id).order(:date).pluck(:date, :amount)

  def catch_all_rule_for(cat) = Budget.where(category_id: cat.id, item_id: nil).sole

  # ** THE WORLD THIS MIGRATION IS AIMED AT, AS SEVEN PLANTED ROWS. **
  #
  #   Groceries  funded Jan 1, carries TWO rules — a catch-all $400 a month and a $600 dated bill
  #              on its Premium item. Set aside $250 on Sep 1; released $80 on Sep 2.
  #   Vacation   funded Jun 1, a GOAL: target $1,200 on the category and NO rule at all.
  #              Set aside $500 on Jul 5.
  #   Car        funded Jan 1, one catch-all rule WRITTEN ON AUG 15 — so a $90 set-aside dated
  #              Feb 10 lies before the rule's countable span and is converted all the same.
  #   Car -> Vacation  $40 on Aug 20: the one transfer with two category ends.
  #   an allocation (available -> Groceries, $400, Sep 1) and a sweep (Groceries -> available,
  #              $30, Aug 31): distribution mechanics, deleted rather than converted.
  #
  # THE PHYSICAL FIGURES, and they are the only conserved ones:
  #   income 3,000 (Aug 2); spending 150 (Groceries, Sep 2). bank truth = 3,000 − 150 = 2,850.
  #   The 750 moved Checking → Ally nets to zero across the two accounts, so physical = 2,850 too.
  def plant_the_distribution_era
    world = build_the_categories
    plant_the_physical_side(world)
    plant_allocation(to: world[:groceries], amount: 250, on: Time.utc(2026, 9, 1, 10))
    plant_allocation(from: world[:groceries], amount: 80, on: Time.utc(2026, 9, 2, 10))
    plant_allocation(to: world[:vacation], amount: 500, on: Time.utc(2026, 7, 5, 10))
    plant_allocation(to: world[:car], amount: 90, on: Time.utc(2026, 2, 10, 10))
    plant_the_mechanics(world)
    world
  end

  # The two rows that are not converted into anything, and the one transfer with two category ends.
  def plant_the_mechanics(world)
    plant_allocation(from: world[:car], to: world[:vacation], amount: 40, on: Time.utc(2026, 8, 20, 10))
    plant_allocation(to: world[:groceries], amount: 400, on: Time.utc(2026, 9, 1, 11), kind: 1)
    plant_allocation(from: world[:groceries], amount: 30, on: Time.utc(2026, 8, 31, 11), kind: 2)
  end

  def build_the_categories
    groceries = category("Groceries", funded_since: Date.new(2026, 1, 1))
    rate(groceries, 400)
    bill(groceries, 600, on: create(:item, category: groceries, name: "Premium"))
    car = category("Car", funded_since: Date.new(2026, 1, 1))
    born_on(rate(car, 120), Time.utc(2026, 8, 15, 9))
    {
      groceries: groceries,
      vacation: category("Vacation", funded_since: Date.new(2026, 6, 1), target: 1_200),
      car: car
    }
  end

  def rate(cat, amount)
    create(:budget, category: cat, item: nil, amount: amount, basis: :monthly, interval_months: 1)
  end

  def bill(cat, amount, on:)
    create(
      :budget,
      category: cat,
      item: on,
      amount: amount,
      basis: :monthly,
      interval_months: 6,
      anchor_date: Date.new(2026, 12, 1)
    )
  end

  # THE PHYSICAL SIDE, WHICH THIS MIGRATION MUST NOT MOVE: $3,000 in, $150 out, and $750 crossing
  # between two of the user's own accounts (which nets to zero across them).
  def plant_the_physical_side(world)
    ally = create(:pool, :account, user: user, name: "Ally")
    create(:account_movement, from_pool: main, to_pool: ally, amount: 750, date: Date.new(2026, 8, 3))
    spend(category("Salary", type: :income), 3_000, on: Date.new(2026, 8, 2))
    spend(world[:groceries], 150, on: Date.new(2026, 9, 2))
  end

  # PAST THE MODEL, deliberately: `created_at` is not writable through `update!` in any spelling that
  # a reader would trust, and the DAY A RULE WAS BORN is the whole subject of two examples here —
  # `ClaimCalculator#accrual_start` is `max(funded_since, the rule's birthday)`.
  def born_on(rule, moment)
    rule.update_column(:created_at, moment) # rubocop:disable Rails/SkipsModelValidations
    rule
  end

  # ---------------------------------------------------------------------------------------------
  # THE PHYSICAL INVARIANT, asked independently of the migration — from `entries`, `pools` and
  # `account_movements` alone, so an error in the migration's formula cannot answer wrong on both
  # sides of the comparison.
  # ---------------------------------------------------------------------------------------------

  def bank_truth
    sql_decimal(<<~SQL.squish, uid: user.id)
      SELECT COALESCE(SUM(CASE WHEN c.category_type = 1 THEN e.amount::numeric
                               ELSE -e.amount::numeric END), 0)
      FROM entries e JOIN items i ON i.id = e.item_id JOIN categories c ON c.id = i.category_id
      WHERE c.user_id = :uid
    SQL
  end

  def physical_total
    sql_decimal(<<~SQL.squish, uid: user.id)
      SELECT COALESCE((SELECT SUM(CASE WHEN c.category_type = 1 THEN e.amount::numeric
                                       ELSE -e.amount::numeric END)
                         FROM entries e
                         JOIN items i ON i.id = e.item_id
                         JOIN categories c ON c.id = i.category_id
                        WHERE c.user_id = :uid), 0)
           + COALESCE((SELECT SUM(m.amount::numeric) FROM account_movements m
                        WHERE m.to_pool_id IN (SELECT id FROM pools WHERE user_id = :uid AND pool_type = 0)), 0)
           - COALESCE((SELECT SUM(m.amount::numeric) FROM account_movements m
                        WHERE m.from_pool_id IN (SELECT id FROM pools WHERE user_id = :uid AND pool_type = 0)), 0)
    SQL
  end

  # ---------------------------------------------------------------------------------------------
  # The conversion
  # ---------------------------------------------------------------------------------------------

  it "turns a set-aside into a positive adjustment on the category's item-less rule, at its own date" do
    world = plant_the_distribution_era

    migrate!

    expect(adjustments_on(catch_all_rule_for(world[:groceries])))
      .to include([Time.utc(2026, 9, 1, 10), 250.to_d])
  end

  it "turns a release into a negative adjustment on the same rule" do
    world = plant_the_distribution_era

    migrate!

    expect(adjustments_on(catch_all_rule_for(world[:groceries])))
      .to include([Time.utc(2026, 9, 2, 10), -80.to_d])
  end

  # THE ITEM-BACKED RULE TAKES NOTHING. §3.1's lane partition is what makes the catch-all the right
  # arm: an item-less rule's lane is the whole category, which is the lane the money was set aside
  # for, while the Premium bill's lane is one item's spending.
  it "leaves the category's item-backed rule alone" do
    world = plant_the_distribution_era

    migrate!

    bill = Budget.where(category_id: world[:groceries].id).where.not(item_id: nil).sole
    expect(adjustments_on(bill)).to be_empty
  end

  # ONE TRANSFER, TWO ADJUSTMENTS — the source's fund really did fall by $40 and the destination's
  # really did rise by $40, and converting one end only would record half of a move the user made
  # whole.
  it "splits a category-to-category transfer into one adjustment each way", :aggregate_failures do
    world = plant_the_distribution_era

    migrate!

    expect(adjustments_on(catch_all_rule_for(world[:car])))
      .to include([Time.utc(2026, 8, 20, 10), -40.to_d])
    expect(adjustments_on(catch_all_rule_for(world[:vacation])))
      .to include([Time.utc(2026, 8, 20, 10), 40.to_d])
  end

  # THE SET-ASIDE DATED BEFORE THE RULE'S COUNTABLE SPAN IS STILL CONVERTED. Car's rule was written
  # on Aug 15, so `ClaimCalculator#countable_span` opens on Aug 1 and a Feb 10 row moves no figure —
  # and it is the user's own history all the same. `AdjustmentForm` is the ONE door that refuses a
  # date outside the span, and it is a door a PERSON types at.
  it "converts a transfer dated before its rule's countable span, at the original date", :aggregate_failures do
    world = plant_the_distribution_era

    migrate!

    rule = catch_all_rule_for(world[:car])
    expect(adjustments_on(rule)).to include([Time.utc(2026, 2, 10, 10), 90.to_d])
    expect(rule.claim_calculator(today: Date.new(2026, 9, 3)).countable_span)
      .not_to cover(Date.new(2026, 2, 10))
  end

  # ---------------------------------------------------------------------------------------------
  # The minted rule
  # ---------------------------------------------------------------------------------------------

  it "mints a target-only rule for a goal that has none, and puts the set-aside on it", :aggregate_failures do
    world = plant_the_distribution_era

    migrate!

    rule = catch_all_rule_for(world[:vacation])
    expect([rule.amount, rule.basis, rule.anchor_date, rule.interval_months, rule.item_id])
      .to eq([0.to_d, "per_period", nil, nil, nil])
    expect(adjustments_on(rule)).to include([Time.utc(2026, 7, 5, 10), 500.to_d])
  end

  # THE SHAPE IS ONE THE APP ITSELF COULD HAVE WRITTEN, asked of the MODEL here — which is exactly
  # what the migration's own SQL restatement of those validations cannot do for itself. It matters
  # beyond tidiness: `CadenceChange#apply` writes `Budget#amount` through an unrescued `update!`, so
  # a rule minted in a shape the model refuses would reach the user as a 500 the first time they
  # changed their period, from a row they never wrote and cannot see.
  #
  # ** THE MODEL MOVED UNDER THIS MIGRATION, AND THE EXAMPLE SAYS SO RATHER THAN GOING QUIET
  # (rules-own-the-budget spec §2.1 row 4, §6). ** `Budget#set_aside_only?` reads `carries_over` and
  # `target_amount` off the RULE now; this migration writes neither, because at ITS moment in the
  # sequence the columns do not exist — `RulesOwnTheBudgetColumns` runs two days later. So the row it
  # mints is legal when it is written and a shape the model refuses by the time the next migration
  # runs, which is an ordinary state for a database mid-sequence and NOT a defect in either file. The
  # data migration that fills the two columns in is what closes it; both halves are pinned here, so
  # neither "it stopped being valid" nor "the fix-up shape is wrong" can pass silently.
  it "mints a rule the model accepts once the target is moved onto it", :aggregate_failures do
    world = plant_the_distribution_era

    migrate!

    rule = catch_all_rule_for(world[:vacation])
    expect(rule).not_to be_valid
    rule.assign_attributes(carries_over: true, target_amount: world[:vacation].target_amount)
    expect(rule).to be_valid
  end

  # BORN NO LATER THAN THE DAY ITS CATEGORY STARTED HOLDING MONEY. `accrual_start` is
  # `max(funded_since, the rule's birthday)`, so a rule minted TODAY would walk no period the July
  # set-aside is dated in and the goal would read $0.00 built up the morning after this runs.
  #
  # THE BUILT-UP IS READ THROUGH THE SHAPE THE NEXT MIGRATION GIVES IT, for the reason the example
  # above states: a rule that neither carries over nor names a figure is a use-it-or-lose-it RATE
  # rule to today's `ClaimCalculator`, and a rate rule's built-up is zero by definition. The
  # BIRTHDAY is this migration's own subject and is asserted before anything is assigned.
  it "backdates the minted rule so the history it inherits still counts", :aggregate_failures do
    world = plant_the_distribution_era

    migrate!

    rule = catch_all_rule_for(world[:vacation])
    expect(user.local_day(rule.created_at)).to be <= Date.new(2026, 6, 1)
    rule.update!(carries_over: true, target_amount: world[:vacation].target_amount)
    expect(rule.claim_calculator(today: Date.new(2026, 9, 3)).built_up).to eq(540.to_d)
  end

  # $500 in on Jul 5 and $40 in on Aug 20 is $540 built up of a $1,200 target, with nothing spent
  # against it — the figure the example above pins, restated as the thing a user would read.

  # ---------------------------------------------------------------------------------------------
  # The mechanics, deleted
  # ---------------------------------------------------------------------------------------------

  # ASSERTED IN TWO STATEMENTS RATHER THAN WITH `change`, because the table is GONE by the time the
  # matcher would read it a second time — the count after the run is taken from `adjustments`, which
  # is where every row that survived went.
  it "deletes every allocation and sweep row", :aggregate_failures do
    plant_the_distribution_era
    expect(sql_value("SELECT COUNT(*) FROM allocations WHERE kind IN (1, 2)").to_i).to eq(2)

    migrate!

    expect(connection.table_exists?(:allocations)).to be(false)
  end

  it "writes no adjustment for a deleted allocation or sweep" do
    plant_the_distribution_era

    migrate!

    expect(Adjustment.count).to eq(6)
  end

  it "drops the allocations table" do
    plant_the_distribution_era

    migrate!

    expect(connection.table_exists?(:allocations)).to be(false)
  end

  # ---------------------------------------------------------------------------------------------
  # The physical invariant
  # ---------------------------------------------------------------------------------------------

  it "leaves the physical invariant exactly where it was", :aggregate_failures do
    plant_the_distribution_era
    before = [physical_total, bank_truth]
    expect(before).to eq([2_850.to_d, 2_850.to_d])

    migrate!

    expect([physical_total, bank_truth]).to eq(before)
  end

  it "writes nothing to the physical tables at all", :aggregate_failures do
    plant_the_distribution_era
    counts = -> { [Entry.count, AccountMovement.count, Pool.count] }
    before = counts.call

    migrate!

    expect(counts.call).to eq(before)
    expect(before).to eq([2, 1, 2])
  end

  # ---------------------------------------------------------------------------------------------
  # The receipt
  # ---------------------------------------------------------------------------------------------

  it "counts what it converted, minted and discarded", :aggregate_failures do
    plant_the_distribution_era

    lines = receipts

    expect(lines).to include(a_string_including("ming@example.com: 5 transfers -> 6 adjustments; 1 target-only rules minted"))
    expect(lines).to include(a_string_including("5 transfers converted into 6 adjustments; 1 rules minted; 2 allocation/sweep rows discarded"))
    expect(lines).to include(a_string_including("ming@example.com: physical 2850.0 == bank 2850.0, unchanged"))
  end

  # THE ROW THAT COUNTS NOWHERE IS SAID OUT LOUD. A set-aside dated before its category started
  # holding money falls outside every period `ClaimCalculator` walks, so it is written, correct and
  # invisible — an operator should be told rather than left to find it.
  it "says how many converted rows land before their category started holding money" do
    world = plant_the_distribution_era
    plant_allocation(to: world[:vacation], amount: 60, on: Time.utc(2026, 5, 1, 10))

    expect(receipts)
      .to include(a_string_including("1 converted rows are dated before their category started holding money"))
  end

  it "says nothing about stranded rows when there are none" do
    plant_the_distribution_era

    expect(receipts).not_to include(a_string_including("count nowhere"))
  end

  # ---------------------------------------------------------------------------------------------
  # The refusals
  # ---------------------------------------------------------------------------------------------

  it "refuses nothing on the world the distribution era leaves behind" do
    plant_the_distribution_era

    expect { migrate! }.not_to raise_error
  end

  # A CATEGORY WITH SET-ASIDES, NO CATCH-ALL RULE AND NO TARGET has no honest rule to write:
  # inventing a `target_amount` would be inventing the user's goal.
  it "refuses a set-aside on a category it can neither find nor mint a rule for", :aggregate_failures do
    plant_the_distribution_era
    orphan = category("Holiday Fund", funded_since: Date.new(2026, 5, 1))
    plant_allocation(to: orphan, amount: 300, on: Time.utc(2026, 6, 1, 10))

    expect { migrate! }.to raise_error(described_class::PreflightFailed, /Holiday Fund/)
    expect(sql_value("SELECT COUNT(*) FROM allocations").to_i).to eq(8)
  end

  it "names the owner and the number of set-asides at stake" do
    plant_the_distribution_era
    orphan = category("Holiday Fund", funded_since: Date.new(2026, 5, 1))
    plant_allocation(to: orphan, amount: 300, on: Time.utc(2026, 6, 1, 10))
    plant_allocation(to: orphan, amount: 20, on: Time.utc(2026, 6, 2, 10))

    expect { migrate! }
      .to raise_error(described_class::PreflightFailed, /ming@example\.com: Holiday Fund cannot take its 2/)
  end

  # `kind` carries no CHECK — the three members lived in the enum alone — so a fourth integer is a
  # row the conversion would skip and the delete would miss, and the drop would take it away
  # without a word.
  it "refuses an allocation whose kind it does not know" do
    world = plant_the_distribution_era
    plant_allocation(to: world[:groceries], amount: 10, on: Time.utc(2026, 9, 1, 12), kind: 7)

    expect { migrate! }.to raise_error(described_class::PreflightFailed, /kind 7/)
  end

  # ** THE ADJUSTMENT CHECK CANNOT BE HIT, AND THIS IS WHY (fix round 1 — L2). ** `adjustments`
  # carries `amount <> 0::money` (`adjustments_non_zero_amount`), and every row this migration
  # writes copies a transfer's amount verbatim — so a $0 transfer would be an unrescued
  # `StatementInvalid` in the middle of `insert_all!`. It cannot exist: `allocations` has carried
  # `amount > 0::money` since `588c15d` (`allocations_positive_amount`), which is the constraint
  # asserted here rather than assumed. The migration therefore needs no guard of its own, and this
  # example is what would fail if the constraint were ever dropped from under it.
  it "cannot be handed a zero-amount transfer to convert" do
    world = plant_the_distribution_era

    expect { plant_allocation(to: world[:groceries], amount: 0, on: Time.utc(2026, 9, 1, 13)) }
      .to raise_error(ActiveRecord::StatementInvalid, /allocations_positive_amount/)
  end

  # ** REFUSING ITS OWN OUTPUT. ** The zero-amount shape is legal only where the category names a
  # target, so a zero-amount rule on a category with none is exactly what `#malformed_minted_rules`
  # is looking for. Planted in SQL because `Budget` refuses the shape at the model, which is the
  # whole point of the check.
  it "refuses to commit a zero-amount rule the app itself would reject", :aggregate_failures do
    plant_the_distribution_era
    plain = category("Fuel", funded_since: Date.new(2026, 1, 1))
    sql(<<~SQL.squish, id: SecureRandom.uuid, cid: plain.id)
      INSERT INTO budgets (id, category_id, amount, basis, interval_months, created_at, updated_at)
      VALUES (:id, :cid, 0, 1, NULL, NOW(), NOW())
    SQL

    expect { migrate! }.to raise_error(described_class::VerificationFailed, /Fuel/)
    expect(connection.table_exists?(:allocations)).to be(true)
  end

  # ** THE OTHER DIRECTION, AND IT IS THE ONE THE VERIFIER GOT WRONG (fix round 1 — M1). ** The SQL
  # flagged `b.item_id IS NOT NULL` on every zero-amount rule and applied
  # `#category_may_hold_one_item_less_rule` to item-BACKED rules too, and `Budget` does neither:
  # `#set_aside_only?` never reads `item_id`, and that validation returns early wherever one is
  # present. So a per-period, amount-0, item-backed rule on a category with a target is a shape the
  # app ACCEPTS — and on a restore carrying one the whole migration aborted.
  #
  # PLANTED THROUGH THE MODEL, which is the assertion: `create` would raise if `Budget` refused it,
  # and `#valid?` is asserted beside it so the example says out loud which layer is the authority.
  #
  # `carries_over` AND `target_amount` ON THE RULE are what make the $0 amount legal today
  # (rules-own-the-budget spec §2.1 row 4); the CATEGORY's target is what the migration's SQL
  # verifier reads, and this fixture carries both because the two readers have not yet been moved
  # onto one column. The verifier's own reading is what this example is about, and it is unchanged.
  it "accepts a pre-existing item-backed $0 rule on a category with a target", :aggregate_failures do
    world = plant_the_distribution_era
    tips = create(:item, category: world[:vacation], name: "Flights")
    set_aside_only = create(:budget, :hand_fed, category: world[:vacation], item: tips, target_amount: 1_200)

    expect(set_aside_only).to be_valid
    expect { migrate! }.not_to raise_error
    expect(set_aside_only.reload.amount).to eq(0)
  end

  # ---------------------------------------------------------------------------------------------
  # The `down`
  # ---------------------------------------------------------------------------------------------

  # SHAPE ONLY, AND IT IS FOR THE SCHEMA REWIND — `spec/support/schema_rewind.rb` runs
  # `CategoriesHoldTheMoney#up`, whose whole subject is creating `allocations` and filling it, so a
  # `down` here that raised would leave three migration specs unable to reach the world their own
  # subjects were written for. The rows are gone; a real reversal is a restore.
  it "restores the table's shape on the way back down", :aggregate_failures do
    plant_the_distribution_era
    migrate!

    migration.suppress_messages { migration.down }

    expect(connection.table_exists?(:allocations)).to be(true)
    expect(sql_value("SELECT COUNT(*) FROM allocations").to_i).to eq(0)
  end
end
