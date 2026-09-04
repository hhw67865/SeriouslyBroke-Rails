# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260905010000_rules_own_the_budget")

# THE TARGET'S MOVE ONTO THE RULE (rules-own-the-budget spec §6), exercised in
# `spec/migrations/drop_the_distribution_spec.rb`'s discipline: the world planted past today's model,
# every expected figure a planted literal with its working beside it, the physical invariant asked in
# raw SQL that shares nothing with the migration's own, and both refusals shown firing.
#
# WHY THE SCHEMA IS REWOUND FOR THE LENGTH OF THIS FILE. This spec's subject is the newest migration,
# so the current schema is the world AFTER it — `categories.target_amount` does not exist, and the
# `up` under test would meet a `PG::UndefinedColumn` on its first read. The shared context runs the
# `down` before the first example and the `up` after the last, which is also what proves the `down`
# correct.
#
# ** WHY EVERY CATEGORY TARGET IS PLANTED IN SQL. ** `Category#target_amount=` is an attribute of a
# column this commit deletes, and the two validations that guarded it are deleted with it — so a
# fixture written through the model would be a fixture that stops compiling the moment the rewind
# ends. An `UPDATE` is the only spelling that survives the deletion this migration exists to make,
# and it is the same move `drop_the_distribution_spec` makes with `allocations` for the same reason.
#
# ---------------------------------------------------------------------------------------------
# ** WHAT "THE CLAIM IS IDENTICAL BEFORE AND AFTER" MEANS HERE, BECAUSE IT IS NOT WHAT IT LOOKS
# LIKE. **
# ---------------------------------------------------------------------------------------------
#
# It cannot be measured by asking `ClaimCalculator` on the PRE-migration schema. That class already
# reads the rule (Task 1 moved it): before this file runs, a goal category's rule has no
# `target_amount` of its own and reads as a plain `:rate` rule — use-it-or-lose-it, built-up zero —
# which is a figure the computed-claims era never produced and no screen ever showed. Comparing
# against it would pin an artefact of the sequence.
#
# THE FIGURE THAT MUST SURVIVE IS THE COMPUTED-CLAIMS ERA'S: what the calculator answered while
# `#shape` still read `categories.target_amount` — §3.2's walk, capped at the CATEGORY's figure. Each
# one is re-derived from §3's formula in the comment above its example and planted as a literal, so
# the assertion is against the number the user was seeing rather than against the class under it.
#
# ** ONE SHAPE'S CLAIM DELIBERATELY CHANGES, AND IT IS THE DEFECT THE SPEC NAMES RATHER THAN A LOSS.
# ** An ITEM-BACKED rate rule on a goal category used to accrue toward the category's figure, because
# the shape was a fact about a neighbouring record — "two rules on one goal category both accrued
# toward the same figure" (§6's header). After the move it is what it always said it was: a rate rule.
# No fixture here plants that pair, because there is no "before" left to measure it against — the
# calculator stopped reading the category one task ago — and pinning the new figure alone would be
# pinning `ClaimCalculator`, which `claim_calculator_spec` already does.
RSpec.describe RulesOwnTheBudget do
  include_context "with the schema its subject was written for", described_class

  let(:migration) { described_class.new }

  # MONTHLY, ANCHORED ON JAN 1 2026, so a period is a calendar month and every literal below is
  # arithmetic anyone can redo by hand. UTC so the owner's day and the stored instant are the same
  # day, which is what keeps the accrual spans off the wall clock.
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

  # THE DAY EVERY FIGURE IS READ ON. Fixed rather than `Date.current` for CLAUDE.md's third flake
  # cause: a walk whose period count moves with the run day makes every planted literal wrong on some
  # mornings of the year.
  let(:today) { Date.new(2026, 9, 3) }
  let(:funding_day) { Date.new(2026, 1, 1) }
  let(:born) { Time.utc(2026, 1, 1, 9) }

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
  # Planting the world the migration is aimed at
  # ---------------------------------------------------------------------------------------------

  def holder(name, funded_since: funding_day, type: :expense)
    create(:category, type, user: user, name: name, funded_since: funded_since)
  end

  # THE CATEGORY'S FIGURE, PAST THE MODEL. See the header: the attribute and its validations are
  # deleted in this commit, so the column can only be written in SQL.
  def name_a_target(category, amount)
    sql("UPDATE categories SET target_amount = :amount WHERE id = :id", amount: amount, id: category.id)
    category
  end

  def target_of(category)
    sql_value("SELECT target_amount FROM categories WHERE id = :id", id: category.id)
  end

  # EVERY RULE IS BORN ON THE FUNDING DAY, so `ClaimCalculator#accrual_start` — `max(funded_since,
  # the rule's birthday)` — lands on the funding day and the walk visits the nine periods the
  # workings below count. A rule born at fixture time would walk one.
  def rate(category, amount, item: nil)
    create(:budget, :per_period_rate, category: category, item: item, amount: amount, created_at: born)
  end

  def dated(category, amount, on:, item: nil, every: 1)
    create(
      :budget,
      category: category,
      item: item,
      amount: amount,
      basis: :monthly,
      interval_months: every,
      anchor_date: on,
      created_at: born
    )
  end

  def spend(category, amount, on:, item_name: "Spending")
    item = category.items.find_by(name: item_name) || create(:item, category: category, name: item_name)
    create(:entry, item: item, amount: amount, date: on)
  end

  def catch_all_rule_for(category) = Budget.where(category_id: category.id, item_id: nil).sole

  # ** THE SHAPE `DropTheDistribution` MINTED, PLANTED PAST THE MODEL. ** Per-period, amount zero,
  # no anchor, no interval, and neither `carries_over` nor a target — legal at that migration's own
  # moment in the sequence and refused by `Budget#set_aside_only?` from the day Task 1's columns
  # landed. `Budget.create!` cannot write it, which is exactly why the migration has to.
  # A SECOND CATCH-ALL RULE ON A CATEGORY THAT ALREADY HAS ONE — the legacy shape
  # `#category_may_hold_one_item_less_rule` refuses, which is why it can only be planted in SQL.
  # Returns its id, so the example asserting that BOTH ids are named has one of them in hand.
  def plant_a_second_lane(category)
    id = SecureRandom.uuid
    sql(<<~SQL.squish, id: id, cid: category.id)
      INSERT INTO budgets (id, category_id, amount, basis, interval_months, carries_over, rule_type,
                           created_at, updated_at)
      VALUES (:id, :cid, 100, 1, NULL, FALSE, 1, NOW(), NOW())
    SQL
    id
  end

  def plant_a_bare_zero_rule(category)
    sql(<<~SQL.squish, id: SecureRandom.uuid, cid: category.id)
      INSERT INTO budgets (id, category_id, amount, basis, interval_months, carries_over, rule_type,
                           created_at, updated_at)
      VALUES (:id, :cid, 0, 1, NULL, FALSE, 1, NOW(), NOW())
    SQL
  end

  def claim_of(category) = category.reload.claim(today: today)

  # THE SEVEN COLUMNS A MINTED RULE IS ABOUT, in the order §2.1 row 4 names them: it demands nothing,
  # comes round every period, has no date and no interval, carries its money over, names the figure
  # it is building toward, and is typed by the column's own default.
  def columns_of(rule)
    [
      rule.amount,
      rule.basis,
      rule.anchor_date,
      rule.interval_months,
      rule.carries_over,
      rule.target_amount,
      rule.rule_type
    ]
  end

  # ** THE WORLD, AS SIX CATEGORIES. **
  #
  #   Vacation      target $1,200 with ONE item-less rate rule, $150 a period — the ordinary goal,
  #                 and the row whose target MOVES. $200 spent in July.
  #   Emergency     target $10,000 whose only rule is an item-BACKED six-monthly bill — nothing for
  #                 the target to move onto, so a catch-all rule is MINTED beside it. One category
  #                 may hold one item-less rule and it has none.
  #   House Deposit target $5,000 and NO rule at all — the mint's other arm.
  #   Groceries     no target, an item-less $400 rate rule. Untouched, and typed `usage`.
  #   Rent          no target, an item-backed $1,350 monthly bill due Sep 10. Typed `bill`.
  #   Salary        the income category the physical figures are built from.
  #
  # THE PHYSICAL FIGURES, and they are the only conserved ones:
  #   income 6,000 (Feb 2); spending 200 (Vacation, Jul 5) + 250 (Groceries, Sep 2) = 450.
  #   bank truth = 6,000 − 450 = 5,550. The 750 moved Checking → Ally nets to zero across the two
  #   accounts, so physical = 5,550 too.
  def plant_the_goal_era
    world = build_the_categories
    plant_the_physical_side(world)
    world
  end

  def build_the_categories
    vacation = name_a_target(holder("Vacation"), 1_200)
    rate(vacation, 150)
    groceries = holder("Groceries")
    rate(groceries, 400)

    {
      vacation: vacation,
      groceries: groceries,
      emergency: build_the_emergency_fund,
      rent: build_the_rent,
      house: name_a_target(holder("House Down Payment"), 5_000)
    }
  end

  # THE TARGET WHOSE ONLY RULE PAYS AN ITEM — the mint's first arm. Six-monthly, due Dec 1, so the
  # bill is `:dated` on both sides of this migration and its own claim cannot move.
  def build_the_emergency_fund
    name_a_target(holder("Emergency Fund"), 10_000).tap do |emergency|
      dated(
        emergency,
        600,
        on: Date.new(2026, 12, 1),
        every: 6,
        item: create(:item, category: emergency, name: "Deductible")
      )
    end
  end

  # A CATEGORY WITH NO TARGET CARRYING A DATED BILL — the row that is typed `bill` and touched in no
  # other way.
  def build_the_rent
    holder("Rent").tap do |rent|
      dated(rent, 1_350, on: Date.new(2026, 9, 10), item: create(:item, category: rent, name: "Monthly Rent"))
    end
  end

  # THE PHYSICAL SIDE, WHICH THIS MIGRATION MUST NOT MOVE: $6,000 in, $450 out, and $750 crossing
  # between two of the user's own accounts (which nets to zero across them).
  def plant_the_physical_side(world)
    ally = create(:pool, :account, user: user, name: "Ally")
    create(:account_movement, from_pool: main, to_pool: ally, amount: 750, date: Date.new(2026, 3, 3))
    spend(holder("Salary", type: :income, funded_since: nil), 6_000, on: Date.new(2026, 2, 2), item_name: "Paycheck")
    spend(world[:vacation], 200, on: Date.new(2026, 7, 5), item_name: "Flights")
    spend(world[:groceries], 250, on: Date.new(2026, 9, 2), item_name: "Supermarket")
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
  # The move
  # ---------------------------------------------------------------------------------------------

  it "moves a category's target onto its item-less rule and makes that rule carry over", :aggregate_failures do
    world = plant_the_goal_era

    migrate!

    rule = catch_all_rule_for(world[:vacation])
    expect([rule.carries_over, rule.target_amount]).to eq([true, 1_200.to_d])
    expect(rule.claim_calculator(today: today).shape).to eq(:building)
  end

  # ** THE FIGURE THE COMPUTED-CLAIMS ERA PRODUCED FOR THIS CATEGORY, RE-DERIVED AND PLANTED. **
  # §3.2's walk with no due date, capped at the target, over the nine monthly periods from the
  # funding day through the day this is read on. The rate is $150 a period and the cap $1,200:
  #
  #   Jan 150 · Feb 300 · Mar 450 · Apr 600 · May 750 · Jun 900
  #   Jul  gap 300 → plans min(150, 300) = 150 → accrued 1,050, less the $200 flight deposit = 850
  #   Aug  gap 350 → plans 150 → 1,000
  #   Sep  gap 200 → plans 150 → **1,150**
  #
  # It is the same walk on both sides of this migration — the era read the cap off
  # `categories.target_amount` and `ClaimCalculator` reads it off the rule — so the claim the user
  # was seeing is the claim they go on seeing, which is what §6 step 4 asks for.
  it "leaves the goal's claim exactly the figure the category's own target produced" do
    world = plant_the_goal_era

    migrate!

    expect(claim_of(world[:vacation])).to eq(1_150.to_d)
  end

  # ** A TARGET CATEGORY WHOSE ONLY RULE PAYS AN ITEM GETS A CATCH-ALL MINTED BESIDE IT. ** §3.1's
  # lane partition is why the bill cannot take the figure: its lane is the Deductible item alone,
  # while the target is what the CATEGORY is building toward. `Budget
  # #category_may_hold_one_item_less_rule` permits exactly one item-less rule and this category had
  # none, so the mint is legal beside the bill rather than instead of it.
  it "mints a catch-all rule beside an item-backed one" do
    world = plant_the_goal_era

    migrate!

    expect(columns_of(catch_all_rule_for(world[:emergency])))
      .to eq([0.to_d, "per_period", nil, nil, true, 10_000.to_d, "usage"])
  end

  # THE BILL TAKES NEITHER COLUMN, which is the half the mint alone cannot say: a target that landed
  # on the item-backed rule as well would be one figure two rules were both accruing toward.
  it "leaves the item-backed bill's build-up columns alone" do
    world = plant_the_goal_era

    migrate!

    bill = Budget.where(category_id: world[:emergency].id).where.not(item_id: nil).sole
    expect([bill.carries_over, bill.target_amount]).to eq([false, nil])
  end

  # ** THE CATEGORY'S CLAIM DOES NOT MOVE, AND THE MINTED RULE IS WHY IT CANNOT. ** A rule with an
  # anchor was `:dated` in the computed-claims era too — the anchor won over the category's figure
  # there exactly as it does here — so the bill's own walk is untouched, and the rule minted beside
  # it accrues NOTHING (amount 0, no adjustments) and adds nothing to the sum.
  #
  # THE BILL'S FIGURE, re-derived: §3.2's catch-up toward $600 due Dec 1. From the opening of period
  # k the boundaries left through Dec 1 are Jan 1 … Dec 1 = 12 in January and one fewer each month,
  # while the gap falls by the same share — so the share is $600 ÷ 12 = **$50.00** every period, and
  # nine periods hold **$450.00**. Nothing has been spent on the Deductible item, so nothing rolls.
  it "leaves a category's claim where it was when a rule is minted beside its bill", :aggregate_failures do
    world = plant_the_goal_era

    migrate!

    expect(claim_of(world[:emergency])).to eq(450.to_d)
    expect(catch_all_rule_for(world[:emergency]).claim_calculator(today: today).claim).to eq(0)
  end

  # ** A GOAL WITH NO RULE AT ALL IS A FIGURE WITH NOWHERE TO LIVE. ** Every claim comes from a rule
  # (§3.3), so the target has to BE one or it leaves with the column. The minted shape is §2.1 row 4
  # — the goal fed by hand — because inventing an amount would be inventing a standing contribution
  # the user never declared.
  it "mints a target-only rule for a goal that has none", :aggregate_failures do
    world = plant_the_goal_era

    migrate!

    minted = catch_all_rule_for(world[:house])
    expect([minted.amount, minted.carries_over, minted.target_amount, minted.item_id])
      .to eq([0.to_d, true, 5_000.to_d, nil])
    expect(claim_of(world[:house])).to eq(0)
  end

  # ** THE MINTED RULE IS A SHAPE THE MODEL ACCEPTS, ASKED OF THE MODEL — which is exactly what the
  # migration's own SQL restatement of those validations cannot do for itself. ** It matters beyond
  # tidiness: `CadenceChange#apply` writes `Budget#amount` through an unrescued `update!`, so a rule
  # minted in a shape the model refuses would reach the user as a 500 the first time they changed
  # their period, from a row they never wrote and cannot see.
  it "mints rules the model itself accepts" do
    world = plant_the_goal_era

    migrate!

    expect([catch_all_rule_for(world[:house]), catch_all_rule_for(world[:emergency])]).to all(be_valid)
  end

  # ** BORN NO LATER THAN THE DAY ITS CATEGORY STARTED HOLDING MONEY. ** `accrual_start` is
  # `max(funded_since, the rule's birthday)`, so a rule minted TODAY would open its fund's walk today
  # — and a set-aside the user afterwards dates back into the history the category has been holding
  # money through would land outside every period the walk visits and count nowhere.
  # `DropTheDistribution#birthday_for`'s ruling, and the two mints are one shape.
  it "backdates a minted rule to the day its category started holding money", :aggregate_failures do
    world = plant_the_goal_era

    migrate!

    minted = catch_all_rule_for(world[:house])
    expect(user.local_day(minted.created_at)).to be <= funding_day
    expect(minted.claim_calculator(today: today).countable_span).to cover(Date.new(2026, 2, 1))
  end

  # ---------------------------------------------------------------------------------------------
  # The types
  # ---------------------------------------------------------------------------------------------

  # ** `bill` WHERE THERE IS A DATE (§6 step 3). ** A rule with an `anchor_date` is a thing that
  # falls due on a day, which is what the word means; both dated rules on this world are one,
  # whether their category is a goal or not.
  it "types every dated rule a bill", :aggregate_failures do
    world = plant_the_goal_era

    migrate!

    expect(Budget.where(category_id: world[:rent].id).sole.rule_type).to eq("bill")
    expect(Budget.where(category_id: world[:emergency].id).where.not(item_id: nil).sole.rule_type).to eq("bill")
  end

  # ** `usage` FOR EVERYTHING ELSE, WHICH IS THE COLUMN'S OWN DEFAULT AND A RULING RATHER THAN A
  # CONVENIENCE. ** It is the widest of the three, so a rule typed by nobody claims neither that it
  # must be paid nor that it is discretionary; the Budget page prints the label, so the default is
  # visible to the user who reclassifies it.
  it "leaves every anchorless rule usage", :aggregate_failures do
    world = plant_the_goal_era

    migrate!

    expect(Budget.where(category_id: world[:groceries].id).sole.rule_type).to eq("usage")
    expect(catch_all_rule_for(world[:vacation]).rule_type).to eq("usage")
  end

  # A RULE ON A CATEGORY WITH NO TARGET IS UNTOUCHED BY THE MOVE, and its claim is what it always
  # was: §3.1's `max(0, rate + Σ deltas − spent)` = `max(0, 400 − 250)` = **$150.00** for the
  # September period this is read in.
  it "leaves a category with no target alone", :aggregate_failures do
    world = plant_the_goal_era

    migrate!

    rule = catch_all_rule_for(world[:groceries])
    expect([rule.carries_over, rule.target_amount]).to eq([false, nil])
    expect(claim_of(world[:groceries])).to eq(150.to_d)
  end

  # THE DATED BILL'S OWN CLAIM, unchanged by a migration that only typed it: §3.2's catch-up toward
  # $1,350 due Sep 10, with nine boundaries left from January (Jan 1 … Sep 10) and one fewer each
  # month — $1,350 ÷ 9 = **$150.00** a period, and nine periods hold the whole **$1,350.00**.
  it "leaves a dated rule's claim where it was" do
    world = plant_the_goal_era

    migrate!

    expect(claim_of(world[:rent])).to eq(1_350.to_d)
  end

  # ---------------------------------------------------------------------------------------------
  # The column
  # ---------------------------------------------------------------------------------------------

  it "drops the category's target column" do
    plant_the_goal_era

    migrate!

    expect(connection.column_exists?(:categories, :target_amount)).to be(false)
  end

  # ---------------------------------------------------------------------------------------------
  # The physical invariant
  # ---------------------------------------------------------------------------------------------

  it "leaves the physical invariant exactly where it was", :aggregate_failures do
    plant_the_goal_era
    before = [physical_total, bank_truth]
    expect(before).to eq([5_550.to_d, 5_550.to_d])

    migrate!

    expect([physical_total, bank_truth]).to eq(before)
  end

  it "writes nothing to the physical tables at all", :aggregate_failures do
    plant_the_goal_era
    counts = -> { [Entry.count, AccountMovement.count, Pool.count] }
    before = counts.call

    migrate!

    expect(counts.call).to eq(before)
    expect(before).to eq([3, 1, 2])
  end

  # ---------------------------------------------------------------------------------------------
  # The receipt
  # ---------------------------------------------------------------------------------------------

  # ** EVERY FIGURE IS A COUNT OF ROWS THIS RUN WROTE. ** The usage figure used to be a census of
  # every `usage` row in the table, so a user whose rules this file barely touched read "9 typed
  # usage" about nine rows it had not written a byte of: `usage` is the column's DEFAULT (§6.3), so
  # an anchorless rule was already `usage` before the typing UPDATE ran. The only rows this file
  # types usage are the ones it MINTS, which is why they are one clause. The plural forms are
  # asserted too — "1 targets moved" is the kind of line that makes a reader wonder what else the
  # file is careless about.
  it "counts what it moved, minted and typed", :aggregate_failures do
    plant_the_goal_era

    lines = receipts

    expect(lines).to include(
      *[
        "ming@example.com: 1 target moved onto rules; 2 rules minted and typed usage; 2 rules typed bill",
        "2 rules typed bill; every other rule kept the column's usage default",
        "ming@example.com: physical 5550.0 == bank 5550.0, unchanged"
      ].map { |line| a_string_including(line) }
    )
  end

  # ---------------------------------------------------------------------------------------------
  # The refusals
  # ---------------------------------------------------------------------------------------------

  it "refuses nothing on the world the goal era leaves behind" do
    plant_the_goal_era

    expect { migrate! }.not_to raise_error
  end

  # ** A DATED RULE CANNOT CARRY OVER, SO A TARGET CANNOT MOVE ONTO ONE. **
  # `Budget#build_up_must_be_valid` refuses the pair outright — a dated rule's build-up is defined by
  # its date — and the category's lane is that one rule, so there is nowhere else to put the figure.
  # Both ways out are decisions about the user's money, so the row is named and the run refuses.
  it "refuses a target whose catch-all rule has a due date", :aggregate_failures do
    plant_the_goal_era
    rainy = name_a_target(holder("Rainy Day"), 2_000)
    dated(rainy, 900, on: Date.new(2026, 11, 1))

    expect { migrate! }.to raise_error(described_class::PreflightFailed, /Rainy Day.*due date/)
    expect(target_of(rainy)).to be_present
  end

  # ** A $0 RULE THAT NO TARGET WILL REPAIR (Task 1's carry). ** `DropTheDistribution` minted its
  # zeroes against the CATEGORY's target, and `#move_the_targets` is what repairs every one of those
  # — they are item-less rules on categories that name a figure. What is left is a rule that demands
  # nothing and builds toward nothing, which `Budget#set_aside_only?` refuses outright.
  #
  # PLANTED IN SQL, because the model refuses the shape: that is the whole point of the check.
  it "refuses a zero-amount rule that names no target", :aggregate_failures do
    plant_the_goal_era
    plant_a_bare_zero_rule(holder("Fuel"))

    expect { migrate! }.to raise_error(described_class::PreflightFailed, /Fuel.*names no target/)
    expect(connection.column_exists?(:categories, :target_amount)).to be(true)
  end

  # THE SAME ROW ON A CATEGORY THAT DOES NAME A FIGURE IS THE ONE THIS MIGRATION REPAIRS, and it is
  # asserted beside the refusal so the refusal cannot be passing because every $0 rule is refused.
  it "repairs a zero-amount rule whose category names a target", :aggregate_failures do
    world = plant_the_goal_era
    someday = name_a_target(holder("Someday"), 3_000)
    plant_a_bare_zero_rule(someday)

    migrate!

    expect(catch_all_rule_for(someday)).to be_valid
    expect(catch_all_rule_for(someday).target_amount).to eq(3_000)
    expect(claim_of(world[:vacation])).to eq(1_150.to_d)
  end

  # ** TWO RULES WITH NO ITEM SHARE ONE LANE, AND THIS RUN CANNOT CHOOSE BETWEEN THEM. **
  # `Budget#category_may_hold_one_item_less_rule` is younger than the data it guards, so the pair is
  # a shape a restore can carry. `CATEGORY_LANE` would hand the target to the OLDER and leave the
  # younger beside it — a category coming out of the migration with one catch-all holding a fund and
  # another claiming the same lane, refused at the far end of the run by `#malformed_rules` under a
  # sentence naming neither as the other's twin. Which one the user meant is a decision about their
  # money, so it is named BEFORE anything moves.
  #
  # PLANTED IN SQL, because `Budget` refuses the second rule outright — which is the whole point.
  it "refuses a category carrying two rules with no item", :aggregate_failures do
    world = plant_the_goal_era
    plant_a_second_lane(world[:vacation])

    expect { migrate! }.to raise_error(described_class::PreflightFailed, /Vacation has two rules with no item/)
    expect(target_of(world[:vacation])).to be_present
  end

  # BOTH IDS ARE NAMED, because "keep one" is not actionable without them.
  it "names both rules of a duplicate lane" do
    world = plant_the_goal_era
    second = plant_a_second_lane(world[:vacation])
    first = Budget.where(category_id: world[:vacation].id, item_id: nil).where.not(id: second).sole

    expect { migrate! }.to raise_error(described_class::PreflightFailed, /#{first.id}, #{second}/)
  end

  # ** THE OTHER DIRECTION, AND IT IS THE ONE A CARELESS `GROUP BY` WOULD GET WRONG. ** An item-less
  # rule beside an item-BACKED one is the demo's own commonest shape (§3.1's lane partition: a
  # catch-all rate rule beside a dated bill), and it is not a duplicate of anything — the two lanes
  # are disjoint by construction.
  it "does not call an item-less rule beside an item-backed one a duplicate" do
    world = plant_the_goal_era
    dated(
      world[:groceries],
      90,
      on: Date.new(2026, 11, 1),
      item: create(:item, category: world[:groceries], name: "Bulk order")
    )

    expect { migrate! }.not_to raise_error
  end

  # ** A TARGET OF ZERO IS ALREADY MET, AND WITHOUT THIS ARM POSTGRES SAYS SO WITHOUT NAMING ANYONE.
  # ** `Category#target_is_a_goal` refused the figure and `update_column` walks past it, so a legacy
  # `0` is a shape a restore can carry. It would reach `budgets_positive_target_amount` — the same
  # sentence re-stated on the new owner — and come back as a `PG::CheckViolation` naming a constraint
  # and a table: no owner, no category, no figure. Named here instead.
  it "refuses a target of zero, naming the category and the figure", :aggregate_failures do
    plant_the_goal_era
    name_a_target(holder("Someday"), 0)

    expect { migrate! }
      .to raise_error(described_class::PreflightFailed, /Someday names a target of \$0\.00, which is not a goal/)
    expect(connection.column_exists?(:categories, :target_amount)).to be(true)
  end

  # ** A TARGET ON A CATEGORY THAT CANNOT HOLD A RULE. ** `Budget#category_must_be_an_expense`
  # refuses a rule on an income category, so neither the move nor the mint has anywhere to land —
  # and skipping it would drop the column with the figure still on it.
  it "refuses a target on a category that is not an expense" do
    plant_the_goal_era
    name_a_target(holder("Bonus", type: :income, funded_since: nil), 4_000)

    expect { migrate! }.to raise_error(described_class::PreflightFailed, /Bonus.*not an expense/)
  end

  # ** REFUSING ITS OWN OUTPUT. ** A pre-existing rule that names a target while its money RESETS is
  # `#build_up_must_be_valid`'s second refusal — a cap on money that resets is a number no formula
  # reads — and it is inside `#malformed_rules`' scope because a target is exactly what this
  # migration is answerable for. Planted past the model, which is what makes the check the authority.
  it "refuses to commit a rule the app itself would reject", :aggregate_failures do
    world = plant_the_goal_era
    sql(
      "UPDATE budgets SET target_amount = 500 WHERE category_id = :cid",
      cid: world[:groceries].id
    )

    expect { migrate! }.to raise_error(described_class::VerificationFailed, /Groceries/)
    expect(connection.column_exists?(:categories, :target_amount)).to be(true)
  end

  # ---------------------------------------------------------------------------------------------
  # The `down`
  # ---------------------------------------------------------------------------------------------

  # ** THE COLUMN AND THE FIGURE, WHICH IS WHAT THE SCHEMA REWIND NEEDS. **
  # `spec/support/schema_rewind.rb` runs `CategoriesHoldTheMoney#down` (which REMOVES this column)
  # and `DropTheDistribution#up` (which READS it), so a `down` that restored only the shape would
  # leave four migration specs planting against a figure that had silently become NULL.
  #
  # THE MINTED RULE STAYS, and so does every type: those are the app's rows now, and a `down` that
  # deleted them would take a user's own edits with them. A rolled-back database therefore carries
  # the figure in both places, which is the honest state of a half-rewound sequence.
  it "puts the column and every figure back on the way down", :aggregate_failures do
    world = plant_the_goal_era
    migrate!

    migration.suppress_messages { migration.down }
    refresh_columns

    expect(connection.column_exists?(:categories, :target_amount)).to be(true)
    expect([target_of(world[:vacation]), target_of(world[:house])]).to eq(["$1,200.00", "$5,000.00"])
    expect(catch_all_rule_for(world[:house]).target_amount).to eq(5_000)
  end

  it "leaves a category that never had a target without one on the way down" do
    world = plant_the_goal_era
    migrate!

    migration.suppress_messages { migration.down }
    refresh_columns

    expect(target_of(world[:groceries])).to be_nil
  end
end
