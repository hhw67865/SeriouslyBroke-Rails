# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:categories).dependent(:destroy) }
    it { is_expected.to have_many(:pools).dependent(:destroy) }
    it { is_expected.to have_many(:items).through(:categories) }
    it { is_expected.to have_many(:entries).through(:items) }

    # `has_many :budgets, through: :categories` is deleted with the category-mode cap it reached
    # (plan 3, task 3): `budgets.category_id` is nil on every row and nothing writes one, so the
    # association could only ever answer empty.
    it "has no budgets association through categories" do
      expect(described_class.reflect_on_association(:budgets)).to be_nil
    end
  end

  # ONE READER NOW, WHERE THERE WERE TWO. This describe held three examples asserting that
  # `#all_budgets` was WIDER than `#budgets` — the narrow association reached the category-mode
  # caps, this one reached both modes — and that pairing is what the cap's deletion retires.
  describe "#all_budgets" do
    let(:user) { create(:user) }
    let!(:rule) { create(:budget, :rate, category: create(:category, :expense, :funded, user: user)) }
    let!(:stranger_rule) { create(:budget, :rate) }

    it "returns every rule the user owns and nobody else's", :aggregate_failures do
      expect(user.all_budgets).to contain_exactly(rule)
      expect(user.all_budgets).not_to include(stranger_rule)
    end
  end

  # DELETED WITH THE NESTING (two-ledger spec §5, Task 8): "destroying a user that owns an account
  # pool with envelopes inside it". Its two examples were a pair — the user cascade had to delete an
  # account holding envelopes while `Pool#child_pools`' `restrict_with_error` still refused the same
  # delete on its own, which is why `User#destroy_child_pools_first` existed. Nothing nests inside an
  # account any more, so both the callback and the pair it balanced are gone.

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
