# frozen_string_literal: true

require "rails_helper"

RSpec.describe SavingsPool, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:categories).dependent(:nullify) }
    it { is_expected.to have_many(:items).through(:categories) }
    it { is_expected.to have_many(:entries).through(:items) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:target_amount) }
  end

  describe "#timeline_entries" do
    it "includes contributions and withdrawals after start_date", :aggregate_failures do
      user = create(:user)
      pool = create(:savings_pool, user: user, start_date: Date.new(2025, 6, 1))
      savings_item = create(:item, category: create(:category, :savings, user: user, savings_pool: pool))
      expense_item = create(:item, category: create(:category, :expense, user: user, savings_pool: pool))

      contribution = create(:entry, item: savings_item, date: Date.new(2025, 7, 1))
      withdrawal = create(:entry, item: expense_item, date: Date.new(2025, 8, 1))
      before_start = create(:entry, item: savings_item, date: Date.new(2025, 5, 1))

      results = pool.timeline_entries

      expect(results).to include(contribution, withdrawal)
      expect(results).not_to include(before_start)
    end
  end
end
