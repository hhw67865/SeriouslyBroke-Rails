# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Item, type: :model do
  describe 'associations' do
    it { should belong_to(:category) }
    it { should have_many(:entries).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
  end

  describe 'enums' do
    it { should define_enum_for(:frequency).with_values(one_time: 0, monthly: 1, yearly: 2) }
  end

  describe 'delegation' do
    let(:user) { create(:user) }
    let(:category) { create(:category, user: user) }
    let(:item) { create(:item, category: category) }

    it 'delegates user to category' do
      expect(item.user).to eq(user)
    end
  end

  describe 'scopes' do
    let(:user) { create(:user) }
    let(:expense_category) { create(:category, category_type: :expense, user: user) }
    let(:income_category) { create(:category, category_type: :income, user: user) }
    let(:savings_category) { create(:category, category_type: :savings, user: user, savings_pool: create(:savings_pool, user: user)) }
    
    let!(:expense_item) { create(:item, category: expense_category) }
    let!(:income_item) { create(:item, category: income_category) }
    let!(:savings_item) { create(:item, category: savings_category) }

    describe '.expenses' do
      it 'returns only items from expense categories' do
        expect(described_class.expenses).to contain_exactly(expense_item)
      end
    end

    describe '.incomes' do
      it 'returns only items from income categories' do
        expect(described_class.incomes).to contain_exactly(income_item)
      end
    end

    describe '.savings' do
      it 'returns only items from savings categories' do
        expect(described_class.savings).to contain_exactly(savings_item)
      end
    end
  end
end
