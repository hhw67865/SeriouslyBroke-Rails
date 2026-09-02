# frozen_string_literal: true

require "rails_helper"

# THE PORT OF `spec/services/pool_status_spec.rb`, state for state and figure for figure
# (two-ledger Task 3). The six-state vocabulary and the precedence order are the display decision
# this class exists to make, and neither moved: what moved is the thing being read, from an
# envelope's balance to a category's holdings.
#
# TWO FIXTURES CHANGED SHAPE and nothing else did:
#   * `bill_rule` hangs its item on the CATEGORY the rule funds (`Budget#item_must_belong_to_
#     category`), where the pool-era version hung it on a category pointing AT the pool. The money
#     is the same money — an entry against that item drains the same holder either way.
#   * the account example at the bottom becomes a category with no rules at all, which is the
#     shape it was really about: a balance with nothing claiming it reads as spendable.
RSpec.describe HoldingStatus, type: :model do
  let(:user) { create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6)) }
  let(:today) { Date.new(2026, 2, 6) }

  def envelope(name)
    create(:category, :expense, :funded, user: user, name: name)
  end

  def goal(name, target: 2_400)
    create(:category, :expense, :funded, user: user, name: name, target_amount: target)
  end

  def fund(category, amount)
    create(:allocation, to_category: category, amount: amount)
  end

  def rule(category, trait = nil, **attrs)
    create(:budget, *Array(trait), pool: nil, category: category, **attrs)
  end

  def spend(category, amount, name: "Something")
    create(:entry, item: create(:item, category: category, name: name), amount: amount, date: today)
  end

  # An item is the only fulfillment signal BudgetCalculator#overdue? accepts, so every example
  # that needs an overdue rule has to route through here. Named per item, not per category:
  # a category with two bills in it calls this twice and item names are its own.
  def bill_rule(category, name, amount:, anchor_date:)
    item = create(:item, category: category, name: name)
    rule(category, amount: amount, interval_months: 6, anchor_date: anchor_date, item: item)
  end

  describe "precedence" do
    it "reports overdrawn ahead of everything else", :aggregate_failures do
      category = envelope("Car")
      rule(category, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(category, 100)
      spend(category, 150)

      status = category.status(today: today)

      expect(status.state).to eq(:overdrawn)
      expect(status.amount).to eq(50)
    end

    it "reports overdue ahead of behind", :aggregate_failures do
      category = envelope("Insurance")
      bill_rule(category, "Insurance", amount: 600, anchor_date: Date.new(2026, 2, 1))
      fund(category, 600)

      status = category.status(today: Date.new(2026, 2, 6))

      expect(status.state).to eq(:overdue)
      expect(status.due_on).to eq(Date.new(2026, 2, 1))
    end

    # Each of the three examples below pins ONE adjacent pair of the chain by building a category
    # that genuinely satisfies both conditions. Without them a swap of that pair changes no result
    # and the ordering is asserted by nothing.

    # overdrawn vs overdue: the category is $50 in the red AND holds a bill whose date passed
    # unpaid.
    it "reports overdrawn ahead of overdue", :aggregate_failures do
      category = envelope("Phone")
      bill_rule(category, "Phone", amount: 600, anchor_date: Date.new(2026, 2, 1))
      fund(category, 100)
      spend(category, 150)

      status = category.status(today: today)

      expect(status.state).to eq(:overdrawn)
      expect(status.amount).to eq(50)
    end

    # overdue vs wont_make_it: the rule's date passed unpaid AND it is $500 short with no boundary
    # left before that date, so both conditions hold.
    it "reports overdue ahead of wont_make_it", :aggregate_failures do
      category = envelope("Water")
      bill_rule(category, "Water", amount: 600, anchor_date: Date.new(2026, 2, 1))
      fund(category, 100)

      status = category.status(today: today)

      expect(status.state).to eq(:overdue)
      expect(status.due_on).to eq(Date.new(2026, 2, 1))
    end

    it "reports what is still unpaid on the overdue rule, not its face value", :aggregate_failures do
      category = envelope("Water")
      rule_row = bill_rule(category, "Water", amount: 600, anchor_date: Date.new(2026, 2, 1))
      fund(category, 600)
      create(:entry, item: rule_row.item, amount: 400, date: Date.new(2026, 2, 2))

      status = category.status(today: today)

      expect(status.state).to eq(:overdue)
      expect(status.amount).to eq(200)
    end

    # Two overdue rules, created LATEST-DUE-FIRST so insertion order and due-date order disagree.
    # `has_many :budgets` carries no ORDER BY, so without a deterministic sort this category reads
    # $200 · Feb 3 or $600 · Feb 1 at random between page loads.
    it "names the earliest of several overdue rules", :aggregate_failures do
      category = envelope("Utilities")
      bill_rule(category, "Electric", amount: 200, anchor_date: Date.new(2026, 2, 3))
      bill_rule(category, "Water", amount: 600, anchor_date: Date.new(2026, 2, 1))
      fund(category, 800)

      status = category.status(today: today)

      expect(status.state).to eq(:overdue)
      expect(status.due_on).to eq(Date.new(2026, 2, 1))
      expect(status.amount).to eq(600)
    end

    # Same due date, so the date cannot break the tie. Created smallest-first, so insertion order
    # and the intended order disagree: the larger obligation is the one to name.
    it "breaks a tie between two overdue rules toward the larger", :aggregate_failures do
      category = envelope("Levies")
      bill_rule(category, "Small", amount: 200, anchor_date: Date.new(2026, 2, 1))
      bill_rule(category, "Large", amount: 600, anchor_date: Date.new(2026, 2, 1))
      fund(category, 800)

      status = category.status(today: today)

      expect(status.state).to eq(:overdue)
      expect(status.amount).to eq(600)
    end

    # The two below are the multi-cycle cases. #paid_since_anchor is cumulative across every cycle
    # since the anchor while the rule's amount is one cycle's worth, so a bare `amount - paid` only
    # holds while nothing has rolled. Cycle 1 is paid in full in both, which is the ordinary state
    # of a recurring bill, not an edge case.
    it "reports the whole amount when a rolled cycle is wholly unpaid", :aggregate_failures do
      category = envelope("Insurance")
      rule_row = bill_rule(category, "Insurance", amount: 600, anchor_date: Date.new(2025, 8, 1))
      fund(category, 1200)
      create(:entry, item: rule_row.item, amount: 600, date: Date.new(2025, 8, 2)) # cycle 1, settled

      status = category.status(today: today)

      expect(status.state).to eq(:overdue)
      expect(status.amount).to eq(600)
    end

    it "reports only the remainder when a rolled cycle is partly paid", :aggregate_failures do
      category = envelope("Insurance")
      rule_row = bill_rule(category, "Insurance", amount: 600, anchor_date: Date.new(2025, 8, 1))
      fund(category, 1200)
      create(:entry, item: rule_row.item, amount: 600, date: Date.new(2025, 8, 2)) # cycle 1, settled
      create(:entry, item: rule_row.item, amount: 250, date: Date.new(2026, 2, 2)) # cycle 2, part paid

      status = category.status(today: today)

      # Owed through cycle 2 is 600 * 2 = 1200; 850 has been paid.
      expect(status.state).to eq(:overdue)
      expect(status.amount).to eq(350)
    end

    # wont_make_it vs behind: due Feb 14 with no boundary before it AND far below a steady
    # schedule. Moving money is the only fix, so that must be the wording.
    it "reports wont_make_it ahead of behind", :aggregate_failures do
      category = envelope("Tires")
      rule(category, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 2, 14))
      fund(category, 20)

      status = category.status(today: today)

      expect(status.state).to eq(:wont_make_it)
      expect(status.amount).to eq(580)
    end

    # The two pairs the seventh state adds. Only these two are OBSERVABLE: `saving?` requires
    # `anchored_budgets.empty?`, and :overdue, :wont_make_it and :behind every one of them require
    # an anchored rule, so no category can satisfy :saving and any of those three at once — a swap
    # there changes no result and would be asserted by nothing. :overdrawn and :left_to_spend are
    # the two that CAN both hold, so they are the two pinned here.

    # overdrawn vs saving: a goal with no dated rule AND a negative balance. Money already spent
    # outranks money being put away, or a goal $50 in the red reads as healthy.
    it "reports overdrawn ahead of saving", :aggregate_failures do
      category = goal("Vacation")
      fund(category, 100)
      spend(category, 150)

      status = category.status(today: today)

      expect(status.state).to eq(:overdrawn)
      expect(status.amount).to eq(50)
    end

    # saving vs left_to_spend: a goal with no dated rule satisfies BOTH guards, which is exactly
    # why :saving has to sit before :left_to_spend — placed after it, it could never fire at all.
    it "reports saving ahead of left_to_spend", :aggregate_failures do
      category = goal("Vacation")
      fund(category, 424)

      status = category.status(today: today)

      expect(status.state).to eq(:saving)
      expect(status.state).not_to eq(:left_to_spend)
    end
  end

  describe ":wont_make_it" do
    it "fires when no period boundary falls before the due date", :aggregate_failures do
      category = envelope("Dentist")
      rule(category, :one_time, amount: 300, anchor_date: Date.new(2026, 2, 14))

      status = category.status(today: today)

      expect(status.state).to eq(:wont_make_it)
      expect(status.amount).to eq(300)
      expect(status.due_on).to eq(Date.new(2026, 2, 14))
    end

    it "does not fire when a period still arrives in time" do
      category = envelope("Dentist")
      rule(category, :one_time, amount: 300, anchor_date: Date.new(2026, 3, 14))

      expect(category.status(today: today).state).not_to eq(:wont_make_it)
    end

    it "does not fire once the rule is fully funded" do
      category = envelope("Dentist")
      rule(category, :one_time, amount: 300, anchor_date: Date.new(2026, 2, 14))
      fund(category, 300)

      expect(category.status(today: today).state).not_to eq(:wont_make_it)
    end

    # The `from` side of the window is `today + 1`, so a boundary landing today does NOT rescue a
    # future bill — today's distribution is the one being looked at right now. The first
    # expectation states that premise instead of leaving it incidental.
    it "fires even when a boundary lands today, which cannot spread a future bill", :aggregate_failures do
      category = envelope("Dentist")
      rule(category, :one_time, amount: 300, anchor_date: Date.new(2026, 2, 14))

      expect(user.period_boundaries(from: today, to: today)).to eq([today])
      expect(category.status(today: today).state).to eq(:wont_make_it)
    end

    # Two rules, both unreachable, created LATEST-DUE-FIRST so insertion order and due-date order
    # disagree. Without a deterministic sort the pick is whatever Postgres returns.
    it "names the earliest of several unreachable rules", :aggregate_failures do
      category = envelope("Repairs")
      rule(category, :one_time, amount: 400, anchor_date: Date.new(2026, 2, 13))
      rule(category, :one_time, amount: 150, anchor_date: Date.new(2026, 2, 12))

      status = category.status(today: today)

      expect(status.state).to eq(:wont_make_it)
      expect(status.due_on).to eq(Date.new(2026, 2, 12))
      expect(status.amount).to eq(150)
    end

    # The two examples below pin the off-by-one deliberately rather than leaving it to whichever
    # way the range happened to be written. A boundary landing ON the due date counts as in time:
    # you distribute that morning and pay the bill the same day.
    it "does not fire when a boundary lands exactly on the due date" do
      category = envelope("Dentist")
      rule(category, :one_time, amount: 300, anchor_date: Date.new(2026, 2, 20))

      expect(category.status(today: today).state).to eq(:on_track)
    end

    it "fires when the only boundary lands the day after the due date" do
      category = envelope("Dentist")
      rule(category, :one_time, amount: 300, anchor_date: Date.new(2026, 2, 19))

      expect(category.status(today: today).state).to eq(:wont_make_it)
    end

    # #unreachable_budget gates on `shortfall_for(budget).positive?`, which reads
    # #allocated_balances — so this state moves with the "a settled rule holds nothing" rule. A
    # settled $200 one-off dated Jan 15 sorts ahead of the live $300 bill due Feb 14 and would
    # otherwise keep $200 of the category's $300, leaving the live bill $100 and a $200 shortfall
    # no remaining period could close. It gets the full $300 instead.
    it "stops firing once the rule ahead of it is settled", :aggregate_failures do
      category = envelope("Dentist")
      settled = rule(category, :one_time, amount: 200, anchor_date: Date.new(2026, 1, 15))
      bill = rule(category, :one_time, amount: 300, anchor_date: Date.new(2026, 2, 14))
      fund(category, 300)

      calc = category.holding_calculator(today: today)
      status = category.status(today: today)

      expect(calc.allocated_balances[settled]).to eq(0)
      expect(calc.allocated_balances[bill]).to eq(300)
      expect(status.state).to eq(:on_track)
      expect(status.amount).to eq(300)
    end

    # The control, and the half that keeps the example above meaning something: the leading rule is
    # merely UNPAID rather than settled — a one-off dated Feb 10, still ahead of Feb 14 in the fill
    # order, still holding its $200. Same balance, same live bill, same order; only settled-ness
    # varies.
    it "still fires when the rule ahead of it is merely unpaid", :aggregate_failures do
      category = envelope("Dentist")
      unpaid = rule(category, :one_time, amount: 200, anchor_date: Date.new(2026, 2, 10))
      bill = rule(category, :one_time, amount: 300, anchor_date: Date.new(2026, 2, 14))
      fund(category, 300)

      calc = category.holding_calculator(today: today)
      status = category.status(today: today)

      expect(calc.allocated_balances[unpaid]).to eq(200)
      expect(calc.allocated_balances[bill]).to eq(100)
      expect(status.state).to eq(:wont_make_it)
      # Names the live bill, not the rule ahead of it: that one is fully allocated, so its own
      # shortfall is 0 and #unreachable_budget's `find` skips past it.
      expect(status.due_on).to eq(Date.new(2026, 2, 14))
    end
  end

  describe ":behind" do
    # $600 due Mar 1, 6-month interval. Biweekly periods, so ~13 in a cycle. Half the cycle
    # elapsed ⇒ a steady schedule would hold ~$300.
    it "fires when the balance is below a steady schedule", :aggregate_failures do
      category = envelope("Car")
      rule(category, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(category, 20)

      status = category.status(today: today)

      expect(status.state).to eq(:behind)
      expect(status.amount).to be > 0
    end

    it "does not fire when the balance is at or above the steady schedule" do
      category = envelope("Car")
      rule(category, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(category, 600)

      expect(category.status(today: today).state).to eq(:on_track)
    end

    # Allocation fills the earliest due date first, so funding $200 settles the Feb 28 rule and
    # starves the Mar 1 one. The lag is entirely the later rule's, and naming the earlier date
    # would point the user at the bill that is on schedule.
    it "names the earliest due date among the rules actually behind", :aggregate_failures do
      category = envelope("Car")
      rule(category, amount: 200, interval_months: 6, anchor_date: Date.new(2026, 2, 28))
      rule(category, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(category, 200)

      status = category.status(today: today)

      expect(status.state).to eq(:behind)
      expect(status.due_on).to eq(Date.new(2026, 3, 1))
    end

    it "sums the lag across every rule behind, and then names the earliest of those", :aggregate_failures do
      category = envelope("Car")
      rule(category, amount: 200, interval_months: 6, anchor_date: Date.new(2026, 2, 28))
      rule(category, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(category, 20)

      status = category.status(today: today)

      # 200 * 11/13 - 20 = 149.23 behind on the Feb rule, 600 * 11/13 - 0 = 507.69 on the Mar one.
      expect(status.amount).to be_within(0.01).of(656.92)
      expect(status.due_on).to eq(Date.new(2026, 2, 28))
    end

    # The user-facing half of "a settled rule holds nothing". A paid-off $200 one-off sorts ahead
    # of the live $600 rule and would otherwise keep its allocation forever, starving the live rule
    # of $200 the category was actually holding — so this category would read `behind $107.69`
    # while carrying enough to be exactly on schedule.
    #
    # The pair below is that isolated: same balance, same live rule, same fill order, differing
    # only in whether the LEADING rule is settled. The control still reads `behind $107.69`, so
    # this cannot pass against an allocation that stopped filling earliest-due-first, or against a
    # :behind branch that has simply gone quiet.
    it "stops reading behind once the rule ahead of it is settled", :aggregate_failures do
      category = envelope("Car")
      rule(category, :one_time, amount: 200, anchor_date: Date.new(2026, 1, 15))
      rule(category, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(category, 600)

      status = category.status(today: today)

      expect(status.state).to eq(:on_track)
      expect(status.amount).to eq(600)
    end

    it "still reads behind when the rule ahead of it is merely unpaid", :aggregate_failures do
      category = envelope("Car")
      rule(category, amount: 200, interval_months: 6, anchor_date: Date.new(2026, 2, 28))
      rule(category, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(category, 600)

      status = category.status(today: today)

      expect(status.state).to eq(:behind)
      expect(status.amount).to be_within(0.01).of(107.69)
    end

    # periods_in_cycle divides by its own return value, so both shapes that make it zero have to
    # be pinned or the guard is asserted by nothing.
    it "does not fire for a one-time rule, which has no interval to spread over" do
      category = envelope("Dentist")
      rule(category, :one_time, amount: 300, anchor_date: Date.new(2026, 3, 14))

      expect(category.status(today: today).state).to eq(:on_track)
    end

    it "does not fire for a user with no period configured" do
      plain = create(:user)
      category = create(:category, :expense, :funded, user: plain, name: "Plain car")
      rule(category, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      create(:allocation, to_category: category, amount: 600)

      expect(category.status(today: today).state).to eq(:on_track)
    end
  end

  describe ":on_track" do
    it "reports the balance and the earliest due date", :aggregate_failures do
      category = envelope("Car")
      rule(category, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      rule(category, amount: 100, interval_months: 6, anchor_date: Date.new(2026, 4, 1))
      fund(category, 700)

      status = category.status(today: today)

      expect(status.state).to eq(:on_track)
      expect(status.amount).to eq(700)
      expect(status.balance).to eq(700)
      expect(status.due_on).to eq(Date.new(2026, 3, 1))
    end
  end

  # The seventh state: a goal with no dated rule could reach NO state but :left_to_spend, so a
  # vacation fund rendered "$424.00 left" — a spendable number for money that is not spendable,
  # which is design principle 2 inverted on every savings row at once.
  describe ":saving" do
    it "fires for a goal with no dated rule, and reports what it holds", :aggregate_failures do
      category = goal("Vacation")
      rule(category, :per_period_rate, amount: 150)
      fund(category, 424)

      status = category.status(today: today)

      expect(status.state).to eq(:saving)
      expect(status.amount).to eq(424)
      expect(status.target).to eq(2_400)
      # Quiet: accumulating on plan is not a problem, and the auto-expand rule keys off this.
      expect(status.needs_attention?).to be(false)
    end

    # The other direction. A budget envelope's balance IS spendable — that is the whole
    # distinction — so the guard must not swallow the state it was carved out of.
    it "does not fire for a category with no target funded at a rate", :aggregate_failures do
      category = envelope("Groceries")
      rule(category, :per_period_rate, amount: 400)
      fund(category, 400)

      expect(category.status(today: today).state).to eq(:left_to_spend)
      expect(category.status(today: today).state).not_to eq(:saving)
    end

    # A dated goal already had a vocabulary that works — the anchored maths spreads the goal across
    # the periods left — and this guard must not take it away.
    it "does not fire for a goal with a dated rule", :aggregate_failures do
      category = goal("Roof")
      rule(category, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(category, 600)

      expect(category.status(today: today).state).to eq(:on_track)
      expect(category.status(today: today).state).not_to eq(:saving)
    end

    # `target_amount` is nil rather than the pool era's 0: `Category#target_is_a_goal` refuses a
    # zero target outright, so "names none" is the only shape left to ask about — and `nil.to_d`
    # is what makes it answerable at all.
    it "reports no target for a category that names none" do
      category = envelope("Rainy Day")

      expect(category.status(today: today).target).to eq(0)
    end
  end

  describe ":left_to_spend" do
    it "fires for a category with only rate rules", :aggregate_failures do
      category = envelope("Groceries")
      rule(category, :per_period_rate, amount: 400)
      fund(category, 400)
      spend(category, 160)

      status = category.status(today: today)

      expect(status.state).to eq(:left_to_spend)
      expect(status.amount).to eq(240)
    end

    it "does not fire when the category also has an anchored rule" do
      category = envelope("Car")
      rule(category, :per_period_rate, amount: 80)
      rule(category, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(category, 600)

      expect(category.status(today: today).state).not_to eq(:left_to_spend)
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
    it "is true for a category that is behind" do
      category = envelope("Car")
      rule(category, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(category, 20)

      expect(category.status(today: today).needs_attention?).to be(true)
    end

    it "is false for a category that is on track" do
      category = envelope("Car")
      rule(category, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(category, 600)

      expect(category.status(today: today).needs_attention?).to be(false)
    end
  end

  # WHICH PERIOD THE FIGURE BELONGS TO. The ` · last period` suffix rides on a status, so every
  # screen that renders one has to be able to ask — and asking through here rather than through a
  # second calculator is what keeps the answer and the balance on one object. Both directions, at
  # the same shape and the same money, so the funding DATE is the only variable.
  describe "#period_closed?" do
    def fund_on(category, amount, date)
      create(:allocation, to_category: category, amount: amount, date: date)
    end

    it "is true for a rate envelope funded in a period that has ended" do
      category = envelope("Groceries")
      rule(category, :per_period_rate, amount: 400)
      fund_on(category, 60, Date.new(2026, 1, 2))

      expect(category.status(today: today).period_closed?).to be(true)
    end

    it "is false for the same envelope funded inside the live period" do
      category = envelope("Groceries")
      rule(category, :per_period_rate, amount: 400)
      fund_on(category, 60, today)

      expect(category.status(today: today).period_closed?).to be(false)
    end
  end

  # WHETHER #amount IS A READING OF THE BALANCE, asked of the class that owns #amount. The Budget
  # page prints the balance beside the label only where this is false, so a state falling out of
  # BILL_STATES silently drops that category's balance off the page.
  describe "#amount_is_balance?" do
    it "is false for the three states whose figure is a bill's", :aggregate_failures do
      expect(described_class::BILL_STATES).to contain_exactly(:overdue, :wont_make_it, :behind)
      described_class::BILL_STATES.each do |state|
        expect(described_class::ATTENTION_STATES).to include(state)
      end
    end

    # The method, not the constant, on live records — and each one asserted against #balance itself
    # rather than against a repeat of the branch.
    it "is false on a category that is behind, whose label prints a shortfall", :aggregate_failures do
      category = envelope("Car")
      rule(category, amount: 600, interval_months: 6, anchor_date: Date.new(2026, 3, 1))
      fund(category, 20)
      status = category.status(today: today)

      expect(status.state).to eq(:behind)
      expect(status.amount_is_balance?).to be(false)
      expect(status.amount).not_to eq(status.balance)
    end

    it "is true on a rate envelope, whose label prints the balance itself", :aggregate_failures do
      category = envelope("Groceries")
      rule(category, :per_period_rate, amount: 400)
      fund(category, 250)
      status = category.status(today: today)

      expect(status.state).to eq(:left_to_spend)
      expect(status.amount_is_balance?).to be(true)
      expect(status.amount).to eq(status.balance)
    end

    # The fourth true state, and the one that is true for a different reason: :overdrawn prints the
    # balance NEGATED, which is still a reading of it — "overdrawn $80.00 · holds -$80.00" is one
    # number twice.
    it "is true on an overdrawn envelope, whose label prints the balance negated", :aggregate_failures do
      category = envelope("Dining Out")
      rule(category, :per_period_rate, amount: 400)
      spend(category, 80)
      status = category.status(today: today)

      expect(status.state).to eq(:overdrawn)
      expect(status.amount_is_balance?).to be(true)
      expect(status.amount).to eq(-status.balance)
    end
  end

  # The port of the account example, which was really about a holder with nothing claiming its
  # money: no rules, so no state above :left_to_spend can fire and the balance is spendable.
  describe "a category with no rules at all" do
    it "reads as left_to_spend" do
      category = envelope("Spare")

      expect(category.status(today: today).state).to eq(:left_to_spend)
    end
  end

  # Both readers run straight off HoldingCalculator#balance, which is aggregates over a `money`
  # column — and an empty sum returns the Integer literal 0. A category holding nothing is the
  # ordinary shape (a fresh envelope, a goal nobody has funded yet), and it is precisely the shape
  # that answered in the wrong type. `eq(0)` alone passes against the Integer, so the type is
  # asserted beside the value on each quiet state that reads the raw balance.
  describe "money types on a category with nothing in it at all", :aggregate_failures do
    it "reports a BigDecimal balance and amount on a rate envelope" do
      category = envelope("Groceries")
      rule(category, :per_period_rate, amount: 400)
      status = category.status(today: today)

      expect(status.state).to eq(:left_to_spend)
      expect(status.balance).to eq(0)
      expect(status.balance).to be_a(BigDecimal)
      expect(status.amount).to eq(0)
      expect(status.amount).to be_a(BigDecimal)
    end

    it "reports a BigDecimal amount on an unfunded goal" do
      status = goal("Vacation").status(today: today)

      expect(status.state).to eq(:saving)
      expect(status.amount).to be_a(BigDecimal)
    end
  end
end
