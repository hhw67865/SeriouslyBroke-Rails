# frozen_string_literal: true

require "rails_helper"

# THE PURPOSE SIDE'S SECOND WRITER (computed-claims spec §3.3): a dated, signed delta on one rule.
#
# BOTH SIGNS, EVERY TIME. This is the only money table in the app with no sign constraint, so every
# guard below is asserted in both directions — a validation that only ever refuses is satisfied by a
# model that refuses everything, and the shape this table exists for is the one where +$100 and
# −$100 are equally legal rows.
RSpec.describe Adjustment, type: :model do
  let(:user) { create(:user) }
  let(:groceries) { create(:category, :expense, :funded, user: user, name: "Groceries") }
  let(:rule) { create(:budget, :per_period_rate, category: groceries, amount: 400) }

  describe "the rule it targets" do
    it "belongs to a rule, which is a Budget under another name" do
      adjustment = create(:adjustment, rule: rule)

      expect(adjustment.reload.rule).to eq(rule)
    end

    it "refuses to exist without one" do
      expect(build(:adjustment, rule: nil)).not_to be_valid
    end

    # A DELTA WITH NO ACCRUAL TO BE A DELTA ON is a claim with no arm to land on.
    it "goes with the rule it adjusts" do
      create(:adjustment, rule: rule)

      expect { rule.destroy }.to change(described_class, :count).from(1).to(0)
    end

    it "reads its owner through the rule rather than through a column of its own" do
      expect(create(:adjustment, rule: rule).user).to eq(user)
    end
  end

  describe "the amount" do
    it "takes a positive delta — a top-up" do
      expect(build(:adjustment, rule: rule, amount: 100)).to be_valid
    end

    it "takes a negative delta — a release" do
      expect(build(:adjustment, rule: rule, amount: -158)).to be_valid
    end

    # ZERO IS THE ONE AMOUNT THAT SAYS NOTHING — deleting the row is what that is for.
    it "refuses a zero delta", :aggregate_failures do
      adjustment = build(:adjustment, rule: rule, amount: 0)

      expect(adjustment).not_to be_valid
      expect(adjustment.errors[:amount]).to be_present
    end

    # THE DATABASE HOLDS THE SAME LINE, for a row written past the model.
    it "refuses a zero delta at the database too" do
      past_the_model = build(:adjustment, rule: rule, amount: 0)

      expect { past_the_model.save(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /adjustments_non_zero_amount/)
    end

    it "refuses a row with no date" do
      expect(build(:adjustment, rule: rule, date: nil)).not_to be_valid
    end
  end

  describe ".dated_within" do
    let!(:inside) { create(:adjustment, rule: rule, amount: 100, date: Time.utc(2026, 9, 10, 12)) }

    before { create(:adjustment, rule: rule, amount: 50, date: Time.utc(2026, 10, 10, 12)) }

    it "holds the rows inside the window and no others" do
      window = Time.utc(2026, 9, 1)..Time.utc(2026, 9, 30, 23, 59, 59)

      expect(described_class.dated_within(window)).to contain_exactly(inside)
    end
  end

  # WHICH PERIOD A DELTA LANDS IN IS THE OWNER'S CALENDAR DAY (§3.3), never UTC's — the same
  # re-zoning `CategoryLedger::ENTRY_LOCAL_DAY` performs in SQL for an entry.
  describe "#local_day" do
    it "reads the day in UTC for a user who has chosen no zone" do
      adjustment = create(:adjustment, rule: rule, date: Time.utc(2026, 9, 11, 15, 0))

      expect(adjustment.local_day).to eq(Date.new(2026, 9, 11))
    end

    it "reads the same instant as the next day for a Tokyo user" do
      user.update!(timezone: "Asia/Tokyo")
      adjustment = create(:adjustment, rule: rule, date: Time.utc(2026, 9, 11, 15, 0))

      expect(adjustment.local_day).to eq(Date.new(2026, 9, 12))
    end
  end
end
