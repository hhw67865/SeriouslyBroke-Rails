# frozen_string_literal: true

require "rails_helper"

# THE PORT OF THE POOL-ERA COMMITTER, FIGURE FOR FIGURE (two-ledger Task 4). Every example that
# pinned a number keeps the number: a sweep is `category → available` where it was `envelope →
# account`, an allocation is `available → category` where it was `account → envelope`, and the
# arithmetic is the same with the root renamed.
#
# WHAT COULD NOT COME ACROSS, and it is one whole group:
#   * "a second account distributing in the same period" — replacement scoped to the ACCOUNT. The
#     purpose ledger has one root (spec §2), so there is one split per period per user and
#     #previous_distribution has one filter fewer. Both of its examples asserted that one account's
#     re-run spared the other's rows; there is no second account's rows to spare. The `kind` and
#     `date` survivors below are what still say replacement is narrow.
RSpec.describe AllocationCommitter, type: :model do
  # The same calendar the calculator's spec uses: biweekly, anchored Fri 6 Feb 2026, so the
  # boundaries around August are Aug 7 and Aug 21 and the period containing Aug 20 is Aug 7..Aug 20.
  # Money allocated on Jul 12 belongs to a period that ended Jul 23 — closed.
  let(:user) { create(:user, :biweekly) }

  # Income has to land in a category and that category may only point at the user's main account
  # (`Category#income_must_land_in_an_account`), so the pot is here to be pointed at. No figure below
  # is read off it.
  # rubocop:disable RSpec/LetSetup -- THE POT HAS TO EXIST, and nothing here reads it: income
  # lands in a category and `Category#income_must_land_in_an_account` says that category may
  # only point at the user's MAIN account, so a user with no account cannot be paid at all. It
  # is setup for the physical side of a fixture whose every assertion is on the purpose side.
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  # rubocop:enable RSpec/LetSetup

  def today = Date.new(2026, 8, 20)
  def last_period = Date.new(2026, 7, 12)
  def this_period = Date.new(2026, 8, 15)

  def rule(category, *traits, **attrs)
    create(:budget, *traits, pool: nil, category: category, **attrs)
  end

  # A category carrying one per-period rate rule, optionally already holding money — funded by an
  # allocation OUT OF AVAILABLE, which is what makes available the root a distribution hands out
  # from.
  def rate_category(name, rate, funded: nil, on: nil, **attrs)
    category = create(:category, :expense, :funded, user: user, name: name, **attrs)
    rule(category, :per_period_rate, amount: rate)
    fund(category, funded, on: on || last_period) if funded
    category
  end

  def fund(category, amount, on:, kind: :transfer)
    create(:allocation, to_category: category, amount: amount, date: on, kind: kind)
  end

  def deposit(amount, on: today)
    category = create(:category, :income, user: user)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # Money leaving the user's life, which is an Entry and never an allocation — the one way the world
  # can change between two commits in a direction no replacement puts back. The category is
  # deliberately UNFUNDED, so the spending drains AVAILABLE rather than a holding (§4).
  def spend(amount, on: today)
    category = create(:category, :expense, user: user)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # Memoised: every reference inside one example is the SAME proposal, which is how a screen holds
  # it, and — after a commit — the stale snapshot the re-run examples are about.
  def proposal = @proposal ||= AllocationCalculator.new(user: user, today: today)

  # A FRESH proposal per commit by default, because that is what a controller hands over: one request
  # renders a proposal, the next builds another and confirms. `from:` hands a particular snapshot
  # instead, and the two must reach the same ledger.
  def commit(overrides: {}, from: nil)
    proposal = from || AllocationCalculator.new(user: user, today: today, overrides: overrides)
    described_class.new(proposal).call
  end

  # A FRESH calculator every time, because HoldingCalculator memoises its balance and this spec reads
  # holdings on both sides of a write.
  def holding(category) = Category.find(category.id).holding_calculator(today: today).balance

  # AVAILABLE, from a fresh ledger, for the same reason.
  def available = CategoryLedger.new(user.categories.expenses.to_a, user: user).available

  # THE PURPOSE PARTITION (§2), which is what `checking.total == Σ pools` was on the physical side:
  # available plus every holding equals what came in less what went out. Pinned against the LITERAL
  # deposits each fixture plants, never against a sum of the app's own parts.
  def purpose_total
    categories = user.categories.expenses.to_a
    ledger = CategoryLedger.new(categories, user: user)

    ledger.available + categories.sum(0.to_d) { |category| ledger.holding_of(category) }
  end

  # THE worked example, materialised. Groceries has a $400 rate rule and is holding $85 of a period
  # that ended a month ago; $585 of income arrives, $85 of which is out in Groceries, so available
  # reads $500.
  describe "a first distribution" do
    let!(:groceries) { rate_category("Groceries", 400, funded: 85) }

    before { deposit(585) }

    # Both directions of "the ledger explains the money's whole journey": the $85 goes OUT of the
    # category back to available, and $400 comes back the other way. A netted $315 line would satisfy
    # every balance assertion below and lose the sweep entirely, so the two rows are pinned by
    # direction, amount, kind and date rather than by their effect.
    #
    # THE NULL SIDE IS AVAILABLE and is asserted as such: a sweep's destination and an allocation's
    # source are the root, and a row that named a category on both ends would be a hand move.
    it "writes the sweep and the allocation in opposite directions", :aggregate_failures do
      result = commit
      sweep = Allocation.kind_sweep.sole
      allocation = Allocation.kind_allocation.sole

      expect(result.allocations).to all(be_persisted)
      expect([sweep.from_category, sweep.to_category, sweep.amount]).to eq([groceries, nil, 85])
      expect([allocation.from_category, allocation.to_category, allocation.amount]).to eq([nil, groceries, 400])
      expect([sweep.date.to_date, allocation.date.to_date]).to eq([today, today])
    end

    # WHAT THE SPLIT SAYS IT IS DISTRIBUTING. Provenance rather than a key — replacement finds its
    # rows by kind, period and owner — so it is pinned here once, on both directions, and the
    # no-income shape is pinned below where the ledger has nothing to name.
    it "records the period's income entry as what caused every row", :aggregate_failures do
      commit

      expect(Allocation.distributed.map(&:source_entry).uniq).to eq([Entry.incomes.sole])
      expect(Entry.incomes.sole.amount).to eq(585)
    end

    # Conservation over the MATERIALISED ledger, read back off the ledger rather than off the proposal
    # that asked for it. `purpose_total` is the §2 partition — the invariant the whole app rests on —
    # and it is pinned on both sides of the write, because "unchanged" asserted only afterwards is
    # half a statement.
    #
    # The category ends at $400, its rule's FULL amount, not at the $315 a live-balance ask would have
    # funded it to; and the three figures 400 / 185 / 585 are all different, so no pair of them can
    # pass by coinciding.
    it "conserves the total and funds the category to its rule", :aggregate_failures do
      expect(purpose_total).to eq(585)
      expect(holding(groceries)).to eq(85)
      expect(available).to eq(500)

      commit

      expect(purpose_total).to eq(585)
      expect(holding(groceries)).to eq(400)
      expect(available).to eq(185)
    end

    # Available lands exactly where the proposal said the money not handed out would be, and the
    # written rows sum to what the proposal proposed. One side of each comparison is read back out of
    # the database, the other is the snapshot — a line with the proposal on both sides would prove
    # nothing about what was written.
    it "leaves available at what the proposal said it would allocate out of", :aggregate_failures do
      expect(proposal.available).to eq(585)
      expect(proposal.total_allocated).to eq(400)

      commit(from: proposal)

      expect(available).to eq(proposal.available - proposal.total_allocated)
      expect(Allocation.kind_allocation.sum(:amount)).to eq(proposal.total_allocated)
      expect(Allocation.kind_sweep.sum(:amount)).to eq(proposal.total_swept)
    end

    # Re-deriving the split after the (empty) deletion cannot change it when nothing was deleted: same
    # user, same day, and no write in between. Pinned so the single-path choice in #call is measured
    # rather than asserted.
    it "writes exactly what the proposal it was handed described", :aggregate_failures do
      proposed = [proposal.total_swept, proposal.total_allocated] # read BEFORE the write, while it is still true

      result = commit(from: proposal)

      expect(result.success?).to be(true)
      expect(result.errors).to be_empty
      expect(proposed).to eq([85, 400])
      expect([result.swept, result.allocated]).to eq(proposed)
      expect(result.allocations.map(&:kind)).to eq(["sweep", "allocation"])
    end
  end

  # The negative direction of "sweeps and allocations both appear": the same category funded inside
  # the LIVE period sweeps nothing, so a distribution that always wrote a sweep row would fail here
  # while the group above still passed.
  it "writes no sweep when there is nothing to sweep", :aggregate_failures do
    deposit(600)
    groceries = rate_category("Groceries", 400, funded: 85, on: this_period)

    commit

    expect(Allocation.kind_sweep).to be_empty
    expect(Allocation.kind_allocation.sole.amount).to eq(315)
    expect(holding(groceries)).to eq(400)
    expect(available).to eq(200)
    expect(purpose_total).to eq(600)
  end

  # THE SPLIT WITH NO PAYCHECK BEHIND IT — a period funded entirely out of carried-over available.
  # `source_entry` is nil rather than a guess, and the split still replaces itself correctly, which is
  # what says the provenance column is not the replacement key.
  it "writes a split with no source entry when no income arrived in the period", :aggregate_failures do
    deposit(600, on: Date.new(2026, 8, 1)) # the previous period
    rate_category("Groceries", 400)

    commit
    commit

    expect(Allocation.distributed.map(&:source_entry)).to eq([nil])
    expect(Allocation.distributed.sole.amount).to eq(400)
  end

  # The zero-skip's PRODUCTION shape, and the one an override cannot stand in for: #fill drops rows
  # whose NEED is zero but keeps a row whose FUNDING is zero — the category below the point the money
  # ran out. $585 against $400 + $300 + $200 of asks funds [400, 185, 0]. Unskipped, Zinc's $0 line
  # fails `amount > 0` and rolls back the whole distribution: one category getting nothing would leave
  # every category unfunded.
  describe "a category the money never reached" do
    let!(:groceries) { rate_category("Groceries", 400, funded: 85) }
    let!(:water) { rate_category("Water", 300) }
    let!(:zinc) { rate_category("Zinc", 200) }

    before { deposit(585) }

    it "writes no line for it and funds the categories above it", :aggregate_failures do
      expect(proposal.rows.map(&:funded)).to eq([400, 185, 0]) # Zinc HAS a row; it is funded nothing

      commit

      expect(Allocation.kind_allocation.map(&:to_category)).to eq([groceries, water])
      expect([holding(groceries), holding(water), holding(zinc)]).to eq([400, 185, 0])
      expect(purpose_total).to eq(585)
    end
  end

  # One transaction, and the sweep is what proves it: sweeps are written FIRST, so a bad allocation
  # has to take an already-saved row back out with it.
  describe "a failure part-way through" do
    let!(:groceries) { rate_category("Groceries", 400, funded: 85) }
    let!(:water) { rate_category("Water", 300) }

    before { deposit(585) }

    it "rolls the whole split back and reports the line that failed", :aggregate_failures do
      result = commit(overrides: { water.id => -50 })

      expect(result.success?).to be(false)
      expect(result.errors).to eq(["Water: Amount must be greater than 0"])
      expect(result.allocations).to be_empty
      expect(Allocation.distributed).to be_empty
      expect(Allocation.count).to eq(1) # the Jul 12 funding transfer, and nothing else
      expect(holding(groceries)).to eq(85)
      expect(available).to eq(500)
      expect(purpose_total).to eq(585)
    end

    # One shape for both outcomes, so a caller reading a total off a failure gets the same TYPE it
    # would off a success. `sum` over no allocations is where a bare Integer 0 would leak into
    # whatever the controller renders beside the errors.
    it "reports BigDecimal totals on a failure too", :aggregate_failures do
      result = commit(overrides: { water.id => -50 })

      expect(result.allocated).to eq(0)
      expect(result.allocated).to be_a(BigDecimal)
      expect(result.swept).to eq(0)
      expect(result.swept).to be_a(BigDecimal)
    end

    # An outer transaction is what makes `requires_new: true` load-bearing: without it the inner block
    # opens no savepoint, `ActiveRecord::Rollback` is swallowed, and the outer transaction COMMITS the
    # sweep and the good allocation while this class reports a failure. A committed partial split
    # described as a failure is the worst thing here can produce, and no assertion inside the block
    # could see it — the ledger is read after the outer transaction has closed.
    it "writes nothing when a caller wraps the commit in its own transaction", :aggregate_failures do
      result = ActiveRecord::Base.transaction { commit(overrides: { water.id => -50 }) }

      expect(result.success?).to be(false)
      expect(Allocation.distributed).to be_empty
      expect([holding(groceries), holding(water), available]).to eq([85, 0, 500])
      expect(purpose_total).to eq(585)
    end

    # The same fixture without the bad override, so the example above cannot pass against a committer
    # that writes nothing at all. Water is the short row — $300 asked, $185 left by the time the
    # waterfall reaches it — and what gets written is what it was FUNDED, never what it needed: a
    # category cannot be handed money that is not there.
    it "writes both lines when every line is valid", :aggregate_failures do
      result = commit

      expect(result.success?).to be(true)
      expect(Allocation.distributed.count).to eq(3)
      expect(holding(groceries)).to eq(400)
      expect(holding(water)).to eq(185)
      expect(purpose_total).to eq(585)
    end
  end

  describe "overrides" do
    let!(:groceries) { rate_category("Groceries", 400, funded: 85) }
    let!(:water) { rate_category("Water", 300) }

    before { deposit(585) }

    # A $0 allocation is not an event, and `Allocation` would refuse it anyway. Asserted against the
    # sibling that IS funded and against the available that keeps the money, so "skipped" cannot pass
    # as "the whole distribution collapsed".
    it "skips a line overridden to zero and leaves that money in available", :aggregate_failures do
      commit(overrides: { water.id => 0 })

      expect(Allocation.kind_allocation.map(&:to_category)).to eq([groceries])
      expect(holding(water)).to eq(0)
      expect(holding(groceries)).to eq(400)
      expect(available).to eq(185)
      expect(purpose_total).to eq(585)
    end

    # AN OVERRIDE ABOVE THE ASK IS HONOURED, BUT ONLY AS FAR AS THE MONEY GOES. Water asks $300 and
    # $185 is left once Groceries has taken its $400, so a $350 override writes $185 and the root
    # lands on zero rather than on -$165.
    #
    # Pinned against a $350 that must NOT appear anywhere, so the example cannot pass on a committer
    # that quietly writes the face value into a different row.
    it "clamps an override larger than the money that is left", :aggregate_failures do
      commit(overrides: { water.id => 350 })

      expect(Allocation.kind_allocation.sum(:amount)).to eq(585)
      expect(holding(water)).to eq(185)
      expect(available).to eq(0)
      expect(Allocation.kind_allocation.pluck(:amount)).not_to include(350)
      expect(purpose_total).to eq(585)
    end

    # The row still SAYS what was asked for, so the clamp is visible rather than silent: the screen
    # renders `$185.00 of $350.00` off exactly these two numbers.
    it "keeps the asked-for figure on the row it clamped", :aggregate_failures do
      row = AllocationCalculator.new(user: user, today: today, overrides: { water.id => 350 }).rows.last

      expect(row.needed).to eq(350)
      expect(row.funded).to eq(185)
      expect(row.short).to eq(165)
    end

    # What a form actually submits: strings. Both shapes in one example because they take different
    # paths — "42.50" is an amount, and an EMPTY box is not an override at all.
    #
    # A blank is a row nobody touched, and it HAS to fall through to the rule's ask, or every
    # untouched row on a submitted form would be pinned at its old figure and no money could ever
    # cascade. "Give it nothing" is typed as `0`, which the example above pins.
    #
    # Water taking its full $300 rather than the $185 the un-overridden proposal left it is the
    # cascade in its smallest form: $357.50 freed above it covers the whole ask.
    it "takes overrides as the strings a form submits, and reads a blank as untouched", :aggregate_failures do
      commit(overrides: { groceries.id => "42.50", water.id => "" })

      expect(Allocation.kind_allocation.pluck(:amount)).to contain_exactly(42.50, 300)
      expect(holding(groceries)).to eq(42.50)
      expect(holding(water)).to eq(300)
      expect(available).to eq(242.50)
      expect(purpose_total).to eq(585)
    end

    # An override naming a category with no line has no line to edit. Reachable whenever the ledger
    # moved between render and confirm, and silent by design — but asserted, so the choice is visible
    # rather than incidental.
    #
    # THE MONEY IS DELIBERATELY SCARCE: available is $385 against $700 of asks and it runs out inside
    # Groceries, whose $385 is the figure that can tell. Gas is FIRST in fill order — `[priority,
    # name]` and every priority here is 0, so it sorts ahead of Groceries and Water — which is the
    # worst case: a row for it would take its $175 off the top and leave Groceries $210.
    it "ignores an override for a category the proposal has no row for", :aggregate_failures do
      gas = rate_category("Gas", 200, funded: 200, on: this_period)
      expect(proposal.rows.map(&:category)).to eq([groceries, water])

      commit(overrides: { gas.id => 175 })

      expect(Allocation.kind_allocation.map(&:to_category)).to eq([groceries])
      expect(holding(groceries)).to eq(385) # $210 if Gas had consumed its override
      expect(holding(water)).to eq(0)
      expect(holding(gas)).to eq(200)
      expect(available).to eq(0)
      expect(purpose_total).to eq(585)
    end
  end

  # Idempotence within a period. The second commit is handed the SAME proposal object as the first —
  # the snapshot the first commit invalidated — because that is what a screen holds.
  describe "re-running a distribution in the same period" do
    let!(:groceries) { rate_category("Groceries", 400, funded: 85) }
    let!(:water) { rate_category("Water", 350) }
    # A manual top-up the user made on Aug 10, inside this very period, out of the same available a
    # distribution funds from. It is a `transfer`, so replacement must not see it — and it touches the
    # same category, so ONLY its kind keeps it alive.
    let!(:reallocation) { fund(water, 30, on: Date.new(2026, 8, 10)) }
    # LAST period's distribution, dated Aug 6 — one day before this period opened on Aug 7. Same kind
    # as the rows replacement deletes, so only the date keeps it alive.
    let!(:previous_period_allocation) { fund(water, 20, on: Date.new(2026, 8, 6), kind: :allocation) }
    # The far edge of the same period: an allocation written at 23:30 on its LAST day, which
    # replacement must take. `date` is a datetime column, so a period bounded by bare dates ends at
    # midnight ON that day and this row would outlive its own replacement — the same split written
    # twice, the defect the whole `kind` column exists to prevent. It differs from the Aug 6 row above
    # in nothing but its date.
    let!(:late_in_period_allocation) { fund(water, 10, on: Time.zone.parse("2026-08-20 23:30"), kind: :allocation) }

    before { deposit(1_000) }

    it "replaces the previous split instead of doubling it", :aggregate_failures do
      commit
      first_run = Allocation.distributed.where(date: today).pluck(:id)
      expect(first_run.size).to eq(3)

      commit

      expect(Allocation.where(id: first_run)).to be_empty
      expect(Allocation.distributed.where(date: today).count).to eq(3)
      expect(holding(groceries)).to eq(400)
      expect(holding(water)).to eq(350)
      expect(available).to eq(250)
      expect(purpose_total).to eq(1_000)
    end

    # The DELETION's rollback, and the only example that can assert it: every other failure here runs
    # on a period with no previous distribution, so `destroy_all` matches nothing and a deletion
    # hoisted out of the transaction looks identical. A re-run carrying a mistyped negative override
    # is the likeliest way to meet it — the very scenario replacement exists for — and hoisted, it
    # destroys the previous split, writes nothing in its place, and reports a failure over a period
    # that has just been emptied.
    it "keeps the previous split when the re-run fails", :aggregate_failures do
      commit
      first_run = Allocation.distributed.where(date: today).pluck(:id)

      result = commit(overrides: { water.id => -50 })

      expect(result.success?).to be(false)
      expect(Allocation.where(id: first_run).count).to eq(3)
      expect([holding(groceries), holding(water), available]).to eq([400, 350, 250])
      expect(purpose_total).to eq(1_000)
    end

    # The committer is not single-use: #call resets its memos, so a second call re-reads the ledger
    # rather than re-committing the first call's snapshot.
    #
    # $800 spent between the two calls is what makes this measurable, and nothing weaker would: the
    # deletion restores exactly the world the first snapshot described, so on an unchanged ledger a
    # memoised committer writes the identical split and looks right. With the money gone there is
    # $150 to hand out, not $700.
    it "re-reads the ledger on a second call rather than re-committing its snapshot", :aggregate_failures do
      committer = described_class.new(proposal)
      committer.call
      spend(800)

      committer.call

      expect([holding(groceries), holding(water), available]).to eq([150, 50, 0])
      expect(purpose_total).to eq(200)
    end

    # The other half of the deletion, and the reason `kind` exists at all: a deletion asserted only by
    # what disappears is half an assertion. Both survivors sit in the blast radius of a looser rule —
    # one by kind, one by date.
    it "leaves a manual transfer and last period's distribution untouched", :aggregate_failures do
      commit
      commit

      expect(reallocation.reload.amount).to eq(30)
      expect(previous_period_allocation.reload.amount).to eq(20)
      expect(Allocation.where(id: late_in_period_allocation.id)).to be_empty
      expect(user.period_containing(today)).to eq(Date.new(2026, 8, 7)..today)
    end

    # A STRANGER'S SPLIT IN THE SAME PERIOD IS NOT THIS USER'S. The account filter that used to carry
    # this is gone with the second root, so the owner test is the only thing left standing between one
    # user's re-run and another user's rows — and it is a subquery over `user.categories` rather than
    # a plucked list, so it cannot be satisfied by a stale id set either.
    it "leaves another user's split for the same period alone", :aggregate_failures do
      stranger = create(:category, :expense, :funded, user: create(:user), name: "Theirs")
      theirs = create(:allocation, to_category: stranger, amount: 77, date: today, kind: :allocation)

      commit
      commit

      expect(Allocation.where(id: theirs.id).sole.amount).to eq(77)
      expect(Allocation.distributed.where(date: today).count).to eq(4) # their one, and this split's three
    end

    # One run and two runs land in the same place, which is what idempotence means here.
    it "ends in the same state as a single run", :aggregate_failures do
      commit
      once = [holding(groceries), holding(water), available]

      commit

      expect([holding(groceries), holding(water), available]).to eq(once)
      expect(once).to eq([400, 350, 250])
    end

    # The same re-run driven by the snapshot the FIRST commit invalidated, rather than by a fresh one.
    # Both callers exist — a screen holds its proposal, a controller builds a new one — and the ledger
    # must not depend on which.
    it "reaches the same ledger from a stale proposal as from a fresh one", :aggregate_failures do
      commit(from: proposal)
      commit(from: proposal)

      expect([holding(groceries), holding(water), available]).to eq([400, 350, 250])
      expect(Allocation.distributed.where(date: today).count).to eq(3)
      expect(purpose_total).to eq(1_000)
    end

    # THE case the plan's "commit the proposal you were handed" rule gets wrong, and the one a re-run
    # actually takes: the screen is rendered AFTER a distribution, so it sees the categories already
    # funded and asks for nothing at all. Committing that proposal deletes the previous split and
    # writes nothing in its place — the button labelled "distribute" undoing the distribution.
    #
    # The empty proposal is pinned FIRST, because an example that only checked the balances afterwards
    # could not tell "re-derived correctly" from "the rendered proposal happened to still be right".
    it "does not undo the split when the proposal was rendered after it", :aggregate_failures do
      commit
      rendered_after = AllocationCalculator.new(user: user, today: today)
      expect(rendered_after.rows).to be_empty
      expect(rendered_after.sweeps).to be_empty

      commit(from: rendered_after)

      expect([holding(groceries), holding(water), available]).to eq([400, 350, 250])
      expect(Allocation.distributed.where(date: today).count).to eq(3)
      expect(purpose_total).to eq(1_000)
    end
  end

  # The reason replacement was chosen over refusal, and the case that decides whether the re-run is
  # computed against the ledger as it is at confirm time. $40 was a typo for $400.
  it "redoes a mistyped override rather than compounding it", :aggregate_failures do
    deposit(585)
    groceries = rate_category("Groceries", 400, funded: 85)

    commit(overrides: { groceries.id => 40 })
    expect(holding(groceries)).to eq(40)
    expect(available).to eq(545)

    commit

    expect(holding(groceries)).to eq(400)
    expect(available).to eq(185)
    expect(purpose_total).to eq(585)
    expect(Allocation.distributed.count).to eq(2)
  end

  # ONE PERIOD SPANNING TWO ALREADY-COMMITTED SPLITS — the ruled behaviour of #previous_distribution
  # when the user changes their cadence.
  #
  # THE STATE IS REACHABLE AND NOT EXOTIC. Nothing stops a user distributing weekly for a month and
  # then telling the app they are paid fortnightly. `#period` is `period_datetimes_containing(today)`
  # read against the cadence AS IT STANDS, so the moment the cadence widens, two splits that were each
  # a period's whole distribution are both inside one period.
  #
  # THE RULE IS "the period's distribution", NOT "the last one". #previous_distribution filters on the
  # period and the owner and nothing else, so it takes BOTH splits — which is the right answer and
  # worth pinning: replacing only the most recent one would leave the earlier split's $400 sitting in
  # Groceries while the new split funded it again, double-funding one rule out of one paycheck.
  #
  # THE ROWS ARE PINNED BY ID, not by count. Three rows go in (an allocation, then a sweep and an
  # allocation) and one comes out, so a count-only assertion cannot tell "both splits replaced" from
  # "one split replaced and one row of the other survived".
  describe "a cadence change that puts two committed splits in one period" do
    let(:user) { create(:user, period_cadence: :weekly, period_anchor_date: Date.new(2026, 2, 6)) }
    let!(:groceries) { rate_category("Groceries", 400) }

    # Weekly off the same Feb 6 anchor: Aug 7..Aug 13 and Aug 14..Aug 20 are two periods, and each
    # gets its own distribution. Widened to biweekly they are ONE period, Aug 7..Aug 20.
    def weekly_first = Date.new(2026, 8, 10)
    def weekly_second = Date.new(2026, 8, 17)

    def commit_on(day)
      described_class.new(AllocationCalculator.new(user: user, today: day)).call
    end

    before { deposit(1_000, on: Date.new(2026, 8, 7)) }

    # The two committed splits, returned as the ids the replacement has to destroy.
    def two_weekly_splits
      (commit_on(weekly_first).allocations + commit_on(weekly_second).allocations).map(&:id)
    end

    # THE FIXTURE, ASSERTED RATHER THAN ASSUMED, because the example below is only about what it says
    # if these really are two separate splits under the old cadence: one allocation in the first week,
    # then a sweep of the now-closed weekly period and a re-fund in the second.
    it "distributes each weekly period on its own before the cadence moves", :aggregate_failures do
      expect(commit_on(weekly_first).allocations.map(&:kind)).to eq(["allocation"])
      expect(commit_on(weekly_second).allocations.map(&:kind)).to eq(["sweep", "allocation"])
      expect(user.period_containing(weekly_first)).not_to eq(user.period_containing(weekly_second))
    end

    it "replaces both splits with a single one", :aggregate_failures do
      old_ids = two_weekly_splits
      user.update!(period_cadence: :biweekly)
      expect(user.reload.period_containing(today)).to eq(Date.new(2026, 8, 7)..today)

      replacement = commit_on(today)

      expect(Allocation.where(id: old_ids)).to be_empty
      expect(replacement.allocations.map { |row| [row.kind, row.amount] }).to eq([["allocation", 400]])
      expect(Allocation.distributed.pluck(:date).map(&:to_date)).to eq([today])
    end

    # Conservation is the invariant, and it is a separate assertion from the row bookkeeping above
    # because the two fail differently: a replacement can lose a row and still balance, and it can
    # balance and still have double-funded a rule. Both figures are planted — $1,000 in, $400 claimed
    # by the rule — and neither is read off the other.
    it "leaves the ledger holding exactly what came in", :aggregate_failures do
      two_weekly_splits
      user.update!(period_cadence: :biweekly)

      commit_on(today)

      expect([holding(groceries), available]).to eq([400, 600])
      expect(purpose_total).to eq(1_000)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────────────────
  # TWO CONFIRMS AT ONCE, which is the one way found to break spec §7.3's "the root can never be
  # over-allocated". Everything else in this class is re-derived inside the write transaction, which
  # is strong against a STALE proposal and says nothing about a CONCURRENT one.
  describe "a confirm arriving while another is still open" do
    let!(:groceries) { rate_category("Groceries", 400, funded: 85) }

    before { deposit(585) }

    # THE NEXT-BEST THING, and it runs in the ordinary transactional world: the lock is taken before
    # the deletion, which is what makes it taken before anything is READ. A lock acquired after
    # `destroy_all` would leave the whole window this defends against open.
    #
    # THE LOCKED ROW IS THE USER'S, where the pool era locked the account: one root, one distribution,
    # one row to contend for. Read off the statements the commit actually issued, in order, rather
    # than off the source — both indexes come from one recorded stream, so neither side is the other
    # restated.
    it "locks the user before it deletes the previous split", :aggregate_failures do
      commit
      statements = []
      recorder = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] }

      ActiveSupport::Notifications.subscribed(recorder, "sql.active_record") { commit }

      lock_at = statements.index { |sql| sql.include?("FOR UPDATE") }
      delete_at = statements.index { |sql| sql.start_with?("DELETE FROM \"allocations\"") }
      expect(lock_at).not_to be_nil
      expect(delete_at).not_to be_nil
      expect(lock_at).to be < delete_at
      expect(statements[lock_at]).to include("\"users\"")
    end

    # THE RACE ITSELF, forced rather than hoped for.
    #
    # Two connections cannot see each other's uncommitted rows, so this cannot run inside the suite's
    # per-example transaction — the fixture would be invisible to the second thread — and the group
    # opts out on both sides (`use_transactional_tests` and DatabaseCleaner's own strategy, see
    # spec/support/database_cleaner.rb).
    #
    # The interleaving is deterministic, not timing-dependent: the racer signals the instant it has
    # finished READING the ledger, and the first commit holds its transaction open until that signal
    # arrives. Without the lock the signal comes in milliseconds and the racer is provably stale; with
    # the lock it never comes at all, because `call` blocks on `user.lock!` before it reads anything —
    # so the first commit waits out its timeout and then releases, and the racer re-reads a ledger that
    # already holds the split.
    #
    # MEASURED ON THE POOL-ERA TWIN WITH THE LOCK REMOVED: two allocations and two sweeps, Groceries
    # $715 against a $400 rule, the root at -$130. The partition still held — conservation is not what
    # breaks — while the root was over-allocated by $130, which is the §7.3 state this plan calls
    # devastating.
    describe "with both commits genuinely overlapping", :truncation do
      self.use_transactional_tests = false

      # A fresh committer on its own connection, wired to say when it has read the ledger. The
      # singleton override wraps the LAST read before the first save — `allocations` builds every line
      # out of the live proposal — so the signal marks exactly the moment a second confirm would be
      # committing figures the first one has already invalidated.
      def racing_commit(user_id, read_signal)
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            proposal = AllocationCalculator.new(user: User.find(user_id), today: today)
            committer = described_class.new(proposal)
            committer.define_singleton_method(:allocations) { super().tap { read_signal.push(:read) } }
            committer.call
          end
        end
      end

      # Both commits, with the second guaranteed to be running while the first's transaction is still
      # open. Returns the finished racer (nil if it never finished) and whether it managed to READ the
      # ledger before that transaction closed — the second is the lock's whole story, and `false` is
      # the answer only a lock can give.
      def race
        signal = Queue.new
        racer = read_early = nil
        ActiveRecord::Base.transaction do
          commit
          racer = racing_commit(user.id, signal)
          read_early = !signal.pop(timeout: 2).nil?
        end
        [racer.join(10), read_early]
      end

      it "leaves exactly one split and a root that is not over-allocated", :aggregate_failures do
        finished, read_early = race

        expect(finished).to be_a(Thread) # it completed rather than deadlocking
        expect(read_early).to be(false) # it was still at the lock while the first commit ran
        expect(Allocation.kind_allocation.count).to eq(1)
        expect(Allocation.kind_sweep.count).to eq(1)
        expect(holding(groceries)).to eq(400) # $715 with the lock removed
        expect(available).to eq(185) # -$130 with the lock removed
        expect(available).to be >= 0 # spec §7.3
        expect(purpose_total).to eq(585)
      end
    end
  end

  # The `money` column keeps an Integer for in-memory records and an empty `sum` returns the Integer
  # literal 0, so the user with nothing at all is the one that changes TYPE. Asserted by type rather
  # than by value: `eq(0)` passes happily on an Integer.
  describe "a user with nothing in it" do
    it "commits nothing and reports BigDecimal zeroes", :aggregate_failures do
      result = commit

      expect(result.success?).to be(true)
      expect(result.allocations).to be_empty
      expect(result.errors).to be_empty
      expect(result.allocated).to eq(0)
      expect(result.allocated).to be_a(BigDecimal)
      expect(result.swept).to eq(0)
      expect(result.swept).to be_a(BigDecimal)
      expect(Allocation.count).to eq(0)
    end

    # The same guarantee on a commit that DID write, so the seeded sums above cannot pass by never
    # having an allocation to add up.
    it "reports BigDecimal totals on a commit that wrote", :aggregate_failures do
      deposit(585)
      rate_category("Groceries", 400, funded: 85)

      result = commit

      expect(result.allocated).to eq(400)
      expect(result.allocated).to be_a(BigDecimal)
      expect(result.swept).to eq(85)
      expect(result.swept).to be_a(BigDecimal)
    end
  end
end
