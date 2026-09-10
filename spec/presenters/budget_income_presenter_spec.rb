# frozen_string_literal: true

require "rails_helper"

RSpec.describe BudgetIncomePresenter do
  let(:user) { create(:user, :biweekly) }
  let!(:salary) { create(:category, :income, user: user, name: "Salary") }
  let!(:bonus) { create(:category, :income, :irregular, user: user, name: "Bonus") }

  before { create(:account, user: user, opening_balance: 1_000) }

  def earn(amount, on:, category: salary) = create(:entry, item: create(:item, category: category), amount: amount, date: on)

  around { |example| travel_to(Date.new(2026, 9, 9)) { example.run } }

  describe "off the saved state (no declaration, no chosen ids)" do
    let(:presenter) { described_class.new(user: user) }

    it "yields the two complete periods with their regular income", :aggregate_failures do
      earn(1_000, on: Date.new(2026, 8, 7))
      earn(1_500, on: Date.new(2026, 8, 25))

      ranges = presenter.periods.map(&:range)
      expect(ranges).to eq([Date.new(2026, 8, 7)..Date.new(2026, 8, 20), Date.new(2026, 8, 21)..Date.new(2026, 9, 3)])
      expect(presenter.periods.map(&:income)).to eq([1_000, 1_500])
      expect(presenter).to be_history
    end

    it "has no history with no complete period", :aggregate_failures do
      expect(presenter.periods).to eq([])
      expect(presenter).not_to be_history
    end

    it "checks a category from its saved regular flag", :aggregate_failures do
      expect(presenter.checked?(salary)).to be true
      expect(presenter.checked?(bonus)).to be false
    end

    it "is declared and has a valid period from the saved cadence", :aggregate_failures do
      expect(presenter).to be_declared
      expect(presenter).to be_valid_period
    end
  end

  describe "off a typed selection" do
    it "checks only the given category ids, regardless of what is saved", :aggregate_failures do
      presenter = described_class.new(user: user, category_ids: [bonus.id])

      expect(presenter.checked?(salary)).to be false
      expect(presenter.checked?(bonus)).to be true
    end
  end

  describe "off a typed but unsaved declaration" do
    it "measures off the typed cadence, not the saved one" do
      earn(2_000, on: Date.new(2026, 6, 15))
      earn(2_400, on: Date.new(2026, 7, 20))

      presenter = described_class.new(
        user: user,
        typed: { period_cadence: "monthly", period_anchor_date: Date.new(2026, 1, 15) },
        category_ids: [salary.id]
      )

      expect(presenter.periods.map(&:range)).to eq(
        [Date.new(2026, 6, 15)..Date.new(2026, 7, 14), Date.new(2026, 7, 15)..Date.new(2026, 8, 14)]
      )
    end

    it "is not declared with a blank cadence, and a blank cadence counts as a valid period", :aggregate_failures do
      presenter = described_class.new(user: user, typed: { period_cadence: "", period_anchor_date: "" })

      expect(presenter).not_to be_declared
      expect(presenter).to be_valid_period
    end

    it "is declared but not a valid period with a cadence and no anchor", :aggregate_failures do
      presenter = described_class.new(user: user, typed: { period_cadence: "monthly", period_anchor_date: "" })

      expect(presenter).to be_declared
      expect(presenter).not_to be_valid_period
    end

    it "renders a probe carrying the typed values and their errors, leaving the user untouched", :aggregate_failures do
      presenter = described_class.new(user: user, typed: { period_cadence: "monthly", period_anchor_date: "" })

      expect(presenter.declaration).not_to equal(user)
      expect(presenter.declaration.period_cadence).to eq("monthly")
      expect(presenter.declaration.errors[:period_anchor_date]).to be_present
      expect(user.reload.period_anchor_date).to be_present
    end
  end
end
