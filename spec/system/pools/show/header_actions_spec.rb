# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings Pools Show - Header Actions", type: :system do
  let(:user) { create(:user) }
  let!(:pool) { create(:pool, user: user, name: "Emergency Fund", target_amount: 10_000) }

  before do
    sign_in user, scope: :user
    visit pool_path(pool)
  end

  describe "page header", :aggregate_failures do
    it "shows savings pool name" do
      expect(page).to have_content("Emergency Fund")
    end

    it "shows breadcrumbs" do
      expect(page).to have_link("Savings Pools", href: pools_path)
      expect(page).to have_content("Emergency Fund")
    end
  end

  describe "edit action", :aggregate_failures do
    it "shows edit button" do
      expect(page).to have_link("Edit", href: edit_pool_path(pool))
    end

    it "navigates to edit page" do
      click_link "Edit"

      expect(page).to have_current_path(edit_pool_path(pool))
      expect(page).to have_content("Edit Savings Pool")
    end
  end

  describe "delete action", :aggregate_failures do
    it "shows delete button with confirmation" do
      delete_button = find("button", text: "Delete")

      expect(delete_button["data-turbo-confirm"]).to be_present
    end

    it "deletes savings pool when confirmed" do
      pool_id = pool.id
      expect(Pool.exists?(pool_id)).to be(true)

      accept_confirm do
        click_button "Delete"
      end

      expect(page).to have_current_path(pools_path)
      expect(page).to have_content("Savings pool was successfully deleted")
      expect(Pool.exists?(pool_id)).to be(false)
    end

    # Both target_amounts are set only so the pool pages render: account and budget pools
    # normally leave target_amount nil, and PoolCalculator#remaining_amount cannot handle
    # nil yet (Plan 2 rebuilds these views). Not what this example is testing.
    it "refuses to delete an account that still holds pools" do
      checking = create(:pool, :account, user: user, name: "Checking", target_amount: 5_000)
      create(:pool, :budget_pool, user: user, account: checking, name: "Groceries", target_amount: 500)
      visit pool_path(checking)

      accept_confirm do
        click_button "Delete"
      end

      expect(page).to have_content("Cannot delete record because dependent child pools exist")
      expect(Pool.exists?(checking.id)).to be(true)
    end
  end

  describe "breadcrumb navigation", :aggregate_failures do
    it "navigates back to savings pools index" do
      within("nav[aria-label='Breadcrumb']") do
        click_link "Savings Pools"
      end

      expect(page).to have_current_path(pools_path)
      expect(page).to have_content("Track your financial goals and savings progress")
    end
  end
end
