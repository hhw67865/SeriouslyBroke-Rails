# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings Pools Index - Empty State", type: :system do
  let(:user) { create(:user) }

  before do
    sign_in user, scope: :user
  end

  describe "when no savings pools exist", :aggregate_failures do
    before { visit savings_pools_path }

    it "shows empty state message" do
      expect(page).to have_content("No savings pools yet")
      expect(page).to have_content("Start building your financial future by creating your first savings pool.")
    end

    it "provides link to create first savings pool" do
      expect(page).to have_link("Create Your First Goal")
    end

    it "navigates to new savings pool page when clicking create link" do
      click_link "Create Your First Goal"

      expect(page).to have_current_path(new_savings_pool_path)
      expect(page).to have_content("New Savings Pool")
    end
  end

  describe "when search returns no results", :aggregate_failures do
    before do
      create(:savings_pool, user: user, name: "Emergency Fund")
      create(:savings_pool, user: user, name: "Vacation Fund")
      visit savings_pools_path
      fill_in "q", with: "Nonexistent"
      find("input[name='q']").send_keys(:return)
    end

    it "shows no results message" do
      expect(page).to have_content("No savings pools yet")
    end

    it "provides option to clear search" do
      click_link "Clear search"

      expect(page).to have_content("Emergency Fund")
      expect(page).to have_content("Vacation Fund")
    end
  end
end
