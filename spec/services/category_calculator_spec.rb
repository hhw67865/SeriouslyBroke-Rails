# frozen_string_literal: true

require "rails_helper"

# WHAT IS LEFT OF THIS FILE, AND WHY (plan 3, task 3).
#
# Every example here was about the monthly category CAP: the flat curve, the prorated daily ramp,
# `#budget_pace`, `#budget_pace_percentage` and `#budget_percentage`, each planting
# `create(:budget, category: ...)` as its fixture. A rule owned by a category is not a shape this
# app can hold any more, and the ramp is deleted with the `prorated` flag it read — so those
# examples are deleted WITH the behaviour rather than rewritten against a cap that cannot exist.
#
# WHAT REPLACES THEM IS THE FACT THE DASHBOARD BRIDGE STANDS ON: with no cap reachable, these
# readers answer their empty forms for every category, which is why `DashboardPresenter
# #enrich_with_budget` never fires and why the budget chart is empty until Task 4 replaces it. That
# is a claim about behaviour, so it is asserted rather than assumed.
RSpec.describe CategoryCalculator do
  let(:user) { create(:user) }
  let(:category) { create(:category, :expense, user: user, name: "Groceries") }
  let(:april1) { Date.new(2026, 4, 1) }

  describe "the cap readers, with no cap left to read" do
    it "has no budget to read at all" do
      expect(category.reload.budget).to be_nil
    end

    it "answers nil for the monthly rate and the effective budget", :aggregate_failures do
      calc = described_class.new(category.reload, april1, period: :monthly)

      expect(calc.monthly_budget_rate).to be_nil
      expect(calc.effective_budget).to be_nil
    end

    it "answers an empty curve in both periods", :aggregate_failures do
      expect(described_class.new(category.reload, april1, period: :monthly).budget_curve).to eq({})
      expect(described_class.new(category.reload, april1, period: :ytd).budget_curve).to eq({})
    end

    it "answers zero for the progress bar, however much was spent" do
      create(:entry, item: create(:item, category: category), amount: 200, date: Date.new(2026, 4, 10))

      expect(described_class.new(category.reload, april1, period: :monthly).budget_percentage).to eq(0)
    end
  end

  # THE SPENDING SIDE IS UNTOUCHED and is what the category page still reads, so it is pinned here
  # rather than left to the deleted cap examples' coverage.
  describe "#total_amount" do
    it "sums the category's entries over the month" do
      item = create(:item, category: category)
      create(:entry, item: item, amount: 200, date: Date.new(2026, 4, 10))
      create(:entry, item: item, amount: 45, date: Date.new(2026, 4, 28))
      create(:entry, item: item, amount: 99, date: Date.new(2026, 5, 1))

      expect(described_class.new(category.reload, april1, period: :monthly).total_amount).to eq(245)
    end

    it "sums from the start of the year in YTD view" do
      item = create(:item, category: category)
      create(:entry, item: item, amount: 30, date: Date.new(2026, 1, 9))
      create(:entry, item: item, amount: 70, date: Date.new(2026, 4, 10))

      expect(described_class.new(category.reload, april1, period: :ytd).total_amount).to eq(100)
    end
  end
end
