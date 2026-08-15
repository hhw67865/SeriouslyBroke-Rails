# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings Pools Show - Recent Activity", type: :system do
  let(:user) { create(:user) }
  let!(:savings_pool) { create(:savings_pool, user: user, name: "Emergency Fund", target_amount: 10_000) }
  let!(:savings_category) { create(:category, user: user, name: "Home Savings", category_type: :savings, savings_pool: savings_pool) }
  let!(:expense_category) { create(:category, user: user, name: "Emergency Withdrawal", category_type: :expense, savings_pool: savings_pool) }

  before { sign_in user, scope: :user }

  describe "with recent entries", :aggregate_failures do
    let!(:savings_item) { create(:item, category: savings_category, name: "Monthly Deposit") }
    let!(:expense_item) { create(:item, category: expense_category, name: "Medical Bill") }

    before do
      create(:entry, item: savings_item, amount: 500.0, date: Date.current)
      create(:entry, item: expense_item, amount: 150.0, date: Date.current - 1.day)
      create(:entry, item: savings_item, amount: 300.0, date: Date.current - 2.days)

      visit savings_pool_path(savings_pool)
    end

    it "shows recent activity section" do
      expect(page).to have_content("Recent Activity")
      expect(page).to have_content("Last 8 transactions")
    end

    it "links to show all activity for this savings pool" do
      activity_header = page.all("div.flex.items-center.justify-between", text: "Recent Activity").first
      within(activity_header) do
        expect(page).to have_link("Show All Activity")
        click_link "Show All Activity"
      end

      expect(page).to have_current_path(entries_path(field: "savings_pool", q: savings_pool.name))
    end

    it "displays all entry items" do
      expect(page).to have_content("Monthly Deposit")
      expect(page).to have_content("Medical Bill")
    end

    it "shows correct amounts with signs" do
      activity_section = page.all("div.bg-white.rounded", text: "Recent Activity").first
      within(activity_section) do
        expect(page).to have_content("+$500.00")
        expect(page).to have_content("-$150.00")
        expect(page).to have_content("+$300.00")
      end
    end

    it "displays category names" do
      activity_section = page.all("div.bg-white.rounded", text: "Recent Activity").first
      within(activity_section) do
        expect(page).to have_content("Home Savings")
        expect(page).to have_content("Emergency Withdrawal")
      end
    end

    it "shows entry types with badges" do
      activity_section = page.all("div.bg-white.rounded", text: "Recent Activity").first
      within(activity_section) do
        expect(page).to have_css(".bg-status-success-light.text-status-success", text: "Savings")
        expect(page).to have_css(".bg-status-danger-light.text-status-danger", text: "Expense")
      end
    end

    it "displays entry dates" do
      activity_section = page.all("div.bg-white.rounded", text: "Recent Activity").first
      within(activity_section) do
        expect(page).to have_content(Date.current.strftime("%b %d, %Y"))
        expect(page).to have_content((Date.current - 1.day).strftime("%b %d, %Y"))
      end
    end
  end

  describe "with many entries", :aggregate_failures do
    let!(:savings_item) { create(:item, category: savings_category) }

    before do
      # Create 10 entries, but only 8 should be displayed
      10.times do |i|
        create(:entry, item: savings_item, amount: 100.0, date: Date.current - i.days)
      end

      visit savings_pool_path(savings_pool)
    end

    it "shows only the 8 most recent entries" do
      entries = page.all("div.bg-gray-50.rounded")
      expect(entries.count).to eq(8)
    end

    it "shows entries in descending date order" do
      activity_section = page.all("div.bg-white.rounded", text: "Recent Activity").first
      within(activity_section) do
        # Get entry date elements (they are in the right column of each entry card)
        dates = page.all("div.bg-gray-50.rounded div.text-right div.text-xs.text-gray-500").map(&:text)
        expect(dates.first).to include(Date.current.strftime("%b %d, %Y"))
        expect(dates.last).to include((Date.current - 7.days).strftime("%b %d, %Y"))
      end
    end
  end

  describe "with no entries" do
    before { visit savings_pool_path(savings_pool) }

    it "does not show recent activity header" do
      expect(page).not_to have_content("Recent Activity")
    end

    it "does not show transaction count label" do
      expect(page).not_to have_content("Last 8 transactions")
    end
  end
end
