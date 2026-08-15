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

  def spend(pool, amount, name: "Something")
    category = create(:category, :expense, user: user, name: "#{pool.name} spend", pool: pool)
    create(:entry, item: create(:item, category: category, name: name), amount: amount, date: today)
  end

  # An item is the only fulfillment signal BudgetCalculator#overdue? accepts, so
  # every example that needs an overdue rule has to route through here.
  def bill_rule(pool, name, amount:, anchor_date:)
    category = create(:category, :expense, user: user, name: "#{pool.name} bills", pool: pool)
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

    it "is false for on_track and left_to_spend", :aggregate_failures do
      expect(described_class::ATTENTION_STATES).not_to include(:on_track)
      expect(described_class::ATTENTION_STATES).not_to include(:left_to_spend)
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
end
