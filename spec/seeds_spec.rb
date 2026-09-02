# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260817000000_cutover_to_envelope_budgeting")

# THE DEMO IS INFRASTRUCTURE, so it gets a spec.
#
# `db/seeds.rb` is what every visual check on this plan is performed against and what `bin/ci`
# replants on every run, and after the cutover it is also a CLAIM: that the demo speaks the
# post-cutover language natively — no category-mode cap, no savings category or entry, no category
# without a pool, no pool without an account.
#
# THE CLAIM IS CHECKED IN BOTH DIRECTIONS, and that is the point of the file-level half. Grepping
# the source catches a legacy construct written into the seeds; asserting the database catches one
# that arrives through a factory, an association callback or a default. Either half alone can be
# satisfied by a file that does the wrong thing somewhere the other cannot see.
#
# EVERY EXPECTED FIGURE IS A PLANTED LITERAL. Reading a count out of the same objects the seeds
# just created would assert that the seeds equal themselves; these numbers are the demo's state
# table — the account → screen-state table in `db/seeds.rb`'s own header, beside the data it
# describes — written down where a change to the seeds has to argue with them.
#
# LOADING THE SEEDS PER EXAMPLE is deliberate and costs about a second. `before(:context)` would
# put ~200 rows outside the per-example transaction, where DatabaseCleaner cleans them out from
# under the group; the seeds are cheap enough that the honest version wins.
# The subject is a FILE, not a class, so there is no constant to hand `describe` — the same reason
# `spec/migrations/cutover_spec.rb` disables a path cop rather than renaming itself.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "db/seeds.rb" do
  # The seeds set `Time.zone` globally — they have to, or every datetime they write lands in UTC.
  # `use_zone` saves and restores the thread-local around the example, so the assignment the seeds
  # make inside is undone rather than leaked into whatever example runs next.
  around { |example| Time.use_zone(Time.zone) { example.run } }

  let(:source) { Rails.root.join("db/seeds.rb").read }
  let(:user) { User.find_by!(email: "demo@example.com") }
  let(:today) { Time.find_zone!(user.timezone).today }

  def replant
    load Rails.root.join("db/seeds.rb")
  end

  # Every table the demo writes to, in one reading — so the count example and the migration's
  # byte-identical check ask the same question of the same tables rather than two hand-kept lists.
  def row_counts
    {
      users: User.count,
      pools: Pool.count,
      categories: Category.count,
      items: Item.count,
      entries: Entry.count,
      budgets: Budget.count,
      movements: PoolMovement.count
    }
  end

  # THE INTEGER THE SCHEMA HOLDS TODAY, not `Category.savings`. `category_type: 2` is deleted from
  # the enum in Task 5, and this assertion has to outlive that: a spec that stopped compiling the
  # moment the legacy value went away would stop guarding the seeds exactly when the guard became
  # cheap to break. Same reasoning as the migration's own written-out constants. A method rather
  # than a constant because a constant declared in a block leaks out of the example group.
  def savings_category_type = 2

  describe "the file itself" do
    it "never writes a category-mode cap", :aggregate_failures do
      expect(source).not_to match(/create_budget/)
      expect(source.scan(/Budget\.create!\((?:[^()]|\([^()]*\))*\)/m).join("\n")).not_to match(/\bcategory:/)
    end

    it "never writes a savings category", :aggregate_failures do
      expect(source).not_to match(/category_type:\s*:savings/)
      expect(source).not_to match(/lane\.call\([^)]*:savings/)
    end

    # An entry can only be savings-typed through a savings category, so the absence above is the
    # absence of a savings entry too — said out loud because the two are separate promises and a
    # future edit could reintroduce either.
    it "never writes an entry against a savings category" do
      expect(source).not_to match(/savings.*\.items\.create!/)
    end
  end

  describe "the database after a replant" do
    before { replant }

    it "holds exactly the rows the demo is made of" do
      expect(row_counts).to eq(
        users: 1, pools: 23, categories: 18, items: 22, entries: 67, budgets: 16, movements: 53
      )
    end

    it "writes no cap, no savings category and no savings entry", :aggregate_failures do
      savings_categories = Category.where(category_type: savings_category_type)

      # `budgets.category_id` is DROPPED (plan 3, task 6), so "no cap" is now asked as "every
      # rule names the pool that owns it" — the post-drop spelling of the same claim.
      expect(Budget.where(pool_id: nil).count).to eq(0)
      expect(savings_categories.count).to eq(0)
      expect(Entry.joins(item: :category).where(categories: { category_type: savings_category_type }).count).to eq(0)
    end

    it "gives every category a lane and every pool a home", :aggregate_failures do
      expect(Category.where(pool_id: nil).count).to eq(0)
      expect(Pool.where.not(pool_type: :account).where(account_id: nil).count).to eq(0)
      expect(Category.incomes.map { |category| category.pool.pool_type }.uniq).to eq(["account"])
      expect(user.default_account).to eq(Pool.find_by!(name: "Checking"))
    end

    # THE INVARIANT THE WHOLE CONVERSION TURNS ON, asked of the demo: every dollar the bank says
    # the household has is sitting in exactly one pool.
    it "conserves the bank balance across the pool tree", :aggregate_failures do
      pooled = user.pools.sum { |pool| pool.calculator.balance }
      # `::numeric` on both arms: `money` is a fixed-scale Postgres type with no unary minus at
      # all, so the expense arm is a type error rather than a wrong figure. The migration's own
      # balance expression casts for the same reason.
      bank = user.entries.joins(item: :category).sum(
        "CASE WHEN categories.category_type = 1 THEN entries.amount::numeric ELSE -entries.amount::numeric END"
      )

      expect(pooled).to eq(7_841.00)
      expect(bank).to eq(7_841.00)
    end

    # ── THE DEMO NO LONGER FEEDS THE DISTRIBUTION SCREEN, AND THAT IS THE POINT OF THIS EXAMPLE.
    #
    # It used to carry four states — one per account, `Ally Savings` short-and-alerting, `Checking`
    # short, `Health Savings` all-clear, `Side Gig Checking` overdrawn — because each of the four
    # screens the demo exists for was carried by exactly ONE account. There is one screen now
    # (two-ledger spec §2), and `db/seeds.rb` still writes POOLS: not one category it plants carries
    # a `funded_since`, so `Category.in_fill_order` is EMPTY and the converted waterfall has no rows
    # to render at all.
    #
    # KEPT AND INVERTED RATHER THAN DELETED, because "the demo stopped exercising the app's headline
    # screen" is exactly the kind of thing that goes unnoticed: this is the row that fails the moment
    # the seeds start planting holder categories, which is where the four states have to be rebuilt.
    # THE SEEDS ARE TASK 7/8'S TO CONVERT and this example is the marker.
    #
    # `available` IS THE WHOLE $7,841 for the same reason, and it ties to the conservation example
    # above: every dollar the household has is money no category has claimed.
    it "leaves the distribution screen empty, because the seeds still plant pools", :aggregate_failures do
      presenter = DistributionPresenter.new(user: user, today: today)

      expect(
        [presenter.available, presenter.short?, presenter.expanded?, presenter.alerts.length, presenter.lines.length]
      ).to eq([7_841.00, false, false, 0, 0])
      expect(user.categories.in_fill_order).to be_empty
    end

    it "leaves the household structurally underwater, so the sacrifice view has a screen", :aggregate_failures do
      expect(Budget.steady_need(user, today: today)).to eq(2_661.92)
      expect(user.typical_income).to eq(2_400.00)
      expect(HomePresenter.new(user: user, today: today)).to be_structurally_underwater
    end

    # EVERY DETECTOR FED. The panel is the Budget page's bottom half, and a demo that starved one
    # of the four would leave whoever works on it next reading a spec instead of a screen.
    it "feeds all four suggestion detectors" do
      kinds = SuggestionEngine.new(user: user, today: today).suggestions.group_by(&:kind)
        .transform_values(&:length)

      expect(kinds).to eq(dated_bill: 6, rate: 4, drift: 4, dead_rule: 1)
    end
  end

  # THE CUTOVER'S IDEMPOTENCE RECEIPT, READ FROM THE OTHER SIDE. Task 1 proved a second run of the
  # migration finds nothing; this proves the FIRST run finds nothing to convert, because the seeds
  # already wrote what the migration exists to produce.
  describe "the cutover migration run against fresh seeds" do
    # The migration reads and writes `budgets.category_id`, which a later migration drops and a
    # later one still puts back. BOTH have to be rewound, and in order: `CategoriesHoldTheMoney`
    # re-adds that very column for the purpose ledger's rules, so rolling `DropCapEraBudgetColumns`
    # back on its own would try to add a column that is already there — which it did, once, and
    # the `after(:all)` that followed then dropped the two-ledger column on its way past. Newest
    # first on the way down; the shared context reverses the list itself.
    #
    # `TightenPoolShape` is still NOT rewound — the seeds already satisfy it and this file asserts
    # as much two examples up ("gives every category a lane and every pool a home").
    include_context "with the schema its subject was written for",
                    DropCapEraBudgetColumns,
                    CategoriesHoldTheMoney

    before { replant }

    # ALL FIVE CONVERSION COUNTERS ARE ZERO, which is the whole of the claim: no pool to house, no
    # cap to convert, no category to point at the buffer, no savings entry to move.
    #
    # `envelopes zeroed` IS NOT ZERO, AND THAT IS A CORRECTION TO THE BRIEF RATHER THAN A MISS.
    # Step 5b is shape-driven by design — it zeroes ANY overdrawn budget envelope, whoever
    # overdrew it — and an overdrawn envelope is an ordinary POST-cutover state: the demo's Dining
    # Out holds $100 against $180 of dinners, which is §4.4's `overdrawn` row, the distribution
    # screen's `overdrawn $80.00` line, Home's one problem row with a real fix candidate, and the
    # entry form's overdraw arm. Seeding a demo with no overdrawn envelope would buy one zero in
    # this receipt at the price of four screens. See the task report.
    it "converts nothing, and its one write is the overdraft it is designed to find" do
      expect { CutoverToEnvelopeBudgeting.new.tap { |m| m.verbose = true }.up }
        .to output(
          /0 pools housed; 0 caps -> 0 envelope rules; 0 categories -> buffer; 0 savings entries -> 0 movements; 1 envelopes zeroed/
        ).to_stdout
    end

    it "leaves every table but pool_movements byte-identical, and a second run writes nothing", :aggregate_failures do
      before_counts = row_counts.except(:movements)
      silence_stream { CutoverToEnvelopeBudgeting.new.up }
      zeroing = PoolMovement.order(:created_at).last

      expect(row_counts.except(:movements)).to eq(before_counts)
      expect(PoolMovement.count).to eq(54)
      expect([zeroing.from_pool.name, zeroing.to_pool.name, zeroing.amount, zeroing.kind])
        .to eq(["Checking", "Dining Out", 80.00, "transfer"])

      expect { silence_stream { CutoverToEnvelopeBudgeting.new.up } }
        .not_to change { [Pool.count, Category.count, Item.count, Entry.count, Budget.count, PoolMovement.count] }
    end

    # `ActiveRecord::Migration#say` writes to `$stdout` unconditionally when verbose; the receipt
    # is asserted in the example above, so the runs that only care about the rows keep the suite's
    # output readable.
    def silence_stream
      original = $stdout
      $stdout = StringIO.new
      yield
    ensure
      $stdout = original
    end
  end
end
# rubocop:enable RSpec/DescribeClass
