# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:categories).dependent(:destroy) }
    it { is_expected.to have_many(:pools).dependent(:destroy) }
    it { is_expected.to have_many(:items).through(:categories) }
    it { is_expected.to have_many(:entries).through(:items) }
    it { is_expected.to have_many(:budgets).through(:categories) }
  end

  # The wider reader beside the narrow one. Both are asserted here, against the SAME
  # fixtures, so "all_budgets is just budgets" can never pass unnoticed.
  describe "#all_budgets" do
    let(:user) { create(:user) }
    let(:account) { create(:pool, :account, user: user) }
    let(:pool) { create(:pool, :budget_pool, user: user, account: account) }

    let!(:category_rule) { create(:budget, category: create(:category, :expense, user: user)) }
    let!(:pool_rule) { create(:budget, :rate, pool: pool, category: nil) }
    let!(:stranger_rule) { create(:budget, category: create(:category, :expense)) }

    it "returns every rule the user owns, in both modes" do
      expect(user.all_budgets).to contain_exactly(category_rule, pool_rule)
    end

    it "is wider than #budgets, which reaches only the category-mode half", :aggregate_failures do
      expect(user.budgets).to contain_exactly(category_rule)
      expect(user.all_budgets).to include(pool_rule)
    end

    it "excludes another user's rules" do
      expect(user.all_budgets).not_to include(stranger_rule)
    end
  end

  # These two are a pair and must be read together: deleting one account pool and
  # deleting a whole user want opposite behaviour from `child_pools`, so the
  # cascade is sequenced on User rather than by relaxing Pool's protection.
  describe "destroying a user that owns an account pool with envelopes inside it" do
    let(:user) { create(:user) }
    let!(:account) { create(:pool, :account, user: user) }
    let!(:envelope) { create(:pool, :budget_pool, user: user, account: account) }

    it "deletes the user, the account, and the envelopes inside it", :aggregate_failures do
      expect { user.destroy! }.to change(described_class, :count).by(-1)
      expect(Pool.where(id: [account.id, envelope.id])).to be_empty
    end

    # Counterweight to the example above: the cascade must not be bought by
    # weakening `child_pools`' restrict_with_error, which is what stops a user
    # deleting an account that still holds envelopes with money in them.
    it "still refuses to delete that account pool on its own", :aggregate_failures do
      expect(account.destroy).to be false
      expect(account).to be_persisted
      expect(Pool.exists?(account.id)).to be true
    end
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
