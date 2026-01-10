# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings Pools Categories - Manage", type: :system do
  let!(:user) { create(:user) }
  let!(:savings_pool) { create(:savings_pool, name: "Emergency Fund", user: user) }

  before do
    sign_in user, scope: :user
  end

  describe "page display", :aggregate_failures do
    before { visit categories_savings_pool_path(savings_pool) }

    it "shows page header and instructions" do
      expect(page).to have_content("Manage Categories")
      expect(page).to have_content("Connect categories to Emergency Fund")
      expect(page).to have_content("How Category Connections Work")
    end

    it "shows form action buttons" do
      expect(page).to have_button("Update Connected Categories")
      expect(page).to have_link("Cancel")
    end
  end

  describe "empty state with no categories", :aggregate_failures do
    before { visit categories_savings_pool_path(savings_pool) }

    it "does not show category section headings when no categories exist" do
      expect(page).not_to have_css("h3", text: /Savings Categories \(\d+\)/)
      expect(page).not_to have_css("h3", text: /Expense Categories \(\d+\)/)
    end
  end

  describe "category display" do
    let!(:savings_category) { create(:category, name: "Monthly Savings", category_type: "savings", user: user) }
    let!(:expense_category) { create(:category, name: "Vacation Expenses", category_type: "expense", user: user) }
    let!(:income_category) { create(:category, name: "Salary", category_type: "income", user: user) }

    before { visit categories_savings_pool_path(savings_pool) }

    it "shows savings and expense categories separated", :aggregate_failures do
      expect(page).to have_content("Savings Categories (1)")
      expect(page).to have_content("Expense Categories (1)")
      expect(page).to have_content("Monthly Savings")
      expect(page).to have_content("Vacation Expenses")
    end

    it "does not show income categories" do
      expect(page).not_to have_content("Salary")
      expect(page).not_to have_content("Income Categories")
    end

    it "shows available status for unconnected categories", :aggregate_failures do
      within(:xpath, "//label[contains(., 'Monthly Savings')]") do
        expect(page).to have_content("Available to connect")
      end
    end

    it "displays monthly amount for each category", :aggregate_failures do
      expect(page).to have_content("this month", minimum: 1)
    end
  end

  describe "connecting categories" do
    let!(:savings_category) { create(:category, name: "Monthly Savings", category_type: "savings", user: user) }
    let!(:expense_category) { create(:category, name: "Vacation Expenses", category_type: "expense", user: user) }

    before { visit categories_savings_pool_path(savings_pool) }

    it "connects a single savings category", :aggregate_failures do
      within(:xpath, "//label[contains(., 'Monthly Savings')]") do
        find("input[type='checkbox']").check
      end
      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      expect(page).to have_current_path(savings_pool_path(savings_pool))
      savings_category.reload
      expect(savings_category.savings_pool).to eq(savings_pool)
    end

    it "connects a single expense category", :aggregate_failures do
      within(:xpath, "//label[contains(., 'Vacation Expenses')]") do
        find("input[type='checkbox']").check
      end
      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      expense_category.reload
      expect(expense_category.savings_pool).to eq(savings_pool)
    end

    it "connects multiple categories at once", :aggregate_failures do
      within(:xpath, "//label[contains(., 'Monthly Savings')]") do
        find("input[type='checkbox']").check
      end
      within(:xpath, "//label[contains(., 'Vacation Expenses')]") do
        find("input[type='checkbox']").check
      end
      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      savings_category.reload
      expense_category.reload
      expect(savings_category.savings_pool).to eq(savings_pool)
      expect(expense_category.savings_pool).to eq(savings_pool)
    end
  end

  describe "disconnecting categories" do
    let!(:connected_savings) do
      create(
        :category,
        name: "Connected Savings",
        category_type: "savings",
        user: user,
        savings_pool: savings_pool
      )
    end
    let!(:other_savings) do
      create(:category, name: "Other Savings", category_type: "savings", user: user)
    end

    before { visit categories_savings_pool_path(savings_pool) }

    it "shows connected status for connected categories", :aggregate_failures do
      within(:xpath, "//label[contains(., 'Connected Savings')]") do
        expect(page).to have_content("Connected")
        expect(find("input[type='checkbox']")).to be_checked
      end
    end

    it "disconnects a category by connecting a different one", :aggregate_failures do
      within(:xpath, "//label[contains(., 'Connected Savings')]") do
        find("input[type='checkbox']").uncheck
      end
      within(:xpath, "//label[contains(., 'Other Savings')]") do
        find("input[type='checkbox']").check
      end

      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      connected_savings.reload
      other_savings.reload
      expect(connected_savings.savings_pool).to be_nil
      expect(other_savings.savings_pool).to eq(savings_pool)
    end
  end

  describe "category conflicts" do
    let!(:other_pool) { create(:savings_pool, name: "Other Pool", user: user) }
    let!(:conflicting_category) do
      create(
        :category,
        name: "Conflicting Category",
        category_type: "savings",
        user: user,
        savings_pool: other_pool
      )
    end

    before { visit categories_savings_pool_path(savings_pool) }

    it "shows conflict warning for categories connected to other pools", :aggregate_failures do
      within(:xpath, "//label[contains(., 'Conflicting Category')]") do
        expect(page).to have_content("Connected to Other Pool")
      end
    end

    it "allows reassigning category from one pool to another", :aggregate_failures do
      within(:xpath, "//label[contains(., 'Conflicting Category')]") do
        find("input[type='checkbox']").check
      end
      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      expect(page).to have_current_path(savings_pool_path(savings_pool))
      conflicting_category.reload
      expect(conflicting_category.savings_pool).to eq(savings_pool)
    end
  end

  describe "navigation", :aggregate_failures do
    before { visit categories_savings_pool_path(savings_pool) }

    it "returns to savings pool show page when clicking cancel" do
      click_link "Cancel"
      expect(page).to have_current_path(savings_pool_path(savings_pool))
    end
  end
end
