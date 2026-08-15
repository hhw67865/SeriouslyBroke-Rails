# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "#pay_dates" do
    it "returns [] when no cadence is configured" do
      user = create(:user)

      expect(user.pay_dates(from: Date.new(2026, 2, 1), to: Date.new(2026, 3, 1))).to eq([])
    end

    it "walks biweekly from the anchor" do
      user = create(:user, pay_cadence: :biweekly, pay_anchor_date: Date.new(2026, 2, 6))

      dates = user.pay_dates(from: Date.new(2026, 2, 6), to: Date.new(2026, 3, 20))

      expect(dates).to eq(
        [
          Date.new(2026, 2, 6),
          Date.new(2026, 2, 20),
          Date.new(2026, 3, 6),
          Date.new(2026, 3, 20)
        ]
      )
    end

    it "starts from the first pay date on or after `from`" do
      user = create(:user, pay_cadence: :biweekly, pay_anchor_date: Date.new(2026, 2, 6))

      dates = user.pay_dates(from: Date.new(2026, 2, 7), to: Date.new(2026, 3, 7))

      expect(dates).to eq([Date.new(2026, 2, 20), Date.new(2026, 3, 6)])
    end

    # An anchor is ONE occurrence of a repeating schedule, not its start, so the
    # series extends backward from it too.
    it "extends backward from an anchor in the future" do
      user = create(:user, pay_cadence: :biweekly, pay_anchor_date: Date.new(2026, 5, 1))

      dates = user.pay_dates(from: Date.new(2026, 4, 1), to: Date.new(2026, 5, 20))

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

      expect(user.pay_dates(from: Date.new(2026, 3, 1), to: Date.new(2026, 2, 1))).to eq([])
    end

    it "walks weekly" do
      user = create(:user, pay_cadence: :weekly, pay_anchor_date: Date.new(2026, 2, 6))

      dates = user.pay_dates(from: Date.new(2026, 2, 6), to: Date.new(2026, 2, 27))

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
      user = create(:user, pay_cadence: :monthly, pay_anchor_date: Date.new(2026, 1, 15))

      dates = user.pay_dates(from: Date.new(2026, 2, 1), to: Date.new(2026, 4, 30))

      expect(dates).to eq([Date.new(2026, 2, 15), Date.new(2026, 3, 15), Date.new(2026, 4, 15)])
    end

    it "clamps a monthly anchor day to short months" do
      user = create(:user, pay_cadence: :monthly, pay_anchor_date: Date.new(2026, 1, 31))

      dates = user.pay_dates(from: Date.new(2026, 2, 1), to: Date.new(2026, 3, 31))

      expect(dates).to eq([Date.new(2026, 2, 28), Date.new(2026, 3, 31)])
    end

    it "pays twice a month for semimonthly, 15 days apart" do
      user = create(:user, pay_cadence: :semimonthly, pay_anchor_date: Date.new(2026, 1, 1))

      dates = user.pay_dates(from: Date.new(2026, 2, 1), to: Date.new(2026, 3, 31))

      expect(dates).to eq(
        [
          Date.new(2026, 2, 1),
          Date.new(2026, 2, 16),
          Date.new(2026, 3, 1),
          Date.new(2026, 3, 16)
        ]
      )
    end

    it "gives a 3-paycheck month for biweekly pay" do
      user = create(:user, pay_cadence: :biweekly, pay_anchor_date: Date.new(2026, 1, 2))

      dates = user.pay_dates(from: Date.new(2026, 1, 1), to: Date.new(2026, 1, 31))

      expect(dates.count).to eq(3)
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

    # Regression: `users.default_account_id` referencing a pool that `dependent: :destroy`
    # is deleting used to raise InvalidForeignKey and block the whole cascade.
    it "does not block destroying the user who points at it" do
      user = create(:user)
      user.update!(default_account: create(:pool, :account, user: user))

      expect { user.destroy! }.to change(described_class, :count).by(-1)
    end
  end
end
