# frozen_string_literal: true

require "rails_helper"

# THE RULE FORM, POOL-MODE ONLY (plan 3, task 3).
#
# WHAT THIS FILE USED TO BE. Every example was about the monthly category CAP: a form reached as
# `/budgets/new?category_id=…`, a "Set spending limits for Groceries" heading, a category select
# offering `expenses.budgetable`, a "Prorate daily" checkbox, and a save that redirected to the
# category's own page. All of it is deleted with the cap — `category_id` is not a permitted
# parameter, `Budget belongs_to :category` is gone, `budgets.prorated` reads nothing, and
# `#owner_path`'s category branch is replaced by the Budget page. Those examples are deleted WITH
# the behaviour rather than rewritten against a shape the app refuses.
#
# WHAT REPLACES THEM is the form the app actually has: a rule that fills an envelope, reached from
# the Budget page's Edit link, plus the owner-less state a bare `/budgets/new` renders. The accept
# flow's own two branches (create an envelope / join one) are covered in
# spec/system/budget_page/suggestions_spec.rb, which is where the links into them live.
RSpec.describe "Budgets Forms", type: :system do
  let(:user) { create(:user, :biweekly, typical_income: 2_400) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let!(:groceries) { create(:pool, :budget_pool, user: user, account: checking, name: "Groceries") }

  before { sign_in user, scope: :user }

  describe "Edit Budget Form", :aggregate_failures do
    let!(:rule) { create(:pool_budget, :per_period_rate, pool: groceries, amount: 400.00) }

    before { visit edit_budget_path(rule) }

    it "shows the rule's own controls and none of the cap's" do
      expect(page).to have_content("Edit Budget")
      expect(page).to have_content("How Groceries gets filled each period")
      expect(page).to have_field("Amount")
      expect(page).to have_button("Update Budget")
      expect(page).to have_link("Cancel")

      expect(page).to have_no_field("Prorate daily")
      expect(page).to have_no_select("Category")
    end

    it "names the pool without offering to change it", :aggregate_failures do
      expect(page).to have_content("Groceries")
      expect(page).to have_no_select("Pool")
    end

    it "pre-fills the amount" do
      expect(page).to have_field("Amount", with: "400.0")
    end

    # THE DESTINATION IS THE BUDGET PAGE, which is the screen the Edit link was clicked from and
    # the only screen that lists rules.
    it "updates the rule and returns to the Budget page" do
      fill_in "Amount", with: "750.00"
      click_button "Update Budget"

      expect(page).to have_current_path(budget_page_path)
      expect(page).to have_content("Budget was successfully updated")
      expect(rule.reload.amount).to eq(750.00)
    end

    it "shows an error for a missing amount" do
      fill_in "Amount", with: ""
      click_button "Update Budget"

      expect(page).to have_current_path(edit_budget_path(rule))
      expect(page).to have_content("can't be blank")
      expect(rule.reload.amount).to eq(400.00)
    end

    it "returns to the Budget page when clicking cancel" do
      click_link "Cancel"

      expect(page).to have_current_path(budget_page_path)
    end
  end

  # A HAND-MADE RULE (Henry's ruling of 2026-08-20). `/budgets/new` existed and rendered no owner
  # control at all — deliberately, because at the time every link into the form carried an owner
  # and nothing linked to the bare URL. Real use found the gap that leaves: a user who wants a rule
  # for something their entries have not yet shown has no door at all, and the only screen that
  # lists rules had no "new" button on it.
  #
  # THE EXAMPLE THAT USED TO STAND HERE — "offers no owner control at all" — is inverted rather
  # than deleted, for the same reason the suggestions panel's dismissal example was: the fact worth
  # pinning is whether this form can name an owner, and the answer changed.
  describe "New Budget Form with no owner", :aggregate_failures do
    let!(:vacation) { create(:pool, :savings_pool, user: user, account: checking, name: "Vacation to Europe") }
    let(:stranger) { create(:user) }

    before do
      create(:pool, :budget_pool, user: stranger, account: create(:pool, :account, user: stranger), name: "Their Rent")
      visit budget_page_path
    end

    # THE TWO NEGATIVES ARE THE OLD EXAMPLE'S SURVIVING HALF, and they are not redundant with the
    # picker assertion beside them: they guard against the CAP-ERA controls coming back — a Category
    # select naming the owner of a monthly spending limit, and the `prorated` checkbox that spread
    # one across the days of a month. Neither column can be written any more (`category_id` and
    # `prorated` are not permitted params), and this is the screen where a regression restoring
    # either would show up first, precisely because it is the one that asks for an owner again.
    it "is reachable from the Budget page's own header, and offers no cap-era control" do
      click_link "New rule"

      expect(page).to have_current_path(new_budget_path)
      expect(page).to have_content("New Budget")
      expect(page).to have_select("Pool")
      expect(page).to have_no_select("Category")
      expect(page).to have_no_field("Prorate daily")
    end

    # A RULE'S OWNER IS AN ENVELOPE OR A GOAL, never an account — `Budget#pool_must_not_be_an_account`
    # is the same fact stated as a refusal, and a picker that offered Checking would be inviting a
    # 422. `options:` is the WHOLE list, so the account's absence and the stranger's are asserted by
    # the same expectation that asserts the two real choices are there.
    it "offers this user's envelopes and goals, and nothing else" do
      click_link "New rule"

      expect(page).to have_select(
        "Pool",
        options: ["Select an envelope or goal", "Groceries", "Vacation to Europe"]
      )
    end

    it "lands the rule on the chosen envelope" do
      click_link "New rule"
      select "Groceries", from: "Pool"
      fill_in "Rule Amount", with: "125.00"
      click_button "Create Budget"

      expect(page).to have_current_path(budget_page_path)
      expect(page).to have_content("Budget was successfully created")
      expect(groceries.budgets.sole.amount).to eq(125)
      expect(groceries.budgets.sole.cadence).to eq(:per_period)
    end

    it "lands one on a goal too" do
      click_link "New rule"
      select "Vacation to Europe", from: "Pool"
      fill_in "Rule Amount", with: "60.00"
      click_button "Create Budget"

      expect(page).to have_content("Budget was successfully created")
      expect(vacation.budgets.sole.amount).to eq(60)
    end

    # THE OWNER-LESS SAVE IS STILL REFUSED, and on `:base` where the form renders base errors —
    # the picker offers a blank because "I have not chosen yet" is a real state, not because a rule
    # may have no owner.
    it "refuses the save when no pool is chosen, and says why" do
      click_link "New rule"
      fill_in "Rule Amount", with: "500.00"
      click_button "Create Budget"

      expect(page).to have_css(".bg-status-danger-light", text: "must belong to a pool")
      expect(page).to have_select("Pool")
      expect(Budget.count).to eq(0)
    end
  end
end
