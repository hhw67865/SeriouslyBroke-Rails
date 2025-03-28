# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budget, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:category) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:amount) }
    it { is_expected.to validate_presence_of(:period) }

    describe "category type validation" do
      let(:income_category) { create(:category, :income) }

      it "requires category to be an expense category", :aggregate_failures do
        budget = build(:budget, category: income_category)
        expect(budget).not_to be_valid
        expect(budget.errors[:category]).to include("must be an expense category")
      end
    end
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:period).with_values(month: 0, year: 1) }
  end
end
