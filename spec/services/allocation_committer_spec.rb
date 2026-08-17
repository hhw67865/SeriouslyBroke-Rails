# frozen_string_literal: true

require "rails_helper"

RSpec.describe AllocationCommitter, type: :model do
  # The same calendar AllocationCalculator's spec uses: biweekly, anchored Fri 6 Feb 2026, so
  # the boundaries around August are Aug 7 and Aug 21 and the period containing Aug 20 is
  # Aug 7..Aug 20. Money paid in on Jul 12 belongs to a period that ended Jul 23 — closed.
  let(:user) { create(:user, :biweekly) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:ally) { create(:pool, :account, user: user, name: "Ally") }

  def today = Date.new(2026, 8, 20)
  def last_period = Date.new(2026, 7, 12)
  def this_period = Date.new(2026, 8, 15)

  def envelope(account: checking, **attrs)
    create(:pool, :budget_pool, user: user, account: account, **attrs)
  end

  # An envelope carrying one per-paycheck rate rule, optionally already holding money — and
  # funded OUT OF ITS OWN ACCOUNT, which is what makes the account's balance the buffer.
  def rate_envelope(name, rate, funded: nil, on: nil, **attrs)
    account = attrs.fetch(:account, checking)
    pool = envelope(name: name, **attrs)
    create(:pool_budget, :per_paycheck_rate, pool: pool, amount: rate)
    fund(pool, funded, on: on || last_period, from: account) if funded
    pool
  end

  def fund(pool, amount, on:, from: checking, kind: :transfer)
    create(:pool_movement, from_pool: from, to_pool: pool, amount: amount, date: on, kind: kind)
  end

  def deposit(amount, into: checking, on: today)
    category = create(:category, :income, user: user, pool: into)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # Money leaving the user's life, which is an Entry and never a movement — the one way the
  # world can change between two commits in a direction no replacement puts back.
  def spend(amount, from: checking, on: today)
    category = create(:category, :expense, user: user, pool: from)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # Memoised per account: every reference inside one example is the SAME proposal, which is
  # how a screen holds it, and — after a commit — the stale snapshot Amendment A is about.
  def proposal(account: checking)
    (@proposals ||= {})[account.id] ||= AllocationCalculator.new(user: user, account: account, today: today)
  end

  # A FRESH proposal per commit by default, because that is what a controller hands over: one
  # request renders a proposal, the next builds another and confirms. `from:` hands a
  # particular snapshot instead, and the two must reach the same ledger.
  # `overrides` go on the PROPOSAL now, not on the committer: the split is decided in one place,
  # inside AllocationCalculator#fill, and this class writes whatever that decided.
  def commit(overrides: {}, account: checking, from: nil)
    proposal = from || AllocationCalculator.new(user: user, account: account, today: today, overrides: overrides)
    described_class.new(proposal).call
  end

  # A FRESH calculator every time, because PoolCalculator memoises its balance and this spec
  # reads balances on both sides of a write.
  def balance(pool) = pool.calculator(today: today).balance

  # THE worked example, materialised. Groceries has a $400 rate rule and is holding $85 of a
  # period that ended a month ago; $585 of income lands in Checking, $85 of which is out in
  # Groceries, so the buffer reads $500.
  describe "a first distribution" do
    let!(:groceries) { rate_envelope("Groceries", 400, funded: 85) }

    before { deposit(585) }

    # Both directions of "the ledger explains the money's whole journey": the $85 goes OUT of
    # the envelope into the account, and $400 comes back the other way. A netted $315 line
    # would satisfy every balance assertion below and lose the sweep entirely, so the two rows
    # are pinned by direction, amount, kind and date rather than by their effect.
    it "writes the sweep and the allocation as movements in opposite directions", :aggregate_failures do
      result = commit
      sweep = PoolMovement.kind_sweep.sole
      allocation = PoolMovement.kind_allocation.sole

      expect(result.movements).to all(be_persisted)
      expect([sweep.from_pool, sweep.to_pool, sweep.amount]).to eq([groceries, checking, 85])
      expect([allocation.from_pool, allocation.to_pool, allocation.amount]).to eq([checking, groceries, 400])
      expect([sweep.date.to_date, allocation.date.to_date]).to eq([today, today])
    end

    # Conservation over the MATERIALISED ledger, read back off the pool records rather than off
    # the proposal that asked for it. `checking.total` is `Σ pools` — the invariant the whole
    # app rests on — and it is pinned on both sides of the write, because "unchanged" asserted
    # only afterwards is half a statement.
    #
    # The envelope ends at $400, its rule's FULL amount, not at the $315 a live-balance ask
    # would have funded it to; and the three figures 400 / 185 / 585 are all different, so no
    # pair of them can pass by coinciding.
    it "conserves the bank balance and funds the envelope to its rule", :aggregate_failures do
      expect(checking.total).to eq(585)
      expect(balance(groceries)).to eq(85)
      expect(balance(checking)).to eq(500)

      commit

      expect(checking.total).to eq(585)
      expect(balance(groceries)).to eq(400)
      expect(balance(checking)).to eq(185)
    end

    # The buffer lands exactly where the proposal said the money not handed out would be, and
    # the written rows sum to what the proposal proposed. One side of each comparison is read
    # back out of the database, the other is the snapshot — a line with the proposal on both
    # sides would prove nothing about what was written.
    it "leaves the buffer at available minus what it allocated", :aggregate_failures do
      expect(proposal.available).to eq(585)
      expect(proposal.total_allocated).to eq(400)

      commit(from: proposal)

      expect(balance(checking)).to eq(proposal.available - proposal.total_allocated)
      expect(PoolMovement.kind_allocation.sum(:amount)).to eq(proposal.total_allocated)
      expect(PoolMovement.kind_sweep.sum(:amount)).to eq(proposal.total_swept)
    end

    # Re-deriving the split after the (empty) deletion cannot change it when nothing was
    # deleted: same user, same account, same day, and no write in between. Pinned so the
    # single-path choice in #call is measured rather than asserted.
    it "writes exactly what the proposal it was handed described", :aggregate_failures do
      proposed = [proposal.total_swept, proposal.total_allocated] # read BEFORE the write, while it is still true

      result = commit(from: proposal)

      expect(result.success?).to be(true)
      expect(result.errors).to be_empty
      expect(proposed).to eq([85, 400])
      expect([result.swept, result.allocated]).to eq(proposed)
      expect(result.movements.map(&:to_pool)).to eq([checking, groceries])
    end
  end

  # The negative direction of "sweeps and allocations both appear": the same envelope funded
  # inside the LIVE period sweeps nothing, so a distribution that always wrote a sweep row
  # would fail here while the group above still passed.
  it "writes no sweep for an account with nothing to sweep", :aggregate_failures do
    deposit(600)
    groceries = rate_envelope("Groceries", 400, funded: 85, on: this_period)

    commit

    expect(PoolMovement.kind_sweep).to be_empty
    expect(PoolMovement.kind_allocation.sole.amount).to eq(315)
    expect(balance(groceries)).to eq(400)
    expect(balance(checking)).to eq(200)
    expect(checking.total).to eq(600)
  end

  # The zero-skip's PRODUCTION shape, and the one an override cannot stand in for: #fill drops
  # rows whose NEED is zero but keeps a row whose FUNDING is zero — the envelope below the
  # point the money ran out. $585 against $400 + $300 + $200 of asks funds [400, 185, 0].
  # Unskipped, Zinc's $0 line fails `amount > 0` and rolls back the whole distribution: one
  # envelope getting nothing would leave every envelope unfunded.
  describe "an envelope the money never reached" do
    let!(:groceries) { rate_envelope("Groceries", 400, funded: 85) }
    let!(:water) { rate_envelope("Water", 300) }
    let!(:zinc) { rate_envelope("Zinc", 200) }

    before { deposit(585) }

    it "writes no line for it and funds the envelopes above it", :aggregate_failures do
      expect(proposal.rows.map(&:funded)).to eq([400, 185, 0]) # Zinc HAS a row; it is funded nothing

      commit

      expect(PoolMovement.kind_allocation.map(&:to_pool)).to eq([groceries, water])
      expect([balance(groceries), balance(water), balance(zinc)]).to eq([400, 185, 0])
      expect(checking.total).to eq(585)
    end
  end

  # One transaction, and the sweep is what proves it: sweeps are written FIRST, so a bad
  # allocation has to take an already-saved row back out with it.
  describe "a failure part-way through" do
    let!(:groceries) { rate_envelope("Groceries", 400, funded: 85) }
    let!(:water) { rate_envelope("Water", 300) }

    before { deposit(585) }

    it "rolls the whole split back and reports the line that failed", :aggregate_failures do
      result = commit(overrides: { water.id => -50 })

      expect(result.success?).to be(false)
      expect(result.errors).to eq(["Water: Amount must be greater than 0"])
      expect(result.movements).to be_empty
      expect(PoolMovement.distributed).to be_empty
      expect(PoolMovement.count).to eq(1) # the Jul 12 funding transfer, and nothing else
      expect(balance(groceries)).to eq(85)
      expect(balance(checking)).to eq(500)
      expect(checking.total).to eq(585)
    end

    # Amendment F: one shape for both outcomes, so a caller reading a total off a failure gets
    # the same TYPE it would off a success. `sum` over no movements is where a bare Integer 0
    # would leak into whatever Task 6 renders beside the errors.
    it "reports BigDecimal totals on a failure too", :aggregate_failures do
      result = commit(overrides: { water.id => -50 })

      expect(result.allocated).to eq(0)
      expect(result.allocated).to be_a(BigDecimal)
      expect(result.swept).to eq(0)
      expect(result.swept).to be_a(BigDecimal)
    end

    # An outer transaction is what makes `requires_new: true` load-bearing: without it the
    # inner block opens no savepoint, `ActiveRecord::Rollback` is swallowed, and the outer
    # transaction COMMITS the sweep and the good allocation while this class reports a
    # failure. A committed partial split described as a failure is the worst thing here can
    # produce, and no assertion inside the block could see it — the ledger is read after the
    # outer transaction has closed.
    it "writes nothing when a caller wraps the commit in its own transaction", :aggregate_failures do
      result = ActiveRecord::Base.transaction { commit(overrides: { water.id => -50 }) }

      expect(result.success?).to be(false)
      expect(PoolMovement.distributed).to be_empty
      expect([balance(groceries), balance(water), balance(checking)]).to eq([85, 0, 500])
      expect(checking.total).to eq(585)
    end

    # The same fixture without the bad override, so the example above cannot pass against a
    # committer that writes nothing at all. Water is the short row — $300 asked, $185 left by
    # the time the waterfall reaches it — and what gets written is what it was FUNDED, never
    # what it needed: an envelope cannot be handed money the account does not have.
    it "writes both lines when every line is valid", :aggregate_failures do
      result = commit

      expect(result.success?).to be(true)
      expect(PoolMovement.distributed.count).to eq(3)
      expect(balance(groceries)).to eq(400)
      expect(balance(water)).to eq(185)
      expect(checking.total).to eq(585)
    end
  end

  describe "overrides" do
    let!(:groceries) { rate_envelope("Groceries", 400, funded: 85) }
    let!(:water) { rate_envelope("Water", 300) }

    before { deposit(585) }

    # A $0 allocation is not an event, and PoolMovement would refuse it anyway. Asserted
    # against the sibling that IS funded and against the buffer that keeps the money, so
    # "skipped" cannot pass as "the whole distribution collapsed".
    it "skips a line overridden to zero and leaves that money in the buffer", :aggregate_failures do
      commit(overrides: { water.id => 0 })

      expect(PoolMovement.kind_allocation.map(&:to_pool)).to eq([groceries])
      expect(balance(water)).to eq(0)
      expect(balance(groceries)).to eq(400)
      expect(balance(checking)).to eq(185)
      expect(checking.total).to eq(585)
    end

    # AN OVERRIDE ABOVE THE ASK IS HONOURED, BUT ONLY AS FAR AS THE CASH GOES. Water asks $300
    # and $185 is left once Groceries has taken its $400, so a $350 override writes $185 and the
    # account lands on zero rather than on -$165.
    #
    # THIS REVERSES AN EARLIER RULING and the reversal is the point of moving overrides into the
    # fill. While the committer substituted figures after the waterfall, an override wrote its
    # face value whatever the account held; spec §7.3 says the account can never be
    # over-allocated — "distribution can only hand out cash that exists — already true of the
    # waterfall" — and it is true of the waterfall again now that the override goes through it.
    #
    # Pinned against a $350 that must NOT appear anywhere, so the example cannot pass on a
    # committer that quietly writes the face value into a different row.
    it "clamps an override larger than the cash that is left", :aggregate_failures do
      commit(overrides: { water.id => 350 })

      expect(PoolMovement.kind_allocation.sum(:amount)).to eq(585)
      expect(balance(water)).to eq(185)
      expect(balance(checking)).to eq(0)
      expect(PoolMovement.kind_allocation.pluck(:amount)).not_to include(350)
      expect(checking.total).to eq(585)
    end

    # The row still SAYS what was asked for, so the clamp is visible rather than silent: the
    # screen renders `$185.00 of $350.00` off exactly these two numbers.
    it "keeps the asked-for figure on the row it clamped", :aggregate_failures do
      row = AllocationCalculator.new(
        user: user,
        account: checking,
        today: today,
        overrides: { water.id => 350 }
      ).rows.last

      expect(row.needed).to eq(350)
      expect(row.funded).to eq(185)
      expect(row.short).to eq(165)
    end

    # What a form actually submits: strings. Both shapes in one example because they take
    # different paths — "42.50" is an amount, and an EMPTY box is not an override at all.
    #
    # THAT SECOND READING INVERTED with this task, and deliberately. A cleared box used to mean
    # "give this envelope nothing", because every box was pre-filled with the proposal's own
    # figure. Boxes now render empty with the proposal as their placeholder, so a blank is a row
    # nobody touched — and it HAS to fall through to the rule's ask, or every untouched row on a
    # submitted form would be pinned at its old figure and no money could ever cascade. "Give it
    # nothing" is typed as `0`, which the example above pins.
    #
    # Water taking its full $300 rather than the $185 the un-overridden proposal left it is the
    # cascade in its smallest form: $357.50 freed above it covers the whole ask.
    it "takes overrides as the strings a form submits, and reads a blank as untouched", :aggregate_failures do
      commit(overrides: { groceries.id => "42.50", water.id => "" })

      expect(PoolMovement.kind_allocation.pluck(:amount)).to contain_exactly(42.50, 300)
      expect(balance(groceries)).to eq(42.50)
      expect(balance(water)).to eq(300)
      expect(balance(checking)).to eq(242.50)
      expect(checking.total).to eq(585)
    end

    # An override naming a pool with no line has no line to edit. Reachable whenever the
    # ledger moved between render and confirm, and silent by design — but asserted, so the
    # choice is visible rather than incidental.
    #
    # THE CASH IS DELIBERATELY SCARCE. This example used to deposit another $415, funding both
    # rows in full out of $1,000 against $700 of asks — so Gas's $175 could have been consumed on
    # the way to being discarded and every assertion would still have passed. Without it the
    # account has $385 against $700 of asks and the money runs out inside Groceries, whose $385
    # is the figure that can tell.
    #
    # Gas is FIRST in fill order — `by_priority` is `[priority, name]` and every priority here is
    # 0, so it sorts ahead of Groceries and Water — which is the worst case: a row for it would
    # take its $175 off the top and leave Groceries $210.
    it "ignores an override for a pool the proposal has no row for", :aggregate_failures do
      gas = rate_envelope("Gas", 200, funded: 200, on: this_period)
      expect(proposal.rows.map(&:pool)).to eq([groceries, water])

      commit(overrides: { gas.id => 175 })

      expect(PoolMovement.kind_allocation.map(&:to_pool)).to eq([groceries])
      expect(balance(groceries)).to eq(385) # $210 if Gas had consumed its override
      expect(balance(water)).to eq(0)
      expect(balance(gas)).to eq(200)
      expect(balance(checking)).to eq(0)
      expect(checking.total).to eq(585)
    end
  end

  # Idempotence within a period. The second commit is handed the SAME proposal object as the
  # first — the snapshot the first commit invalidated — because that is what a screen holds.
  describe "re-running a distribution in the same period" do
    let!(:groceries) { rate_envelope("Groceries", 400, funded: 85) }
    let!(:water) { rate_envelope("Water", 350) }
    # A manual top-up the user made on Aug 10, inside this very period, out of the same buffer
    # a distribution funds from. It is a `transfer`, so replacement must not see it — and it
    # touches the account, so ONLY its kind keeps it alive. An envelope-to-envelope
    # reallocation would have survived a committer that had no `kind` column at all.
    let!(:reallocation) { create(:pool_movement, from_pool: checking, to_pool: water, amount: 30, date: Date.new(2026, 8, 10)) }
    # LAST period's distribution, dated Aug 6 — one day before this period opened on Aug 7.
    # Same kind as the rows replacement deletes, so only the date keeps it alive.
    let!(:previous_period_allocation) { fund(water, 20, on: Date.new(2026, 8, 6), kind: :allocation) }
    # The far edge of the same period: an allocation written at 23:30 on its LAST day, which
    # replacement must take. `date` is a datetime column, so a period bounded by bare dates
    # ends at midnight ON that day and this row would outlive its own replacement — the same
    # split written twice, the defect the whole `kind` column exists to prevent. It differs
    # from the Aug 6 row above in nothing but its date.
    let!(:late_in_period_allocation) { fund(water, 10, on: Time.zone.parse("2026-08-20 23:30"), kind: :allocation) }

    before { deposit(1_000) }

    it "replaces the previous split instead of doubling it", :aggregate_failures do
      commit
      first_run = PoolMovement.distributed.where(date: today).pluck(:id)
      expect(first_run.size).to eq(3)

      commit

      expect(PoolMovement.where(id: first_run)).to be_empty
      expect(PoolMovement.distributed.where(date: today).count).to eq(3)
      expect(balance(groceries)).to eq(400)
      expect(balance(water)).to eq(350)
      expect(balance(checking)).to eq(250)
      expect(checking.total).to eq(1_000)
    end

    # The DELETION's rollback, and the only example that can assert it: every other failure
    # here runs on a period with no previous distribution, so `destroy_all` matches nothing
    # and a deletion hoisted out of the transaction looks identical. A re-run carrying a
    # mistyped negative override is the likeliest way to meet it — the very scenario
    # replacement exists for — and hoisted, it destroys the previous split, writes nothing in
    # its place, and reports a failure over a period that has just been emptied.
    it "keeps the previous split when the re-run fails", :aggregate_failures do
      commit
      first_run = PoolMovement.distributed.where(date: today).pluck(:id)

      result = commit(overrides: { water.id => -50 })

      expect(result.success?).to be(false)
      expect(PoolMovement.where(id: first_run).count).to eq(3)
      expect([balance(groceries), balance(water), balance(checking)]).to eq([400, 350, 250])
      expect(checking.total).to eq(1_000)
    end

    # The committer is not single-use: #call resets its memos, so a second call re-reads the
    # ledger rather than re-committing the first call's snapshot.
    #
    # $800 spent between the two calls is what makes this measurable, and nothing weaker
    # would: the deletion restores exactly the world the first snapshot described, so on an
    # unchanged ledger a memoised committer writes the identical split and looks right. With
    # the money gone there is $150 to hand out, not $700 — memoised, the second call funds
    # Groceries $400 and Water $300 out of an account that has $65 in it and leaves the buffer
    # at -$550. Measured both ways; the reset is what stands between them.
    it "re-reads the ledger on a second call rather than re-committing its snapshot", :aggregate_failures do
      committer = described_class.new(proposal)
      committer.call
      spend(800)

      committer.call

      expect([balance(groceries), balance(water), balance(checking)]).to eq([150, 50, 0])
      expect(checking.total).to eq(200)
    end

    # The other half of the deletion, and the reason `kind` exists at all: a deletion asserted
    # only by what disappears is half an assertion. Both survivors sit in the blast radius of
    # a looser rule — one by kind, one by date.
    it "leaves a manual transfer and last period's distribution untouched", :aggregate_failures do
      commit
      commit

      expect(reallocation.reload.amount).to eq(30)
      expect(previous_period_allocation.reload.amount).to eq(20)
      expect(PoolMovement.where(id: late_in_period_allocation.id)).to be_empty
      expect(user.period_containing(today)).to eq(Date.new(2026, 8, 7)..today)
    end

    # One run and two runs land in the same place, which is what idempotence means here.
    it "ends in the same state as a single run", :aggregate_failures do
      commit
      once = [balance(groceries), balance(water), balance(checking)]

      commit

      expect([balance(groceries), balance(water), balance(checking)]).to eq(once)
      expect(once).to eq([400, 350, 250])
    end

    # The same re-run driven by the snapshot the FIRST commit invalidated, rather than by a
    # fresh one. Both callers exist — a screen holds its proposal, a controller builds a new
    # one — and the ledger must not depend on which.
    it "reaches the same ledger from a stale proposal as from a fresh one", :aggregate_failures do
      commit(from: proposal)
      commit(from: proposal)

      expect([balance(groceries), balance(water), balance(checking)]).to eq([400, 350, 250])
      expect(PoolMovement.distributed.where(date: today).count).to eq(3)
      expect(checking.total).to eq(1_000)
    end

    # THE case the plan's "commit the proposal you were handed" rule gets wrong, and the one
    # a re-run actually takes: the screen is rendered AFTER a distribution, so it sees the
    # envelopes already funded and asks for nothing at all. Committing that proposal deletes
    # the previous split and writes nothing in its place — the button labelled "distribute"
    # undoing the distribution. Measured before the fix: 400/350/250 fell back to 85/50/865.
    #
    # The empty proposal is pinned FIRST, because an example that only checked the balances
    # afterwards could not tell "re-derived correctly" from "the rendered proposal happened to
    # still be right".
    it "does not undo the split when the proposal was rendered after it", :aggregate_failures do
      commit
      rendered_after = AllocationCalculator.new(user: user, account: checking, today: today)
      expect(rendered_after.rows).to be_empty
      expect(rendered_after.sweeps).to be_empty

      commit(from: rendered_after)

      expect([balance(groceries), balance(water), balance(checking)]).to eq([400, 350, 250])
      expect(PoolMovement.distributed.where(date: today).count).to eq(3)
      expect(checking.total).to eq(1_000)
    end
  end

  # The reason replacement was chosen over refusal, and the case that decides whether the
  # re-run is computed against the ledger as it is at confirm time. $40 was a typo for $400.
  it "redoes a mistyped override rather than compounding it", :aggregate_failures do
    deposit(585)
    groceries = rate_envelope("Groceries", 400, funded: 85)

    commit(overrides: { groceries.id => 40 })
    expect(balance(groceries)).to eq(40)
    expect(balance(checking)).to eq(545)

    commit

    expect(balance(groceries)).to eq(400)
    expect(balance(checking)).to eq(185)
    expect(checking.total).to eq(585)
    expect(PoolMovement.distributed.count).to eq(2)
  end

  # ONE PERIOD SPANNING TWO ALREADY-COMMITTED SPLITS — the ruled behaviour of
  # #previous_distribution when the user changes their cadence, and until now exercised nowhere.
  #
  # THE STATE IS REACHABLE AND NOT EXOTIC. Nothing stops a user distributing weekly for a month
  # and then telling the app they are paid fortnightly; the Budget page's declaration form is one
  # select away. `#period` is `period_datetimes_containing(today)` read against the cadence AS IT
  # STANDS, so the moment the cadence widens, two splits that were each a period's whole
  # distribution are both inside one period.
  #
  # THE RULE IS "the period's distribution", NOT "the last one". #previous_distribution filters on
  # the period and the account and nothing else, so it takes BOTH splits — which is the right
  # answer and worth pinning: replacing only the most recent one would leave the earlier split's
  # $400 sitting in Groceries while the new split funded it again, double-funding one rule out of
  # one paycheck.
  #
  # THE ROWS ARE PINNED BY ID, not by count. Three rows go in (an allocation, then a sweep and an
  # allocation) and one comes out, so a count-only assertion cannot tell "both splits replaced"
  # from "one split replaced and one row of the other survived".
  #
  # `Σ pools` IS PINNED AGAINST THE PLANTED DEPOSIT, never against `Pool#total`'s own parts: $1,000
  # went in, nothing was spent, and $1,000 is what the tree holds before and after. A replacement
  # that lost or duplicated a movement moves this figure and nothing else would say so.
  describe "a cadence change that puts two committed splits in one period" do
    let(:user) { create(:user, period_cadence: :weekly, period_anchor_date: Date.new(2026, 2, 6)) }
    let!(:groceries) { rate_envelope("Groceries", 400) }

    # Weekly off the same Feb 6 anchor: Aug 7..Aug 13 and Aug 14..Aug 20 are two periods, and each
    # gets its own distribution. Widened to biweekly they are ONE period, Aug 7..Aug 20.
    def weekly_first = Date.new(2026, 8, 10)
    def weekly_second = Date.new(2026, 8, 17)

    def commit_on(day)
      described_class.new(AllocationCalculator.new(user: user, account: checking, today: day)).call
    end

    before { deposit(1_000, on: Date.new(2026, 8, 7)) }

    # The two committed splits, returned as the ids the replacement has to destroy.
    def two_weekly_splits
      (commit_on(weekly_first).movements + commit_on(weekly_second).movements).map(&:id)
    end

    # THE FIXTURE, ASSERTED RATHER THAN ASSUMED, because the example below is only about what it
    # says if these really are two separate splits under the old cadence: one allocation in the
    # first week, then a sweep of the now-closed weekly period and a re-fund in the second.
    it "distributes each weekly period on its own before the cadence moves", :aggregate_failures do
      expect(commit_on(weekly_first).movements.map(&:kind)).to eq(["allocation"])
      expect(commit_on(weekly_second).movements.map(&:kind)).to eq(["sweep", "allocation"])
      expect(user.period_containing(weekly_first)).not_to eq(user.period_containing(weekly_second))
    end

    it "replaces both splits with a single one", :aggregate_failures do
      old_ids = two_weekly_splits
      user.update!(period_cadence: :biweekly)
      expect(user.reload.period_containing(today)).to eq(Date.new(2026, 8, 7)..today)

      replacement = commit_on(today)

      expect(PoolMovement.where(id: old_ids)).to be_empty
      expect(replacement.movements.map { |movement| [movement.kind, movement.amount] })
        .to eq([["allocation", 400]])
      expect(PoolMovement.distributed.pluck(:date).map(&:to_date)).to eq([today])
    end

    # Conservation is the invariant, and it is a separate assertion from the row bookkeeping above
    # because the two fail differently: a replacement can lose a row and still balance, and it can
    # balance and still have double-funded a rule. Both figures are planted — $1,000 deposited,
    # $400 claimed by the rule — and neither is read off the other.
    it "leaves the tree holding exactly what was paid in", :aggregate_failures do
      two_weekly_splits
      user.update!(period_cadence: :biweekly)

      commit_on(today)

      expect([balance(groceries), balance(checking)]).to eq([400, 600])
      expect(checking.total).to eq(1_000)
    end
  end

  # Replacement is scoped to the account being distributed, not to the period alone. Both
  # directions: Checking's re-run keeps Ally's rows, and Ally's own re-run keeps Checking's.
  describe "a second account distributing in the same period" do
    let!(:groceries) { rate_envelope("Groceries", 400, funded: 85) }
    let!(:holiday) { rate_envelope("Holiday", 700, account: ally, funded: 90) }

    before do
      deposit(585)
      deposit(1_000, into: ally)
      commit
      commit(account: ally)
    end

    def rows_for(*pools) = PoolMovement.distributed.where(to_pool: pools).pluck(:id)

    it "replaces Checking's rows and keeps Ally's", :aggregate_failures do
      ally_rows = rows_for(ally, holiday)
      checking_rows = rows_for(checking, groceries)
      expect([ally_rows.size, checking_rows.size]).to eq([2, 2])

      commit

      expect(PoolMovement.where(id: ally_rows).count).to eq(2)
      expect(PoolMovement.where(id: checking_rows)).to be_empty
    end

    # The same statement from the other side, because "replaces only the account it was given"
    # asserted in one direction is satisfied by a committer that simply never touches Ally.
    it "replaces Ally's rows and keeps Checking's", :aggregate_failures do
      ally_rows = rows_for(ally, holiday)
      checking_rows = rows_for(checking, groceries)

      commit(account: ally)

      expect(PoolMovement.where(id: checking_rows).count).to eq(2)
      expect(PoolMovement.where(id: ally_rows)).to be_empty
      expect(balance(holiday)).to eq(700)
    end

    # Both accounts are whole, and neither took anything from the other: two distributions on
    # the same day, each conserving its own bank balance.
    it "leaves both accounts conserved after the re-run", :aggregate_failures do
      commit

      expect(balance(holiday)).to eq(700)
      expect(balance(groceries)).to eq(400)
      expect(ally.total).to eq(1_000)
      expect(checking.total).to eq(585)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────────────────────
  # TWO CONFIRMS AT ONCE, which is the one way found to break spec §7.3's "the account can never
  # be over-allocated". Everything else in this class is re-derived inside the write transaction,
  # which is strong against a STALE proposal and says nothing about a CONCURRENT one.
  describe "a confirm arriving while another is still open" do
    let!(:groceries) { rate_envelope("Groceries", 400, funded: 85) }

    before { deposit(585) }

    # THE NEXT-BEST THING, and it runs in the ordinary transactional world: the lock is taken
    # before the deletion, which is what makes it taken before anything is READ. A lock acquired
    # after `destroy_all` would leave the whole window this defends against open.
    #
    # Read off the statements the commit actually issued, in order, rather than off the source —
    # both indexes come from one recorded stream, so neither side is the other restated.
    it "locks the account before it deletes the previous split", :aggregate_failures do
      commit
      statements = []
      recorder = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] }

      ActiveSupport::Notifications.subscribed(recorder, "sql.active_record") { commit }

      lock_at = statements.index { |sql| sql.include?("FOR UPDATE") }
      delete_at = statements.index { |sql| sql.start_with?("DELETE FROM \"pool_movements\"") }
      expect(lock_at).not_to be_nil
      expect(delete_at).not_to be_nil
      expect(lock_at).to be < delete_at
      expect(statements[lock_at]).to include("\"pools\"")
    end

    # THE RACE ITSELF, forced rather than hoped for.
    #
    # Two connections cannot see each other's uncommitted rows, so this cannot run inside the
    # suite's per-example transaction — the fixture would be invisible to the second thread — and
    # the group opts out on both sides (`use_transactional_tests` and DatabaseCleaner's own
    # strategy, see spec/support/database_cleaner.rb).
    #
    # The interleaving is deterministic, not timing-dependent: the racer signals the instant it
    # has finished READING the ledger, and the first commit holds its transaction open until that
    # signal arrives. Without the lock the signal comes in milliseconds and the racer is provably
    # stale; with the lock it never comes at all, because `call` blocks on `account.lock!` before
    # it reads anything — so the first commit waits out its timeout and then releases, and the
    # racer re-reads a ledger that already holds the split.
    #
    # MEASURED WITH THE LOCK REMOVED: two allocations and two sweeps, Groceries $715 against a
    # $400 rule, Checking -$130. `Σ pools` still held at $585 — conservation is not what breaks —
    # while the account was over-allocated by $130, which is the §7.3 state this plan calls
    # devastating. Every other example in this file passed unchanged.
    describe "with both commits genuinely overlapping", :truncation do
      self.use_transactional_tests = false

      # A fresh committer on its own connection, wired to say when it has read the ledger. The
      # singleton override wraps the LAST read before the first save — `movements` builds every
      # line out of the live proposal — so the signal marks exactly the moment a second confirm
      # would be committing figures the first one has already invalidated.
      def racing_commit(account_id, user_id, read_signal)
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            account = Pool.find(account_id)
            proposal = AllocationCalculator.new(user: User.find(user_id), account: account, today: today)
            committer = described_class.new(proposal)
            committer.define_singleton_method(:movements) { super().tap { read_signal.push(:read) } }
            committer.call
          end
        end
      end

      # Both commits, with the second guaranteed to be running while the first's transaction is
      # still open. Returns the finished racer (nil if it never finished) and whether it managed
      # to READ the ledger before that transaction closed — the second is the lock's whole story,
      # and `false` is the answer only a lock can give.
      def race
        signal = Queue.new
        racer = read_early = nil
        ActiveRecord::Base.transaction do
          commit
          racer = racing_commit(checking.id, user.id, signal)
          read_early = !signal.pop(timeout: 2).nil?
        end
        [racer.join(10), read_early]
      end

      it "leaves exactly one split and an account that is not over-allocated", :aggregate_failures do
        finished, read_early = race

        expect(finished).to be_a(Thread) # it completed rather than deadlocking
        expect(read_early).to be(false) # it was still at the lock while the first commit ran
        expect(PoolMovement.kind_allocation.count).to eq(1)
        expect(PoolMovement.kind_sweep.count).to eq(1)
        expect(balance(groceries)).to eq(400) # $715 with the lock removed
        expect(balance(checking)).to eq(185) # -$130 with the lock removed
        expect(balance(checking)).to be >= 0 # spec §7.3
        expect(checking.total).to eq(585)
      end
    end
  end

  # The `money` column keeps an Integer for in-memory records and an empty `sum` returns the
  # Integer literal 0, so the account with nothing in it is the one that changes TYPE.
  # Asserted by type rather than by value: `eq(0)` passes happily on an Integer.
  describe "an account with nothing in it" do
    it "commits nothing and reports BigDecimal zeroes", :aggregate_failures do
      result = commit

      expect(result.success?).to be(true)
      expect(result.movements).to be_empty
      expect(result.errors).to be_empty
      expect(result.allocated).to eq(0)
      expect(result.allocated).to be_a(BigDecimal)
      expect(result.swept).to eq(0)
      expect(result.swept).to be_a(BigDecimal)
      expect(PoolMovement.count).to eq(0)
    end

    # The same guarantee on a commit that DID write, so the seeded sums above cannot pass by
    # never having a movement to add up.
    it "reports BigDecimal totals on a commit that wrote", :aggregate_failures do
      deposit(585)
      rate_envelope("Groceries", 400, funded: 85)

      result = commit

      expect(result.allocated).to eq(400)
      expect(result.allocated).to be_a(BigDecimal)
      expect(result.swept).to eq(85)
      expect(result.swept).to be_a(BigDecimal)
    end
  end
end
