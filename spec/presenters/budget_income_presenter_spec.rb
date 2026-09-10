# frozen_string_literal: true

require "rails_helper"

RSpec.describe BudgetIncomePresenter do
  let(:user) { create(:user, :biweekly) }
  let(:presenter) { described_class.new(user: user) }
  let(:salary) { create(:category, :income, user: user, name: "Salary") }

  before { create(:account, user: user, opening_balance: 1_000) }

  def earn(amount, on:) = create(:entry, item: create(:item, category: salary), amount: amount, date: on)

  around { |example| travel_to(Date.new(2026, 9, 9)) { example.run } }

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
end
