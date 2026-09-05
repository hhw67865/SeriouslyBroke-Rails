# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260906000000_two_shapes")

# EVERY FUND BECOMES A DATED RULE (two-shapes spec §6), exercised in
# `spec/migrations/rules_own_the_budget_spec.rb`'s discipline: the world planted past today's model
# where the model refuses it, every expected figure a planted literal with its working beside it, the
# physical invariant asked in raw SQL that shares nothing with the migration's own, and the refusal
# shown firing with nothing written.
#
# WHY THE SCHEMA IS REWOUND FOR THE LENGTH OF THIS FILE. This spec's subject is the newest migration,
# so the current schema is the world AFTER it — `budgets.carries_over` and `budgets.target_amount` do
# not exist, and the `up` under test would meet a `PG::UndefinedColumn` on its first statement. The
# shared context runs the `down` before the first example and the `up` after the last, which is also
# what proves the `down` correct.
#
# ---------------------------------------------------------------------------------------------
# ** WHAT "THE CLAIM DOES NOT MOVE" MEANS HERE, AND WHY IT IS A LITERAL. **
# ---------------------------------------------------------------------------------------------
#
# It cannot be measured by asking `ClaimCalculator` before the run. That class has no building arm
# from this commit (`#shape` is `anchor_date.present? ? :dated : :rate`), so a pre-migration fund
# reads there as a plain RATE rule — use-it-or-lose-it, built-up zero — which is a figure the
# rules-own-the-budget era never produced and no screen ever showed. The figure that must survive is
# THAT era's: the §3.2 walk with no due date, its own rate every period, capped at the target. It is
# re-derived from the formula in the comment above each example and planted as a literal, so the
# assertion is against the number the user was seeing rather than against the class under it.
#
# ** A BIWEEKLY GRID ANCHORED JAN 1 2026, so every date below is arithmetic anyone can redo by hand: **
#
#   P1 Jan 1–14 · P2 Jan 15–28 · P3 Jan 29–Feb 11 · P4 Feb 12–25 · P5 Feb 26–Mar 11
#   P6 Mar 12–25 · P7 Mar 26–Apr 8 · P8 Apr 9–22 · P9 Apr 23–May 6
#
# UTC, so the owner's day and the stored instant are the same day — which is what keeps the accrual
# spans off the wall clock. `today` is FIXED for CLAUDE.md's third flake cause: a walk whose period
# count moves with the run day makes every literal below wrong on some mornings of the year.
RSpec.describe TwoShapes do
  include ActiveSupport::Testing::TimeHelpers

  include_context "with the schema its subject was written for", described_class

  let(:migration) { described_class.new }

  let(:user) do
    create(
      :user,
      email: "ming@example.com",
      timezone: "UTC",
      period_cadence: :biweekly,
      period_anchor_date: Date.new(2026, 1, 1)
    )
  end
  let(:main) { create(:pool, :account, user: user, name: "Checking") }

  # TODAY IS IN P2 (Jan 15–28), which is what makes the rate-fed fund's built-up exactly two periods
  # of its rate — see `plant_the_fund_era`.
  let(:today) { Date.new(2026, 1, 20) }
  let(:funding_day) { Date.new(2026, 1, 1) }
  let(:born) { Time.utc(2026, 1, 1, 9) }

  # THE CLOCK IS FROZEN AT `today`, and it is not decoration: the migration derives its anchor from
  # `User#today`, which is `Time.current` re-zoned. A run day left to the wall clock would put every
  # literal below on a different period of the year.
  before do
    travel_to Time.utc(2026, 1, 20, 12)
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

  # EVERY RULE IS BORN ON THE FUNDING DAY, so `accrual_start` — `max(funded_since, the rule's
  # birthday)` — lands on the funding day and the walk visits the two periods the workings count. A
  # rule born at fixture time would walk one.
  def fund(category, rate, target: nil)
    create(
      :budget,
      :per_period_rate,
      category: category,
      amount: rate,
      carries_over: true,
      target_amount: target,
      created_at: born
    )
  end

  # ** THE HAND-FED FUND, PLANTED PAST THE MODEL. ** `amount = 0` was how "no standing rate" was
  # spelled and `Budget` validates `amount > 0` on every shape from this commit, so `create!` cannot
  # write it — which is exactly why the migration has to be able to meet it.
  def plant_a_hand_fed_fund(category, target)
    id = SecureRandom.uuid
    sql(<<~SQL.squish, id: id, cid: category.id, target: target, born: born)
      INSERT INTO budgets (id, category_id, amount, basis, interval_months, anchor_date,
                           carries_over, target_amount, rule_type, created_at, updated_at)
      VALUES (:id, :cid, 0, 1, NULL, NULL, TRUE, :target, 2, :born, :born)
    SQL
    id
  end

  def rate(category, amount)
    create(:budget, :per_period_rate, category: category, amount: amount, created_at: born)
  end

  def dated(category, amount, on:, item: nil, every: nil)
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

  def rule_of(category) = Budget.where(category_id: category.id).sole

  # THE FIVE COLUMNS A CONVERTED RULE IS ABOUT, in the order §6 names them.
  def columns_of(rule) = [rule.amount, rule.basis, rule.interval_months, rule.anchor_date]

  def claim_of(category) = category.reload.claim(today: today)

  # ** THE WORLD, AS FIVE CATEGORIES. **
  #
  #   Vacation      the ordinary fund: $150 a period toward $1,200, carrying over. TWO periods have
  #                 passed, so it holds $300 — and the derived date is 6 periods on.
  #   Emergency     the HAND-FED fund: $0 a period toward $5,000, planted in SQL. No rate, no
  #                 crossing date; one year from today.
  #   Groceries     no fund, an item-less $400 rate rule. Untouched.
  #   Rent          no fund, an item-backed $1,350 monthly bill due Feb 10. Untouched.
  #   Salary        the income category the physical figures are built from.
  #
  # THE PHYSICAL FIGURES, and they are the only conserved ones:
  #   income 6,000 (Jan 2); spending 250 (Groceries, Jan 16) = 250.
  #   bank truth = 6,000 − 250 = 5,750. The 750 moved Checking → Ally nets to zero across the two
  #   accounts, so physical = 5,750 too.
  def plant_the_fund_era
    world = {
      vacation: holder("Vacation to Europe"),
      emergency: holder("Emergency Fund"),
      groceries: holder("Groceries"),
      rent: holder("Rent")
    }
    fund(world[:vacation], 150, target: 1_200)
    plant_a_hand_fed_fund(world[:emergency], 5_000)
    rate(world[:groceries], 400)
    dated(world[:rent], 1_350, on: Date.new(2026, 2, 10), item: create(:item, category: world[:rent], name: "Monthly Rent"))
    plant_the_physical_side(world)
    world
  end

  def plant_the_physical_side(world)
    ally = create(:pool, :account, user: user, name: "Ally")
    create(:account_movement, from_pool: main, to_pool: ally, amount: 750, date: Date.new(2026, 1, 5))
    spend(holder("Salary", type: :income, funded_since: nil), 6_000, on: Date.new(2026, 1, 2), item_name: "Paycheck")
    spend(world[:groceries], 250, on: Date.new(2026, 1, 16), item_name: "Supermarket")
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
  # The rate-fed fund
  # ---------------------------------------------------------------------------------------------

  # ** THE DERIVATION, RE-DERIVED. ** The rules-own-the-budget era's walk: its own rate every period,
  # capped at the target, from the funding day through the period containing today.
  #
  #   P1 (Jan 1–14)  gap 1,200 → plans min(150, 1,200) = 150 → built up 150
  #   P2 (Jan 15–28) gap 1,050 → plans 150                   → built up **300**
  #
  # So `ceil((1,200 − 300) ÷ 150)` = **6** periods forward from P2 — P3 Jan 29, P4 Feb 12, P5 Feb 26,
  # P6 Mar 12, P7 Mar 26, P8 Apr 9 — and the anchor is P8's LAST DAY, **Apr 22 2026**.
  it "turns a rate-fed fund into a one-off dated rule at the day its rate would reach the target" do
    world = plant_the_fund_era

    migrate!

    expect(columns_of(rule_of(world[:vacation])))
      .to eq([1_200.to_d, "monthly", nil, Date.new(2026, 4, 22)])
  end

  # ** AND THE CLAIM DOES NOT MOVE, which is what the derivation is FOR. ** §3.2's catch-up walk over
  # the same two periods, against the anchor above:
  #
  #   P1  boundaries from Jan 1 through Apr 22 = Jan 1, 15, 29, Feb 12, 26, Mar 12, 26, Apr 9 = 8
  #       → plans 1,200 ÷ 8 = 150.00 → built up 150
  #   P2  gap 1,050; boundaries from Jan 15 through Apr 22 = 7 → plans 150.00 → built up **300**
  #
  # The same $300 the fund held the day before, to the cent: the derived horizon is exactly the one
  # on which `remaining ÷ periods left` IS the old rate.
  it "leaves the fund's claim exactly the figure its own rate produced" do
    world = plant_the_fund_era

    migrate!

    expect(claim_of(world[:vacation])).to eq(300.to_d)
  end

  # THE SHAPE IS ONE THE MODEL ITSELF ACCEPTS, asked of the model — which is exactly what the
  # migration's SQL restatement of those validations cannot do for itself. It matters beyond
  # tidiness: `CadenceChange#apply` writes `Budget#amount` through an unrescued `update!`, so a rule
  # left in a shape the model refuses would reach the user as a 500 from a row they never wrote.
  it "converts funds the model itself accepts" do
    world = plant_the_fund_era

    migrate!

    expect([rule_of(world[:vacation]), rule_of(world[:emergency])]).to all(be_valid)
  end

  # ---------------------------------------------------------------------------------------------
  # ** THE RATE IS WHAT THE APP CHARGED, NOT THE FIGURE ON THE ROW (fix round 1 — HIGH-1) **
  # ---------------------------------------------------------------------------------------------
  #
  # `$260 a month` is a shape a fund could carry — §2.1 row 5, `basis: monthly, interval 1,
  # carries over`, model-valid at this file's own moment in the sequence and reachable from the form
  # the rules-own-the-budget task shipped. `Budget#steady_ask` prices it at `260 × 12 ÷ 26` =
  # **$120.00** a fortnight, and that is the figure `#planned_for`'s retired building arm asked for
  # every period, so it is the figure the walk and the derivation have to use.
  #
  # BY HAND, at $120.00 a period on the two periods this world walks:
  #   P1 (Jan 1–14)  gap 5,000 → plans min(120, 5,000) = 120 → built up 120
  #   P2 (Jan 15–28) gap 4,880 → plans 120                   → built up **240**
  # `ceil((5,000 − 240) ÷ 120)` = `ceil(39.67)` = **40** periods forward from P2 — P2 opens Jan 15
  # 2026, and 40 × 14 = 560 days later that period opens on Jul 29 2027 — so the anchor is its LAST
  # DAY, **Aug 11 2027**.
  #
  # READ OFF `budgets.amount` INSTEAD it converts at $260 a period: two periods hold **$520** rather
  # than $240, `ceil((5,000 − 520) ÷ 260)` = 18 periods, and the anchor lands inside 2026 — nearly a
  # year early, with the morning-after claim more than double what the screens had said. The date is
  # asserted rather than the rate alone, because a conversion that used the wrong unit would still
  # produce a plausible-looking date.
  describe "a fund whose rate is stated per month" do
    let(:monthly_fund) do
      create(
        :budget,
        :rate,
        category: holder("Repairs"),
        amount: 260,
        carries_over: true,
        target_amount: 5_000,
        created_at: born
      )
    end

    it "walks the rate the grid charges and dates the fund off that", :aggregate_failures do
      plant_the_fund_era
      monthly_fund

      migrate!

      expect(columns_of(monthly_fund.reload))
        .to eq([5_000.to_d, "monthly", nil, Date.new(2027, 8, 11)])
    end

    # THE RECEIPT NAMES THE CHARGED RATE FIRST — it is the number the date came from — with the
    # figure the owner typed beside it, so a person reading the line can tie it back to their form.
    it "prints the charged rate with the stated one beside it" do
      plant_the_fund_era
      monthly_fund

      expect(receipts)
        .to include(a_string_including("Repairs · was $120.00 a period ($260.00 a month) · now $5000.00 by 2027-08-11"))
    end

    # AND THE PER-PERIOD FUNDS DO NOT GROW THE CLAUSE, because the two figures are the same number
    # there and `was $150.00 a period ($150.00 a month)` would be noise on every ordinary row.
    it "says nothing about a month where the rate is already per period" do
      plant_the_fund_era

      expect(receipts).to include(a_string_including("Vacation to Europe · was $150.00 a period · now $1200.00"))
    end
  end

  # ---------------------------------------------------------------------------------------------
  # ** "THE CLAIM DOES NOT MOVE" IS EXACT ONLY WHERE THE TARGET DIVIDES (fix round 1 — MED-3) **
  # ---------------------------------------------------------------------------------------------
  #
  # `ceil` places the date at or beyond the true crossing, so the catch-up share afterwards is
  # `target ÷ ceil(target ÷ rate)` — the rate exactly when the division is whole, and a little under
  # it when it is not. THE SHORTFALL IS NOT A ROUNDING: measured here, and re-derived.
  #
  #   $5,000 at $300 a period, TEN periods walked (the rule and its category are born nine periods
  #   before the current one opens, Sep 11 2025) → built up **$3,000.00**.
  #   `ceil(2,000 ÷ 300)` = `ceil(6.67)` = **7** periods forward from P2 (opens Jan 15 2026), so the
  #   anchor is **May 6 2026**.
  #   The live walk then counts the boundaries from Sep 11 2025 through May 6 2026 — seventeen of
  #   them — so its share is `5,000 ÷ 17` = **$294.12** and ten periods hold **$2,941.20**.
  #   `3,000.00 − 2,941.20` = **$58.80**, which the receipt names on that rule's own line.
  #
  # IT IS NOT A REFUSAL. The alternative is refusing every fund whose target does not divide by its
  # rate, which is most of them; the conversion is still the best available date and the owner is
  # told the figure beside the two numbers it came from.
  describe "a target that does not divide by the rate" do
    let(:ten_periods_back) { Date.new(2025, 9, 11) }

    let(:awkward_fund) do
      category = holder("New Roof", funded_since: ten_periods_back)
      create(
        :budget,
        :per_period_rate,
        category: category,
        amount: 300,
        carries_over: true,
        target_amount: 5_000,
        created_at: ten_periods_back.beginning_of_day
      )
    end

    it "dates the fund at the ceiling of the crossing", :aggregate_failures do
      plant_the_fund_era
      awkward_fund

      migrate!

      expect(columns_of(awkward_fund.reload)).to eq([5_000.to_d, "monthly", nil, Date.new(2026, 5, 6)])
      expect(awkward_fund.claim_calculator(today: today).claim).to eq(2_941.20)
    end

    it "names how far the claim moved, on that rule's own line" do
      plant_the_fund_era
      awkward_fund

      expect(receipts).to include(
        a_string_including(
          "New Roof · was $300.00 a period · now $5000.00 by 2026-05-06 · " \
          "claim moved $58.80: the target does not divide by the rate"
        )
      )
    end

    # THE OTHER DIRECTION, one figure apart: $1,200 at $150 divides exactly, so the date lands on the
    # true crossing, the share IS the rate and the claim is the same $300 the day after as the day
    # before — which is the sentence the header makes and this is what keeps it honest.
    # ONE `#receipts` CALL AND A LOCAL, because that helper RUNS the migration: asking it twice in
    # one example runs `up` against a schema the first call already dropped the columns from.
    it "says nothing about a claim that did not move", :aggregate_failures do
      plant_the_fund_era

      lines = receipts

      expect(lines).to include(a_string_including("Vacation to Europe"))
      expect(lines.grep(/Vacation to Europe/).sole).not_to include("claim moved")
    end
  end

  # ---------------------------------------------------------------------------------------------
  # The hand-fed fund
  # ---------------------------------------------------------------------------------------------

  # ** A RATE OF ZERO CROSSES NOTHING, so the horizon is STATED: one year from the owner's today. **
  # Jan 20 2026 + 1 year = **Jan 20 2027**, to the day rather than to a period boundary — a figure
  # this file states rather than one it derived. The amount becomes the target, which is also what
  # makes the row valid at all under `amount > 0`.
  it "gives a hand-fed fund one year, and its target as its amount" do
    world = plant_the_fund_era

    migrate!

    expect(columns_of(rule_of(world[:emergency])))
      .to eq([5_000.to_d, "monthly", nil, Date.new(2027, 1, 20)])
  end

  # ---------------------------------------------------------------------------------------------
  # The rules it does not touch
  # ---------------------------------------------------------------------------------------------

  # A RATE RULE IS LEFT WHERE IT IS, and its claim is what it always was: §3.1's
  # `max(0, rate + Σ deltas − spent)` = `max(0, 400 − 250)` = **$150.00** for the P2 period this is
  # read in (the $250 supermarket receipt is dated Jan 16).
  it "leaves a rate rule alone", :aggregate_failures do
    world = plant_the_fund_era

    migrate!

    expect(columns_of(rule_of(world[:groceries]))).to eq([400.to_d, "per_period", nil, nil])
    expect(claim_of(world[:groceries])).to eq(150.to_d)
  end

  # A DATED RULE IS LEFT WHERE IT IS TOO, and its claim is §3.2's catch-up toward $1,350 due Feb 10.
  # From P1's open the boundaries through Feb 10 are Jan 1, Jan 15, Jan 29 = 3, and one fewer each
  # period, so the share is 1,350 ÷ 3 = **$450.00** and two periods hold **$900.00**. Nothing has
  # been spent on Monthly Rent, so nothing rolls.
  it "leaves a dated rule alone", :aggregate_failures do
    world = plant_the_fund_era

    migrate!

    expect(columns_of(rule_of(world[:rent]))).to eq([1_350.to_d, "monthly", nil, Date.new(2026, 2, 10)])
    expect(claim_of(world[:rent])).to eq(900.to_d)
  end

  # ---------------------------------------------------------------------------------------------
  # The columns
  # ---------------------------------------------------------------------------------------------

  it "drops both build-up columns and the check that guarded the target", :aggregate_failures do
    plant_the_fund_era

    migrate!

    expect(connection.column_exists?(:budgets, :carries_over)).to be(false)
    expect(connection.column_exists?(:budgets, :target_amount)).to be(false)
    expect(connection.check_constraints(:budgets).map(&:name)).not_to include("budgets_positive_target_amount")
  end

  # ---------------------------------------------------------------------------------------------
  # The physical invariant
  # ---------------------------------------------------------------------------------------------

  it "leaves the physical invariant exactly where it was", :aggregate_failures do
    plant_the_fund_era
    before = [physical_total, bank_truth]
    expect(before).to eq([5_750.to_d, 5_750.to_d])

    migrate!

    expect([physical_total, bank_truth]).to eq(before)
  end

  it "writes nothing to the physical tables at all", :aggregate_failures do
    plant_the_fund_era
    counts = -> { [Entry.count, AccountMovement.count, Pool.count] }
    before = counts.call

    migrate!

    expect(counts.call).to eq(before)
    expect(before).to eq([2, 1, 2])
  end

  # ---------------------------------------------------------------------------------------------
  # The receipt
  # ---------------------------------------------------------------------------------------------

  # ** THE OLD RATE IS ON EVERY LINE AND IT IS THE POINT. ** The date this file derives is a
  # consequence of that rate, so an owner who disagrees with the date has the number it came from in
  # front of them. The totals line and the invariant line are asserted too, because a receipt nobody
  # reads is a receipt that can quietly stop counting.
  it "names every fund with its old rate and its new date", :aggregate_failures do
    plant_the_fund_era

    lines = receipts

    expect(lines).to include(*expected_receipt_lines.map { |line| a_string_including(line) })
  end

  def expected_receipt_lines
    [
      "ming@example.com: 2 funds became dated rules",
      "Vacation to Europe · was $150.00 a period · now $1200.00 by 2026-04-22",
      "Emergency Fund · was $0.00 a period · now $5000.00 by 2027-01-20",
      "2 funds converted in total across 1 owner",
      "ming@example.com: physical 5750.0 == bank 5750.0, unchanged"
    ]
  end

  # ---------------------------------------------------------------------------------------------
  # The refusal
  # ---------------------------------------------------------------------------------------------

  it "refuses nothing on the world the fund era leaves behind" do
    plant_the_fund_era

    expect { migrate! }.not_to raise_error
  end

  # ** A FUND WITH NO CEILING HAS NO FIGURE TO BE DUE AND NO DAY TO BE DUE ON. ** "Grow for ever" was
  # a legal declaration; under two shapes it is neither an amount nor a date, and inventing either
  # would be inventing the user's goal. Named by owner, category and rule id, before anything moves.
  it "refuses an uncapped fund by name, with nothing written", :aggregate_failures do
    world = plant_the_fund_era
    forever = fund(holder("Retirement"), 200)

    expect { migrate! }.to raise_error(described_class::PreflightFailed, /Retirement.*names no target/)
    expect { migrate! }.to raise_error(described_class::PreflightFailed, /#{forever.id}/)
    expect(connection.column_exists?(:budgets, :carries_over)).to be(true)
    expect(rule_of(world[:vacation]).anchor_date).to be_nil
  end

  # ---------------------------------------------------------------------------------------------
  # The `down`
  # ---------------------------------------------------------------------------------------------

  # ** THE SHAPE, AND NOT THE DATA, WHICH IS WHAT THE SCHEMA REWIND NEEDS. **
  # `spec/support/schema_rewind.rb` runs `RulesOwnTheBudget#down`, which copies a rule's target back
  # onto its category — so a `down` that restored nothing would leave six migration specs writing to
  # a column that is not there. What it does NOT restore is the building shape: a rule this file
  # converted stays a dated one-off, because there is no code left in the app that could compute the
  # other one.
  it "puts both columns and the check back on the way down, and leaves the converted rule dated", :aggregate_failures do
    world = plant_the_fund_era
    migrate!

    migration.suppress_messages { migration.down }
    refresh_columns

    expect(connection.column_exists?(:budgets, :carries_over)).to be(true)
    expect(connection.column_exists?(:budgets, :target_amount)).to be(true)
    expect(connection.check_constraints(:budgets).map(&:name)).to include("budgets_positive_target_amount")
    expect(columns_of(rule_of(world[:vacation])))
      .to eq([1_200.to_d, "monthly", nil, Date.new(2026, 4, 22)])
  end

  it "restores the columns empty, because the data is not what comes back", :aggregate_failures do
    world = plant_the_fund_era
    migrate!

    migration.suppress_messages { migration.down }
    refresh_columns

    rule = rule_of(world[:vacation])
    expect([rule.carries_over, rule.target_amount]).to eq([false, nil])
  end
end
