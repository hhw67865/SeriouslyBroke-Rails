# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings Pools Index - Search", type: :system do
  let(:user) { create(:user) }
  let!(:emergency_fund) { create(:savings_pool, user: user, name: "Emergency Fund", target_amount: 10_000) }
  let!(:vacation_fund) { create(:savings_pool, user: user, name: "Vacation Fund", target_amount: 5000) }
  let!(:car_fund) { create(:savings_pool, user: user, name: "New Car Fund", target_amount: 20_000) }

  before do
    sign_in user, scope: :user
    visit savings_pools_path
  end

  describe "search by name", :aggregate_failures do
    before do
      select "Name", from: "field"
    end

    it "finds savings pools matching search query" do
      fill_in "q", with: "Emergency"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content(emergency_fund.name)
      expect(page).not_to have_content(vacation_fund.name)
      expect(page).not_to have_content(car_fund.name)
    end

    it "performs case-insensitive search" do
      fill_in "q", with: "vacation"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content(vacation_fund.name)
      expect(page).not_to have_content(emergency_fund.name)
    end

    it "finds partial matches" do
      fill_in "q", with: "Fund"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content(emergency_fund.name)
      expect(page).to have_content(vacation_fund.name)
      expect(page).to have_content(car_fund.name)
    end
  end

  describe "search by category", :aggregate_failures do
    before do
      create(:category, user: user, name: "Home Savings", savings_pool: emergency_fund)
      create(:category, user: user, name: "Travel Budget", savings_pool: vacation_fund)
      create(:category, user: user, name: "Vehicle Fund", savings_pool: car_fund)
      visit savings_pools_path
      select "Category", from: "field"
    end

    it "finds savings pools by category name" do
      fill_in "q", with: "Home"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content(emergency_fund.name)
      expect(page).not_to have_content(vacation_fund.name)
      expect(page).not_to have_content(car_fund.name)
    end

    it "performs case-insensitive category search" do
      fill_in "q", with: "travel"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content(vacation_fund.name)
      expect(page).not_to have_content(emergency_fund.name)
      expect(page).not_to have_content(car_fund.name)
    end

    it "finds partial category matches" do
      fill_in "q", with: "Fund"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content(emergency_fund.name)
      expect(page).to have_content(car_fund.name)
      expect(page).not_to have_content(vacation_fund.name)
    end

    it "shows savings pool when any of its categories match" do
      create(:category, user: user, name: "Medical Emergency", savings_pool: emergency_fund)

      fill_in "q", with: "Medical"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content(emergency_fund.name)
    end
  end

  describe "field selector", :aggregate_failures do
    it "shows available search fields" do
      expect(page).to have_select("field", options: ["Name", "Category"])
    end

    it "defaults to Name field" do
      expect(page).to have_select("field", selected: "Name")
    end
  end

  describe "search results information", :aggregate_failures do
    before do
      select "Name", from: "field"
    end

    it "displays result count for name search" do
      fill_in "q", with: "Emergency"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content('Found 1 result for "Emergency" in Name')
    end

    it "displays result count for category search" do
      create(:category, user: user, name: "Home Savings", savings_pool: emergency_fund)

      select "Category", from: "field"
      fill_in "q", with: "Home"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content('Found 1 result for "Home" in Category')
    end

    it "shows clear search link" do
      fill_in "q", with: "Emergency"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_link("Clear search")
    end
  end

  describe "clearing search", :aggregate_failures do
    before do
      fill_in "q", with: "Emergency"
      find("input[name='q']").send_keys(:return)
    end

    it "returns to full list when clearing search" do
      click_link "Clear search"

      expect(page).to have_content(emergency_fund.name)
      expect(page).to have_content(vacation_fund.name)
      expect(page).to have_content(car_fund.name)
      expect(page).not_to have_link("Clear search")
    end
  end

  describe "empty search results", :aggregate_failures do
    it "shows no results message" do
      fill_in "q", with: "Nonexistent Pool"
      find("input[name='q']").send_keys(:return)

      expect(page).to have_content("No savings pools yet")
    end

    it "provides clear search option" do
      fill_in "q", with: "Nonexistent Pool"
      find("input[name='q']").send_keys(:return)

      click_link "Clear search"

      expect(page).to have_content(emergency_fund.name)
      expect(page).to have_content(vacation_fund.name)
    end
  end
end
