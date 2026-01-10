# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings Pools Show - Progress Section", type: :system do
  let(:user) { create(:user) }
  let!(:savings_pool) { create(:savings_pool, user: user, name: "Emergency Fund", target_amount: 10_000) }
  let!(:savings_category) { create(:category, user: user, category_type: :savings, savings_pool: savings_pool) }
  let!(:expense_category) { create(:category, user: user, category_type: :expense, savings_pool: savings_pool) }

  before { sign_in user, scope: :user }

  describe "progress metrics", :aggregate_failures do
    let!(:savings_item) { create(:item, category: savings_category) }
    let!(:expense_item) { create(:item, category: expense_category) }

    before do
      # Contributions: 3 × $200 = $600
      create_list(:entry, 3, item: savings_item, amount: 200.0)
      # Withdrawals: 2 × $50 = $100
      create_list(:entry, 2, item: expense_item, amount: 50.0)
      # Current balance: $600 - $100 = $500
      # Progress: ($500 / $10,000) × 100 = 5%

      visit savings_pool_path(savings_pool)
    end

    it "shows correct progress percentage" do
      expect(page).to have_content("5% complete")
    end

    it "shows correct current balance" do
      metric_boxes = page.all("div.text-center")
      current_balance_box = metric_boxes.find { |box| box.text.include?("CURRENT BALANCE") }
      expect(current_balance_box).to have_content("$500.00")
    end

    it "shows correct target amount" do
      metric_boxes = page.all("div.text-center")
      target_box = metric_boxes.find { |box| box.text.include?("TARGET GOAL") }
      expect(target_box).to have_content("$10,000.00")
    end

    it "shows correct remaining amount" do
      metric_boxes = page.all("div.text-center")
      remaining_box = metric_boxes.find { |box| box.text.include?("STILL NEEDED") }
      expect(remaining_box).to have_content("$9,500.00")
    end

    it "shows correct status badge" do
      expect(page).to have_content("Getting Started")
    end
  end

  describe "progress states" do
    context "with 50% progress", :aggregate_failures do
      let!(:savings_item) { create(:item, category: savings_category) }

      before do
        create(:entry, item: savings_item, amount: 5000.0)
        visit savings_pool_path(savings_pool)
      end

      it "shows correct progress and status" do
        expect(page).to have_content("50% complete")
        expect(page).to have_content("Making Progress")
      end

      it "shows correct remaining amount" do
        metric_boxes = page.all("div.text-center")
        remaining_box = metric_boxes.find { |box| box.text.include?("STILL NEEDED") }
        expect(remaining_box).to have_content("$5,000.00")
      end
    end

    context "with 80% progress", :aggregate_failures do
      let!(:savings_item) { create(:item, category: savings_category) }

      before do
        create(:entry, item: savings_item, amount: 8000.0)
        visit savings_pool_path(savings_pool)
      end

      it "shows correct progress and status" do
        expect(page).to have_content("80% complete")
        expect(page).to have_content("Almost There")
      end
    end

    context "when goal is reached", :aggregate_failures do
      let!(:savings_item) { create(:item, category: savings_category) }

      before do
        create(:entry, item: savings_item, amount: 10_000.0)
        visit savings_pool_path(savings_pool)
      end

      it "shows goal achieved status" do
        expect(page).to have_content("100% complete")
        expect(page).to have_content("Goal Achieved!")
      end

      it "shows excess saved instead of still needed" do
        metric_boxes = page.all("div.text-center")
        excess_box = metric_boxes.find { |box| box.text.include?("EXCESS SAVED") }
        expect(excess_box).to have_content("$0.00")
      end
    end

    context "with negative balance", :aggregate_failures do
      let!(:expense_item) { create(:item, category: expense_category) }

      before do
        create(:entry, item: expense_item, amount: 500.0)
        visit savings_pool_path(savings_pool)
      end

      it "shows negative progress" do
        expect(page).to have_content("-5% Complete")
      end

      it "shows negative current balance" do
        metric_boxes = page.all("div.text-center")
        current_balance_box = metric_boxes.find { |box| box.text.include?("CURRENT BALANCE") }
        expect(current_balance_box).to have_content("-$500.00")
      end
    end
  end
end
