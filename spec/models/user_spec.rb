# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { should have_many(:categories).dependent(:destroy) }
    it { should have_many(:savings_pools).dependent(:destroy) }
    it { should have_many(:items).through(:categories) }
    it { should have_many(:entries).through(:items) }
    it { should have_many(:budgets).through(:categories) }
  end
end 