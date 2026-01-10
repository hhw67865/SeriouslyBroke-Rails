# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings Pools Index - Cards", type: :system do
  let(:user) { create(:user) }
  let!(:savings_pool) do
    create(:savings_pool, user: user, name: "Emergency Fund", target_amount: 10_000)
  end

  before { sign_in user, scope: :user }

  describe "savings pool card display", :aggregate_failures do
    let!(:savings_category) { create(:category, user: user, category_type: :savings, savings_pool: savings_pool) }
    let!(:expense_category) { create(:category, user: user, category_type: :expense, savings_pool: savings_pool) }
    let!(:savings_item) { create(:item, category: savings_category) }
    let!(:expense_item) { create(:item, category: expense_category) }

    # Current balance: (3 savings × $200) - (2 expenses × $50) = $600 - $100 = $500
    # Target: $10,000
    # Progress: ($500 / $10,000) × 100 = 5%

    before do
      create_list(:entry, 3, item: savings_item, amount: 200.0)
      create_list(:entry, 2, item: expense_item, amount: 50.0)
      visit savings_pools_path
    end

    it "shows correct current balance" do
      within(".bg-white.rounded-xl", text: "Emergency Fund") do
        current_label = find("span.text-xs.text-gray-500", text: "Current")
        current_amount = current_label.sibling("span.text-base.font-semibold")
        expect(current_amount.text).to eq("$500.00")
      end
    end

    it "shows correct target amount" do
      within(".bg-white.rounded-xl", text: "Emergency Fund") do
        target_label = find("span.text-xs.text-gray-500", text: "Target")
        target_amount = target_label.sibling("span.text-base.font-medium")
        expect(target_amount.text).to eq("$10,000.00")
      end
    end

    it "shows correct progress percentage" do
      within(".bg-white.rounded-xl", text: "Emergency Fund") do
        expect(page).to have_content("5% complete")
      end
    end

    it "shows recent activity section" do
      within(".bg-white.rounded-xl", text: "Emergency Fund") do
        expect(page).to have_content("Recent activity")
      end
    end
  end

  describe "progress states" do
    context "with 50% progress", :aggregate_failures do
      let!(:savings_category) { create(:category, user: user, category_type: :savings, savings_pool: savings_pool) }
      let!(:savings_item) { create(:item, category: savings_category) }

      # Current balance: $5,000
      # Target: $10,000
      # Progress: 50%

      before do
        create(:entry, item: savings_item, amount: 5000.0)
        visit savings_pools_path
      end

      it "shows correct progress percentage and balance" do
        within(".bg-white.rounded-xl", text: "Emergency Fund") do
          expect(page).to have_content("50% complete")

          current_label = find("span.text-xs.text-gray-500", text: "Current")
          current_amount = current_label.sibling("span.text-base.font-semibold")
          expect(current_amount.text).to eq("$5,000.00")
        end
      end
    end

    context "when goal is reached", :aggregate_failures do
      let!(:savings_category) { create(:category, user: user, category_type: :savings, savings_pool: savings_pool) }
      let!(:savings_item) { create(:item, category: savings_category) }

      # Current balance: $10,000
      # Target: $10,000
      # Progress: 100%

      before do
        create(:entry, item: savings_item, amount: 10_000.0)
        visit savings_pools_path
      end

      it "shows goal reached message" do
        within(".bg-white.rounded-xl", text: "Emergency Fund") do
          expect(page).to have_content("Goal reached!")
        end
      end
    end

    context "with negative balance", :aggregate_failures do
      let!(:expense_category) { create(:category, user: user, category_type: :expense, savings_pool: savings_pool) }
      let!(:expense_item) { create(:item, category: expense_category) }

      # Current balance: -$500
      # Target: $10,000
      # Progress: -5%

      before do
        create(:entry, item: expense_item, amount: 500.0)
        visit savings_pools_path
      end

      it "shows negative progress and balance" do
        within(".bg-white.rounded-xl", text: "Emergency Fund") do
          expect(page).to have_content("-5% complete")

          current_label = find("span.text-xs.text-gray-500", text: "Current")
          current_amount = current_label.sibling("span.text-base.font-semibold")
          expect(current_amount.text).to eq("-$500.00")
        end
      end
    end
  end

  describe "recent activity section", :aggregate_failures do
    let!(:savings_category) do
      create(
        :category,
        user: user,
        category_type: :savings,
        savings_pool: savings_pool
      )
    end
    let!(:expense_category) do
      create(
        :category,
        user: user,
        category_type: :expense,
        savings_pool: savings_pool
      )
    end
    let!(:deposit_item) { create(:item, category: savings_category, name: "Monthly Deposit") }
    let!(:withdrawal_item) { create(:item, category: expense_category, name: "Emergency Withdrawal") }

    before do
      create(:entry, item: deposit_item, amount: 1000, date: Date.current)
      create(:entry, item: withdrawal_item, amount: 200, date: Date.current - 1.day)
      visit savings_pools_path
    end

    it "shows recent activity with correct entry details" do
      within(".bg-white.rounded-xl", text: "Emergency Fund") do
        expect(page).to have_content("Recent activity")
        expect(page).to have_content("Monthly Deposit")
        expect(page).to have_content("+$1,000.00")
        expect(page).to have_content("Emergency Withdrawal")
        expect(page).to have_content("-$200.00")
      end
    end
  end

  describe "card interactions", :aggregate_failures do
    before { visit savings_pools_path }

    it "navigates to savings pool show page when clicked" do
      find("div.group", text: savings_pool.name).click

      expect(page).to have_current_path(savings_pool_path(savings_pool))
      expect(page).to have_content(savings_pool.name)
    end
  end
end
