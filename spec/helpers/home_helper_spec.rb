# frozen_string_literal: true

require "rails_helper"

# Grid: biweekly from 2026-02-06. Today 2026-09-09 sits in Sep 4..Sep 17.
RSpec.describe HomeHelper, type: :helper do
  describe "#steady_words" do
    # A fund never catches up — the period that tops its pile off is still "full at the cap", not
    # "$X a period once caught up", even though that period's own per_period (50) is short of the
    # rule's ask (100).
    it "says a capped fund's steady figure is its cap, even in the period that fills it", :aggregate_failures do
      user = create(:user, :biweekly)
      pantry = create(:category, user: user, name: "Pantry")
      rule = create(:rule, :keeps_unspent, category: pantry, amount: 100, cap: 250, starts_on: Date.new(2026, 8, 7))
      calculator = ClaimCalculator.new(rule, today: Date.new(2026, 9, 9))
      line = ClaimRows.line_for(rule, calculator)

      expect(calculator.planned_this_period).to eq(50)
      expect(helper.steady_words(line)).to eq("full at $250.00")
    end
  end
end
