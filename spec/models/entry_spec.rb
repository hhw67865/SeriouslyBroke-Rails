# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entry, type: :model do
  describe 'associations' do
    it { should belong_to(:item) }
  end

  describe 'validations' do
    it { should validate_presence_of(:amount) }
    it { should validate_presence_of(:date) }
  end

  describe 'money handling' do
    it 'stores decimal values correctly' do
      entry = create(:entry, amount: 15.99)
      expect(entry.amount).to eq(15.99)
    end

    it 'handles negative amounts' do
      entry = create(:entry, amount: -10.50)
      expect(entry.amount).to eq(-10.50)
    end

    it 'handles zero amounts' do
      entry = create(:entry, amount: 0)
      expect(entry.amount).to eq(0.00)
    end
  end

  describe 'delegations' do
    let(:user) { create(:user) }
    let(:category) { create(:category, user: user) }
    let(:item) { create(:item, category: category) }
    let(:entry) { create(:entry, item: item) }

    it 'delegates category to item' do
      expect(entry.category).to eq(category)
    end

    it 'delegates user to item' do
      expect(entry.user).to eq(user)
    end
  end

  describe 'scopes' do
    let(:user) { create(:user) }
    let(:expense_category) { create(:category, category_type: :expense, user: user) }
    let(:income_category) { create(:category, category_type: :income, user: user) }
    let(:savings_category) { create(:category, category_type: :savings, user: user, savings_pool: create(:savings_pool, user: user)) }
    
    let(:expense_item) { create(:item, category: expense_category) }
    let(:income_item) { create(:item, category: income_category) }
    let(:savings_item) { create(:item, category: savings_category) }

    let!(:expense_entry) { create(:entry, item: expense_item) }
    let!(:income_entry) { create(:entry, item: income_item) }
    let!(:savings_entry) { create(:entry, item: savings_item) }

    describe '.expenses' do
      it 'returns only entries from expense categories' do
        expect(described_class.expenses).to contain_exactly(expense_entry)
      end
    end

    describe '.incomes' do
      it 'returns only entries from income categories' do
        expect(described_class.incomes).to contain_exactly(income_entry)
      end
    end

    describe '.savings' do
      it 'returns only entries from savings categories' do
        expect(described_class.savings).to contain_exactly(savings_entry)
      end
    end
  end
end
