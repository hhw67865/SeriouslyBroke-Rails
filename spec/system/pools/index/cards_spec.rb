# frozen_string_literal: true

require "rails_helper"

# EVERY CONTRIBUTION HERE IS A MOVEMENT (plan 3, task 5). They were entries in a savings CATEGORY,
# which is the shape the cutover converted; every balance, percentage and card state below is
# unchanged, because `PoolCalculator#balance` counted that term and counts `movements_in` at the
# same sign. The card's activity strip is `Pool#timeline` now — see the "recent activity" group.
RSpec.describe "Savings Pools Index - Cards", type: :system do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let!(:pool) do
    create(:pool, user: user, name: "Emergency Fund", target_amount: 10_000, account: checking)
  end

  before { sign_in user, scope: :user }

  def contribute(amount, on: Date.current)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: amount, date: on)
  end

  describe "savings pool card display", :aggregate_failures do
    let!(:expense_category) { create(:category, user: user, category_type: :expense, pool: pool) }
    let!(:expense_item) { create(:item, category: expense_category) }

    # Current balance: (3 movements × $200) - (2 expenses × $50) = $600 - $100 = $500
    # Target: $10,000
    # Progress: ($500 / $10,000) × 100 = 5%

    before do
      3.times { contribute(200.0) }
      create_list(:entry, 2, item: expense_item, amount: 50.0)
      visit pools_path
    end

    it "shows correct current balance" do
      within(".bg-white.rounded", text: "Emergency Fund") do
        current_label = find("span.text-xs.text-gray-500", text: "Current")
        current_amount = current_label.sibling("span.text-base.font-semibold")
        expect(current_amount.text).to eq("$500.00")
      end
    end

    it "shows correct target amount" do
      within(".bg-white.rounded", text: "Emergency Fund") do
        target_label = find("span.text-xs.text-gray-500", text: "Target")
        target_amount = target_label.sibling("span.text-base.font-medium")
        expect(target_amount.text).to eq("$10,000.00")
      end
    end

    it "shows correct progress percentage" do
      within(".bg-white.rounded", text: "Emergency Fund") do
        expect(page).to have_content("5% complete")
      end
    end

    it "shows recent activity section" do
      within(".bg-white.rounded", text: "Emergency Fund") do
        expect(page).to have_content("Recent activity")
      end
    end
  end

  describe "progress states" do
    context "with 50% progress", :aggregate_failures do
      # Current balance: $5,000
      # Target: $10,000
      # Progress: 50%

      before do
        contribute(5000.0)
        visit pools_path
      end

      it "shows correct progress percentage and balance" do
        within(".bg-white.rounded", text: "Emergency Fund") do
          expect(page).to have_content("50% complete")

          current_label = find("span.text-xs.text-gray-500", text: "Current")
          current_amount = current_label.sibling("span.text-base.font-semibold")
          expect(current_amount.text).to eq("$5,000.00")
        end
      end
    end

    context "when goal is reached", :aggregate_failures do
      # Current balance: $10,000
      # Target: $10,000
      # Progress: 100%

      before do
        contribute(10_000.0)
        visit pools_path
      end

      it "shows goal reached message" do
        within(".bg-white.rounded", text: "Emergency Fund") do
          expect(page).to have_content("Goal reached!")
        end
      end
    end

    context "with negative balance", :aggregate_failures do
      let!(:expense_category) { create(:category, user: user, category_type: :expense, pool: pool) }
      let!(:expense_item) { create(:item, category: expense_category) }

      # Current balance: -$500
      # Target: $10,000
      # Progress: 0% — see below.

      before do
        create(:entry, item: expense_item, amount: 500.0)
        visit pools_path
      end

      # CHANGED WITH THE FLOOR (2d whole-plan review, fix 1). This pinned "-5% complete", which is
      # the figure `PoolCalculator#progress_percentage` produced before it clamped at zero as well
      # as at 100 — the same unclamped reader that drew "-30% complete" on an account's page. The
      # expectation was pinning the defect, so it moves with the fix: a bar measures how much of a
      # target is there, and less than none of it is there is still none of it.
      #
      # THE BALANCE ASSERTION IS UNTOUCHED AND IS THE POINT OF KEEPING THIS EXAMPLE. The money is
      # still -$500.00 and the card still says so in red — the clamp is on the RATIO, not on the
      # figure, and `Σ pools == your bank balance` would be broken by rounding an overdraft up to
      # zero anywhere.
      it "floors progress at zero and still prints the negative balance" do
        within(".bg-white.rounded", text: "Emergency Fund") do
          expect(page).to have_content("0% complete")
          expect(page).to have_no_content("-5% complete")

          current_label = find("span.text-xs.text-gray-500", text: "Current")
          current_amount = current_label.sibling("span.text-base.font-semibold")
          expect(current_amount.text).to eq("-$500.00")
        end
      end
    end
  end

  # THE CARD'S ACTIVITY STRIP IS `Pool#timeline` (plan 3, task 5): movements in and out plus the
  # spending of the categories pointing here. A movement's row names the pool at the OTHER end,
  # which is the fact a goal's history is about; an entry's names its item, exactly as before.
  describe "recent activity section", :aggregate_failures do
    let!(:expense_category) { create(:category, user: user, category_type: :expense, pool: pool) }
    let!(:withdrawal_item) { create(:item, category: expense_category, name: "Emergency Withdrawal") }

    before do
      contribute(1000, on: Date.current)
      create(:entry, item: withdrawal_item, amount: 200, date: Date.current - 1.day)
      visit pools_path
    end

    it "shows recent activity with both directions" do
      within(".bg-white.rounded", text: "Emergency Fund") do
        expect(page).to have_content("Recent activity")
        expect(page).to have_content("Checking")
        expect(page).to have_content("+$1,000.00")
        expect(page).to have_content("Emergency Withdrawal")
        expect(page).to have_content("-$200.00")
      end
    end
  end

  describe "card interactions", :aggregate_failures do
    before { visit pools_path }

    it "navigates to savings pool show page when clicked" do
      find("div.group", text: pool.name).click

      expect(page).to have_current_path(pool_path(pool))
      expect(page).to have_content(pool.name)
    end
  end
end
