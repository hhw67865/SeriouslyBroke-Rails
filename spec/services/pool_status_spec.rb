# frozen_string_literal: true

require "rails_helper"

RSpec.describe PoolStatus, type: :model do
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6)) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:today) { Date.new(2026, 2, 6) }

  def envelope(name)
    create(:pool, :budget_pool, user: user, account: checking, name: name)
  end

  def fund(pool, amount)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: amount)
  end

  def goal(name, target: 2_400)
    create(:pool, :savings_pool, user: user, account: checking, name: name, target_amount: target)
  end

  def spend(pool, amount, name: "Something")
    category = create(:category, :expense, user: user, name: "#{pool.name} spend", pool: pool)
    create(:entry, item: create(:item, category: category, name: name), amount: amount, date: today)
  end

  # An item is the only fulfillment signal BudgetCalculator#overdue? accepts, so
  # every example that needs an overdue rule has to route through here.
  def bill_rule(pool, name, amount:, anchor_date:)
    # Named per item, not per pool: category names are unique per user, and a pool with two
    # bills in it calls this twice.
    category = create(:category, :expense, user: user, name: "#{pool.name} #{name}", pool: pool)
    item = create(:item, category: category, name: name)
    create(:pool_budget, pool: pool, amount: amount, interval_months: 6, anchor_date: anchor_date, item: item)
  end

  describe "precedence" do
    it "reports overdrawn ahead of everything else", :aggregate_failures do
      pool = envelope("Car")
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(pool, 100)
      spend(pool, 150)

      status = pool.status(today: today)

      expect(status.state).to eq(:overdrawn)
      expect(status.amount).to eq(50)
    end

    it "reports overdue ahead of behind", :aggregate_failures do
      pool = envelope("Insurance")
      bill_rule(pool, "Insurance", amount: 600, anchor_date: Date.new(2026, 2, 1))
      fund(pool, 600)

      status = pool.status(today: Date.new(2026, 2, 6))

      expect(status.state).to eq(:overdue)
      expect(status.due_on).to eq(Date.new(2026, 2, 1))
    end

    # Each of the three examples below pins ONE adjacent pair of the chain by
    # building a pool that genuinely satisfies both conditions. Without them a
    # swap of that pair changes no result and the ordering is asserted by nothing.

    # overdrawn vs overdue: the pool is $50 in the red AND holds a bill whose
    # date passed unpaid.
    it "reports overdrawn ahead of overdue", :aggregate_failures do
      pool = envelope("Phone")
      bill_rule(pool, "Phone", amount: 600, anchor_date: Date.new(2026, 2, 1))
      fund(pool, 100)
      spend(pool, 150)

      status = pool.status(today: today)

      expect(status.state).to eq(:overdrawn)
      expect(status.amount).to eq(50)
    end

    # overdue vs wont_make_it: the rule's date passed unpaid AND it is $500 short
    # with no boundary left before that date, so both conditions hold.
    it "reports overdue ahead of wont_make_it", :aggregate_failures do
      pool = envelope("Water")
      bill_rule(pool, "Water", amount: 600, anchor_date: Date.new(2026, 2, 1))
      fund(pool, 100)

      status = pool.status(today: today)

      expect(status.state).to eq(:overdue)
      expect(status.due_on).to eq(Date.new(2026, 2, 1))
    end

    it "reports what is still unpaid on the overdue rule, not its face value", :aggregate_failures do
      pool = envelope("Water")
      rule = bill_rule(pool, "Water", amount: 600, anchor_date: Date.new(2026, 2, 1))
      fund(pool, 600)
      create(:entry, item: rule.item, amount: 400, date: Date.new(2026, 2, 2))

      status = pool.status(today: today)

      expect(status.state).to eq(:overdue)
      expect(status.amount).to eq(200)
    end

    # Two overdue rules, created LATEST-DUE-FIRST so insertion order and due-date order
    # disagree. `has_many :budgets` carries no ORDER BY, so without a deterministic sort
    # this pool reads $200 · Feb 3 or $600 · Feb 1 at random between page loads.
    it "names the earliest of several overdue rules", :aggregate_failures do
      pool = envelope("Utilities")
      bill_rule(pool, "Electric", amount: 200, anchor_date: Date.new(2026, 2, 3))
      bill_rule(pool, "Water", amount: 600, anchor_date: Date.new(2026, 2, 1))
      fund(pool, 800)

      status = pool.status(today: today)

      expect(status.state).to eq(:overdue)
      expect(status.due_on).to eq(Date.new(2026, 2, 1))
      expect(status.amount).to eq(600)
    end

    # Same due date, so the date cannot break the tie. Created smallest-first, so insertion
    # order and the intended order disagree: the larger obligation is the one to name.
    it "breaks a tie between two overdue rules toward the larger", :aggregate_failures do
      pool = envelope("Levies")
      bill_rule(pool, "Small", amount: 200, anchor_date: Date.new(2026, 2, 1))
      bill_rule(pool, "Large", amount: 600, anchor_date: Date.new(2026, 2, 1))
      fund(pool, 800)

      status = pool.status(today: today)

      expect(status.state).to eq(:overdue)
      expect(status.amount).to eq(600)
    end

    # The two below are the multi-cycle cases. #paid_since_anchor is cumulative across
    # every cycle since the anchor while the rule's amount is one cycle's worth, so a
    # bare `amount - paid` only holds while nothing has rolled. Cycle 1 is paid in full
    # in both, which is the ordinary state of a recurring bill, not an edge case.
    it "reports the whole amount when a rolled cycle is wholly unpaid", :aggregate_failures do
      pool = envelope("Insurance")
      rule = bill_rule(pool, "Insurance", amount: 600, anchor_date: Date.new(2025, 8, 1))
      fund(pool, 1200)
      create(:entry, item: rule.item, amount: 600, date: Date.new(2025, 8, 2)) # cycle 1, settled

      status = pool.status(today: today)

      expect(status.state).to eq(:overdue)
      expect(status.amount).to eq(600)
    end

    it "reports only the remainder when a rolled cycle is partly paid", :aggregate_failures do
      pool = envelope("Insurance")
      rule = bill_rule(pool, "Insurance", amount: 600, anchor_date: Date.new(2025, 8, 1))
      fund(pool, 1200)
      create(:entry, item: rule.item, amount: 600, date: Date.new(2025, 8, 2)) # cycle 1, settled
      create(:entry, item: rule.item, amount: 250, date: Date.new(2026, 2, 2)) # cycle 2, part paid

      status = pool.status(today: today)

      # Owed through cycle 2 is 600 * 2 = 1200; 850 has been paid.
      expect(status.state).to eq(:overdue)
      expect(status.amount).to eq(350)
    end

    # wont_make_it vs behind: due Feb 14 with no boundary before it AND far below
    # a steady schedule. Moving money is the only fix, so that must be the wording.
    it "reports wont_make_it ahead of behind", :aggregate_failures do
      pool = envelope("Tires")
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 2, 14))
      fund(pool, 20)

      status = pool.status(today: today)

      expect(status.state).to eq(:wont_make_it)
      expect(status.amount).to eq(580)
    end

    # The two pairs the seventh state adds. Only these two are OBSERVABLE: `saving?` requires
    # `anchored_budgets.empty?`, and :overdue, :wont_make_it and :behind every one of them
    # require an anchored rule, so no pool can satisfy :saving and any of those three at once
    # — a swap there changes no result and would be asserted by nothing. :overdrawn and
    # :left_to_spend are the two that CAN both hold, so they are the two pinned here.

    # overdrawn vs saving: a savings pool with no dated rule AND a negative balance. Money
    # already spent outranks money being put away, or a goal $50 in the red reads as healthy.
    it "reports overdrawn ahead of saving", :aggregate_failures do
      pool = goal("Vacation")
      fund(pool, 100)
      spend(pool, 150)

      status = pool.status(today: today)

      expect(status.state).to eq(:overdrawn)
      expect(status.amount).to eq(50)
    end

    # saving vs left_to_spend: a savings pool with no dated rule satisfies BOTH guards, which
    # is exactly why :saving has to sit before :left_to_spend — placed after it, it could
    # never fire at all.
    it "reports saving ahead of left_to_spend", :aggregate_failures do
      pool = goal("Vacation")
      fund(pool, 424)

      status = pool.status(today: today)

      expect(status.state).to eq(:saving)
      expect(status.state).not_to eq(:left_to_spend)
    end
  end

  describe ":wont_make_it" do
    it "fires when no period boundary falls before the due date", :aggregate_failures do
      pool = envelope("Dentist")
      create(:pool_budget, :one_time, pool: pool, amount: 300, anchor_date: Date.new(2026, 2, 14))

      status = pool.status(today: today)

      expect(status.state).to eq(:wont_make_it)
      expect(status.amount).to eq(300)
      expect(status.due_on).to eq(Date.new(2026, 2, 14))
    end

    it "does not fire when a period still arrives in time" do
      pool = envelope("Dentist")
      create(:pool_budget, :one_time, pool: pool, amount: 300, anchor_date: Date.new(2026, 3, 14))

      expect(pool.status(today: today).state).not_to eq(:wont_make_it)
    end

    it "does not fire once the rule is fully funded" do
      pool = envelope("Dentist")
      create(:pool_budget, :one_time, pool: pool, amount: 300, anchor_date: Date.new(2026, 2, 14))
      fund(pool, 300)

      expect(pool.status(today: today).state).not_to eq(:wont_make_it)
    end

    # The `from` side of the window is `today + 1`, so a boundary landing today does NOT
    # rescue a future bill — today's distribution is the one being looked at right now.
    # The first expectation states that premise instead of leaving it incidental.
    it "fires even when a boundary lands today, which cannot spread a future bill", :aggregate_failures do
      pool = envelope("Dentist")
      create(:pool_budget, :one_time, pool: pool, amount: 300, anchor_date: Date.new(2026, 2, 14))

      expect(user.period_boundaries(from: today, to: today)).to eq([today])
      expect(pool.status(today: today).state).to eq(:wont_make_it)
    end

    # Two rules, both unreachable, created LATEST-DUE-FIRST so insertion order and due-date
    # order disagree. Without a deterministic sort the pick is whatever Postgres returns.
    it "names the earliest of several unreachable rules", :aggregate_failures do
      pool = envelope("Repairs")
      create(:pool_budget, :one_time, pool: pool, amount: 400, anchor_date: Date.new(2026, 2, 13))
      create(:pool_budget, :one_time, pool: pool, amount: 150, anchor_date: Date.new(2026, 2, 12))

      status = pool.status(today: today)

      expect(status.state).to eq(:wont_make_it)
      expect(status.due_on).to eq(Date.new(2026, 2, 12))
      expect(status.amount).to eq(150)
    end

    # The two examples below pin the off-by-one deliberately rather than leaving it to
    # whichever way the range happened to be written. A boundary landing ON the due date
    # counts as in time: you distribute that morning and pay the bill the same day.
    it "does not fire when a boundary lands exactly on the due date" do
      pool = envelope("Dentist")
      create(:pool_budget, :one_time, pool: pool, amount: 300, anchor_date: Date.new(2026, 2, 20))

      expect(pool.status(today: today).state).to eq(:on_track)
    end

    it "fires when the only boundary lands the day after the due date" do
      pool = envelope("Dentist")
      create(:pool_budget, :one_time, pool: pool, amount: 300, anchor_date: Date.new(2026, 2, 19))

      expect(pool.status(today: today).state).to eq(:wont_make_it)
    end

    # #unreachable_budget gates on `shortfall_for(budget).positive?`, which reads
    # #allocated_balances — so this state moves with the same "a settled rule holds nothing"
    # change that moved :behind. A settled $200 one-off dated Jan 15 sorts ahead of the live
    # $300 bill due Feb 14 and used to keep $200 of the envelope's $300, leaving the live bill
    # $100 and a $200 shortfall no remaining period could close. It now gets the full $300.
    #
    # Measured across the change: :wont_make_it $200 (allocations 200/100) -> :on_track $300
    # (allocations 0/300). Both rules are one-offs, so :behind cannot catch the fall-through
    # (#periods_in_cycle is 0 without an interval) and the state lands on :on_track.
    it "stops firing once the rule ahead of it is settled", :aggregate_failures do
      pool = envelope("Dentist")
      settled = create(:pool_budget, :one_time, pool: pool, amount: 200, anchor_date: Date.new(2026, 1, 15))
      bill = create(:pool_budget, :one_time, pool: pool, amount: 300, anchor_date: Date.new(2026, 2, 14))
      fund(pool, 300)

      calc = pool.calculator(today: today)
      status = pool.status(today: today)

      expect(calc.allocated_balances[settled]).to eq(0)
      expect(calc.allocated_balances[bill]).to eq(300)
      expect(status.state).to eq(:on_track)
      expect(status.amount).to eq(300)
    end

    # The control, and the half that keeps the example above meaning something: the leading
    # rule is merely UNPAID rather than settled — a one-off dated Feb 10, still ahead of Feb 14
    # in the fill order, still holding its $200. Same balance, same live bill, same order; only
    # settled-ness varies. This state must NOT move, and measured it does not: :wont_make_it
    # $200 before and after, on allocations of 200/100 that differ from the treatment's 0/300.
    it "still fires when the rule ahead of it is merely unpaid", :aggregate_failures do
      pool = envelope("Dentist")
      unpaid = create(:pool_budget, :one_time, pool: pool, amount: 200, anchor_date: Date.new(2026, 2, 10))
      bill = create(:pool_budget, :one_time, pool: pool, amount: 300, anchor_date: Date.new(2026, 2, 14))
      fund(pool, 300)

      calc = pool.calculator(today: today)
      status = pool.status(today: today)

      expect(calc.allocated_balances[unpaid]).to eq(200)
      expect(calc.allocated_balances[bill]).to eq(100)
      expect(status.state).to eq(:wont_make_it)
      # Names the live bill, not the rule ahead of it: that one is fully allocated, so its own
      # shortfall is 0 and #unreachable_budget's `find` skips past it.
      expect(status.due_on).to eq(Date.new(2026, 2, 14))
    end
  end

  describe ":behind" do
    # $600 due Mar 1, 6-month interval. Biweekly periods, so ~13 in a cycle.
    # Half the cycle elapsed ⇒ a steady schedule would hold ~$300.
    it "fires when the balance is below a steady schedule", :aggregate_failures do
      pool = envelope("Car")
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(pool, 20)

      status = pool.status(today: today)

      expect(status.state).to eq(:behind)
      expect(status.amount).to be > 0
    end

    it "does not fire when the balance is at or above the steady schedule" do
      pool = envelope("Car")
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(pool, 600)

      expect(pool.status(today: today).state).to eq(:on_track)
    end

    # Allocation fills the earliest due date first, so funding $200 settles the Feb 28
    # rule and starves the Mar 1 one. The lag is entirely the later rule's, and naming
    # the earlier date would point the user at the bill that is on schedule.
    it "names the earliest due date among the rules actually behind", :aggregate_failures do
      pool = envelope("Car")
      create(:pool_budget, pool: pool, amount: 200, interval_months: 6, anchor_date: Date.new(2026, 2, 28))
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(pool, 200)

      status = pool.status(today: today)

      expect(status.state).to eq(:behind)
      expect(status.due_on).to eq(Date.new(2026, 3, 1))
    end

    it "sums the lag across every rule behind, and then names the earliest of those", :aggregate_failures do
      pool = envelope("Car")
      create(:pool_budget, pool: pool, amount: 200, interval_months: 6, anchor_date: Date.new(2026, 2, 28))
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(pool, 20)

      status = pool.status(today: today)

      # 200 * 11/13 - 20 = 149.23 behind on the Feb rule, 600 * 11/13 - 0 = 507.69 on the Mar one.
      expect(status.amount).to be_within(0.01).of(656.92)
      expect(status.due_on).to eq(Date.new(2026, 2, 28))
    end

    # The user-facing half of PoolCalculator's "a settled rule holds nothing" fix. A paid-off
    # $200 one-off sorts ahead of the live $600 rule and used to keep its allocation forever,
    # starving the live rule of $200 the envelope was actually holding — so this pool read
    # `behind $107.69` while carrying enough to be exactly on schedule. It now reads on track.
    #
    # The pair below is that change isolated: same balance, same live rule, same fill order,
    # differing only in whether the LEADING rule is settled. The control still reads
    # `behind $107.69`, so this cannot pass against an allocation that stopped filling
    # earliest-due-first, or against a :behind branch that has simply gone quiet.
    it "stops reading behind once the rule ahead of it is settled", :aggregate_failures do
      pool = envelope("Car")
      create(:pool_budget, :one_time, pool: pool, amount: 200, anchor_date: Date.new(2026, 1, 15))
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(pool, 600)

      status = pool.status(today: today)

      expect(status.state).to eq(:on_track)
      expect(status.amount).to eq(600)
    end

    it "still reads behind when the rule ahead of it is merely unpaid", :aggregate_failures do
      pool = envelope("Car")
      create(:pool_budget, pool: pool, amount: 200, interval_months: 6, anchor_date: Date.new(2026, 2, 28))
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(pool, 600)

      status = pool.status(today: today)

      expect(status.state).to eq(:behind)
      expect(status.amount).to be_within(0.01).of(107.69)
    end

    # periods_in_cycle divides by its own return value, so both shapes that make
    # it zero have to be pinned or the guard is asserted by nothing.
    it "does not fire for a one-time rule, which has no interval to spread over" do
      pool = envelope("Dentist")
      create(:pool_budget, :one_time, pool: pool, amount: 300, anchor_date: Date.new(2026, 3, 14))

      expect(pool.status(today: today).state).to eq(:on_track)
    end

    it "does not fire for a user with no period configured" do
      plain = create(:user)
      account = create(:pool, :account, user: plain, name: "Plain checking")
      pool = create(:pool, :budget_pool, user: plain, account: account, name: "Plain car")
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      create(:pool_movement, from_pool: account, to_pool: pool, amount: 600)

      expect(pool.status(today: today).state).to eq(:on_track)
    end
  end

  describe ":on_track" do
    it "reports the balance and the earliest due date", :aggregate_failures do
      pool = envelope("Car")
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      create(:pool_budget, pool: pool, amount: 100, interval_months: 6, anchor_date: Date.new(2026, 4, 1))
      fund(pool, 700)

      status = pool.status(today: today)

      expect(status.state).to eq(:on_track)
      expect(status.amount).to eq(700)
      expect(status.balance).to eq(700)
      expect(status.due_on).to eq(Date.new(2026, 3, 1))
    end
  end

  # The seventh state, added after Home was seen on a screen: a savings pool with no dated
  # rule could reach NO state but :left_to_spend, so a vacation fund rendered "$424.00 left"
  # — a spendable number for money that is not spendable, which is design principle 2
  # inverted on every savings row at once.
  describe ":saving" do
    it "fires for a savings pool with no dated rule, and reports what it holds", :aggregate_failures do
      pool = goal("Vacation")
      create(:pool_budget, :per_paycheck_rate, pool: pool, amount: 150)
      fund(pool, 424)

      status = pool.status(today: today)

      expect(status.state).to eq(:saving)
      expect(status.amount).to eq(424)
      expect(status.target).to eq(2_400)
      # Quiet: accumulating on plan is not a problem, and the auto-expand rule keys off this.
      expect(status.needs_attention?).to be(false)
    end

    # The other direction. A budget envelope's balance IS spendable — that is the whole
    # distinction — so the new guard must not swallow the state it was carved out of.
    it "does not fire for a budget envelope funded at a rate", :aggregate_failures do
      pool = envelope("Groceries")
      create(:pool_budget, :per_paycheck_rate, pool: pool, amount: 400)
      fund(pool, 400)

      expect(pool.status(today: today).state).to eq(:left_to_spend)
      expect(pool.status(today: today).state).not_to eq(:saving)
    end

    # A dated savings pool already had a vocabulary that works — the anchored maths spreads
    # the goal across the periods left — and this guard must not take it away.
    it "does not fire for a savings pool with a dated rule", :aggregate_failures do
      pool = goal("Roof")
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(pool, 600)

      expect(pool.status(today: today).state).to eq(:on_track)
      expect(pool.status(today: today).state).not_to eq(:saving)
    end

    it "reports no target for a savings pool that names none" do
      pool = create(:pool, :savings_pool, user: user, account: checking, name: "Rainy Day", target_amount: 0)

      expect(pool.status(today: today).target).to eq(0)
    end
  end

  describe ":left_to_spend" do
    it "fires for a pool with only rate rules", :aggregate_failures do
      pool = envelope("Groceries")
      create(:pool_budget, :per_paycheck_rate, pool: pool, amount: 400)
      fund(pool, 400)
      spend(pool, 160)

      status = pool.status(today: today)

      expect(status.state).to eq(:left_to_spend)
      expect(status.amount).to eq(240)
    end

    it "does not fire when the pool also has an anchored rule" do
      pool = envelope("Car")
      create(:pool_budget, :per_paycheck_rate, pool: pool, amount: 80)
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(pool, 600)

      expect(pool.status(today: today).state).not_to eq(:left_to_spend)
    end
  end

  describe "#needs_attention?" do
    it "is true for the four problem states", :aggregate_failures do
      [:overdrawn, :overdue, :wont_make_it, :behind].each do |state|
        expect(described_class::ATTENTION_STATES).to include(state)
      end
    end

    it "is false for on_track, left_to_spend and saving", :aggregate_failures do
      expect(described_class::ATTENTION_STATES).not_to include(:on_track)
      expect(described_class::ATTENTION_STATES).not_to include(:left_to_spend)
      expect(described_class::ATTENTION_STATES).not_to include(:saving)
    end

    # The constant examples above never call the method; these do, in both directions.
    it "is true for a pool that is behind" do
      pool = envelope("Car")
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(pool, 20)

      expect(pool.status(today: today).needs_attention?).to be(true)
    end

    it "is false for a pool that is on track" do
      pool = envelope("Car")
      create(:pool_budget, pool: pool, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(pool, 600)

      expect(pool.status(today: today).needs_attention?).to be(false)
    end
  end

  describe "an account pool" do
    it "reads as left_to_spend, since a buffer is always spendable" do
      status = checking.status(today: today)

      expect(status.state).to eq(:left_to_spend)
    end
  end

  # Both readers run straight off PoolCalculator#balance, which is five `sum(:amount)`
  # calls over a `money` column — and an empty sum returns the Integer literal 0. An
  # entry-less pool is the ordinary shape (a fresh envelope, a goal nobody has funded
  # yet), and it is precisely the shape that answered in the wrong type. `eq(0)` alone
  # passes against the Integer, so the type is asserted beside the value on each quiet
  # state that reads the raw balance.
  describe "money types on a pool with no entries at all", :aggregate_failures do
    it "reports a BigDecimal balance and amount on a rate envelope" do
      pool = envelope("Groceries")
      create(:pool_budget, :per_paycheck_rate, pool: pool, amount: 400)
      status = pool.status(today: today)

      expect(status.state).to eq(:left_to_spend)
      expect(status.balance).to eq(0)
      expect(status.balance).to be_a(BigDecimal)
      expect(status.amount).to eq(0)
      expect(status.amount).to be_a(BigDecimal)
    end

    it "reports a BigDecimal amount on an unfunded savings goal" do
      status = goal("Vacation").status(today: today)

      expect(status.state).to eq(:saving)
      expect(status.amount).to be_a(BigDecimal)
    end
  end
end
