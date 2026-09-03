# frozen_string_literal: true

require "rails_helper"

# THE PORT OF THE POOL-ERA WATERFALL, FIGURE FOR FIGURE (two-ledger Task 4). Every example that
# pinned a number keeps the number: a category is funded by an allocation out of AVAILABLE where an
# envelope was funded by a movement out of its ACCOUNT, and the two are the same arithmetic with the
# root renamed — `available = income − unfunded spending − Σ allocations out + Σ back in` is exactly
# what `account.balance` was for a user whose money all sat in one account.
#
# WHAT COULD NOT COME ACROSS, and it is one whole group:
#   * "two accounts" — the per-account fill. The purpose ledger has ONE root (spec §2), so there is
#     one distribution per period per user and no second proposal to be built for a second account.
#     Its statement ("sweeps and funds only the account it was built for") is not a weaker claim
#     under the new model, it is a claim about a thing that no longer exists. The order examples
#     below are what still say which categories a proposal covers.
RSpec.describe AllocationCalculator, type: :model do
  # Biweekly, anchored Fri 6 Feb 2026, so the boundaries around August are Aug 7 and Aug 21.
  # Money allocated on Jul 12 belongs to the period that ended Jul 23 — closed. Money allocated on
  # Aug 15 belongs to the period ending Aug 20 — live. Same $85, same rule, and only the funding
  # date separates the two.
  let(:user) { create(:user, :biweekly) }

  # THE POT STILL EXISTS, and it is here for one reason that has nothing to do with the waterfall:
  # income has to land in a category, and `Category#income_must_land_in_an_account` says that
  # category may only point at the user's main account. The `:account` trait claims the role. No
  # figure below is read off it — the physical ledger is `AccountLedger`'s business now.
  # rubocop:disable RSpec/LetSetup -- THE POT HAS TO EXIST, and nothing here reads it: income
  # lands in a category and `Category#income_must_land_in_an_account` says that category may
  # only point at the user's MAIN account, so a user with no account cannot be paid at all. It
  # is setup for the physical side of a fixture whose every assertion is on the purpose side.
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  # rubocop:enable RSpec/LetSetup

  def today = Date.new(2026, 8, 20)
  def last_period = Date.new(2026, 7, 12)
  def this_period = Date.new(2026, 8, 15)

  # EVERY RULE HERE BELONGS TO A CATEGORY, which is the only owner a rule has — said once here
  # rather than on every line.
  # ** A CATEGORY MAY CARRY ONLY ONE ITEM-LESS RULE (`Budget#category_may_hold_one_item_less_rule`,
  # computed-claims ruling of 2026-09-03): two rules whose lane is the whole category would each
  # subtract the same spending. ** So the SECOND catch-all rule this file plants on a category is
  # given an item of its own, and only then — every single-rule fixture below is untouched, and the
  # item is plumbing rather than a change of subject, since these examples are about the waterfall's
  # order and the sweep's partiality and never about item-lessness.
  def rule(category, *traits, **attrs)
    attrs = attrs.merge(item: fresh_item(category)) if second_catch_all?(category, attrs)
    create(:budget, *traits, category: category, **attrs)
  end

  def second_catch_all?(category, attrs)
    attrs[:item].nil? && attrs[:item_id].nil? && Budget.exists?(category_id: category.id, item_id: nil)
  end

  def fresh_item(category)
    create(:item, category: category, name: "Lane #{Budget.where(category_id: category.id).count}")
  end

  def holder(name, **attrs)
    create(:category, :expense, :funded, user: user, name: name, **attrs)
  end

  # A category carrying one per-period rate rule, optionally already holding money. Categories are
  # funded by an allocation out of AVAILABLE, which is what makes available the root the waterfall
  # hands out from: `available + Σ holdings == income − expenses`.
  def rate_category(name, rate, funded: nil, on: nil, **attrs)
    category = holder(name, **attrs)
    rule(category, :per_period_rate, amount: rate)
    fund(category, funded, on: on || last_period) if funded
    category
  end

  def fund(category, amount, on:)
    create(:allocation, to_category: category, amount: amount, date: on)
  end

  def deposit(amount, on: today)
    category = create(:category, :income, user: user)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # Memoised, so every reference inside one example is the SAME proposal — which is how a screen
  # holds it, and the only way `#leftover` and `#rows` can be asserted as answers from one object
  # rather than from two that happen to agree.
  def proposal = @proposal ||= described_class.new(user: user, today: today)

  def row_for(category, from: proposal) = from.rows.find { |row| row.category == category }

  # AVAILABLE AS THE LEDGER READS IT, from a FRESH ledger each time: a ledger is a snapshot, and
  # this is asked on both sides of fixture writes.
  def available_now = CategoryLedger.new(user.categories.expenses.to_a, user: user).available

  # THE PURPOSE PARTITION (§2), which is what `checking.total == Σ pools` was on the physical side:
  # available plus every holding must equal what came into the user's life less what left it. It is
  # read off the LEDGER rather than off the proposal, so no line below is the proposal restated.
  def purpose_total
    categories = user.categories.expenses.to_a
    ledger = CategoryLedger.new(categories, user: user)

    ledger.available + categories.sum(0.to_d) { |category| ledger.holding_of(category) }
  end

  # THE worked example, and the defect the plan's step 3 carried. Groceries has a $400 rate rule
  # and is holding $85 of a period that ended a month ago. $585 of income arrives, $85 of which is
  # out in Groceries, so available reads $500.
  describe "a category holding a closed period's leftover" do
    let!(:groceries) { rate_category("Groceries", 400, funded: 85) }

    before { deposit(585) }

    # `required` reads the LIVE balance, and the sweep is not materialised until the user confirms
    # — so at proposal time the $85 is still in the category and the naive ask is $315. Fund that,
    # sweep the $85 out, and Groceries starts the period at $315 against a $400 rule: short by
    # exactly its own leftover, silently, every period.
    #
    # Both figures are pinned, and they differ ($315 vs $400), so this cannot pass on a fixture
    # where the adjustment happens not to matter.
    it "asks for the rule's whole amount, not the amount less its own leftover", :aggregate_failures do
      expect(groceries.holding_calculator(today: today).required).to eq(315)
      expect(groceries.holding_calculator(today: today, net_of_sweep: true).required).to eq(400)
      expect(proposal.sweeps).to eq({ groceries => 85 })
      expect(proposal.total_swept).to eq(85)
    end

    # The sweep is genuinely additive: the $85 is inside the $585 that came in but not inside the
    # $500 available, because funding the category was an allocation OUT of available.
    #
    # `available + Σ holdings == income − expenses` is carried by `purpose_total`, which is the only
    # figure here derived from the LEDGER rather than from the proposal: the category ends at
    # 85 − 85 + 400 = $400 and available at 500 + 85 − 400 = $185, and $585 came in before and
    # after. An equation written over #leftover cannot state that, because
    # `leftover ≡ available - total_allocated` makes every such line expand to
    # `available == available`. Conservation over the MATERIALISED allocations is the committer's
    # to assert, where there are real rows to sum.
    it "adds the sweep to available and funds the category whole", :aggregate_failures do
      expect(available_now).to eq(500)
      expect(proposal.available).to eq(585)
      expect(row_for(groceries).needed).to eq(400)
      expect(row_for(groceries).funded).to eq(400)
      expect(proposal.total_allocated).to eq(400)
      expect(proposal.leftover).to eq(185)
      expect(purpose_total).to eq(585)
    end
  end

  # The negative direction at the same shape and the same $85, funded on Aug 15 instead: the money
  # belongs to the live period, nothing sweeps, and the naive ask is now the RIGHT one. Without this
  # the group above passes against a calculator that always subtracts the balance.
  #
  # The deposit differs ($600, not $585) so the two cannot share a passing number by accident, and
  # `purpose_total` is pinned beside `available` because "available is everything that came in" is
  # the other wrong reading this has to exclude.
  it "sweeps nothing from a category funded inside the live period", :aggregate_failures do
    deposit(600)
    groceries = rate_category("Groceries", 400, funded: 85, on: this_period)

    expect(groceries.holding_calculator(today: today, net_of_sweep: true).required).to eq(315)
    expect(proposal.sweeps).to be_empty
    expect(proposal.total_swept).to eq(0)
    expect(purpose_total).to eq(600)
    expect(proposal.available).to eq(515)
    expect(row_for(groceries).needed).to eq(315)
    expect(proposal.leftover).to eq(200)
  end

  # A mixed category, where the amendment's "do not recover it arithmetically" bites. Car holds
  # $900: a $500 bill due Sep 1 and a $100/period rate rule. The bill's reserve is $500, so $400
  # sweeps.
  describe "a mixed category carrying a live bill" do
    let(:car) { holder("Car") }
    let!(:rate) { rule(car, :per_period_rate, amount: 100) }
    let!(:rent) { rule(car, amount: 500, interval_months: 1, anchor_date: Date.new(2026, 9, 1)) }

    before do
      deposit(1_000)
      fund(car, 900, on: last_period)
    end

    # Removing the swept money reorders nothing but changes who holds what: post-sweep the category
    # has $500, the rate rule (due at this period's end, Aug 20) still fills first and takes its
    # $100, and the bill is left holding $400 — so the bill, and only the bill, asks for the $100 it
    # is now missing. Adding the $400 sweep back onto the live `required` of $0 would have asked for
    # $400 instead.
    #
    # The bill's reserve SURVIVES the adjustment: $500 → $400, not $500 → $0. Both are pinned and
    # they differ, so this cannot pass against a calculator that zeroes the allocations along with
    # the balance.
    it "keeps the bill's reserve when it asks as if the sweep had happened", :aggregate_failures do
      live = car.holding_calculator(today: today)
      post_sweep = car.holding_calculator(today: today, net_of_sweep: true)

      expect(live.balance).to eq(900)
      expect(live.allocated_balances[rent]).to eq(500)
      expect(live.required).to eq(0)
      expect(post_sweep.balance).to eq(500)
      expect(post_sweep.allocated_balances[rent]).to eq(400)
      expect(post_sweep.allocated_balances[rate]).to eq(100)
      expect(post_sweep.required).to eq(100)
    end

    # Car ends at 900 - 400 + 100 = $600, which is exactly rent $500 + gas $100: the category starts
    # the period holding what its rules ask for, and $1,000 is still all there is.
    it "proposes the $100 the bill is now missing, and nothing more", :aggregate_failures do
      expect(proposal.sweeps).to eq({ car => 400 })
      expect(proposal.available).to eq(500)
      expect(row_for(car).needed).to eq(100)
      expect(row_for(car).funded).to eq(100)
      expect(proposal.leftover).to eq(400)
      expect(purpose_total).to eq(1_000)
    end
  end

  # Plan decision 2 as Task 3 re-anchored it: a dateless goal IS a rate rule on a category with a
  # TARGET, so eligibility written as "has a rate rule whose period ended" empties every goal the
  # user has. Vacation's $600 sits in a period that closed a month ago and its `free_amount` is
  # $450 — the number a naive sweep reaches for — and none of it moves.
  #
  # Asserted beside a category that DOES sweep, so it cannot pass against a proposal that simply
  # never sweeps anything. And Vacation still gets a ROW: never swept is not the same as never
  # funded, and a goal that quietly stopped being funded is the other way to break it.
  it "never sweeps a savings goal, and still funds it", :aggregate_failures do
    deposit(2_000)
    vacation = rate_category("Vacation", 150, target_amount: 2_400, funded: 600)
    groceries = rate_category("Groceries", 400, funded: 85)

    expect(vacation.holding_calculator(today: today).free_amount).to eq(450)
    expect(vacation.holding_calculator(today: today, net_of_sweep: true).balance).to eq(600)
    expect(proposal.sweeps).to eq({ groceries => 85 })
    expect(row_for(vacation).needed).to eq(150)
    expect(row_for(vacation).funded).to eq(150)
    expect(row_for(groceries).needed).to eq(400)
    expect(proposal.leftover).to eq(850)
  end

  # A NEGATIVE OVERRIDE, which is bad input the screen deliberately carries through so it fails
  # `Allocation`'s `amount > 0` loudly rather than vanishing from a split it was meant to change
  # (see #row_for). What it must NOT do on the way there is inflate the money the screen says is
  # left: `Σ funded` counts the -$50 and reports available $50 higher than it is, and the
  # available line is the one figure here that must never overstate.
  #
  # Both directions on one fixture: Groceries takes its $200 and $100 is left, not the $150 a raw
  # sum reports. The row keeps the negative, because the commit has to see it.
  describe "a negative override" do
    let!(:groceries) { rate_category("Groceries", 200, priority: 1) }
    let!(:water) { rate_category("Water", 300, priority: 2) }

    before { deposit(300) }

    def overridden(amount)
      described_class.new(user: user, today: today, overrides: { water.id => amount })
    end

    it "keeps it on the row but never counts it as money leaving", :aggregate_failures do
      expect(row_for(water, from: overridden(-50)).funded).to eq(-50)
      expect(row_for(groceries, from: overridden(-50)).funded).to eq(200)
      expect(overridden(-50).total_allocated).to eq(200)
      expect(overridden(-50).leftover).to eq(100) # $150 if the -$50 were summed in
    end

    # The paired positive, same fixture with the sign flipped, so "never counts it" cannot pass on a
    # #total_allocated that has stopped counting anything.
    it "counts a positive override in full", :aggregate_failures do
      expect(overridden(50).total_allocated).to eq(250)
      expect(overridden(50).leftover).to eq(50)
    end
  end

  describe "the fill" do
    # `[priority, name]`, and the tie-break is the half that goes wrong quietly. Both categories sit
    # at priority 1, Zebra is created FIRST and carries the LOWER uuid, so insertion order and id
    # order both say [Zebra, Apple] while the rule says [Apple, Zebra]. The ids are pinned rather
    # than left to `gen_random_uuid()` precisely so a database-ordered read cannot agree with the
    # rule by luck.
    #
    # Available is $300 against $400 of asks, so the order decides who gets short-changed: this is
    # asserted in MONEY, not only in row order, because a proposal that sorts its rows for display
    # and fills them in another order is the defect that actually costs the user.
    it "breaks a priority tie by name, not by id or insertion order", :aggregate_failures do
      deposit(300)
      zebra = rate_category("Zebra", 200, priority: 1, id: "00000000-0000-4000-8000-000000000001")
      apple = rate_category("Apple", 200, priority: 1, id: "ffffffff-ffff-4fff-8fff-ffffffffffff")

      expect(proposal.rows.map(&:category)).to eq([apple, zebra])
      expect(row_for(apple).funded).to eq(200)
      expect(row_for(zebra).funded).to eq(100)
      expect(row_for(zebra).short).to eq(100)
      expect(proposal.leftover).to eq(0)
    end

    # The other half of the same key, and deliberately the OPPOSITE order over the same two names:
    # priority wins, so Zebra at 1 is filled before Apple at 5. Neither example can pass under a
    # single wrong rule — sort by name alone and this one fails, sort by priority alone and the
    # tie-break above fails.
    it "fills by priority before name", :aggregate_failures do
      deposit(300)
      apple = rate_category("Apple", 200, priority: 5)
      zebra = rate_category("Zebra", 200, priority: 1)

      expect(proposal.rows.map(&:category)).to eq([zebra, apple])
      expect(row_for(zebra).funded).to eq(200)
      expect(row_for(apple).funded).to eq(100)
    end

    # A CATEGORY THAT HAS NEVER HELD MONEY IS NOT IN THE WATERFALL, whatever rules it carries.
    # `funded_since` is what makes a category a holder (§4): its own spending drains AVAILABLE, so
    # allocating to it would put money somewhere nothing takes it out of. This replaces the pool
    # era's "an envelope with no account" — the same fact about the other model's own root.
    #
    # Water is beside it and funded in the same example, so the exclusion cannot pass by the
    # proposal collapsing to nothing.
    it "leaves a category that has never been funded out of the rows", :aggregate_failures do
      deposit(1_000)
      never = create(:category, :expense, user: user, name: "Never Funded")
      rule(never, :per_period_rate, amount: 400)
      water = rate_category("Water", 300)

      expect(never.holder?).to be(false)
      expect(proposal.rows.map(&:category)).to eq([water])
      expect(proposal.total_allocated).to eq(300)
      expect(proposal.leftover).to eq(700)
    end

    # Matching Home's waterfall: a category that asks for nothing is not part of the story of where
    # the money goes, and a "$0.00 of $0.00" row below the point the money ran out reads as money
    # DENIED rather than money not wanted. Gas's ask is pinned at zero first, so this cannot pass by
    # dropping a row that genuinely wanted something.
    it "leaves a category that asks for nothing out of the rows", :aggregate_failures do
      deposit(1_000)
      gas = rate_category("Gas", 200, funded: 200, on: this_period)
      water = rate_category("Water", 300)

      expect(gas.holding_calculator(today: today, net_of_sweep: true).required).to eq(0)
      expect(proposal.rows.map(&:category)).to eq([water])
      expect(proposal.available).to eq(800)
      expect(proposal.total_allocated).to eq(300)
      expect(proposal.leftover).to eq(500)
      expect(proposal.short?).to be(false)
    end

    it "reports every category funded in full as not short", :aggregate_failures do
      deposit(1_000)
      rate_category("Gas", 200)
      rate_category("Water", 300)

      expect(proposal.rows.map(&:funded)).to eq([200, 300])
      expect(proposal.rows.map(&:short)).to eq([0, 0])
      expect(proposal.short?).to be(false)
      expect(proposal.leftover).to eq(500)
    end

    # The opposite state at the same two categories: $350 against $500 of asks. `short?` has to
    # agree with the rows it is derived from — Gas is filled, Water takes the whole gap.
    it "reports a category the money did not reach as short", :aggregate_failures do
      deposit(350)
      rate_category("Gas", 200)
      rate_category("Water", 300)

      expect(proposal.rows.map(&:funded)).to eq([200, 150])
      expect(proposal.rows.map(&:short)).to eq([0, 150])
      expect(proposal.short?).to be(true)
      expect(proposal.total_allocated).to eq(350)
      expect(proposal.leftover).to eq(0)
    end

    # A rule with a negative amount is invalid input, but this is a READ path and one bad row must
    # not be able to turn the distribution screen into a 500. Measured before the guard existed:
    # #goal_required returns `[rate, remaining].min`, so this goal asks for -$150 and
    # `clamp(0.to_d, -150)` raised ArgumentError out of #rows.
    #
    # `update_column` writes past the validation deliberately — the shape this defends against is a
    # row that reached the table some other way, which is exactly what a validation cannot promise.
    # The healthy category beside it is funded in the same example, so the guard cannot pass by the
    # proposal collapsing to nothing.
    it "survives a rule whose amount is negative", :aggregate_failures do
      deposit(1_000)
      vacation = rate_category("Vacation", 150, target_amount: 2_400)
      vacation.budgets.first.update_column(:amount, -150) # rubocop:disable Rails/SkipsModelValidations
      gas = rate_category("Gas", 200)

      expect(vacation.holding_calculator(today: today).required).to eq(-150)
      expect(proposal.rows.map(&:category)).to eq([gas])
      expect(row_for(gas).funded).to eq(200)
      expect(proposal.leftover).to eq(800)
      expect(proposal.short?).to be(false)
    end

    # A user who has allocated out more than came in has less than nothing to hand out. `available`
    # is NOT clamped at zero: the overdraft is a fact the distribution screen has to state, and
    # clamping would report "nothing left" for a root that is $200 in the hole. Nothing is funded,
    # which is what the per-row clamp is for.
    it "funds nothing out of a negative available and says so in the leftover", :aggregate_failures do
      deposit(100)
      gas = rate_category("Gas", 400, funded: 300, on: this_period)

      expect(available_now).to eq(-200)
      expect(proposal.available).to eq(-200)
      expect(row_for(gas).needed).to eq(100)
      expect(row_for(gas).funded).to eq(0)
      expect(row_for(gas).funded).to be_a(BigDecimal)
      expect(proposal.short?).to be(true)
      expect(proposal.leftover).to eq(-200)
      expect(proposal.leftover).to be_a(BigDecimal)
    end
  end

  # The `money` column keeps an Integer for in-memory records and an empty `sum(:amount)` returns
  # the Integer literal 0, so the user with nothing at all is the one that changes TYPE. Asserted by
  # type rather than by value: `eq(0)` passes happily on an Integer.
  describe "money types on a user with nothing in it" do
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

    # The same guarantee one row down: a category asking for something out of an empty root produces
    # a funded figure that came from the clamp's low bound, which is the one place a bare `0` would
    # leak into a row.
    it "reports BigDecimal figures on a row nothing could fund", :aggregate_failures do
      gas = rate_category("Gas", 200)

      expect(row_for(gas).needed).to be_a(BigDecimal)
      expect(row_for(gas).funded).to eq(0)
      expect(row_for(gas).funded).to be_a(BigDecimal)
      expect(row_for(gas).short).to be_a(BigDecimal)
    end
  end
end
