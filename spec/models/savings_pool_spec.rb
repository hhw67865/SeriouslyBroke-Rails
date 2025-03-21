# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SavingsPool, type: :model do
  describe 'associations' do
    it { should belong_to(:user) }
    it { should have_many(:categories).dependent(:nullify) }
    it { should have_many(:items).through(:categories) }
    it { should have_many(:entries).through(:items) }
  end

  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:target_amount) }
  end
end
