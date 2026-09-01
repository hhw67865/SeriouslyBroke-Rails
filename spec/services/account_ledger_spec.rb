# frozen_string_literal: true

require "rails_helper"

# THE PHYSICAL LEDGER'S READER (spec §2): the pot is main checking — income minus every expense,
# plus and minus what has been moved between accounts. Other accounts are movement-fed ONLY, and
# each mirrors its bank statement.
RSpec.describe AccountLedger, type: :model do
  let(:user) { create(:user) }
  let!(:main) { create(:pool, :account, user: user, name: "Checking") }
  let(:ally) { create(:pool, :account, user: user, name: "Ally") }
  let(:ledger) { described_class.new(user) }

  before { user.update!(default_account: main) }

  def spend(amount, on: Date.new(2026, 8, 7), category: create(:category, :expense, user: user))
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  def earn(amount, on: Date.new(2026, 8, 5))
    create(:entry, item: create(:item, category: create(:category, :income, user: user)), amount: amount, date: on)
  end

  def move(from:, to:, amount:, on: Time.zone.parse("2026-08-08 12:00"))
    create(:pool_movement, from_pool: from, to_pool: to, amount: amount, date: on)
  end

  describe "#pot" do
    it "is income, less every expense, less what has been moved out to another account" do
      earn(1000)
      spend(75)
      move(from: main, to: ally, amount: 200)

      expect(ledger.pot).to eq(725)
    end

    it "rises by what comes back from another account" do
      earn(1000)
      move(from: main, to: ally, amount: 200)
      move(from: ally, to: main, amount: 50, on: Time.zone.parse("2026-08-09 12:00"))

      expect(ledger.pot).to eq(850)
    end

    # EVERY EXPENSE LEAVES CHECKING (§2), whatever category it names — there is no "paid from"
    # lane, and a savings category's spending is no exception. The purpose ledger is the only
    # place a category's name changes anything.
    it "counts an expense in a funded category exactly like any other" do
      earn(500)
      spend(60, category: create(:category, :expense, :funded, user: user, name: "Food"))

      expect(ledger.pot).to eq(440)
    end

    # A LEGACY ENVELOPE IS NOT A PLACE MONEY SITS. Task 1's migration converted the pool movements
    # with a non-account end into allocations, but a pool layer still exists until Task 8 — and a
    # movement into a budget pool must not lower the pot, or the physical ledger would count an
    # act of intention as an act of location.
    it "ignores a movement into a pool that is not an account" do
      earn(300)
      envelope = create(:pool, :budget_pool, user: user, account: main, name: "Groceries")
      move(from: main, to: envelope, amount: 120)

      expect(ledger.pot).to eq(300)
    end

    it "is a decimal zero for a user with nothing at all", :aggregate_failures do
      expect(ledger.pot).to eq(0)
      expect(ledger.pot).to be_a(BigDecimal)
    end
  end

  describe "#balance_of" do
    it "is movements in less movements out, and nothing else" do
      earn(1000)
      spend(75)
      move(from: main, to: ally, amount: 200)
      move(from: ally, to: main, amount: 50, on: Time.zone.parse("2026-08-09 12:00"))

      expect(ledger.balance_of(ally)).to eq(150)
    end

    it "is zero for an account no money has ever moved into" do
      earn(1000)
      spend(75)

      expect(ledger.balance_of(ally)).to eq(0)
    end

    it "answers for main the same figure #pot does" do
      earn(400)
      move(from: main, to: ally, amount: 100)

      expect(ledger.balance_of(main)).to eq(ledger.pot)
    end

    # A pool that is not an account has no physical balance to report, and zero would be a wrong
    # money figure rather than an absent one.
    it "refuses a pool that is not an account" do
      envelope = create(:pool, :budget_pool, user: user, account: main, name: "Groceries")

      expect { ledger.balance_of(envelope) }.to raise_error(described_class::NotAnAccount, /Groceries/)
    end

    it "refuses another user's account" do
      theirs = create(:pool, :account, user: create(:user), name: "Their Bank")

      expect { ledger.balance_of(theirs) }.to raise_error(described_class::NotAnAccount, /Their Bank/)
    end
  end

  # THE PHYSICAL HALF OF THE INVARIANT, over both accounts at once.
  it "partitions bank truth across the accounts" do
    earn(1000)
    spend(75)
    move(from: main, to: ally, amount: 200)

    expect(ledger.pot + ledger.balance_of(ally)).to eq(925)
  end

  # `PoolCalculator#income_within`'s semantics on the physical side: what arrived in the pot inside
  # a window. The distribute screen names this figure separately from the balance it is part of.
  describe "#income_within" do
    it "sums the income entries inside the range and no others", :aggregate_failures do
      earn(600, on: Date.new(2026, 8, 5))
      earn(40, on: Date.new(2026, 7, 20))
      spend(90, on: Date.new(2026, 8, 6))

      window = Time.zone.parse("2026-08-01 00:00")..Time.zone.parse("2026-08-31 23:59")
      expect(ledger.income_within(window)).to eq(600)
      expect(ledger.income_within(window)).to be_a(BigDecimal)
    end

    it "ignores another user's income" do
      stranger = create(:user)
      create(:pool, :account, user: stranger, name: "Their Checking")
      create(
        :entry,
        item: create(:item, category: create(:category, :income, user: stranger)),
        amount: 999,
        date: Date.new(2026, 8, 5)
      )

      window = Time.zone.parse("2026-08-01 00:00")..Time.zone.parse("2026-08-31 23:59")
      expect(ledger.income_within(window)).to eq(0)
    end
  end
end
