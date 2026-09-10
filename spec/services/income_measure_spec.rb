# frozen_string_literal: true

require "rails_helper"

RSpec.describe IncomeMeasure do
  let(:user) { create(:user, :biweekly) }
  let(:salary) { create(:category, :income, user: user, name: "Salary") }
  let(:bonus) { create(:category, :income, user: user, name: "Bonus") }
  let(:today) { Date.new(2026, 9, 9) }

  def earn(amount, on:, category: salary) = create(:entry, item: create(:item, category: category), amount: amount, date: on)

  describe "#periods and #typical" do
    it "sums the chosen categories' entries over the last two complete periods", :aggregate_failures do
      earn(1_000, on: Date.new(2026, 8, 7))
      earn(1_500, on: Date.new(2026, 8, 25))

      measure = described_class.new(user, category_ids: [salary.id], today: today)

      expect(measure.periods.map(&:range)).to eq(
        [Date.new(2026, 8, 7)..Date.new(2026, 8, 20), Date.new(2026, 8, 21)..Date.new(2026, 9, 3)]
      )
      expect(measure.periods.map(&:income)).to eq([1_000, 1_500])
      expect(measure.typical).to eq(1_250)
    end

    it "is nil with no complete period", :aggregate_failures do
      measure = described_class.new(user, category_ids: [salary.id], today: today)

      expect(measure.typical).to be_nil
      expect(measure.periods).to eq([])
    end

    it "ignores categories not in the given ids" do
      earn(1_000, on: Date.new(2026, 8, 7), category: salary)
      earn(5_000, on: Date.new(2026, 8, 7), category: bonus)

      measure = described_class.new(user, category_ids: [salary.id], today: today)

      expect(measure.periods.first.income).to eq(1_000)
    end
  end

  it "walks the probe's own typed cadence, not the saved user's", :aggregate_failures do
    # Saved user is biweekly; the probe types a monthly cadence, so the grid it walks is anchored
    # on the 15th, not Feb 6 — the saved user's own periods never come into it.
    probe = User.find(user.id)
    probe.assign_attributes(period_cadence: "monthly", period_anchor_date: Date.new(2026, 1, 15))

    # The first entry sits ON the older period's opening boundary — a period that only STARTS
    # after the first entry would not be complete history, so the walk stops one short of it.
    earn(2_000, on: Date.new(2026, 6, 15))
    earn(2_400, on: Date.new(2026, 7, 20))

    measure = described_class.new(probe, category_ids: [salary.id], today: today)

    expect(measure.periods.map(&:range)).to eq(
      [Date.new(2026, 6, 15)..Date.new(2026, 7, 14), Date.new(2026, 7, 15)..Date.new(2026, 8, 14)]
    )
    expect(measure.periods.map(&:income)).to eq([2_000, 2_400])
  end
end
