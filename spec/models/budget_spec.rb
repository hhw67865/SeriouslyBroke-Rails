# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Budget, type: :model do
  describe 'associations' do
    it { should belong_to(:category) }
  end

  describe 'validations' do
    it { should validate_presence_of(:amount) }
    it { should validate_presence_of(:period) }

    context 'category type validation' do
      let(:income_category) { create(:category, :income) }
      
      it 'requires category to be an expense category' do
        budget = build(:budget, category: income_category)
        expect(budget).not_to be_valid
        expect(budget.errors[:category]).to include('must be an expense category')
      end
    end
  end

  describe 'enums' do
    it { should define_enum_for(:period).with_values(month: 0, year: 1) }
  end
end
