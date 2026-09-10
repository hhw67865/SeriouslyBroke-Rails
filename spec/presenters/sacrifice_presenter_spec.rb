# frozen_string_literal: true

require "rails_helper"

RSpec.describe SacrificePresenter do
  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:presenter) { described_class.new(user: user, today: today) }
  let(:salary) { create(:category, :income, user: user, name: "Salary") }

  # Two periods of $1,000, because typical income averages COMPLETE periods that begin on or after
  # the first entry — one entry inside the previous period completes none and reads nil.
  before do
    create(:account, user: user)
    [Date.new(2026, 8, 7), Date.new(2026, 8, 25)].each do |on|
      create(:entry, item: create(:item, category: salary), amount: 1_000, date: on)
    end
  end

  def rule_on(name, *traits, **attributes)
    create(:rule, *traits, category: create(:category, user: user, name: name), starts_on: Date.new(2026, 1, 1), **attributes)
  end

  it "measures the gap and splits rules into cuttable and fixed", :aggregate_failures do
    rule_on("Rent", :bill, amount: 900, anchor_date: Date.new(2026, 9, 12), starts_on: Date.new(2026, 9, 4))
    rule_on("Fun", :choice, amount: 300)
    rule_on("Insurance", :bill, amount: 600, anchor_date: Date.new(2026, 10, 1), interval_months: 6)

    expect(presenter).to be_declared
    expect(presenter).to be_underwater
    expect(presenter.gap).to eq(246.15)
    expect(presenter.cuttable_rows.map { |row| row.rule.category.name }).to eq(["Rent", "Fun"])
    expect(presenter.fixed_rows.map { |row| row.rule.category.name }).to eq(["Insurance"])
    expect(presenter).not_to be_unwinnable
    expect(presenter.rows_total).to eq(1_246.15)
  end

  it "is not underwater without a cadence or history" do
    expect(described_class.new(user: create(:user), today: today)).not_to be_underwater
  end
end
