# frozen_string_literal: true

require "rails_helper"

# WHAT IS LEFT OF THIS FILE, AND WHY.
#
# Task 3 deleted the cap FIXTURES (`create(:budget, category: ...)` is not a shape this app can
# hold) and left four examples asserting that `#monthly_budget_rate`, `#effective_budget`,
# `#budget_curve` and `#budget_percentage` answered their empty forms — the fact the dashboard's
# bridge stood on. Task 4 deletes the four readers themselves, so those four examples go with the
# behaviour: there is nothing left to answer nil.
#
# `#monthly_contribution` went too, and it was `#total_amount` behind a `category.savings?` gate —
# so `#total_amount` below is now the only reader of a category's spend in a period, which is what
# the category page, the category cards and every dashboard breakdown read.
RSpec.describe CategoryCalculator do
  let(:user) { create(:user) }
  let(:category) { create(:category, :expense, user: user, name: "Groceries") }
  let(:april1) { Date.new(2026, 4, 1) }

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
