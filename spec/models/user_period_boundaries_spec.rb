# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "#period_boundaries" do
    it "returns [] when no cadence is configured" do
      user = create(:user)

      expect(user.period_boundaries(from: Date.new(2026, 2, 1), to: Date.new(2026, 3, 1))).to eq([])
    end

    it "walks biweekly from the anchor" do
      user = create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6))

      dates = user.period_boundaries(from: Date.new(2026, 2, 6), to: Date.new(2026, 3, 20))

      expect(dates).to eq(
        [
          Date.new(2026, 2, 6),
          Date.new(2026, 2, 20),
          Date.new(2026, 3, 6),
          Date.new(2026, 3, 20)
        ]
      )
    end

    it "starts from the first boundary on or after `from`" do
      user = create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6))

      dates = user.period_boundaries(from: Date.new(2026, 2, 7), to: Date.new(2026, 3, 7))

      expect(dates).to eq([Date.new(2026, 2, 20), Date.new(2026, 3, 6)])
    end

    # An anchor is ONE occurrence of a repeating schedule, not its start, so the
    # series extends backward from it too.
    it "extends backward from an anchor in the future" do
      user = create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 5, 1))

      dates = user.period_boundaries(from: Date.new(2026, 4, 1), to: Date.new(2026, 5, 20))

      expect(dates).to eq(
        [
          Date.new(2026, 4, 3),
          Date.new(2026, 4, 17),
          Date.new(2026, 5, 1),
          Date.new(2026, 5, 15)
        ]
      )
    end

    it "returns [] when the range is inverted" do
      user = create(:user, :biweekly)

      expect(user.period_boundaries(from: Date.new(2026, 3, 1), to: Date.new(2026, 2, 1))).to eq([])
    end

    it "walks weekly" do
      user = create(:user, period_cadence: :weekly, period_anchor_date: Date.new(2026, 2, 6))

      dates = user.period_boundaries(from: Date.new(2026, 2, 6), to: Date.new(2026, 2, 27))

      expect(dates).to eq(
        [
          Date.new(2026, 2, 6),
          Date.new(2026, 2, 13),
          Date.new(2026, 2, 20),
          Date.new(2026, 2, 27)
        ]
      )
    end

    it "walks monthly on the anchor's day" do
      user = create(:user, period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 15))

      dates = user.period_boundaries(from: Date.new(2026, 2, 1), to: Date.new(2026, 4, 30))

      expect(dates).to eq([Date.new(2026, 2, 15), Date.new(2026, 3, 15), Date.new(2026, 4, 15)])
    end

    it "clamps a monthly anchor day to short months" do
      user = create(:user, period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 31))

      dates = user.period_boundaries(from: Date.new(2026, 2, 1), to: Date.new(2026, 3, 31))

      expect(dates).to eq([Date.new(2026, 2, 28), Date.new(2026, 3, 31)])
    end

    it "gives two boundaries a month for semimonthly, 15 days apart" do
      user = create(:user, period_cadence: :semimonthly, period_anchor_date: Date.new(2026, 1, 1))

      dates = user.period_boundaries(from: Date.new(2026, 2, 1), to: Date.new(2026, 3, 31))

      expect(dates).to eq(
        [
          Date.new(2026, 2, 1),
          Date.new(2026, 2, 16),
          Date.new(2026, 3, 1),
          Date.new(2026, 3, 16)
        ]
      )
    end

    # The other half of #semimonthly_days. Every example above anchors on day 1, which only
    # ever exercises `first + 15`; an anchor past the 15th takes the `first - 15` branch and
    # puts the earlier day of the month first.
    it "lands on the anchor day and 15 days earlier when the anchor is late in the month" do
      user = create(:user, period_cadence: :semimonthly, period_anchor_date: Date.new(2026, 1, 20))

      dates = user.period_boundaries(from: Date.new(2026, 2, 1), to: Date.new(2026, 3, 31))

      expect(dates).to eq(
        [
          Date.new(2026, 2, 5),
          Date.new(2026, 2, 20),
          Date.new(2026, 3, 5),
          Date.new(2026, 3, 20)
        ]
      )
    end

    it "gives a 3-boundary month for a biweekly period" do
      user = create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 1, 2))

      dates = user.period_boundaries(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 31))

      expect(dates.count).to eq(3)
    end
  end

  # A period is a RANGE — the caller that needs it deletes a period's distribution and would
  # otherwise reach for a bare date equality, leaving a second split alongside the first.
  describe "#period_containing" do
    let(:biweekly) { create(:user, :biweekly) } # anchored Fri 6 Feb 2026, so Aug 7 and Aug 21

    # Three days of the same period, one at each end and one in the middle, all answering with
    # the same range: that is what "the period containing" has to mean.
    it "runs from the boundary that opened it to the day before the next", :aggregate_failures do
      expect(biweekly.period_containing(Date.new(2026, 8, 7))).to eq(Date.new(2026, 8, 7)..Date.new(2026, 8, 20))
      expect(biweekly.period_containing(Date.new(2026, 8, 14))).to eq(Date.new(2026, 8, 7)..Date.new(2026, 8, 20))
      expect(biweekly.period_containing(Date.new(2026, 8, 20))).to eq(Date.new(2026, 8, 7)..Date.new(2026, 8, 20))
    end

    # The opposite direction at one day's distance on either side, so a range built off the
    # wrong boundary cannot pass: Aug 6 and Aug 21 each belong to a different period.
    it "puts the days either side of a boundary in different periods", :aggregate_failures do
      expect(biweekly.period_containing(Date.new(2026, 8, 6))).to eq(Date.new(2026, 7, 24)..Date.new(2026, 8, 6))
      expect(biweekly.period_containing(Date.new(2026, 8, 21))).to eq(Date.new(2026, 8, 21)..Date.new(2026, 9, 3))
    end

    # A user who declared no period has no boundaries at all, so the calendar month stands in —
    # the same fallback BudgetCalculator#period_end uses, chosen so the two cannot disagree.
    it "falls back to the calendar month without a cadence" do
      expect(create(:user).period_containing(Date.new(2026, 8, 20))).to eq(Date.new(2026, 8, 1)..Date.new(2026, 8, 31))
    end

    it "takes a Time as readily as a Date" do
      expect(biweekly.period_containing(Time.zone.parse("2026-08-20 23:30"))).to eq(Date.new(2026, 8, 7)..Date.new(2026, 8, 20))
    end
  end

  describe "#typical_income" do
    it "is optional" do
      expect(build(:user, typical_income: nil)).to be_valid
    end

    it "must be positive when set", :aggregate_failures do
      user = build(:user, typical_income: -100)

      expect(user).not_to be_valid
      expect(user.errors[:typical_income]).to include("must be greater than 0")
    end
  end

  describe "period configuration" do
    it "requires an anchor date when a cadence is set", :aggregate_failures do
      user = build(:user, period_cadence: :biweekly, period_anchor_date: nil)

      expect(user).not_to be_valid
      expect(user.errors[:period_anchor_date]).to include("is required when you set a period")
    end

    it "allows both to be blank" do
      expect(build(:user, period_cadence: nil, period_anchor_date: nil)).to be_valid
    end

    # Pins the enum prefix. Nothing else in the suite calls a cadence predicate, so a
    # stale `:pay` prefix would survive every other example here — and a validation or
    # view calling a predicate that no longer exists is the exact shape of a Plan 1 bug.
    # Both directions: a predicate that answered true for every cadence would satisfy
    # the positive assertion alone.
    it "prefixes its cadence predicates with `period`", :aggregate_failures do
      user = build(:user, :biweekly)

      expect(user).to be_period_biweekly
      expect(user).not_to be_period_weekly
    end
  end

  describe "#default_account" do
    it "must be an account pool owned by the user", :aggregate_failures do
      user = create(:user)
      other = create(:pool, :account)
      user.default_account = other

      expect(user).not_to be_valid
      expect(user.errors[:default_account]).to include("must be an account you own")
    end

    it "accepts an account pool the user owns" do
      user = create(:user)
      user.default_account = create(:pool, :account, user: user)

      expect(user).to be_valid
    end

    # Both sides unsaved is the only shape that discriminates: with either one persisted the
    # id comparison already rejects. Unsaved, `default_account.user_id` and `id` are both nil,
    # so `nil == nil` waved through an account belonging to nobody.
    it "rejects an unsaved account belonging to nobody", :aggregate_failures do
      user = described_class.new(default_account: Pool.new(pool_type: :account))

      user.valid?

      expect(user.errors[:default_account]).to include("must be an account you own")
    end

    it "accepts an unsaved account the unsaved user owns" do
      user = build(:user)
      user.default_account = build(:pool, :account, user: user)

      expect(user).to be_valid
    end

    # Regression: `users.default_account_id` referencing a pool that `dependent: :destroy`
    # is deleting used to raise InvalidForeignKey and block the whole cascade.
    it "does not block destroying the user who points at it" do
      user = create(:user)
      user.update!(default_account: create(:pool, :account, user: user))

      expect { user.destroy! }.to change(described_class, :count).by(-1)
    end
  end
end
