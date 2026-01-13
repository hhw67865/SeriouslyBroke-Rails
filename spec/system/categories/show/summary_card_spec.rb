# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Show - Summary Card Period Labels", type: :system do
  let!(:user) { create(:user) }
  let(:base_date) { Date.current.beginning_of_month }

  before { sign_in user, scope: :user }

  describe "expense category labels", :aggregate_failures do
    let!(:category) { create(:category, category_type: "expense", user: user, name: "Food") }
    let!(:item) { create(:item, category: category, name: "Groceries") }

    before do
      create(:budget, category: category, amount: 500)
      create(:entry, item: item, amount: 100, date: base_date + 5.days)
    end

    it "shows Monthly labels in default view" do
      visit category_path(category)

      expect(page).to have_content("Monthly Budget")
      expect(page).to have_content("Monthly Spending Trend")
      expect(page).to have_content("Items This Month")
    end

    it "shows YTD labels in YTD view" do
      visit category_path(category, period: "ytd")

      expect(page).to have_content("YTD Budget")
      expect(page).to have_content("YTD Spending Trend")
      expect(page).to have_content("Items This Year")
    end
  end

  describe "income category labels", :aggregate_failures do
    let!(:category) { create(:category, category_type: "income", user: user, name: "Salary") }
    let!(:item) { create(:item, category: category, name: "Paycheck") }

    before { create(:entry, item: item, amount: 1000, date: base_date + 3.days) }

    it "shows Monthly labels in default view" do
      visit category_path(category)

      expect(page).to have_content("Monthly Income")
      expect(page).to have_content("Items This Month")
    end

    it "shows YTD labels in YTD view" do
      visit category_path(category, period: "ytd")

      expect(page).to have_content("YTD Income")
      expect(page).to have_content("Items This Year")
    end
  end

  describe "savings category labels", :aggregate_failures do
    let!(:pool) { create(:savings_pool, user: user) }
    let!(:category) { create(:category, category_type: "savings", user: user, savings_pool: pool, name: "Emergency") }
    let!(:item) { create(:item, category: category, name: "Transfer") }

    before { create(:entry, item: item, amount: 200, date: base_date + 7.days) }

    it "shows Monthly labels in default view" do
      visit category_path(category)

      expect(page).to have_content("Monthly Contribution")
      expect(page).to have_content("Items This Month")
    end

    it "shows YTD labels in YTD view" do
      visit category_path(category, period: "ytd")

      expect(page).to have_content("YTD Contribution")
      expect(page).to have_content("Items This Year")
    end
  end
end
