# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  describe "validations", :aggregate_failures do
    it "needs an anchor date with a cadence" do
      expect(build(:user, period_cadence: :weekly, period_anchor_date: nil)).not_to be_valid
      expect(build(:user, period_cadence: nil, period_anchor_date: nil)).to be_valid
    end

    it "only takes one of its own accounts as main" do
      user = create(:user)
      other = create(:account)

      user.main_account = other

      expect(user).not_to be_valid
      expect(user.errors[:main_account]).to include("must be an account you own")
    end

    it "only takes a real timezone" do
      expect(build(:user, timezone: "Mars/Olympus")).not_to be_valid
      expect(build(:user, timezone: "America/New_York")).to be_valid
    end
  end

  describe "#today" do
    it "is the calendar day in the user's timezone" do
      user = build(:user, timezone: "Pacific/Auckland")

      travel_to Time.utc(2026, 3, 1, 23, 0) do
        expect(user.today).to eq(Date.new(2026, 3, 2))
      end
    end
  end

  describe "#period_boundaries and #period_containing", :aggregate_failures do
    it "strides fortnightly from the anchor" do
      user = build(:user, :biweekly)

      expect(user.period_boundaries(from: Date.new(2026, 9, 1), to: Date.new(2026, 9, 30)))
        .to eq([Date.new(2026, 9, 4), Date.new(2026, 9, 18)])
      expect(user.period_containing(Date.new(2026, 9, 9))).to eq(Date.new(2026, 9, 4)..Date.new(2026, 9, 17))
      expect(user.period_containing(Date.new(2026, 9, 18))).to eq(Date.new(2026, 9, 18)..Date.new(2026, 10, 1))
    end

    it "lands monthly periods on the anchor's day, clamped to short months" do
      user = build(:user, period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 31))

      expect(user.period_boundaries(from: Date.new(2026, 2, 1), to: Date.new(2026, 4, 30)))
        .to eq([Date.new(2026, 2, 28), Date.new(2026, 3, 31), Date.new(2026, 4, 30)])
      expect(user.period_containing(Date.new(2026, 3, 15))).to eq(Date.new(2026, 2, 28)..Date.new(2026, 3, 30))
    end

    it "splits a month in two for semimonthly" do
      user = build(:user, period_cadence: :semimonthly, period_anchor_date: Date.new(2026, 1, 1))

      expect(user.period_boundaries(from: Date.new(2026, 3, 1), to: Date.new(2026, 3, 31)))
        .to eq([Date.new(2026, 3, 1), Date.new(2026, 3, 16)])
    end

    it "falls back to the calendar month with no cadence" do
      user = build(:user)

      expect(user.period_boundaries(from: Date.new(2026, 9, 9), to: Date.new(2026, 12, 5)))
        .to eq([Date.new(2026, 10, 1), Date.new(2026, 11, 1), Date.new(2026, 12, 1)])
      expect(user.period_containing(Date.new(2026, 9, 9))).to eq(Date.new(2026, 9, 1)..Date.new(2026, 9, 30))
      expect(user.periods_per_year).to eq(12)
    end
  end

  describe "#complete_periods" do
    let(:user) { create(:user, :biweekly) }
    let(:today) { Date.new(2026, 9, 9) }

    def earn(amount, on:) = create(:entry, item: create(:item, category: create(:category, user: user)), amount: amount, date: on)

    it "returns the last N complete periods, oldest first" do
      earn(1_000, on: Date.new(2026, 8, 7))
      earn(1_500, on: Date.new(2026, 8, 25))

      expect(user.complete_periods(2, today: today)).to eq(
        [Date.new(2026, 8, 7)..Date.new(2026, 8, 20), Date.new(2026, 8, 21)..Date.new(2026, 9, 3)]
      )
    end

    it "is empty with no entries at all" do
      expect(user.complete_periods(2, today: today)).to eq([])
    end

    # The first entry sits ON the older period's opening boundary — a period that only STARTS
    # after the first entry would not be complete history, so the walk stops one short of it. This
    # also proves the walk uses THIS user's own cadence, not some other grid.
    it "stops at the period the first entry opens, on whatever cadence is set" do
      user.period_cadence = "monthly"
      user.period_anchor_date = Date.new(2026, 1, 15)

      earn(2_000, on: Date.new(2026, 6, 15))
      earn(2_400, on: Date.new(2026, 7, 20))

      expect(user.complete_periods(2, today: today)).to eq(
        [Date.new(2026, 6, 15)..Date.new(2026, 7, 14), Date.new(2026, 7, 15)..Date.new(2026, 8, 14)]
      )
    end
  end

  describe "#toggle_theme!" do
    it "flips between light and dark" do
      user = create(:user)

      expect { user.toggle_theme! }.to change(user, :theme).from("light").to("dark")
    end
  end
end
