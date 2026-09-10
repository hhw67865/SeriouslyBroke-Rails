# frozen_string_literal: true

require "rails_helper"

# The last day of a month belongs to that month on every screen, whatever the clock says in UTC.
RSpec.describe Entry do
  include ActiveSupport::Testing::TimeHelpers

  shared_examples "a month that keeps its last day" do |zone, utc_now|
    let(:user) { create(:user, timezone: zone) }
    let(:category) { create(:category, user: user, name: "Food", category_type: :expense) }
    let(:item) { create(:item, category: category, name: "Groceries") }
    let(:august) { Date.new(2026, 8, 1) }

    before do
      create(:account, user: user)
      create(:entry, item: item, amount: 1, date: Date.new(2026, 7, 31))
      create(:entry, item: item, amount: 10, date: Date.new(2026, 8, 1))
      create(:entry, item: item, amount: 100, date: Date.new(2026, 8, 31))
      create(:entry, item: item, amount: 1000, date: Date.new(2026, 9, 1))
    end

    around { |example| travel_to(utc_now) { example.run } }

    it "is the user's own day at the edge" do
      expect(user.today).to eq(Date.new(2026, 8, 31))
    end

    it "sums both edges of August into the reports, and nothing beyond them", :aggregate_failures do
      presenter = DashboardPresenter.new(user: user, date: august)

      expect(presenter.total_expenses).to eq(110)
      expect(presenter.previous_month_range).to cover(Date.new(2026, 7, 31))
      expect(presenter.six_month_range).to cover(Date.new(2026, 8, 31))
      expect(presenter.ytd_range).to cover(Date.new(2026, 8, 31))
    end

    it "counts both edges in the category's month", :aggregate_failures do
      expect(category.stats(august).total_amount).to eq(110)
      expect(category.stats(august, period: :ytd).total_amount).to eq(111)
    end

    it "draws the 31st inside August on the calendar", :aggregate_failures do
      days = MonthlyCalendarPresenter.new(user: user, month_date: august).weeks.flatten
      last = days.find { |day| day[:date] == Date.new(2026, 8, 31) }

      expect(last[:in_month]).to be(true)
      expect(last[:totals].values.flatten.sum(&:to_d)).to eq(100)
    end

    it "finds the 31st when entries are searched by month", :aggregate_failures do
      found = described_class.search_by(:date, "2026-08").pluck(:amount).map(&:to_i)

      expect(found).to contain_exactly(10, 100)
    end
  end

  describe "for a user far west of UTC, late on the 31st" do
    it_behaves_like "a month that keeps its last day", "Pacific/Honolulu", Time.utc(2026, 9, 1, 9, 30)
  end

  describe "for a user far east of UTC, early on the 31st" do
    it_behaves_like "a month that keeps its last day", "Pacific/Auckland", Time.utc(2026, 8, 30, 12, 30)
  end
end
