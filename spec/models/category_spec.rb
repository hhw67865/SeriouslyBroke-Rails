# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Category, type: :model do
  describe 'associations' do
    it { should belong_to(:user) }
    it { should belong_to(:savings_pool).optional }
    it { should have_many(:items).dependent(:destroy) }
    it { should have_many(:entries).through(:items) }
    it { should have_one(:budget).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:category_type) }
    
    context 'when category type is savings' do
      subject { build(:category, :savings, savings_pool: nil) }
      
      it 'requires a savings_pool' do
        expect(subject).not_to be_valid
        expect(subject.errors[:savings_pool]).to include("can't be blank")
      end
    end

    context 'when category has a budget' do
      let(:category) { create(:category, :income) }
      
      it 'only allows budgets for expense categories' do
        budget = build(:budget, category: category)
        expect(budget).not_to be_valid
        expect(budget.errors[:category]).to include('must be an expense category')
      end
    end
  end

  describe 'enums' do
    it { should define_enum_for(:category_type).with_values(income: 0, expense: 1, savings: 2) }
  end

  describe 'scopes' do
    let(:user) { create(:user) }
    let!(:expense_category) { create(:category, category_type: :expense, user: user) }
    let!(:income_category) { create(:category, category_type: :income, user: user) }
    let!(:savings_category) { create(:category, category_type: :savings, user: user, savings_pool: create(:savings_pool, user: user)) }

    describe '.expenses' do
      it 'returns only expense categories' do
        expect(described_class.expenses).to contain_exactly(expense_category)
      end
    end

    describe '.incomes' do
      it 'returns only income categories' do
        expect(described_class.incomes).to contain_exactly(income_category)
      end
    end

    describe '.savings' do
      it 'returns only savings categories' do
        expect(described_class.savings).to contain_exactly(savings_category)
      end
    end
  end
end
