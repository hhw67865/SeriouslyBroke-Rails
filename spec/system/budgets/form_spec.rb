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

  # A BARE `/budgets/new` HAS NO OWNER, and the form no longer invents one. Every link into this
  # form carries a pool id or an envelope half; typing the URL reaches a page that can only be
  # refused, and `Budget#must_belong_to_a_pool` refuses it on `:base` — which is the one place the
  # form renders base errors.
  describe "New Budget Form with no owner", :aggregate_failures do
    before { visit new_budget_path }

    it "offers no owner control at all" do
      expect(page).to have_content("New Budget")
      expect(page).to have_field("Amount")
      expect(page).to have_no_select("Category")
      expect(page).to have_no_field("Prorate daily")
    end

    it "refuses the save and says why" do
      fill_in "Amount", with: "500.00"
      click_button "Create Budget"

      expect(page).to have_current_path(new_budget_path)
      expect(page).to have_css(".bg-status-danger-light", text: "must belong to a pool")
      expect(Budget.count).to eq(0)
    end
  end
end
