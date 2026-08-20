# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings Pools Categories - Manage", type: :system do
  let!(:user) { create(:user) }

  # THE GOAL IS HOUSED IN AN ACCOUNT, which is the post-cutover shape (the migration houses every
  # non-account pool) and is load-bearing here: DISCONNECTING a category hands it back to the
  # pool's account, because `Category belongs_to :pool` refuses the nil this screen used to write.
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let!(:pool) { create(:pool, :savings_pool, name: "Emergency Fund", user: user, account: checking) }

  before do
    sign_in user, scope: :user
  end

  describe "page display", :aggregate_failures do
    before { visit categories_pool_path(pool) }

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
    before { visit categories_pool_path(pool) }

    it "shows the section with a zero count and no rows", :aggregate_failures do
      expect(page).to have_content("Expense Categories (0)")
      expect(page).to have_content("No expense categories found")
      expect(page).to have_no_content("Savings Categories")
    end
  end

  # ONE GROUP, NOT TWO (plan 3, task 5). The screen offered SAVINGS categories as contributors and
  # EXPENSE ones as withdrawers; nothing contributes through a category any more, so the controller
  # loads expense categories only and the type heading has one arm.
  describe "category display", :aggregate_failures do
    before do
      create(:category, name: "Household Bills", category_type: "expense", user: user, pool: checking)
      create(:category, name: "Vacation Expenses", category_type: "expense", user: user, pool: checking)
      create(:category, name: "Salary", category_type: "income", user: user, pool: checking)
      visit categories_pool_path(pool)
    end

    it "lists the expense categories under one heading", :aggregate_failures do
      expect(page).to have_content("Expense Categories (2)")
      expect(page).to have_content("Household Bills")
      expect(page).to have_content("Vacation Expenses")
      expect(page).to have_no_content("Savings Categories")
    end

    it "does not show income categories" do
      expect(page).not_to have_content("Salary")
      expect(page).not_to have_content("Income Categories")
    end

    # "Available to connect" — the arm for a category with NO pool at all — is unreachable since
    # plan 3 required a pool on every category. A category not connected to THIS goal is connected
    # to something, and the row says which, which is the more useful sentence anyway: it is where
    # the money currently lives.
    it "names the pool an unconnected category's money currently lives in" do
      within(:xpath, "//label[contains(., 'Household Bills')]") do
        expect(page).to have_content("Connected to Checking")
        expect(page).to have_no_content("Available to connect")
      end
    end

    it "displays monthly amount for each category" do
      expect(page).to have_content("this month", minimum: 1)
    end
  end

  describe "connecting categories" do
    let!(:household) { create(:category, name: "Household Bills", category_type: "expense", user: user) }
    let!(:expense_category) { create(:category, name: "Vacation Expenses", category_type: "expense", user: user) }

    before { visit categories_pool_path(pool) }

    it "connects a single category", :aggregate_failures do
      check_category("Household Bills")
      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      expect(page).to have_current_path(pool_path(pool))
      expect(household.reload.pool).to eq(pool)
    end

    it "connects multiple categories at once", :aggregate_failures do
      check_category("Household Bills")
      check_category("Vacation Expenses")
      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      expect(household.reload.pool).to eq(pool)
      expect(expense_category.reload.pool).to eq(pool)
    end
  end

  describe "disconnecting categories" do
    let!(:connected_spending) do
      create(
        :category,
        name: "Connected Spending",
        category_type: "expense",
        user: user,
        pool: pool
      )
    end
    let!(:other_spending) do
      create(:category, name: "Other Spending", category_type: "expense", user: user)
    end

    before { visit categories_pool_path(pool) }

    it "shows connected status for connected categories", :aggregate_failures do
      expect(category_label("Connected Spending")).to have_content("Connected")
      expect(category_checkbox("Connected Spending")).to be_checked
    end

    # DISCONNECTING HANDS THE CATEGORY BACK TO THE GOAL'S ACCOUNT (plan 3, task 3). It used to null
    # `pool_id`, which `Category belongs_to :pool` now refuses — `update` returned false, the
    # category stayed connected, and the page said "Categories updated successfully!" over it. The
    # destination is the one `Pool#hand_categories_to_the_account` already uses when a pool is
    # destroyed, so the category's history moves into the buffer rather than out of the pool tree.
    # THE LONE-UNCHECK, and it is the case the screen has ALWAYS got wrong. Rails emits a hidden
    # `""` per checkbox, so unchecking everything submits `[""]`; on a uuid column that casts to nil
    # and a single-element array renders `id != NULL`, which is NULL for every row — so `where.not`
    # matched nothing and the disconnect silently did nothing. The example below never caught it
    # because it checks another box in the same submission, which puts a real id in the array.
    it "disconnects the only connected category when nothing else is checked", :aggregate_failures do
      uncheck_category("Connected Spending")
      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      expect(connected_spending.reload.pool).to eq(checking)
      expect(pool.categories.reload).to be_empty
    end

    it "disconnects a category by connecting a different one", :aggregate_failures do
      uncheck_category("Connected Spending")
      check_category("Other Spending")
      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      expect(connected_spending.reload.pool).to eq(checking)
      expect(other_spending.reload.pool).to eq(pool)
    end
  end

  # THE TWO ARMS WHERE THE DISCONNECT HAS NOWHERE TO GO. Both used to be silent: `update(pool: nil)`
  # (and then `update(pool: <nil destination>)`) returns FALSE, unchecked, and the user was
  # redirected with "Categories updated successfully!" over a category that had not moved. Each is
  # refused up front now, with its own sentence, and NOTHING is written on either — not even the
  # connect half, because a screen that added categories while silently declining to remove others
  # leaves the checkboxes and the data disagreeing.
  #
  # THE FIXTURE IS THE OUTER SAVINGS ENVELOPE NOW, NOT A STRANDED ACCOUNT (main-account spec §6,
  # fix round 2 — B3). `disconnect_destination` dropped `@pool.account ||` entirely — it is always
  # `current_user.default_account` — so the ONE way left to reach this refusal is a user with no
  # main account named, whatever pool holds the category. An account-typed `@pool` is not a
  # distinct case any more (that was the old first arm's own account being nil), so the fixture is
  # simplified to reuse `pool`, the ordinary envelope every other describe block in this file uses.
  describe "disconnecting with nowhere to hand the category back to" do
    let!(:connected) do
      create(:category, name: "Connected Spending", category_type: "expense", user: user, pool: pool)
    end
    let!(:other_spending) { create(:category, name: "Other Spending", category_type: "expense", user: user) }

    # NO SHARED `before` NILLING `default_account` (main-account spec §6, fix round 2 — B3). Both
    # examples used to visit the page under one nilled-out setup, which happened to work when a
    # non-main ACCOUNT was the fixture — connecting to it needed no main account at all. `pool` is
    # an ENVELOPE, and `Category#pool_must_be_reachable` refuses pointing ANY category at ANY
    # envelope while the user has no main account, whether or not something is being disconnected
    # in the same submission — so "connects even with nowhere to send a disconnect" cannot share
    # that state with "refuses because there is nowhere to send a disconnect". Each example nils
    # (or doesn't) and visits for itself.
    it "refuses and says why, writing neither half", :aggregate_failures do
      user.update!(default_account: nil)
      visit categories_pool_path(pool)

      uncheck_category("Connected Spending")
      check_category("Other Spending")
      click_button "Update Connected Categories"

      expect(page).to have_content("Disconnecting a category needs a main account to hand its spending back to")
      expect(page).to have_no_content("Categories updated successfully!")
      expect(connected.reload.pool).to eq(pool)
      expect(other_spending.reload.pool).not_to eq(pool)
    end

    # THE OTHER DIRECTION on the same screen: with nothing being disconnected there is nothing to
    # refuse, so a pure connect still goes through. Without this the refusal could be unconditional
    # and the example above would still pass. Runs with the user's main account intact, deliberately
    # — connecting a category to an envelope needs one to exist at all, independent of whether
    # anything is being disconnected in the same request.
    it "still connects when nothing is being disconnected", :aggregate_failures do
      visit categories_pool_path(pool)

      check_category("Other Spending")
      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      expect(other_spending.reload.pool).to eq(pool)
      expect(connected.reload.pool).to eq(pool)
    end
  end

  # THE NO-OP ARM, and it is the subtler of the two: managing the categories of the very account
  # that disconnected categories are handed BACK to. The destination and the pool are the same
  # record, so "disconnect" would leave the category exactly where it is — which is not a failure
  # the model can report, and was therefore reported as a success.
  describe "disconnecting from the account the categories would be handed back to" do
    let!(:on_the_buffer) do
      create(:category, name: "Buffer Spending", category_type: "expense", user: user, pool: checking)
    end

    before do
      user.update!(default_account: checking)
      visit categories_pool_path(checking)
    end

    it "refuses and says so rather than reporting a move that did not happen", :aggregate_failures do
      uncheck_category("Buffer Spending")
      click_button "Update Connected Categories"

      expect(page).to have_content("Checking is where disconnected spending goes")
      expect(page).to have_no_content("Categories updated successfully!")
      expect(on_the_buffer.reload.pool).to eq(checking)
    end
  end

  # B3 (main-account spec §6, fix round 2) — THE SECOND DOOR THE SAME BUG OPENED. The old
  # destination, `@pool.account || current_user.default_account`, handed a disconnected category
  # back to the ENVELOPE'S OWN account — legal only by accident, when that account happened to be
  # main. For an envelope living anywhere else it tried to write a pool
  # `Category#pool_must_be_reachable` refuses, `update` returned false, and the screen reported
  # "Could not update Side Gig Spending" with no route to a successful disconnect at all. The
  # destination is now always `current_user.default_account`, main, regardless of which account
  # houses the envelope.
  describe "disconnecting from an envelope in a non-main account" do
    let!(:ally) { create(:pool, :account, user: user, name: "Ally") }
    let!(:side_gig) { create(:pool, :budget_pool, user: user, account: ally, name: "Side Gig") }
    let!(:spending) do
      create(:category, name: "Side Gig Spending", category_type: "expense", user: user, pool: side_gig)
    end

    before { visit categories_pool_path(side_gig) }

    it "hands the category back to main, not to the envelope's own account", :aggregate_failures do
      uncheck_category("Side Gig Spending")
      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      expect(spending.reload.pool).to eq(checking)
    end
  end

  describe "category conflicts" do
    let!(:other_pool) { create(:pool, :savings_pool, name: "Other Pool", user: user, account: checking) }
    let!(:conflicting_category) do
      create(
        :category,
        name: "Conflicting Category",
        category_type: "expense",
        user: user,
        pool: other_pool
      )
    end

    before { visit categories_pool_path(pool) }

    it "shows conflict warning for categories connected to other pools", :aggregate_failures do
      expect(category_label("Conflicting Category")).to have_content("Connected to Other Pool")
    end

    it "allows reassigning category from one pool to another", :aggregate_failures do
      check_category("Conflicting Category")
      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      expect(page).to have_current_path(pool_path(pool))
      expect(conflicting_category.reload.pool).to eq(pool)
    end
  end

  describe "navigation", :aggregate_failures do
    before { visit categories_pool_path(pool) }

    it "returns to savings pool show page when clicking cancel" do
      click_link "Cancel"
      expect(page).to have_current_path(pool_path(pool))
    end
  end

  private

  def category_label(name)
    find(:xpath, "//label[contains(., '#{name}')]")
  end

  def category_checkbox(name)
    category_label(name).find("input[type='checkbox']")
  end

  def check_category(name)
    category_checkbox(name).check
  end

  def uncheck_category(name)
    category_checkbox(name).uncheck
  end
end
