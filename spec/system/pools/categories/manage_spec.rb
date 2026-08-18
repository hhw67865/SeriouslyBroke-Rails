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

    it "does not show category section headings when no categories exist" do
      expect(page).not_to have_css("h3", text: /Savings Categories \(\d+\)/)
      expect(page).not_to have_css("h3", text: /Expense Categories \(\d+\)/)
    end
  end

  describe "category display", :aggregate_failures do
    before do
      create(:category, name: "Monthly Savings", category_type: "savings", user: user, pool: checking)
      create(:category, name: "Vacation Expenses", category_type: "expense", user: user, pool: checking)
      create(:category, name: "Salary", category_type: "income", user: user, pool: checking)
      visit categories_pool_path(pool)
    end

    it "shows savings and expense categories separated" do
      expect(page).to have_content("Savings Categories (1)")
      expect(page).to have_content("Expense Categories (1)")
      expect(page).to have_content("Monthly Savings")
      expect(page).to have_content("Vacation Expenses")
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
      within(:xpath, "//label[contains(., 'Monthly Savings')]") do
        expect(page).to have_content("Connected to Checking")
        expect(page).to have_no_content("Available to connect")
      end
    end

    it "displays monthly amount for each category" do
      expect(page).to have_content("this month", minimum: 1)
    end
  end

  describe "connecting categories" do
    let!(:savings_category) { create(:category, name: "Monthly Savings", category_type: "savings", user: user) }
    let!(:expense_category) { create(:category, name: "Vacation Expenses", category_type: "expense", user: user) }

    before { visit categories_pool_path(pool) }

    it "connects a single savings category", :aggregate_failures do
      check_category("Monthly Savings")
      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      expect(page).to have_current_path(pool_path(pool))
      expect(savings_category.reload.pool).to eq(pool)
    end

    it "connects a single expense category", :aggregate_failures do
      check_category("Vacation Expenses")
      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      expect(expense_category.reload.pool).to eq(pool)
    end

    it "connects multiple categories at once", :aggregate_failures do
      check_category("Monthly Savings")
      check_category("Vacation Expenses")
      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      expect(savings_category.reload.pool).to eq(pool)
      expect(expense_category.reload.pool).to eq(pool)
    end
  end

  describe "disconnecting categories" do
    let!(:connected_savings) do
      create(
        :category,
        name: "Connected Savings",
        category_type: "savings",
        user: user,
        pool: pool
      )
    end
    let!(:other_savings) do
      create(:category, name: "Other Savings", category_type: "savings", user: user)
    end

    before { visit categories_pool_path(pool) }

    it "shows connected status for connected categories", :aggregate_failures do
      expect(category_label("Connected Savings")).to have_content("Connected")
      expect(category_checkbox("Connected Savings")).to be_checked
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
      uncheck_category("Connected Savings")
      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      expect(connected_savings.reload.pool).to eq(checking)
      expect(pool.categories.reload).to be_empty
    end

    it "disconnects a category by connecting a different one", :aggregate_failures do
      uncheck_category("Connected Savings")
      check_category("Other Savings")
      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      expect(connected_savings.reload.pool).to eq(checking)
      expect(other_savings.reload.pool).to eq(pool)
    end
  end

  # THE TWO ARMS WHERE THE DISCONNECT HAS NOWHERE TO GO. Both used to be silent: `update(pool: nil)`
  # (and then `update(pool: <nil destination>)`) returns FALSE, unchecked, and the user was
  # redirected with "Categories updated successfully!" over a category that had not moved. Each is
  # refused up front now, with its own sentence, and NOTHING is written on either — not even the
  # connect half, because a screen that added categories while silently declining to remove others
  # leaves the checkboxes and the data disagreeing.
  describe "disconnecting with nowhere to hand the category back to" do
    let!(:stranded) { create(:pool, :savings_pool, name: "Stranded Goal", user: user, account: nil) }
    let!(:connected) do
      create(:category, name: "Connected Savings", category_type: "savings", user: user, pool: stranded)
    end
    let!(:other_savings) { create(:category, name: "Other Savings", category_type: "savings", user: user) }

    before do
      user.update!(default_account: nil)
      visit categories_pool_path(stranded)
    end

    it "refuses and says why, writing neither half", :aggregate_failures do
      uncheck_category("Connected Savings")
      check_category("Other Savings")
      click_button "Update Connected Categories"

      expect(page).to have_content("Disconnecting a category needs an account to hand its spending back to")
      expect(page).to have_no_content("Categories updated successfully!")
      expect(connected.reload.pool).to eq(stranded)
      expect(other_savings.reload.pool).not_to eq(stranded)
    end

    # THE OTHER DIRECTION on the same screen: with nothing being disconnected there is nothing to
    # refuse, so a pure connect still goes through. Without this the refusal could be unconditional
    # and the example above would still pass.
    it "still connects when nothing is being disconnected", :aggregate_failures do
      check_category("Other Savings")
      click_button "Update Connected Categories"

      expect(page).to have_content("Categories updated successfully!")
      expect(other_savings.reload.pool).to eq(stranded)
      expect(connected.reload.pool).to eq(stranded)
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

  describe "category conflicts" do
    let!(:other_pool) { create(:pool, :savings_pool, name: "Other Pool", user: user, account: checking) }
    let!(:conflicting_category) do
      create(
        :category,
        name: "Conflicting Category",
        category_type: "savings",
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
