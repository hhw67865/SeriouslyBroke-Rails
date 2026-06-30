# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:categories).dependent(:destroy) }
    it { is_expected.to have_many(:savings_pools).dependent(:destroy) }
    it { is_expected.to have_many(:items).through(:categories) }
    it { is_expected.to have_many(:entries).through(:items) }
    it { is_expected.to have_many(:budgets).through(:categories) }
  end

  describe "#toggle_theme!", :aggregate_failures do
    let(:user) { create(:user) }

    it "flips light to dark" do
      expect(user.theme).to eq("light")
      user.toggle_theme!
      expect(user.reload.theme).to eq("dark")
    end

    it "flips dark to light" do
      user.update!(theme: :dark)
      user.toggle_theme!
      expect(user.reload.theme).to eq("light")
    end
  end

  describe "email confirmation on update", :aggregate_failures do
    let(:user) { create(:user) }

    it "requires email_confirmation to match when email changes" do
      user.email = "new@example.com"
      user.email_confirmation = "different@example.com"
      expect(user).not_to be_valid
      expect(user.errors[:email_confirmation]).to be_present
    end

    it "saves when email_confirmation matches" do
      user.email = "new@example.com"
      user.email_confirmation = "NEW@example.com"
      expect(user.save).to be true
    end

    it "does not require email_confirmation when email is unchanged" do
      user.name = "Renamed"
      expect(user).to be_valid
    end
  end

  describe "timezone validation", :aggregate_failures do
    it "allows a real IANA identifier" do
      expect(build(:user, timezone: "America/New_York")).to be_valid
    end

    it "allows a non-curated but real IANA identifier" do
      expect(build(:user, timezone: "America/Detroit")).to be_valid
    end

    it "allows nil (not yet detected)" do
      expect(build(:user, timezone: nil)).to be_valid
    end

    it "rejects a bogus zone" do
      user = build(:user, timezone: "Mars/Olympus")
      expect(user).not_to be_valid
      expect(user.errors[:timezone]).to be_present
    end

    it "normalizes a blank submission to nil so the edit form can clear it" do
      user = create(:user, timezone: "")
      expect(user.timezone).to be_nil
    end
  end
end
