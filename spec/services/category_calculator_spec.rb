# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategoryCalculator do
  let(:user) { create(:user) }
  let(:category) { create(:category, :expense, user: user, name: "Groceries") }
  let(:april1) { Date.new(2026, 4, 1) }

  describe "#budget_curve" do
    context "with a flat (non-prorated) $300 budget in monthly view" do
      before { create(:budget, category: category, amount: 300) }

      it "returns every day of April mapping to the full $300 cap", :aggregate_failures do
        curve = described_class.new(category.reload, april1, period: :monthly).budget_curve
        expect(curve.size).to eq(30)
        expect(curve[april1]).to eq(300)
        expect(curve[Date.new(2026, 4, 15)]).to eq(300)
        expect(curve[Date.new(2026, 4, 30)]).to eq(300)
      end
    end

    context "with a prorated $300 budget in monthly view" do
      before { create(:budget, category: category, amount: 300, prorated: true) }

      it "ramps linearly from day 1 to day 30", :aggregate_failures do
        curve = described_class.new(category.reload, april1, period: :monthly).budget_curve
        expect(curve.size).to eq(30)
        expect(curve[april1]).to eq(10.0)
        expect(curve[Date.new(2026, 4, 15)]).to eq(150.0)
        expect(curve[Date.new(2026, 4, 30)]).to eq(300.0)
      end
    end

    context "when in YTD view (proration ignored)" do
      before { create(:budget, category: category, amount: 300, prorated: true) }

      it "returns an accumulating monthly series regardless of prorated flag", :aggregate_failures do
        curve = described_class.new(category.reload, april1, period: :ytd).budget_curve
        # Jan, Feb, Mar, Apr
        expect(curve.size).to eq(4)
        expect(curve[Date.new(2026, 1, 1)]).to eq(300)
        expect(curve[Date.new(2026, 4, 1)]).to eq(1200)
      end
    end

    context "without a budget" do
      it "returns empty hash" do
        expect(described_class.new(category, april1).budget_curve).to eq({})
      end
    end
  end

  describe "#budget_pace" do
    let(:april15) { Date.new(2026, 4, 15) }

    context "with a non-prorated budget" do
      before { create(:budget, category: category, amount: 300) }

      it "returns effective_budget (same as cap) in monthly view", :aggregate_failures do
        calc = described_class.new(category.reload, april1, period: :monthly)
        expect(calc.budget_pace(today: april15)).to eq(calc.effective_budget)
        expect(calc.budget_pace(today: april15)).to eq(300)
      end

      it "returns effective_budget in YTD view", :aggregate_failures do
        calc = described_class.new(category.reload, april1, period: :ytd)
        expect(calc.budget_pace(today: april15)).to eq(calc.effective_budget)
        expect(calc.budget_pace(today: april15)).to eq(1200)
      end
    end

    context "with a prorated budget in monthly view" do
      before { create(:budget, category: category, amount: 300, prorated: true) }

      it "returns ramp-to-today when viewing the current month" do
        calc = described_class.new(category.reload, april1, period: :monthly)
        expect(calc.budget_pace(today: april15)).to eq(150.0) # 300 * 15 / 30
      end

      it "returns the full cap when viewing a past month" do
        march1 = Date.new(2026, 3, 1)
        calc = described_class.new(category.reload, march1, period: :monthly)
        # "today" is April 15 — past the end of March, so pace fully accrued
        expect(calc.budget_pace(today: april15)).to eq(300)
      end

      it "returns 0 when viewing a future month" do
        may1 = Date.new(2026, 5, 1)
        calc = described_class.new(category.reload, may1, period: :monthly)
        # "today" is April 15 — before May starts, so pace hasn't accrued
        expect(calc.budget_pace(today: april15)).to eq(0)
      end
    end

    context "with a prorated budget in YTD view (proration ignored)" do
      before { create(:budget, category: category, amount: 300, prorated: true) }

      it "returns effective_budget" do
        calc = described_class.new(category.reload, april1, period: :ytd)
        expect(calc.budget_pace(today: april15)).to eq(calc.effective_budget)
      end
    end

    context "without a budget" do
      it "returns nil" do
        calc = described_class.new(category, april1)
        expect(calc.budget_pace(today: april15)).to be_nil
      end
    end
  end

  describe "#budget_percentage with prorated budget" do
    before { create(:budget, category: category, amount: 300, prorated: true) }

    it "divides spent by the full monthly cap (prorated flag does not change the progress bar)" do
      item = create(:item, category: category)
      create(:entry, item: item, amount: 200, date: Date.new(2026, 4, 10))
      calc = described_class.new(category.reload, april1, period: :monthly)

      # spent = 200, cap = 300. percentage = 200/300 * 100 = 67.
      expect(calc.budget_percentage).to eq(67)
    end
  end

  describe "#budget_pace_percentage" do
    let(:april15) { Date.new(2026, 4, 15) }

    it "matches budget_percentage for non-prorated budgets", :aggregate_failures do
      create(:budget, category: category, amount: 300)
      item = create(:item, category: category)
      create(:entry, item: item, amount: 200, date: Date.new(2026, 4, 10))
      calc = described_class.new(category.reload, april1, period: :monthly)

      expect(calc.budget_pace_percentage).to eq(calc.budget_percentage)
      expect(calc.budget_pace_percentage).to eq(67)
    end

    it "divides spent by the prorated pace for prorated budgets in the current month" do
      create(:budget, category: category, amount: 300, prorated: true)
      item = create(:item, category: category)
      create(:entry, item: item, amount: 200, date: Date.new(2026, 4, 10))
      calc = described_class.new(category.reload, april1, period: :monthly)

      # pace on day 15 = 300 * 15 / 30 = 150. spent = 200. percentage = 200/150 * 100 = 133.
      allow(Date).to receive(:current).and_return(april15)
      expect(calc.budget_pace_percentage).to eq(133)
    end

    it "returns 0 when pace is 0 (future month)" do
      create(:budget, category: category, amount: 300, prorated: true)
      may1 = Date.new(2026, 5, 1)
      calc = described_class.new(category.reload, may1, period: :monthly)

      allow(Date).to receive(:current).and_return(april15) # before May
      expect(calc.budget_pace_percentage).to eq(0)
    end

    it "returns 0 without a budget" do
      calc = described_class.new(category, april1)
      expect(calc.budget_pace_percentage).to eq(0)
    end
  end
end
