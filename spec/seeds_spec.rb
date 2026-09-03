# frozen_string_literal: true

require "rails_helper"

# THE DEMO IS INFRASTRUCTURE, so it gets a spec.
#
# `db/seeds.rb` is what every visual check on this plan is performed against and what `bin/ci`
# replants on every run, and after the drop it is also a CLAIM: that the demo speaks the two-ledger
# language natively — accounts and categories, allocations and account movements, and not one
# construct from the pool layer, which no longer has columns to be written into.
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

  # THE CODE ALONE, WITH EVERY COMMENT STRIPPED. The seeds' header explains at length what the pool
  # layer WAS, so a grep over the raw file finds `categories.pool_id` in prose and fails on a
  # sentence rather than on a construct. What this file polices is what the demo WRITES.
  let(:code) { source.lines.reject { |line| line.strip.start_with?("#") }.join }
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
      movements: AccountMovement.count,
      allocations: Allocation.count
    }
  end

  # THE INTEGER THE SCHEMA HOLDS TODAY, not `Category.savings`. `category_type: 2` was deleted from
  # the enum in plan 3, and this assertion has to outlive that: a spec that stopped compiling the
  # moment the legacy value went away would stop guarding the seeds exactly when the guard became
  # cheap to break. A method rather than a constant because a constant declared in a block leaks out
  # of the example group.
  def savings_category_type = 2

  # The root, in the app's own tables and nobody's reader: income, minus the spending NO category
  # holds, minus what has been allocated out of it, plus what has come back.
  #
  # "SPENDING NO CATEGORY HOLDS" IS TWO SHAPES, not one, and both arms are here because the second
  # is the funding-start rule itself (§4): a category with no `funded_since` holds nothing ever, and
  # a category that has one still sends everything dated BEFORE it to the root. Every seeded holder
  # starts six months back and nothing is dated earlier, so today the second arm is empty — it is
  # written anyway, because a spec that only happens to be right on one fixture is a spec that
  # stops being right the first time the fixture moves.
  def available_at_the_root
    (earned - unheld - allocated_out + allocated_back).to_d
  end

  def earned = user.entries.joins(item: :category).where(categories: { category_type: :income }).sum(:amount)

  # ** THE DAY BOUNDARY IS THE OWNER'S, AND THE TWO `AT TIME ZONE`s ARE WHY (final fix wave, M-5). **
  # The second arm compared `entries.date` — a naive DATETIME holding a UTC instant — against
  # `categories.funded_since`, a DATE. `CategoryLedger::ENTRY_CATEGORY_ID` is the app's ONE statement
  # of that comparison and it re-zones first: the demo user is `America/New_York`, so an entry filed
  # at 8pm on the funding date is stored `…T00:00Z` the NEXT day and a raw comparison would put it on
  # the wrong side of the line — this arm would then call the app's answer wrong, or agree with it by
  # accident. The spelling below is that constant's, with the user's own zone bound rather than read
  # off a joined `users` row, because this whole reader is already scoped to one user.
  #
  # RUNS OVER AN ARM THAT IS EMPTY ON TODAY'S FIXTURE, and is written correctly anyway for the reason
  # the arm exists at all: a conservation anchor that only happens to be right on one fixture stops
  # being right the first time the fixture moves, and a timezone-naive one stops being right at 8pm.
  def unheld
    user.entries.joins(item: :category).where(categories: { category_type: :expense })
      .where(
        "categories.funded_since IS NULL OR " \
        "(entries.date AT TIME ZONE 'UTC' AT TIME ZONE :zone)::date < categories.funded_since",
        zone: user.timezone.presence || "UTC"
      ).sum(:amount)
  end

  def allocated_out = Allocation.where(from_category_id: nil, to_category_id: user.categories.select(:id)).sum(:amount)

  def allocated_back = Allocation.where(to_category_id: nil, from_category_id: user.categories.select(:id)).sum(:amount)

  # THE FILE-LEVEL HALF IS NOW ABOUT THE POOL LAYER (two-ledger spec §5, Task 8), because that is
  # what the demo may no longer speak. The cap and the savings category are two schema eras back and
  # have no columns to be written into at all; a pool CONSTRUCT is different in kind — `pools` still
  # exists as the accounts table, so `pool_type: :budget` or a `Budget.create!(pool: …)` is a
  # sentence somebody could still type, and it is the one this grep is for.
  describe "the file itself" do
    it "never writes a pool that is not an account", :aggregate_failures do
      expect(code).not_to match(/pool_type:\s*:(budget|savings)/)
      expect(code).not_to match(/\baccount:\s/)
    end

    it "never names a column the drop deleted", :aggregate_failures do
      expect(code).not_to match(/\bpool_id\b/)
      expect(code).not_to match(/\bstart_date\b/)
      expect(code).not_to match(/\bPoolMovement\b/)
    end

    # A rule belongs to the category that holds the money, and nothing else can own one.
    it "gives every rule a category", :aggregate_failures do
      rules = code.scan(/Budget\.create!\((?:[^()]|\([^()]*\))*\)/m)

      expect(rules.length).to eq(16)
      expect(rules.reject { |rule| rule.include?("category:") }).to eq([])
    end

    it "never writes a savings category", :aggregate_failures do
      expect(code).not_to match(/category_type:\s*:savings/)
      expect(code).not_to match(/lane\.call\([^)]*:savings/)
    end
  end

  describe "the database after a replant" do
    before { replant }

    it "holds exactly the rows the demo is made of" do
      expect(row_counts).to eq(
        users: 1,
        pools: 4,
        categories: 28,
        items: 24,
        entries: 75,
        budgets: 16,
        movements: 8,
        allocations: 61
      )
    end

    it "writes no savings category and no savings entry", :aggregate_failures do
      savings_categories = Category.where(category_type: savings_category_type)

      expect(savings_categories.count).to eq(0)
      expect(Entry.joins(item: :category).where(categories: { category_type: savings_category_type }).count).to eq(0)
    end

    # EVERY POOL IS AN ACCOUNT AND EVERY RULE HAS A HOLDER — the two structural promises the drop
    # leaves the demo with, plus the pot itself, which every entry lands in.
    it "writes accounts, holders and a nominated pot", :aggregate_failures do
      expect(Pool.where.not(pool_type: :account).count).to eq(0)
      expect(Budget.where(category_id: nil).count).to eq(0)
      expect(Budget.all.map { |rule| rule.category.holder? }.uniq).to eq([true])
      expect(user.default_account).to eq(Pool.find_by!(name: "Checking"))
    end

    # SPEC §2'S INVARIANT, ASKED OF THE DEMO AND IN BOTH PARTITIONS: every dollar the bank says the
    # household has is sitting in exactly one account AND has exactly one job.
    #
    # AVAILABLE IS COMPUTED HERE RATHER THAN READ OFF `AllocationCalculator#available`, and the
    # difference is the whole reason: that reader adds back what the closed rate categories would
    # SWEEP ($125.00 on this demo), because the screen it feeds is about to offer the sweep. The
    # money is still in those categories until the user confirms, so adding it to the holdings would
    # count it twice. This is the root as it stands — income, less the spending of categories that
    # hold nothing, less everything allocated out of it and plus everything given back.
    #
    # `::numeric` on the entry arms: `money` is a fixed-scale Postgres type with no unary minus at
    # all, so the expense arm is a type error rather than a wrong figure.
    it "conserves the bank balance across both ledgers", :aggregate_failures do
      ledger = AccountLedger.new(user)
      physical = user.pools.accounts.sum(0.to_d) { |account| ledger.balance_of(account) }
      holdings = user.categories.expenses.sum(0.to_d) { |category| category.status(today: today).balance }
      bank = user.entries.joins(item: :category).sum(
        "CASE WHEN categories.category_type = 1 THEN entries.amount::numeric ELSE -entries.amount::numeric END"
      )

      expect(bank).to eq(7_461.00)
      expect(physical).to eq(7_461.00)
      expect(holdings + available_at_the_root).to eq(7_461.00)
    end

    # ── THE DISTRIBUTION SCREEN, RESTORED (Task 8). This example was INVERTED for four tasks: while
    # the seeds still planted pools, no category carried a `funded_since`, `Category.in_fill_order`
    # was empty and the converted waterfall had no rows at all — so it asserted the emptiness and
    # said in capitals that the seeds were Task 7/8's to convert. They are converted, and this is
    # what they now put on the app's headline screen.
    #
    # ONE SCREEN CARRIES WHAT FOUR ACCOUNTS USED TO. `AllocationCalculator` walks one root, so SHORT
    # (the cutoff line), the ALERTS band and both sweep clauses have to coexist on it — see the
    # table in `db/seeds.rb`'s own header, beside the data it describes.
    #
    # `available` IS $1,900.00 AND IT IS TWO FIGURES: $1,775.00 at the root, plus the $125.00 the
    # two closed rate categories would sweep back. The root figure is the conservation example's own
    # arithmetic — income, less spending no category holds, less everything allocated out.
    it "puts the household on a short waterfall with one alert", :aggregate_failures do
      presenter = DistributionPresenter.new(user: user, today: today)

      expect(
        [presenter.available, presenter.short?, presenter.expanded?, presenter.alerts.length, presenter.lines.length]
      ).to eq([1_900.00, true, true, 1, 12])
      expect(user.categories.in_fill_order.count).to eq(19)
    end

    it "leaves the household structurally underwater, so the sacrifice view has a screen", :aggregate_failures do
      expect(Budget.steady_need(user, today: today)).to eq(2_484.99)
      expect(user.typical_income).to eq(2_400.00)
      expect(HomePresenter.new(user: user, today: today)).to be_structurally_underwater
    end

    # `dated_bill: 3` WAS 6 (answers-first Home spec §7, the occurrence gate). Three of the six
    # were one-off spends — the Body Shop repair, the quarterly tax estimate — that the engine read
    # as annual bills and disclaimed as guesses in their own rows; that shape is deleted, so the
    # three MEASURED utility bills are what is left. The other three figures are unmoved, which is
    # the second half of what this example now says: the demo's history runs back far enough that
    # the new history gate on drift and dead-rule changes nothing for it.
    #
    # EVERY DETECTOR FED, AND `drift: 4` IS THE FIGURE THIS EXAMPLE WAS INVERTED AGAINST. While the
    # seeds planted pools, a seeded rule named no category, `CategoryLedger::ENTRY_CATEGORY_ID` could
    # not attribute a penny of spending to it, and the demo's four drifting envelopes read as four
    # zeroes the detector declined to report — so this asserted `dead_rule` without `drift` and said
    # so. The rules belong to categories now and the four are back.
    #
    # WHICH FOUR, AND WHY NOT MORE: Groceries (the one UPWARD suggestion), Dining Out, Household
    # Supplies and Pet Care are the categories whose spending genuinely diverges from their rules.
    # Every other rate rule in the demo either has spending that matches it or is dated instead —
    # `db/seeds.rb` chooses those shapes deliberately, because a rate rule on a category with no
    # spending at all is drift's starkest sentence and four of those would be four suggestions
    # telling the demo user to zero rules they simply have not spent from yet.
    it "feeds all four suggestion detectors" do
      kinds = SuggestionEngine.new(user: user, today: today).suggestions.group_by(&:kind)
        .transform_values(&:length)

      expect(kinds).to eq(dated_bill: 3, rate: 4, drift: 4, dead_rule: 1)
    end
  end

  # ── "the cutover migration run against fresh seeds" IS DELETED (two-ledger spec §5, Task 8), and
  # the reason is the schema rather than the claim. That describe rewound the schema past
  # `CategoriesHoldTheMoney` and replanted INSIDE the rewind, so it could run
  # `CutoverToEnvelopeBudgeting` over fresh seeds and prove it found nothing to convert. The seeds
  # are category-native now: replanting them against a schema with no `categories.funded_since` and
  # no `allocations` table cannot even build the demo, and the migration it exercised is two schema
  # eras back — its own idempotence is asserted in `spec/migrations/cutover_spec.rb`, against the
  # legacy worlds it was written for, which is where a claim about a migration belongs.
end
# rubocop:enable RSpec/DescribeClass
