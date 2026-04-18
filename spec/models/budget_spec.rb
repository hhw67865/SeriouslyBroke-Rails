# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budget, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:category) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:amount) }

    describe "category type validation" do
      let(:income_category) { create(:category, :income) }

      it "requires category to be an expense category", :aggregate_failures do
        budget = build(:budget, category: income_category)
        expect(budget).not_to be_valid
        expect(budget.errors[:category]).to include("must be an expense category")
      end
    end

    describe "pool mutual exclusivity" do
      let(:user) { create(:user) }
      let(:pool) { create(:savings_pool, user: user) }
      let(:expense_category) { create(:category, :expense, user: user, savings_pool: pool) }

      it "rejects budget on a category linked to a savings pool", :aggregate_failures do
        budget = build(:budget, category: expense_category)
        expect(budget).not_to be_valid
        expect(budget.errors[:category]).to include("cannot have a budget when linked to a savings pool")
      end
    end
  end

  describe "prorated flag" do
    it "defaults to false" do
      expect(build(:budget).prorated).to be(false)
    end

    it "accepts true when explicitly set" do
      expect(build(:budget, :prorated).prorated).to be(true)
    end
  end
end
