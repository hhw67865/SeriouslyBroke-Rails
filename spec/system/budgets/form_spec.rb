# frozen_string_literal: true

require "rails_helper"

# THE RULE FORM, ONE OWNER (two-ledger spec §3).
#
# WHAT THIS FILE USED TO BE, TWICE OVER. Every example was once about the monthly category CAP — a
# form reached as `/budgets/new?category_id=…`, a "Set spending limits for Groceries" heading, a
# "Prorate daily" checkbox — and all of it was deleted with the cap in plan 3. What replaced it was
# a POOL-mode rule form: a picker offering `Pool.rule_owners`, a read-only pool name on the edit
# path, and an ENVELOPE half for the accept flow. That is deleted here with the pool layer.
#
# THE EXAMPLES ARE CONVERTED RATHER THAN DELETED, because every one of them pins a fact that still
# has to be true of a form that names an owner: the picker offers this user's own owners and
# nothing else, a chosen owner is where the rule lands, an owner-less save is refused on `:base`,
# and the edit path names the owner without offering to change it. The `category_id` the cap era
# used to write means the opposite thing now — the OWNER rather than the thing being capped — so
# the two negatives that guarded against the cap's controls coming back are kept and re-aimed at
# the pool's.
RSpec.describe "Budgets Forms", type: :system do
  let(:user) { create(:user, :biweekly, typical_income: 2_400) }
  let!(:groceries) { create(:category, :expense, :funded, user: user, name: "Groceries") }

  before { sign_in user, scope: :user }

  describe "Edit Budget Form", :aggregate_failures do
    let!(:rule) { create(:budget, :per_period_rate, category: groceries, amount: 400.00) }

    before { visit edit_budget_path(rule) }

    it "shows the rule's own controls and none of the cap's" do
      expect(page).to have_content("Edit Budget")
      expect(page).to have_content("How Groceries gets filled each period")
      expect(page).to have_field("Amount")
      expect(page).to have_button("Update Budget")
      expect(page).to have_link("Cancel")

      expect(page).to have_no_field("Prorate daily")
      expect(page).to have_no_select("Pool")
    end

    it "names the category without offering to change it", :aggregate_failures do
      expect(page).to have_content("Groceries")
      expect(page).to have_no_select("Category")
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
  describe "New Budget Form with no owner", :aggregate_failures do
    let!(:vacation) { create(:category, :expense, :savings, user: user, name: "Vacation to Europe") }
    let!(:salary) { create(:category, :income, user: user, name: "Salary") }
    let(:stranger) { create(:user) }

    before do
      create(:category, :expense, :funded, user: stranger, name: "Their Rent")
      visit budget_page_path
    end

    # THE TWO NEGATIVES ARE THE OLD EXAMPLE'S SURVIVING HALF, and they are not redundant with the
    # picker assertion beside them: they guard against the two dead eras' controls coming back —
    # the cap's `prorated` checkbox, and the pool picker whose every option is a layer Task 8
    # deletes. Neither column can be written any more (`prorated` and `pool_id` are not permitted
    # params), and this is the screen where a regression restoring either would show up first,
    # precisely because it is the one that asks for an owner again.
    it "is reachable from the Budget page's own header, and offers no dead-era control" do
      click_link "New rule"

      expect(page).to have_current_path(new_budget_path)
      expect(page).to have_content("New Budget")
      expect(page).to have_select("Category")
      expect(page).to have_no_select("Pool")
      expect(page).to have_no_field("Prorate daily")
    end

    # A RULE'S OWNER IS AN EXPENSE CATEGORY, never an income one — income lands in available and is
    # allocated out of it (§2), so a rule on one would claim money that category never holds, and
    # `Category#only_expenses_hold_money` refuses the `funded_since` stamp that accepting it writes.
    # A SAVINGS category IS offered: §3's "typically no refill rule" is a typically, and a goal a
    # rate rule refills is the demo's own Retirement Supplement.
    #
    # `options:` is the WHOLE list, so the income category's absence and the stranger's are asserted
    # by the same expectation that asserts the two real choices are there.
    it "offers this user's expense categories, and nothing else" do
      click_link "New rule"

      expect(page).to have_select(
        "Category",
        options: ["Select a category", "Groceries", "Vacation to Europe"]
      )
      expect(salary.reload.budgets).to be_empty
    end

    it "lands the rule on the chosen category" do
      click_link "New rule"
      select "Groceries", from: "Category"
      fill_in "Rule Amount", with: "125.00"
      click_button "Create Budget"

      expect(page).to have_current_path(budget_page_path)
      expect(page).to have_content("Budget was successfully created")
      expect(groceries.budgets.sole.amount).to eq(125)
      expect(groceries.budgets.sole.cadence).to eq(:per_period)
    end

    it "lands one on a savings category too" do
      click_link "New rule"
      select "Vacation to Europe", from: "Category"
      fill_in "Rule Amount", with: "60.00"
      click_button "Create Budget"

      expect(page).to have_content("Budget was successfully created")
      expect(vacation.budgets.sole.amount).to eq(60)
    end

    # THE STAMP, THROUGH THE BROWSER (two-ledger spec §4). A rule is one of the two things that make
    # a category start holding its own money, and the hand-made path writes it exactly as the accept
    # flow does — `BudgetProposal` is the one writer, and this form goes through it.
    it "starts an unfunded category holding money from today" do
      unfunded = create(:category, :expense, user: user, name: "Coffee")

      click_link "New rule"
      select "Coffee", from: "Category"
      fill_in "Rule Amount", with: "35.00"
      click_button "Create Budget"

      expect(page).to have_content("Budget was successfully created")
      expect(unfunded.reload.funded_since).to eq(Date.current)
    end

    # THE OWNER-LESS SAVE IS STILL REFUSED, and on `:base` where the form renders base errors —
    # the picker offers a blank because "I have not chosen yet" is a real state, not because a rule
    # may have no owner.
    it "refuses the save when no category is chosen, and says why" do
      click_link "New rule"
      fill_in "Rule Amount", with: "500.00"
      click_button "Create Budget"

      expect(page).to have_css(".bg-status-danger-light", text: "must belong to a category")
      expect(page).to have_select("Category")
      expect(Budget.count).to eq(0)
    end
  end
end
