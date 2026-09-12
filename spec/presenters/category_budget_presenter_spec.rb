# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategoryBudgetPresenter do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let(:ledger) { ClaimLedger.new(user, today: today) }
  let(:presenter) { described_class.new(category: groceries, claims: ledger, rows: ClaimRows.new(ledger: ledger, today: today), today: today) }

  before { create(:account, user: user) }

  it "is unruled with no rules", :aggregate_failures do
    expect(presenter).not_to be_ruled
    expect(presenter.claim).to eq(0)
    expect(presenter.lines).to be_empty
    expect(presenter).not_to be_fund
  end

  it "sums its rules' claims and finds a goal among them", :aggregate_failures do
    create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1))
    goal = create(:rule, :choice, amount: 600, anchor_date: Date.new(2026, 10, 15), item: create(:item, category: groceries), category: groceries, starts_on: Date.new(2026, 8, 1))

    expect(presenter).to be_ruled
    expect(presenter.claim).to eq(800)
    expect(presenter).to be_fund
    expect(presenter.fund_rule).to eq(goal)
    expect(presenter).not_to be_fund_is_the_only_rule
    expect(presenter.target).to be_nil
  end

  # A rule that repeats is a recurring cost, not a figure being saved toward, so the card has no goal.
  it "does not read a rolling rule as the category's goal", :aggregate_failures do
    create(:rule, :rolling, :choice, amount: 600, anchor_date: Date.new(2026, 10, 15), category: groceries, starts_on: Date.new(2026, 8, 1))

    expect(presenter).to be_ruled
    expect(presenter).not_to be_fund
    expect(presenter.fund_line).to be_nil
  end

  it "shows a progress bar when the goal is the category's only rule", :aggregate_failures do
    create(:rule, :choice, amount: 600, anchor_date: Date.new(2026, 10, 15), category: groceries, starts_on: Date.new(2026, 8, 1))

    expect(presenter).to be_fund_is_the_only_rule
    expect(presenter.target).to eq(600)
    expect(presenter.fund_figure).to eq(400)
    expect(presenter.progress_percentage).to eq(67)
    expect(presenter).to be_bar
  end
end
