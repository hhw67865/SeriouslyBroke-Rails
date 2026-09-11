# frozen_string_literal: true

require "rails_helper"

RSpec.describe Adjustment do
  it "is a non-zero amount on a date, on a rule", :aggregate_failures do
    expect(build(:adjustment, amount: 0)).not_to be_valid
    expect(build(:adjustment, date: nil)).not_to be_valid
    expect(build(:adjustment, :release)).to be_valid
  end

  it "belongs to the rule's user and can be picked by date", :aggregate_failures do
    adjustment = create(:adjustment, date: Date.new(2026, 9, 5))

    expect(adjustment.user).to eq(adjustment.source.category.user)
    expect(described_class.dated_within(Date.new(2026, 9, 1)..Date.new(2026, 9, 30))).to eq([adjustment])
    expect(described_class.dated_within(Date.new(2026, 10, 1)..Date.new(2026, 10, 31))).to be_empty
  end

  it "lets an account only reduce", :aggregate_failures do
    account = create(:account, :savings)

    expect(build(:adjustment, source: account, amount: -50)).to be_valid
    expect(build(:adjustment, source: account, amount: 50)).not_to be_valid
  end
end
