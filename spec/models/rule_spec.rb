# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rule do
  let(:user) { create(:user, :biweekly) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let(:bread) { create(:item, category: groceries, name: "Bread") }

  describe "shapes", :aggregate_failures do
    it "reads its shape and cadence off two columns" do
      expect(build(:rule, :rate).shape).to eq(:rate)
      expect(build(:rule, :keeps_unspent).shape).to eq(:fund)
      expect(build(:rule, :one_off).shape).to eq(:dated)
      expect(build(:rule, :rate).cadence).to eq(:per_period)
      expect(build(:rule, :one_off).cadence).to eq(:one_off)
      expect(build(:rule, :rolling).cadence).to eq(:every_n)
    end

    it "knows a goal: dated once, whole category, not a bill" do
      expect(build(:rule, :by_date, :choice).saving_toward_a_date?).to be(true)
      expect(build(:rule, :by_date, :bill).saving_toward_a_date?).to be(false)
      expect(build(:rule, :rolling, :choice).saving_toward_a_date?).to be(false)
      expect(build(:rule, :by_date, :choice, item: bread, category: groceries).saving_toward_a_date?).to be(false)
    end
  end

  describe "validations", :aggregate_failures do
    it "needs a positive amount, a start, a type and a positive interval" do
      expect(build(:rule, amount: 0)).not_to be_valid
      expect(build(:rule, starts_on: nil)).not_to be_valid
      expect(build(:rule, rule_type: nil)).not_to be_valid
      expect(build(:rule, :rolling, interval_months: 0)).not_to be_valid
    end

    it "only rules an expense category, with an item from that category" do
      expect(build(:rule, category: create(:category, :income, user: user))).not_to be_valid
      expect(build(:rule, category: groceries, item: create(:item))).not_to be_valid
      expect(build(:rule, category: groceries, item: bread)).to be_valid
    end

    it "allows one whole-category rule per category and one rule per item" do
      create(:rule, category: groceries)
      create(:rule, category: groceries, item: bread)

      second_whole = build(:rule, category: groceries)
      expect(second_whole).not_to be_valid
      expect(second_whole.errors[:base]).to include(Rule::CATCH_ALL_TAKEN)
      expect(build(:rule, category: groceries, item: bread)).not_to be_valid
    end

    it "never keeps and dates at once, and never has an interval without a date" do
      expect(build(:rule, :one_off, keeps_unspent: true)).not_to be_valid
      expect(build(:rule, :rate, interval_months: 3)).not_to be_valid
    end
  end

  describe "#steady_ask", :aggregate_failures do
    let(:today) { Date.new(2026, 9, 9) }

    it "is the amount for a per-period rule and the per-period share for a rolling one" do
      expect(build(:rule, :rate, amount: 300, category: groceries).steady_ask(today: today)).to eq(300)
      expect(build(:rule, :keeps_unspent, amount: 60, category: groceries).steady_ask(today: today)).to eq(60)
      # $600 every 6 months on a biweekly grid: 600 × 12 / (26 × 6)
      expect(build(:rule, :rolling, amount: 600, interval_months: 6, category: groceries).steady_ask(today: today)).to eq(46.15)
    end
  end

  describe ".sort_key" do
    it "puts dated rules first, soonest first, then the largest amount" do
      keys = [
        described_class.sort_key(next_due_on: nil, amount: 500, id: "b"),
        described_class.sort_key(next_due_on: Date.new(2026, 10, 1), amount: 100, id: "a"),
        described_class.sort_key(next_due_on: Date.new(2026, 9, 20), amount: 50, id: "c")
      ]

      expect(keys.sort.map(&:last)).to eq(["c", "a", "b"])
    end
  end

  it "ranks types choice, usage, bill" do
    expect([build(:rule, :bill), build(:rule, :choice), build(:rule, :usage)].sort_by(&:type_rank).map(&:rule_type))
      .to eq(["choice", "usage", "bill"])
  end
end
