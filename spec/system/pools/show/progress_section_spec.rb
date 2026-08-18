# frozen_string_literal: true

require "rails_helper"

# EVERY CONTRIBUTION HERE IS A MOVEMENT (plan 3, task 5). They were entries in a savings CATEGORY,
# the shape the cutover converted; every balance, percentage, badge and tile below is unchanged,
# because `PoolCalculator#balance` counted that term and counts `movements_in` at the same sign.
RSpec.describe "Savings Pools Show - Progress Section", type: :system do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let!(:pool) { create(:pool, user: user, name: "Emergency Fund", target_amount: 10_000, account: checking) }
  let!(:expense_category) { create(:category, user: user, category_type: :expense, pool: pool) }

  before { sign_in user, scope: :user }

  def contribute(amount) = create(:pool_movement, from_pool: checking, to_pool: pool, amount: amount)

  describe "progress metrics", :aggregate_failures do
    let!(:expense_item) { create(:item, category: expense_category) }

    before do
      # Contributions: 3 × $200 = $600
      3.times { contribute(200.0) }
      # Withdrawals: 2 × $50 = $100
      create_list(:entry, 2, item: expense_item, amount: 50.0)
      # Current balance: $600 - $100 = $500
      # Progress: ($500 / $10,000) × 100 = 5%

      visit pool_path(pool)
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
      before do
        contribute(5000.0)
        visit pool_path(pool)
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
      before do
        contribute(8000.0)
        visit pool_path(pool)
      end

      it "shows correct progress and status" do
        expect(page).to have_content("80% complete")
        expect(page).to have_content("Almost There")
      end
    end

    context "when goal is reached", :aggregate_failures do
      before do
        contribute(10_000.0)
        visit pool_path(pool)
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
        visit pool_path(pool)
      end

      # CHANGED WITH THE FLOOR (2d whole-plan review, fix 1). This pinned "-5% Complete" — the red
      # badge branch that `PoolCalculator#progress_percentage` reached before it clamped at zero,
      # and the same unclamped reader that put "-30% complete" on an account's page. The
      # expectation was pinning the defect, so it moves with the fix; the badge falls back to the
      # bottom band, which is what 0% means on this page for every other pool at 0%.
      it "floors progress at zero rather than reading it back as a negative percentage" do
        expect(page).to have_content("0% complete")
        expect(page).to have_no_content("-5%")
        expect(page).to have_content("Getting Started")
      end

      # UNTOUCHED, AND THE REASON THE EXAMPLE ABOVE IS SAFE: the clamp is on the RATIO and not on
      # the money. The overdraft is still -$500.00 on screen and in the ledger.
      it "shows negative current balance" do
        metric_boxes = page.all("div.text-center")
        current_balance_box = metric_boxes.find { |box| box.text.include?("CURRENT BALANCE") }
        expect(current_balance_box).to have_content("-$500.00")
      end
    end
  end

  # WHOSE TARGET IS A GOAL (2d whole-plan review, fix 1, second half). All three pool kinds may
  # carry a `target_amount` — the form says so — and this page gated its whole savings hero on
  # `target_amount.present?` alone, so an ACCOUNT got a progress bar, a "% complete" figure and a
  # "Still Needed" tile measured against its buffer marker. On the demo that was Side Gig
  # Checking: a $1,000 marker, a -$300 overdraft and "-30% complete" drawn in red, one click from
  # Task 6's "View Account" button on the category page.
  #
  # BOTH DIRECTIONS PER TYPE, because a gate that took the bar off the savings goal too would
  # "pass" the negative assertions while removing the feature.
  describe "a target that is not a goal", :aggregate_failures do
    # The demo's own shape: a $1,000 buffer marker and $300 moved out to an envelope, leaving the
    # account overdrawn.
    def overdrawn_account
      create(:pool, :account, user: user, name: "Side Gig Checking", target_amount: 1_000).tap do |account|
        envelope = create(:pool, :budget_pool, user: user, account: account, name: "Groceries")
        create(:pool_movement, from_pool: account, to_pool: envelope, amount: 300, date: Date.current)
      end
    end

    it "gives an account the buffer register and no savings chrome" do
      visit pool_path(overdrawn_account)

      # The tile labels are CSS-uppercased, so that is what Capybara reads and what these assert —
      # the same shape `metric_boxes.find { |box| box.text.include?("CURRENT BALANCE") }` above
      # already relies on.
      expect(page).to have_no_content("% complete")
      expect(page).to have_no_content("-30")
      expect(page).to have_no_content("STILL NEEDED")
      expect(page).to have_no_content("TARGET GOAL")
      expect(page).to have_no_content("Goal Achieved")
      # What replaced it: Home's own words for an account's target, and the money still said out
      # loud — `Σ pools == your bank balance` is not softened by taking the bar off.
      expect(page).to have_content("BUFFER TARGET")
      expect(page).to have_css("[data-buffer-marker]", text: "buffer now -$300.00 · target $1,000.00")
    end

    # THE OTHER DIRECTION. Same page, same "has a target" condition, a savings pool: the hero is
    # exactly as it was.
    it "leaves a savings goal's progress hero standing" do
      visit pool_path(pool)

      expect(page).to have_content("0% complete")
      expect(page).to have_content("TARGET GOAL")
      expect(page).to have_content("STILL NEEDED")
      expect(page).to have_no_css("[data-buffer-marker]")
    end

    # AND THE THIRD KIND. An envelope's target is read by nothing in the app — no sweep, no fill,
    # no status — so the figure the user typed is still printed back, under a label that does not
    # call it a goal, and without the bar or the "Still Needed" shortfall.
    it "prints a budget envelope's target without calling it a goal" do
      # The `checking` account is already this user's (the goal above lives in it), and Pool
      # validates its name unique per user.
      envelope = create(:pool, :budget_pool, user: user, account: checking, name: "Groceries", target_amount: 400)

      visit pool_path(envelope)

      expect(page).to have_content("TARGET")
      expect(page).to have_content("$400.00")
      expect(page).to have_no_content("% complete")
      expect(page).to have_no_content("TARGET GOAL")
      expect(page).to have_no_content("STILL NEEDED")
    end
  end
end
