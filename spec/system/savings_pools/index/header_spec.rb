# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings Pools Index - Header", type: :system do
  let(:user) { create(:user) }

  before do
    sign_in user, scope: :user
    visit savings_pools_path
  end

  describe "page header elements", :aggregate_failures do
    it "shows correct title and subtitle" do
      expect(page).to have_content("Savings Pools")
      expect(page).to have_content("Track your financial goals and savings progress")
    end

    it "shows create button" do
      expect(page).to have_link("New Savings Pool")
    end
  end

  describe "search form presence", :aggregate_failures do
    before do
      create(:savings_pool, user: user, name: "Emergency Fund")
      visit savings_pools_path
    end

    it "shows search field and field selector" do
      expect(page).to have_field("q")
      expect(page).to have_select("field")
    end
  end

  describe "create button navigation", :aggregate_failures do
    it "navigates to new savings pool page" do
      click_link "New Savings Pool"

      expect(page).to have_current_path(new_savings_pool_path)
      expect(page).to have_content("New Savings Pool")
    end
  end
end
