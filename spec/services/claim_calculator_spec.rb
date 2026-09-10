# frozen_string_literal: true

require "rails_helper"

# Grid: biweekly from 2026-02-06. Today 2026-09-09 sits in Sep 4..Sep 17. Earlier periods:
# Jul 24..Aug 6, Aug 7..Aug 20, Aug 21..Sep 3.
RSpec.describe ClaimCalculator do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let(:bread) { create(:item, category: groceries, name: "Bread") }

  def spend(amount, on:) = create(:entry, item: bread, amount: amount, date: on)

  def calculator(rule) = described_class.new(rule, today: today)

  describe "a rate rule" do
    let(:rule) { create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1)) }

    it "claims the amount less this period's spending, never below zero", :aggregate_failures do
      spend(310, on: Date.new(2026, 9, 5))
      spend(999, on: Date.new(2026, 9, 1)) # last period: does not count

      expect(calculator(rule).claim).to eq(90)
      expect(calculator(rule).spent_this_period).to eq(310)
      expect(calculator(rule).accrued_this_period).to eq(400)
      expect(calculator(rule).planned_this_period).to eq(400)
      expect(calculator(rule).standing_ask).to eq(400)
      expect(calculator(rule)).not_to be_over
    end

    it "takes adjustments this period and reports overspending", :aggregate_failures do
      spend(310, on: Date.new(2026, 9, 5))
      create(:adjustment, rule: rule, amount: -100, date: Date.new(2026, 9, 6))

      expect(calculator(rule).claim).to eq(0)
      expect(calculator(rule).raw_rate).to eq(-10)
      expect(calculator(rule)).to be_over
      expect(calculator(rule).over_by).to eq(10)
      expect(calculator(rule).next_due_on).to be_nil
    end

    it "counts only this period, from its start or from the rule's start", :aggregate_failures do
      expect(calculator(rule).countable_span).to eq(Date.new(2026, 9, 4)..today)
      late = create(:rule, :rate, amount: 100, category: create(:category, user: user), starts_on: Date.new(2026, 9, 7))
      expect(calculator(late).countable_span).to eq(Date.new(2026, 9, 7)..today)
    end
  end

  describe "a fund rule" do
    let(:rule) { create(:rule, :keeps_unspent, amount: 60, category: groceries, starts_on: Date.new(2026, 8, 1)) }

    it "adds the amount every period and keeps what is unspent", :aggregate_failures do
      # Periods since Aug 1: Jul 24, Aug 7, Aug 21, Sep 4 = four.
      expect(calculator(rule).claim).to eq(240)
      expect(calculator(rule).built_up).to eq(240)
      expect(calculator(rule).planned_this_period).to eq(60)
      expect(calculator(rule).standing_ask).to eq(60)
      expect(calculator(rule).target).to be_nil

      spend(100, on: Date.new(2026, 8, 25))
      expect(calculator(rule).claim).to eq(140)
      expect(calculator(rule).accrued_this_period).to eq(60)
    end

    it "never goes negative, and says over when spending outruns it", :aggregate_failures do
      spend(300, on: Date.new(2026, 9, 5))

      expect(calculator(rule).claim).to eq(0)
      expect(calculator(rule)).to be_over
      expect(calculator(rule).over_by).to eq(60)
    end
  end

  describe "a dated one-off rule" do
    let(:rule) { create(:rule, :bill, amount: 600, anchor_date: Date.new(2026, 10, 15), category: groceries, starts_on: Date.new(2026, 8, 1)) }

    it "plans an even share per period toward the target", :aggregate_failures do
      # Six boundaries from Jul 24 to Oct 15 (Jul 24, Aug 7, Aug 21, Sep 4, Sep 18, Oct 2): $100 a period.
      expect(calculator(rule).standing_ask).to eq(100)
      expect(calculator(rule).claim).to eq(400)
      expect(calculator(rule).built_up).to eq(400)
      expect(calculator(rule).planned_this_period).to eq(100)
      expect(calculator(rule).periods_left).to eq(3)
      expect(calculator(rule).next_due_on).to eq(Date.new(2026, 10, 15))
      expect(calculator(rule).target).to eq(600)
      expect(calculator(rule)).not_to be_overdue
      expect(calculator(rule)).not_to be_settled
    end

    it "settles once paid", :aggregate_failures do
      spend(600, on: Date.new(2026, 9, 5))

      expect(calculator(rule)).to be_settled
      expect(calculator(rule).settled_on).to eq(Date.new(2026, 9, 5))
      expect(calculator(rule).claim).to eq(0)
    end

    it "is overdue past its date until paid" do
      overdue = create(:rule, :bill, amount: 100, anchor_date: Date.new(2026, 9, 1), category: create(:category, user: user), starts_on: Date.new(2026, 8, 1))

      expect(calculator(overdue)).to be_overdue
    end

    it "caps a set-aside at the target and takes it back with a negative adjustment", :aggregate_failures do
      create(:adjustment, rule: rule, amount: 500, date: Date.new(2026, 9, 5))
      expect(calculator(rule).claim).to eq(600)

      create(:adjustment, rule: rule, amount: -500, date: Date.new(2026, 9, 6))
      expect(calculator(rule).claim).to eq(400)
    end
  end

  describe "a rolling rule" do
    let(:rule) { create(:rule, :bill, amount: 180, anchor_date: Date.new(2026, 3, 1), interval_months: 6, category: groceries, starts_on: Date.new(2026, 1, 1)) }

    it "advances the due date by one interval for each target paid", :aggregate_failures do
      expect(calculator(rule).next_due_on).to eq(Date.new(2026, 3, 1))
      expect(calculator(rule)).to be_overdue

      spend(180, on: Date.new(2026, 3, 2))
      expect(calculator(rule).next_due_on).to eq(Date.new(2026, 9, 1))

      spend(180, on: Date.new(2026, 9, 2))
      expect(calculator(rule).next_due_on).to eq(Date.new(2027, 3, 1))
      expect(calculator(rule)).not_to be_overdue
    end

    it "asks per period what the rule asks" do
      expect(calculator(rule).standing_ask).to eq(rule.steady_ask(today: today)).and eq(13.85)
    end

    # One cycle paid, the next saved for in full. The walk, period by period:
    #
    #   period      due     left  planned  built_up
    #   Dec 26      Mar 1      5    36.00     36.00
    #   Jan 9       Mar 1      4    36.00     72.00
    #   Jan 23      Mar 1      3    36.00    108.00
    #   Feb 6       Mar 1      2    36.00    144.00
    #   Feb 20      Mar 1      1    36.00      0.00  (180 accrued, 180 spent on Mar 2)
    #   Mar 6       Sep 1     13    13.85     13.85
    #   Mar 20 .. Aug 7, twelve more periods, 13.84 or 13.85 each
    #   Aug 21      Sep 1      1    13.84    180.00
    #   Sep 4       Sep 1      1     0.00    180.00  (the gap is closed)
    it "saves the next cycle in full once the first is paid", :aggregate_failures do
      spend(180, on: Date.new(2026, 3, 2))

      expect(calculator(rule).next_due_on).to eq(Date.new(2026, 9, 1))
      expect(calculator(rule).claim).to eq(180)
      expect(calculator(rule).built_up).to eq(180)
      expect(calculator(rule).planned_this_period).to eq(0)
    end
  end

  describe "a user with no cadence" do
    let(:plain) { create(:user) }
    let(:rule) do
      create(:rule, :bill, amount: 1_200, anchor_date: Date.new(2027, 3, 15), category: create(:category, user: plain), starts_on: Date.new(2026, 9, 1))
    end

    it "spreads a one-off over the calendar months to its date", :aggregate_failures do
      # Month firsts from Sep 1 2026 to Mar 15 2027 are seven, so 1200 / 7 = 171.43 a month.
      expect(calculator(rule).standing_ask).to eq(171.43)
      expect(calculator(rule).claim).to eq(171.43)
      expect(calculator(rule).planned_this_period).to eq(171.43)
    end
  end

  describe "a rule that starts in the future" do
    it "claims nothing and counts nothing yet", :aggregate_failures do
      rule = create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 10, 1))

      expect(calculator(rule).claim).to eq(0)
      expect(calculator(rule).planned_this_period).to eq(0)
      expect(calculator(rule).countable_span).to be_none
    end
  end

  describe "given rows" do
    it "uses the rows it is handed instead of querying", :aggregate_failures do
      rule = create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1))
      spend(310, on: Date.new(2026, 9, 5))

      handed = described_class.new(rule, today: today, spending: [[Date.new(2026, 9, 5), 50.to_d]], adjustments: [])
      expect(handed.claim).to eq(350)
    end
  end

  describe "#counted_entries" do
    it "sums to spent_this_period for a rate rule, off entries in its lane, its period and since it started", :aggregate_failures do
      rule = create(:rule, :rate, amount: 400, category: groceries, item: bread, starts_on: Date.new(2026, 9, 5))
      create(:entry, item: bread, amount: 20, date: Date.new(2026, 9, 4)) # before starts_on
      spend(310, on: Date.new(2026, 9, 6)) # in the lane, in the period, since it started
      other_item = create(:item, category: groceries, name: "Milk")
      create(:entry, item: other_item, amount: 50, date: Date.new(2026, 9, 6)) # another item

      expect(calculator(rule).counted_entries.sum(:amount)).to eq(310)
      expect(calculator(rule).counted_entries.sum(:amount)).to eq(calculator(rule).spent_this_period)
    end

    it "excludes an item's own entries from a whole-category rule's lane", :aggregate_failures do
      whole = create(:rule, :rate, amount: 300, category: groceries, starts_on: Date.new(2026, 1, 1))
      create(:rule, :rate, amount: 100, category: groceries, item: bread, starts_on: Date.new(2026, 1, 1))
      milk = create(:item, category: groceries, name: "Milk")
      create(:entry, item: milk, amount: 40, date: Date.new(2026, 9, 5))
      create(:entry, item: bread, amount: 60, date: Date.new(2026, 9, 5))

      expect(calculator(whole).counted_entries.pluck(:item_id)).to eq([milk.id])
      expect(calculator(whole).counted_entries.sum(:amount)).to eq(calculator(whole).spent_this_period)
    end
  end
end
