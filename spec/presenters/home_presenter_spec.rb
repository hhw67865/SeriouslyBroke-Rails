# frozen_string_literal: true

require "rails_helper"

RSpec.describe HomePresenter do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6), typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking", target_amount: 2_000) }
  let(:today) { Date.new(2026, 2, 6) }
  let(:presenter) { described_class.new(user: user, today: today) }

  def envelope(name, priority:)
    create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
  end

  def savings_goal(name, priority:, target: 1_200)
    create(:pool, :savings_pool, user: user, account: checking, name: name, target_amount: target, priority: priority)
  end

  describe "#accounts" do
    it "returns only this user's accounts, by name", :aggregate_failures do
      savings_account = create(:pool, :account, user: user, name: "Ally")
      envelope("Groceries", priority: 1)
      create(:pool, :account, user: create(:user), name: "Someone Else")

      expect(presenter.accounts).to eq([savings_account, checking])
      expect(presenter.accounts.map(&:name)).to eq(["Ally", "Checking"])
    end
  end

  describe "#pools_for" do
    it "returns the account's own pools by priority then name, and no others", :aggregate_failures do
      other_account = create(:pool, :account, user: user, name: "Ally")
      # Reverse alphabetical at a shared priority, so the name tie-break is visible.
      zoo = envelope("Zoo", priority: 1)
      apples = envelope("Apples", priority: 1)
      later = envelope("Later", priority: 2)
      elsewhere = create(:pool, :budget_pool, user: user, account: other_account, name: "Elsewhere", priority: 0)

      expect(presenter.pools_for(checking)).to eq([apples, zoo, later])
      expect(presenter.pools_for(other_account)).to eq([elsewhere])
    end
  end

  describe "#status_for" do
    let(:dentist) do
      pool = envelope("Dentist", priority: 1)
      create(:pool_budget, :one_time, pool: pool, amount: 300, anchor_date: Date.new(2026, 2, 14))
      pool
    end

    # The whole reason this method exists. Asserted in BOTH directions: the second
    # expectation proves a bare `pool.status` genuinely disagrees on this data, so
    # the first is pinning the injected day rather than passing by coincidence.
    it "computes against the injected day, not Date.current", :aggregate_failures do
      travel_to(Date.new(2026, 2, 20)) do
        expect(presenter.status_for(dentist).state).to eq(:wont_make_it)
        expect(dentist.status.state).not_to eq(:wont_make_it)
      end
    end

    it "memoises per pool so a row does not rebuild its status" do
      first_call = presenter.status_for(dentist)

      expect(presenter.status_for(dentist)).to be(first_call)
    end

    it "keeps distinct pools on distinct statuses", :aggregate_failures do
      quiet = envelope("Groceries", priority: 2)
      create(:pool_budget, :per_paycheck_rate, pool: quiet, amount: 100)

      expect(presenter.status_for(dentist)).not_to be(presenter.status_for(quiet))
      expect(presenter.status_for(quiet).state).not_to eq(:wont_make_it)
    end
  end

  describe "#available" do
    it "is the account's unclaimed cash" do
      income_category = create(:category, :income, user: user, pool: checking)
      create(:entry, item: create(:item, category: income_category), amount: 2_400, date: today)

      expect(presenter.available).to eq(2_400)
    end

    # Documents a real consequence rather than asserting it is desirable: see the
    # report for Task 4. An overdraft in one account reduces what Home says is
    # available to fund envelopes that live in a different, healthy account.
    it "nets an overdrawn account against a healthy one", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")
      income_category = create(:category, :income, user: user, pool: checking)
      create(:entry, item: create(:item, category: income_category), amount: 1_000, date: today)
      overdraft = create(:category, :expense, user: user, pool: ally, name: "Ally fees")
      create(:entry, item: create(:item, category: overdraft), amount: 400, date: today)

      expect(presenter.buffer_for(checking)).to eq(1_000)
      expect(presenter.buffer_for(ally)).to eq(-400)
      expect(presenter.available).to eq(600)
    end

    it "is a decimal zero, not an integer, for a user with nothing", :aggregate_failures do
      expect(presenter.available).to eq(0)
      expect(presenter.available).to be_a(BigDecimal)
      expect(presenter.buffer_for(checking)).to be_a(BigDecimal)
    end
  end

  describe "#total_required" do
    it "sums what every pool needs this period" do
      groceries = envelope("Groceries", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: groceries, amount: 400)
      gas = envelope("Gas", priority: 2)
      create(:pool_budget, :per_paycheck_rate, pool: gas, amount: 80)

      expect(presenter.total_required).to eq(480)
    end

    it "counts savings goals alongside budget envelopes", :aggregate_failures do
      groceries = envelope("Groceries", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: groceries, amount: 400)
      vacation = savings_goal("Vacation", priority: 2)
      create(:pool_budget, :per_paycheck_rate, pool: vacation, amount: 150)

      expect(presenter.total_required).to eq(550)
      expect(presenter.waterfall.map { |r| r[:pool].name }).to eq(["Groceries", "Vacation"])
    end

    it "is a decimal zero, not an integer, for a user with no pools", :aggregate_failures do
      expect(presenter.total_required).to eq(0)
      expect(presenter.total_required).to be_a(BigDecimal)
      expect(presenter.shortfall).to be_a(BigDecimal)
    end
  end

  describe "#waterfall" do
    before do
      rent = envelope("Rent", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: rent, amount: 500)
      food = envelope("Groceries", priority: 2)
      create(:pool_budget, :per_paycheck_rate, pool: food, amount: 400)
      vacation = envelope("Vacation", priority: 3)
      create(:pool_budget, :per_paycheck_rate, pool: vacation, amount: 150)

      income_category = create(:category, :income, user: user, pool: checking)
      create(:entry, item: create(:item, category: income_category), amount: 700, date: today)
    end

    it "fills top-down by priority and marks the cutoff", :aggregate_failures do
      rows = presenter.waterfall

      expect(rows.map { |r| r[:pool].name }).to eq(["Rent", "Groceries", "Vacation"])
      expect(rows[0][:funded]).to eq(500)
      expect(rows[1][:funded]).to eq(200)
      expect(rows[2][:funded]).to eq(0)
    end

    it "records each row's shortfall", :aggregate_failures do
      rows = presenter.waterfall

      expect(rows[0][:short]).to eq(0)
      expect(rows[1][:short]).to eq(200)
      expect(rows[2][:short]).to eq(150)
    end

    it "reports the total gap", :aggregate_failures do
      expect(presenter.shortfall).to eq(350)
      expect(presenter).not_to be_covered
    end

    it "records what each row asked for, funded or not", :aggregate_failures do
      rows = presenter.waterfall

      expect(rows.pluck(:needed)).to eq([500, 400, 150])
      # `needed` is the ask, never the outcome: the cut-off row must still state its
      # full requirement, or the screen cannot show what running out actually cost.
      expect(rows.map { |r| r[:needed] - r[:funded] }).to eq(rows.pluck(:short))
    end
  end

  # Separate from the block above because that one's `before` fixes three distinct
  # priorities, which is exactly the shape that cannot see a tie-break at all.
  describe "#waterfall priority ties" do
    it "breaks a tie by name so the same data funds the same pool every load", :aggregate_failures do
      # Written in reverse alphabetical order on purpose: the pools query carries no
      # ORDER BY, so the database hands these back in insertion order and a sort on
      # priority alone would fund Zoo first for no reason the user can see.
      zoo = envelope("Zoo", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: zoo, amount: 300)
      apples = envelope("Apples", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: apples, amount: 300)

      income_category = create(:category, :income, user: user, pool: checking)
      create(:entry, item: create(:item, category: income_category), amount: 300, date: today)

      rows = presenter.waterfall

      expect(rows.map { |r| r[:pool].name }).to eq(["Apples", "Zoo"])
      # Keyed by name rather than by row index: the tie is not cosmetic, it decides
      # which envelope the money actually reaches, and a positional assertion would
      # hold just as well with the two pools swapped.
      expect(rows.to_h { |r| [r[:pool].name, r[:funded]] }).to eq("Apples" => 300, "Zoo" => 0)
    end
  end

  describe "#waterfall with an overdrawn user" do
    # `remaining.clamp(0.to_d, needed)` is the guard: a negative `remaining` would
    # otherwise raise ArgumentError on `clamp(0, negative)` the way PoolCalculator's
    # draft did, turning the whole Home screen into a 500 for the users most in need
    # of reading it.
    it "funds nothing and still states every ask", :aggregate_failures do
      overdraft = create(:category, :expense, user: user, pool: checking, name: "Fees")
      create(:entry, item: create(:item, category: overdraft), amount: 500, date: today)
      rent = envelope("Rent", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: rent, amount: 300)

      rows = presenter.waterfall

      expect(presenter.available).to eq(-500)
      expect(rows.pluck(:funded)).to eq([0])
      expect(rows.pluck(:short)).to eq([300])
      # The overdraft is part of the gap: you have to climb out of it before a
      # single envelope can be filled.
      expect(presenter.shortfall).to eq(800)
      expect(presenter).not_to be_covered
    end
  end

  describe "#covered?" do
    it "is true when available meets the requirement", :aggregate_failures do
      groceries = envelope("Groceries", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: groceries, amount: 100)
      income_category = create(:category, :income, user: user, pool: checking)
      create(:entry, item: create(:item, category: income_category), amount: 500, date: today)

      expect(presenter).to be_covered
      expect(presenter.shortfall).to eq(0)
    end
  end

  describe "#attention_pools" do
    it "returns only pools whose status needs attention" do
      quiet = envelope("Groceries", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: quiet, amount: 100)
      create(:pool_movement, from_pool: checking, to_pool: quiet, amount: 100)

      loud = envelope("Dentist", priority: 2)
      create(:pool_budget, :one_time, pool: loud, amount: 300, anchor_date: Date.new(2026, 2, 14))

      expect(presenter.attention_pools.map(&:name)).to eq(["Dentist"])
    end

    it "lists them by priority, then name" do
      # Created in the reverse of the expected order, so insertion order alone cannot
      # produce the answer: `all_pools` has no ORDER BY and Postgres hands rows back in
      # heap order, which a plain UPDATE relocates.
      [["Zoo", 2], ["Apples", 2], ["Urgent", 1]].each do |name, priority|
        pool = envelope(name, priority: priority)
        create(:pool_budget, :one_time, pool: pool, amount: 300, anchor_date: Date.new(2026, 2, 14))
      end

      expect(presenter.attention_pools.map(&:name)).to eq(["Urgent", "Apples", "Zoo"])
    end
  end

  describe "#structurally_underwater?" do
    it "is true when the rules need more than typical income" do
      big = envelope("Rent", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: big, amount: 3_000)

      expect(presenter).to be_structurally_underwater
    end

    it "is false when they fit" do
      small = envelope("Rent", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: small, amount: 500)

      expect(presenter).not_to be_structurally_underwater
    end

    # The boundary the `>` sits on. Rules that consume the declared income exactly are
    # not a structural problem — there is nothing reallocation could not still fix —
    # so this must not fire, and a `>=` here would tell a user their budget is
    # impossible on the day it balances.
    it "is false when the rules land exactly on typical income", :aggregate_failures do
      exact = envelope("Rent", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: exact, amount: 2_400)

      expect(presenter.total_required).to eq(user.typical_income)
      expect(presenter).not_to be_structurally_underwater
    end

    it "is false when typical income is unset" do
      user.update!(typical_income: nil)
      big = envelope("Rent", priority: 1)
      create(:pool_budget, :per_paycheck_rate, pool: big, amount: 3_000)

      expect(presenter).not_to be_structurally_underwater
    end
  end
end
