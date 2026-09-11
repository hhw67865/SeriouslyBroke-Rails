# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityPresenter do
  let(:user) { create(:user, :biweekly) }
  let!(:checking) { create(:account, user: user, name: "Checking", opening_balance: 1_000) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }
  let(:bread) { create(:item, category: groceries, name: "Bread") }

  describe "#rows" do
    let!(:emergency) { create(:account, user: user, name: "Emergency") }
    let!(:rule) { create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1)) }

    before do
      create(:entry, item: bread, amount: 30, date: Date.new(2026, 9, 6))
      create(:transfer, from_account: checking, to_account: emergency, amount: 200, date: Date.new(2026, 9, 7))
      create(:adjustment, source: rule, amount: -50, date: Date.new(2026, 9, 8))
      create(:entry, item: create(:item, :income, user: user, name: "Paycheck"), amount: 2_000, date: Date.new(2026, 9, 8))
    end

    it "interleaves entries, transfers and adjustments newest first with their words", :aggregate_failures do
      rows = described_class.new(user: user, page: nil).rows
      expect(rows.map { |r| [r.kind, r.date] }).to eq([[:entry, Date.new(2026, 9, 8)], [:adjustment, Date.new(2026, 9, 8)], [:transfer, Date.new(2026, 9, 7)], [:entry, Date.new(2026, 9, 6)]])
      expect(rows.map(&:words)).to eq(["Paycheck · #{Item.find_by!(name: "Paycheck").category.name}", "Groceries · reduced", "Checking → Emergency", "Bread · Groceries"])
      expect(rows.map(&:amount)).to eq([2_000, -50, 200, -30])
      expect(rows.first.edit_path).to be_present
      expect(rows[2].remove_path).to include("/transfers/")
    end
  end

  it "pages fifty at a time" do
    60.times { |n| create(:entry, item: bread, amount: 1, date: Date.new(2026, 9, 1) - n) }
    expect(described_class.new(user: user, page: 2).rows.size).to eq(10)
  end

  it "loads rule-sourced adjustments in a fixed number of queries, not one per category" do
    categories = Array.new(3) { |n| create(:category, user: user, name: "Category #{n}") }
    rules = categories.map { |category| create(:rule, :rate, amount: 100, category: category, starts_on: Date.new(2026, 1, 1)) }
    rules.each { |rule| create_list(:adjustment, 2, source: rule, amount: -10, date: Date.new(2026, 9, 8)) }
    queries = 0
    counter = ->(_name, _start, _finish, _id, payload) { queries += 1 unless ["SCHEMA", "CACHE"].include?(payload[:name]) }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { described_class.new(user: user, page: nil).rows }

    expect(queries).to be <= 8
  end
end
