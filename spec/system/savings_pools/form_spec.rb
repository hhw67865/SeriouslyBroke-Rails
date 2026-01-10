# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings Pools Form", type: :system do
  let!(:user) { create(:user) }

  before { sign_in user, scope: :user }

  describe "New Form" do
    before { visit new_savings_pool_path }

    describe "form display", :aggregate_failures do
      it "shows all form elements" do
        expect(page).to have_field("Savings Pool Name")
        expect(page).to have_field("Target Amount")
        expect(page).to have_button("Create Savings Pool")
      end

      it "shows navigation elements" do
        expect(page).to have_link("Cancel")
      end

      it "shows informational content" do
        expect(page).to have_content("How it works")
        expect(page).to have_content("After creating your goal, connect categories")
      end

      it "does not show progress indicator for new pool" do
        expect(page).not_to have_content("Current Progress")
      end
    end

    describe "form validation", :aggregate_failures do
      it "shows error for missing name" do
        fill_in "Target Amount", with: "1000"
        click_button "Create Savings Pool"

        expect(page).to have_content("can't be blank")
        expect(page).to have_field("Savings Pool Name")
      end

      it "shows error for missing target amount" do
        fill_in "Savings Pool Name", with: "Emergency Fund"
        click_button "Create Savings Pool"

        expect(page).to have_content("can't be blank")
        expect(page).to have_field("Target Amount")
      end

      it "shows errors for both missing fields" do
        click_button "Create Savings Pool"

        expect(page).to have_content("can't be blank", count: 2)
      end
    end

    describe "successful submission", :aggregate_failures do
      it "creates savings pool and redirects to show page" do
        fill_in "Savings Pool Name", with: "Emergency Fund"
        fill_in "Target Amount", with: "5000"
        click_button "Create Savings Pool"

        expect(page).to have_content("Savings pool was successfully created")
        expect(page).to have_current_path(savings_pool_path(SavingsPool.last))
        expect(page).to have_content("Emergency Fund")
      end

      it "creates savings pool with correct attributes" do
        fill_in "Savings Pool Name", with: "Vacation Fund"
        fill_in "Target Amount", with: "2500"
        click_button "Create Savings Pool"

        expect(page).to have_content("Savings pool was successfully created")
        pool = SavingsPool.last
        expect(pool.name).to eq("Vacation Fund")
        expect(pool.target_amount).to eq(2500)
        expect(pool.user).to eq(user)
      end
    end

    describe "navigation", :aggregate_failures do
      it "returns to index when clicking cancel" do
        click_link "Cancel"
        expect(page).to have_current_path(savings_pools_path)
      end
    end
  end

  describe "Edit Form" do
    let!(:savings_pool) { create(:savings_pool, name: "Original Name", target_amount: 1000, user: user) }

    before { visit edit_savings_pool_path(savings_pool) }

    describe "form display", :aggregate_failures do
      it "shows all form elements pre-filled" do
        expect(page).to have_field("Savings Pool Name", with: "Original Name")
        expect(page).to have_field("Target Amount", with: "1000.0")
        expect(page).to have_button("Update Savings Pool")
      end

      it "shows navigation elements" do
        expect(page).to have_link("Cancel")
      end

      it "shows current progress section" do
        expect(page).to have_content("Current Progress")
        expect(page).to have_content("Progress toward goal")
      end
    end

    describe "progress indicator with data", :aggregate_failures do
      let!(:savings_category) { create(:category, category_type: "savings", user: user, savings_pool: savings_pool) }
      let!(:savings_item) { create(:item, category: savings_category) }

      before do
        create(:entry, item: savings_item, amount: 300)
        visit edit_savings_pool_path(savings_pool)
      end

      it "shows current balance and progress" do
        expect(page).to have_content("$300.00")
        expect(page).to have_content("30%")
      end

      it "shows remaining amount" do
        expect(page).to have_content("$700.00")
      end
    end

    describe "form validation", :aggregate_failures do
      it "shows error when name is removed" do
        fill_in "Savings Pool Name", with: ""
        click_button "Update Savings Pool"

        expect(page).to have_content("can't be blank")
        expect(page).to have_field("Savings Pool Name")
      end
    end

    describe "successful update", :aggregate_failures do
      it "updates name and redirects to show page" do
        fill_in "Savings Pool Name", with: "Updated Name"
        click_button "Update Savings Pool"

        expect(page).to have_content("Savings pool was successfully updated")
        expect(page).to have_current_path(savings_pool_path(savings_pool))
        expect(page).to have_content("Updated Name")
      end

      it "updates target amount" do
        fill_in "Target Amount", with: "5000"
        click_button "Update Savings Pool"

        expect(page).to have_content("Savings pool was successfully updated")
        savings_pool.reload
        expect(savings_pool.target_amount).to eq(5000)
      end

      it "updates both fields simultaneously" do
        fill_in "Savings Pool Name", with: "New Vacation Fund"
        fill_in "Target Amount", with: "3500"
        click_button "Update Savings Pool"

        expect(page).to have_content("Savings pool was successfully updated")
        savings_pool.reload
        expect(savings_pool.name).to eq("New Vacation Fund")
        expect(savings_pool.target_amount).to eq(3500)
      end
    end

    describe "navigation", :aggregate_failures do
      it "returns to index when clicking cancel" do
        click_link "Cancel"
        expect(page).to have_current_path(savings_pools_path)
      end
    end
  end
end
