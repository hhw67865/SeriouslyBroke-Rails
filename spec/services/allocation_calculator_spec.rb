# frozen_string_literal: true

require "rails_helper"

RSpec.describe AllocationCalculator, type: :model do
  # Biweekly, anchored Fri 6 Feb 2026, so the boundaries around August are Aug 7 and Aug 21.
  # Money paid in on Jul 12 belongs to the period that ended Jul 23 — closed. Money paid in on
  # Aug 15 belongs to the period ending Aug 20 — live. Same $85, same rule, and only the
  # funding date separates the two.
  let(:user) { create(:user, :biweekly) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:ally) { create(:pool, :account, user: user, name: "Ally") }

  def today = Date.new(2026, 8, 20)
  def last_period = Date.new(2026, 7, 12)
  def this_period = Date.new(2026, 8, 15)

  def envelope(trait = :budget_pool, account: checking, **attrs)
    create(:pool, trait, user: user, account: account, **attrs)
  end

  # An envelope carrying one per-paycheck rate rule, optionally already holding money.
  # Envelopes are funded out of their account, which is what makes the account's own balance
  # the buffer rather than the whole bank: `Σ pools == your bank balance`.
  def rate_envelope(name, rate, funded: nil, on: nil, **attrs)
    trait = attrs.delete(:trait) || :budget_pool
    account = attrs.fetch(:account, checking)
    pool = envelope(trait, name: name, **attrs)
    create(:pool_budget, :per_paycheck_rate, pool: pool, amount: rate)
    fund(pool, funded, on: on || last_period, from: account) if funded
    pool
  end

  def fund(pool, amount, on:, from: checking)
    create(:pool_movement, from_pool: from, to_pool: pool, amount: amount, date: on)
  end

  def deposit(amount, into: checking, on: today)
    category = create(:category, :income, user: user, pool: into)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # Memoised per account, so every reference inside one example is the SAME proposal — which
  # is how a screen holds it, and the only way `#leftover` and `#rows` can be asserted as
  # answers from one object rather than from two that happen to agree.
  def proposal(account: checking)
    (@proposals ||= {})[account.id] ||= described_class.new(user: user, account: account, today: today)
  end

  def row_for(pool, from: proposal) = from.rows.find { |row| row.pool == pool }

  # THE worked example, and the defect the plan's step 3 carried. Groceries has a $400 rate
  # rule and is holding $85 of a period that ended a month ago. $585 of income lands in
  # Checking, $85 of which is out in Groceries, so the buffer reads $500.
  describe "an envelope holding a closed period's leftover" do
    let!(:groceries) { rate_envelope("Groceries", 400, funded: 85) }

    before { deposit(585) }

    # `required` reads the LIVE balance, and the sweep is not materialised until the user
    # confirms — so at proposal time the $85 is still in the envelope and the naive ask is
    # $315. Fund that, sweep the $85 out, and Groceries starts the period at $315 against a
    # $400 rule: short by exactly its own leftover, silently, every period.
    #
    # Both figures are pinned, and they differ ($315 vs $400), so this cannot pass on a
    # fixture where the adjustment happens not to matter.
    it "asks for the rule's whole amount, not the amount less its own leftover", :aggregate_failures do
      expect(groceries.calculator(today: today).required).to eq(315)
      expect(groceries.calculator(today: today, net_of_sweep: true).required).to eq(400)
      expect(proposal.sweeps).to eq({ groceries => 85 })
      expect(proposal.total_swept).to eq(85)
    end

    # The sweep is genuinely additive: the $85 is inside the bank's $585 but not inside the
    # $500 buffer, because funding the envelope was a movement out of the account.
    #
    # `Σ pools == your bank balance` is carried by `checking.total`, which is the only figure
    # here derived from the pool RECORDS rather than from the proposal: the envelope ends at
    # 85 - 85 + 400 = $400 and the buffer at 500 + 85 - 400 = $185, and $585 was there before
    # and after. An equation written over #leftover cannot state that, because
    # `leftover ≡ available - total_allocated` makes every such line expand to
    # `available == available`. Conservation over the MATERIALISED movements is Task 3's to
    # assert, where there are real rows to sum.
    it "adds the sweep to the buffer and funds the envelope whole", :aggregate_failures do
      expect(checking.calculator(today: today).balance).to eq(500)
      expect(proposal.available).to eq(585)
      expect(row_for(groceries).needed).to eq(400)
      expect(row_for(groceries).funded).to eq(400)
      expect(proposal.total_allocated).to eq(400)
      expect(proposal.leftover).to eq(185)
      expect(checking.total).to eq(585)
    end
  end

  # The negative direction at the same shape and the same $85, funded on Aug 15 instead: the
  # money belongs to the live period, nothing sweeps, and the naive ask is now the RIGHT one.
  # Without this the group above passes against a calculator that always subtracts the balance.
  #
  # The deposit differs ($600, not $585) so the two cannot share a passing number by accident,
  # and `checking.total` is pinned beside `available` because "available is the account's
  # total" is the other wrong reading this has to exclude.
  it "sweeps nothing from an envelope funded inside the live period", :aggregate_failures do
    deposit(600)
    groceries = rate_envelope("Groceries", 400, funded: 85, on: this_period)

    expect(groceries.calculator(today: today, net_of_sweep: true).required).to eq(315)
    expect(proposal.sweeps).to be_empty
    expect(proposal.total_swept).to eq(0)
    expect(checking.total).to eq(600)
    expect(proposal.available).to eq(515)
    expect(row_for(groceries).needed).to eq(315)
    expect(proposal.leftover).to eq(200)
  end

  # A mixed envelope, where the amendment's "do not recover it arithmetically" bites. Car
  # holds $900: a $500 bill due Sep 1 and a $100/period rate rule. The bill's reserve is $500,
  # so $400 sweeps.
  describe "a mixed envelope carrying a live bill" do
    let(:car) { envelope(name: "Car") }
    let!(:rate) { create(:pool_budget, :per_paycheck_rate, pool: car, amount: 100) }
    let!(:rent) { create(:pool_budget, pool: car, amount: 500, interval_months: 1, anchor_date: Date.new(2026, 9, 1)) }

    before do
      deposit(1_000)
      fund(car, 900, on: last_period)
    end

    # Removing the swept money reorders nothing but changes who holds what: post-sweep the
    # envelope has $500, the rate rule (due at this period's end, Aug 20) still fills first
    # and takes its $100, and the bill is left holding $400 — so the bill, and only the bill,
    # asks for the $100 it is now missing. Adding the $400 sweep back onto the live `required`
    # of $0 would have asked for $400 instead.
    #
    # The bill's reserve SURVIVES the adjustment: $500 → $400, not $500 → $0. Both are pinned
    # and they differ, so this cannot pass against a calculator that zeroes the allocations
    # along with the balance.
    it "keeps the bill's reserve when it asks as if the sweep had happened", :aggregate_failures do
      live = car.calculator(today: today)
      post_sweep = car.calculator(today: today, net_of_sweep: true)

      expect(live.balance).to eq(900)
      expect(live.allocated_balances[rent]).to eq(500)
      expect(live.required).to eq(0)
      expect(post_sweep.balance).to eq(500)
      expect(post_sweep.allocated_balances[rent]).to eq(400)
      expect(post_sweep.allocated_balances[rate]).to eq(100)
      expect(post_sweep.required).to eq(100)
    end

    # Car ends at 900 - 400 + 100 = $600, which is exactly rent $500 + gas $100: the envelope
    # starts the period holding what its rules ask for, and the bank still has $1,000 in it.
    it "proposes the $100 the bill is now missing, and nothing more", :aggregate_failures do
      expect(proposal.sweeps).to eq({ car => 400 })
      expect(proposal.available).to eq(500)
      expect(row_for(car).needed).to eq(100)
      expect(row_for(car).funded).to eq(100)
      expect(proposal.leftover).to eq(400)
      expect(checking.total).to eq(1_000)
    end
  end

  # Plan decision 2, and the trap most likely to bite: a dateless goal IS a rate rule on a
  # savings pool, so eligibility written as "has a rate rule whose period ended" empties every
  # goal the user has. Vacation's $600 sits in a period that closed a month ago and its
  # `free_amount` is $450 — the number a naive sweep reaches for — and none of it moves.
  #
  # Asserted beside an envelope that DOES sweep, so it cannot pass against a proposal that
  # simply never sweeps anything. And Vacation still gets a ROW: never swept is not the same
  # as never funded, and a goal that quietly stopped being funded is the other way to break it.
  it "never sweeps a savings goal, and still funds it", :aggregate_failures do
    deposit(2_000)
    vacation = rate_envelope("Vacation", 150, trait: :savings_pool, target_amount: 2_400, funded: 600)
    groceries = rate_envelope("Groceries", 400, funded: 85)

    expect(vacation.calculator(today: today).free_amount).to eq(450)
    expect(vacation.calculator(today: today, net_of_sweep: true).balance).to eq(600)
    expect(proposal.sweeps).to eq({ groceries => 85 })
    expect(row_for(vacation).needed).to eq(150)
    expect(row_for(vacation).funded).to eq(150)
    expect(row_for(groceries).needed).to eq(400)
    expect(proposal.leftover).to eq(850)
  end

  # One account per proposal (spec §5 drops cross-account transfers), asserted from BOTH sides
  # so it cannot pass against a proposal that simply misses the second account's pools. Ally's
  # $910 buffer and its envelope's $90 leftover are invisible to Checking's proposal, and
  # Checking's $500 and $85 are invisible to Ally's.
  describe "two accounts" do
    before do
      deposit(585)
      deposit(1_000, into: ally)
    end

    it "sweeps and funds only the account it was built for", :aggregate_failures do
      groceries = rate_envelope("Groceries", 400, funded: 85)
      holiday = rate_envelope("Holiday", 700, account: ally, funded: 90)

      expect(proposal.sweeps).to eq({ groceries => 85 })
      expect(proposal.available).to eq(585)
      expect(proposal.rows.map(&:pool)).to eq([groceries])
      expect(proposal(account: ally).sweeps).to eq({ holiday => 90 })
      expect(proposal(account: ally).available).to eq(1_000)
      expect(proposal(account: ally).rows.map(&:pool)).to eq([holiday])
      expect(row_for(holiday, from: proposal(account: ally)).needed).to eq(700)
    end
  end

  # A NEGATIVE OVERRIDE, which is bad input the screen deliberately carries through so it fails
  # PoolMovement's `amount > 0` loudly rather than vanishing from a split it was meant to change
  # (see #row_for). What it must NOT do on the way there is inflate the money the screen says is
  # left: `Σ funded` counts the -$50 and reports the buffer $50 higher than the account holds,
  # and the buffer line is the one figure here that must never overstate.
  #
  # Both directions on one fixture: Groceries takes its $200 and the account is left with the
  # $100 it actually has, not the $150 a raw sum reports. The row keeps the negative, because the
  # commit has to see it.
  describe "a negative override" do
    let!(:groceries) { rate_envelope("Groceries", 200, priority: 1) }
    let!(:water) { rate_envelope("Water", 300, priority: 2) }

    before { deposit(300) }

    def overridden(amount)
      described_class.new(user: user, account: checking, today: today, overrides: { water.id => amount })
    end

    it "keeps it on the row but never counts it as money leaving", :aggregate_failures do
      expect(row_for(water, from: overridden(-50)).funded).to eq(-50)
      expect(row_for(groceries, from: overridden(-50)).funded).to eq(200)
      expect(overridden(-50).total_allocated).to eq(200)
      expect(overridden(-50).leftover).to eq(100) # $150 if the -$50 were summed in
    end

    # The paired positive, same fixture with the sign flipped, so "never counts it" cannot pass
    # on a #total_allocated that has stopped counting anything.
    it "counts a positive override in full", :aggregate_failures do
      expect(overridden(50).total_allocated).to eq(250)
      expect(overridden(50).leftover).to eq(50)
    end
  end

  describe "the fill" do
    # `[priority, name]`, and the tie-break is the half that goes wrong quietly. Both pools sit
    # at priority 1, Zebra is created FIRST and carries the LOWER uuid, so insertion order and
    # id order both say [Zebra, Apple] while the rule says [Apple, Zebra]. The ids are pinned
    # rather than left to `gen_random_uuid()` precisely so a database-ordered read cannot agree
    # with the rule by luck.
    #
    # The pot is $300 against $400 of asks, so the order decides who gets short-changed: this
    # is asserted in MONEY, not only in row order, because a proposal that sorts its rows for
    # display and fills them in another order is the defect that actually costs the user.
    it "breaks a priority tie by name, not by id or insertion order", :aggregate_failures do
      deposit(300)
      zebra = rate_envelope("Zebra", 200, priority: 1, id: "00000000-0000-4000-8000-000000000001")
      apple = rate_envelope("Apple", 200, priority: 1, id: "ffffffff-ffff-4fff-8fff-ffffffffffff")

      expect(proposal.rows.map(&:pool)).to eq([apple, zebra])
      expect(row_for(apple).funded).to eq(200)
      expect(row_for(zebra).funded).to eq(100)
      expect(row_for(zebra).short).to eq(100)
      expect(proposal.leftover).to eq(0)
    end

    # The other half of the same key, and deliberately the OPPOSITE order over the same two
    # names: priority wins, so Zebra at 1 is filled before Apple at 5. Neither example can pass
    # under a single wrong rule — sort by name alone and this one fails, sort by priority alone
    # and the tie-break above fails.
    it "fills by priority before name", :aggregate_failures do
      deposit(300)
      apple = rate_envelope("Apple", 200, priority: 5)
      zebra = rate_envelope("Zebra", 200, priority: 1)

      expect(proposal.rows.map(&:pool)).to eq([zebra, apple])
      expect(row_for(zebra).funded).to eq(200)
      expect(row_for(apple).funded).to eq(100)
    end

    # Matching Home's waterfall: a pool that asks for nothing is not part of the story of where
    # the money goes, and a "$0.00 of $0.00" row below the point the money ran out reads as
    # money DENIED rather than money not wanted. Gas's ask is pinned at zero first, so this
    # cannot pass by dropping a row that genuinely wanted something.
    it "leaves an envelope that asks for nothing out of the rows", :aggregate_failures do
      deposit(1_000)
      gas = rate_envelope("Gas", 200, funded: 200, on: this_period)
      water = rate_envelope("Water", 300)

      expect(gas.calculator(today: today, net_of_sweep: true).required).to eq(0)
      expect(proposal.rows.map(&:pool)).to eq([water])
      expect(proposal.available).to eq(800)
      expect(proposal.total_allocated).to eq(300)
      expect(proposal.leftover).to eq(500)
      expect(proposal.short?).to be(false)
    end

    it "reports every envelope funded in full as not short", :aggregate_failures do
      deposit(1_000)
      rate_envelope("Gas", 200)
      rate_envelope("Water", 300)

      expect(proposal.rows.map(&:funded)).to eq([200, 300])
      expect(proposal.rows.map(&:short)).to eq([0, 0])
      expect(proposal.short?).to be(false)
      expect(proposal.leftover).to eq(500)
    end

    # The opposite state at the same two envelopes: $350 against $500 of asks. `short?` has to
    # agree with the rows it is derived from — Gas is filled, Water takes the whole gap.
    it "reports an envelope the money did not reach as short", :aggregate_failures do
      deposit(350)
      rate_envelope("Gas", 200)
      rate_envelope("Water", 300)

      expect(proposal.rows.map(&:funded)).to eq([200, 150])
      expect(proposal.rows.map(&:short)).to eq([0, 150])
      expect(proposal.short?).to be(true)
      expect(proposal.total_allocated).to eq(350)
      expect(proposal.leftover).to eq(0)
    end

    # A rule with a negative amount is invalid input, but this is a READ path and one bad row
    # must not be able to turn the distribution screen into a 500. Measured before the guard
    # existed: PoolCalculator#goal_required returns `[rate, remaining].min`, so this goal asks
    # for -$150 and `clamp(0.to_d, -150)` raised ArgumentError out of #rows.
    #
    # `update_column` writes past the validation deliberately — the shape this defends against
    # is a row that reached the table some other way, which is exactly what a validation cannot
    # promise. The healthy envelope beside it is funded in the same example, so the guard
    # cannot pass by the proposal collapsing to nothing.
    it "survives a rule whose amount is negative", :aggregate_failures do
      deposit(1_000)
      vacation = rate_envelope("Vacation", 150, trait: :savings_pool, target_amount: 2_400)
      vacation.budgets.first.update_column(:amount, -150) # rubocop:disable Rails/SkipsModelValidations
      gas = rate_envelope("Gas", 200)

      expect(vacation.calculator(today: today).required).to eq(-150)
      expect(proposal.rows.map(&:pool)).to eq([gas])
      expect(row_for(gas).funded).to eq(200)
      expect(proposal.leftover).to eq(800)
      expect(proposal.short?).to be(false)
    end

    # An overdrawn account has less than nothing to hand out. `available` is NOT clamped at
    # zero: the overdraft is a fact the distribution screen has to state, and clamping would
    # report "nothing left" for an account that is $200 in the hole. Nothing is funded, which
    # is what the per-row clamp is for.
    it "funds nothing from an overdrawn account and says so in the leftover", :aggregate_failures do
      deposit(100)
      gas = rate_envelope("Gas", 400, funded: 300, on: this_period)

      expect(checking.calculator(today: today).balance).to eq(-200)
      expect(proposal.available).to eq(-200)
      expect(row_for(gas).needed).to eq(100)
      expect(row_for(gas).funded).to eq(0)
      expect(row_for(gas).funded).to be_a(BigDecimal)
      expect(proposal.short?).to be(true)
      expect(proposal.leftover).to eq(-200)
      expect(proposal.leftover).to be_a(BigDecimal)
    end
  end

  # The `money` column keeps an Integer for in-memory records and an empty `sum(:amount)`
  # returns the Integer literal 0, so the emptiest account is the one that changes TYPE.
  # Asserted by type rather than by value: `eq(0)` passes happily on an Integer.
  describe "money types on an account with nothing in it" do
    it "reports BigDecimal zeroes throughout", :aggregate_failures do
      expect(proposal.sweeps).to eq({})
      expect(proposal.total_swept).to be_a(BigDecimal)
      expect(proposal.available).to eq(0)
      expect(proposal.available).to be_a(BigDecimal)
      expect(proposal.rows).to be_empty
      expect(proposal.total_allocated).to eq(0)
      expect(proposal.total_allocated).to be_a(BigDecimal)
      expect(proposal.leftover).to eq(0)
      expect(proposal.leftover).to be_a(BigDecimal)
      expect(proposal.short?).to be(false)
    end

    # The same guarantee one row down: an envelope asking for something out of an empty account
    # produces a funded figure that came from the clamp's low bound, which is the one place a
    # bare `0` would leak into a row.
    it "reports BigDecimal figures on a row nothing could fund", :aggregate_failures do
      gas = rate_envelope("Gas", 200)

      expect(row_for(gas).needed).to be_a(BigDecimal)
      expect(row_for(gas).funded).to eq(0)
      expect(row_for(gas).funded).to be_a(BigDecimal)
      expect(row_for(gas).short).to be_a(BigDecimal)
    end
  end
end
