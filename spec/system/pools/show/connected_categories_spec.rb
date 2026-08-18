# frozen_string_literal: true

require "rails_helper"

# ONE LIST, NOT TWO COLUMNS (plan 3, task 5). The section split its categories into "Contributing"
# (savings-typed) and "Withdrawing" (expense-typed); nothing contributes through a category any
# more — money arrives in a pool as a `PoolMovement`, which the timeline above this section lists —
# so the contributing column was an empty box on every pool of every user.
#
# THE ROW STILL ASKS WHICH WAY THE MONEY GOES, because two directions survive: an expense category
# spends out of the pool, and an INCOME category lands its paychecks in it, which only an account
# can be. Income rows were rendered by NEITHER old column, so that arm is new and is asserted here.
RSpec.describe "Savings Pools Show - Connected Categories", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let!(:pool) { create(:pool, user: user, name: "Emergency Fund", target_amount: 10_000, account: checking) }

  before { sign_in user, scope: :user }

  describe "with connected categories", :aggregate_failures do
    before do
      create(:category, user: user, name: "Medical Bills", category_type: :expense, pool: pool)
      create(:category, user: user, name: "Holiday Trips", category_type: :expense, pool: pool)
      visit pool_path(pool)
    end

    it "shows connected categories section" do
      expect(page).to have_content("Connected Categories")
      expect(page).to have_link("Manage Categories")
    end

    it "lists every connected category" do
      expect(page).to have_content("Medical Bills")
      expect(page).to have_content("Holiday Trips")
    end

    # THE COLUMN HEADINGS AND THEIR EMPTY STATES ARE GONE, both directions asserted: the surviving
    # sentence is on screen, and the two headings and the "No contributing categories connected"
    # box are not.
    it "says what a connected category does, in the pool's own noun", :aggregate_failures do
      expect(page).to have_content("Spends from this goal")
      expect(page).to have_no_content("Contributing Categories")
      expect(page).to have_no_content("Withdrawing Categories")
      expect(page).to have_no_content("No contributing categories connected")
      expect(page).to have_no_content("Savings category")
    end
  end

  describe "an income category on an account", :aggregate_failures do
    before do
      create(:category, user: user, name: "Salary", category_type: :income, pool: checking)
      create(:category, user: user, name: "Petrol", category_type: :expense, pool: checking)
      visit pool_path(checking)
    end

    # BOTH DIRECTIONS ON THE SURVIVING ROW BRANCH. An account is the one pool an income category may
    # name, and a single sentence for every row would have the salary category read "spends from
    # this buffer".
    it "says money lands in the buffer rather than being spent from it" do
      expect(page).to have_content("Lands in this buffer")
      expect(page).to have_content("Spends from this buffer")
    end
  end

  describe "with category amounts", :aggregate_failures do
    let!(:expense_category) { create(:category, user: user, name: "Medical Bills", category_type: :expense, pool: pool) }
    let!(:expense_item) { create(:item, category: expense_category) }

    before do
      travel_to Date.current.beginning_of_month do
        create(:entry, item: expense_item, amount: 90.0, date: Date.current + 1.day)
        create(:entry, item: expense_item, amount: 60.0, date: Date.current + 6.days)
      end

      prev_month = Date.current.prev_month
      travel_to prev_month.beginning_of_month do
        create(:entry, item: expense_item, amount: 40.0, date: prev_month.beginning_of_month + 3.days)
        create(:entry, item: expense_item, amount: 30.0, date: prev_month.beginning_of_month + 9.days)
      end

      visit pool_path(pool)
    end

    it "shows current month category amounts" do
      within("a.bg-status-danger-light", text: "Medical Bills") do
        expect(page).to have_content("-$150.00")
        expect(page).to have_content(Date.current.strftime("%B %Y"))
      end
    end

    it "updates category amounts when navigating to previous month" do
      find("button[title='Previous month']").click

      within("a.bg-status-danger-light", text: "Medical Bills") do
        expect(page).to have_content("-$70.00")
        expect(page).to have_content(Date.current.prev_month.strftime("%B %Y"))
      end
    end
  end

  describe "with no connected categories", :aggregate_failures do
    before { visit pool_path(pool) }

    it "shows empty state message" do
      expect(page).to have_content("No categories connected")
      expect(page).to have_content("Connect categories to start tracking your progress automatically")
    end

    it "shows connect first category button" do
      expect(page).to have_link("Connect Your First Category")
    end
  end

  describe "manage categories link", :aggregate_failures do
    before do
      create(:category, user: user, category_type: :expense, pool: pool)
      visit pool_path(pool)
    end

    it "navigates to categories management page" do
      click_link "Manage Categories"
      expect(page).to have_current_path(categories_pool_path(pool))
    end
  end

  describe "clickable category cards", :aggregate_failures do
    let!(:expense_category) do
      create(:category, user: user, name: "Medical Bills", category_type: :expense, pool: pool)
    end

    before { visit pool_path(pool) }

    it "renders the category card as a link to the category show page" do
      expect(page).to have_link("Medical Bills", href: category_path(expense_category))
    end

    it "navigates to the category show page when a card is clicked" do
      click_link "Medical Bills"
      expect(page).to have_current_path(category_path(expense_category))
    end
  end
end
