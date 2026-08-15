# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings Pools Show - Header Actions", type: :system do
  let(:user) { create(:user) }
  let!(:savings_pool) { create(:savings_pool, user: user, name: "Emergency Fund", target_amount: 10_000) }

  before do
    sign_in user, scope: :user
    visit savings_pool_path(savings_pool)
  end

  describe "page header", :aggregate_failures do
    it "shows savings pool name" do
      expect(page).to have_content("Emergency Fund")
    end

    it "shows breadcrumbs" do
      expect(page).to have_link("Savings Pools", href: savings_pools_path)
      expect(page).to have_content("Emergency Fund")
    end
  end

  describe "edit action", :aggregate_failures do
    it "shows edit button" do
      expect(page).to have_link("Edit", href: edit_savings_pool_path(savings_pool))
    end

    it "navigates to edit page" do
      click_link "Edit"

      expect(page).to have_current_path(edit_savings_pool_path(savings_pool))
      expect(page).to have_content("Edit Savings Pool")
    end
  end

  describe "delete action", :aggregate_failures do
    it "shows delete button with confirmation" do
      delete_button = find("button", text: "Delete")

      expect(delete_button["data-turbo-confirm"]).to be_present
    end

    it "deletes savings pool when confirmed" do
      savings_pool_id = savings_pool.id
      expect(SavingsPool.exists?(savings_pool_id)).to be(true)

      accept_confirm do
        click_button "Delete"
      end

      expect(page).to have_current_path(savings_pools_path)
      expect(page).to have_content("Savings pool was successfully deleted")
      expect(SavingsPool.exists?(savings_pool_id)).to be(false)
    end
  end

  describe "breadcrumb navigation", :aggregate_failures do
    it "navigates back to savings pools index" do
      within("nav[aria-label='Breadcrumb']") do
        click_link "Savings Pools"
      end

      expect(page).to have_current_path(savings_pools_path)
      expect(page).to have_content("Track your financial goals and savings progress")
    end
  end
end
