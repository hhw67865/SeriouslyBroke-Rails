# frozen_string_literal: true

require "rails_helper"

# The Budget page's top half (spec §8): every active rule, under the pool it fills, in the order
# money arrives. `Capybara.exact` is unset in this suite, so every row assertion is scoped with
# `within` — an unscoped `have_content("Groceries")` matches the group heading, the rule name and
# the nav all at once.
RSpec.describe "Budget page rules", type: :system do
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.current, typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  before { sign_in user, scope: :user }

  def group(name) = find("[data-pool-group='#{name}']")

  def rule_row(name) = find("[data-rule='#{name}']")

  def envelope(name, priority: 1)
    create(:pool, :budget_pool, user: user, account: checking, name: name, priority: priority)
  end

  def rate(pool, amount) = create(:pool_budget, :per_paycheck_rate, pool: pool, amount: amount)

  def rolling(pool, amount:, anchor:, every: 1)
    create(:pool_budget, pool: pool, amount: amount, interval_months: every, anchor_date: anchor)
  end

  describe "the fill order", :aggregate_failures do
    before do
      rate(envelope("Groceries", priority: 2), 400)
      rolling(envelope("Car Insurance", priority: 1), amount: 1_200, anchor: Date.current + 3.months, every: 6)
      visit budget_page_path
    end

    it "renders each rule under its pool, with its amount and basis" do
      within(group("Groceries")) { expect(page).to have_content("$400.00 / period") }
      within(group("Car Insurance")) { expect(page).to have_content("$1,200.00 every 6 months") }
    end

    it "puts the pools in priority order" do
      expect(page.all("[data-pool-group]").pluck("data-pool-group"))
        .to eq(["Car Insurance", "Groceries"])
      expect(page).to have_no_content("Nothing is in the fill order yet")
    end

    it "states each pool's priority position" do
      within(group("Car Insurance")) { expect(page).to have_content("priority 1") }
      within(group("Groceries")) { expect(page).to have_content("priority 2") }
    end

    # The date on the dated rule and NOT on the rate rule, on one screen: an anchorless rule is
    # never due, and BudgetCalculator#due_date answers the end of the period for one.
    it "prints a next date only for the anchored rule" do
      within(rule_row("Car Insurance")) do
        expect(page).to have_content("next #{(Date.current + 3.months).strftime("%b %-d")}")
      end
      within(rule_row("Groceries")) { expect(page).to have_no_content("next") }
    end

    # The row vocabulary is the app's one vocabulary (`pool_status_label`), and the balance is
    # printed only where the label has not already said it — see BudgetPageHelper::BALANCE_UNSAID.
    it "says how each pool is doing, and holds only where the label names a bill" do
      within(group("Car Insurance")) { expect(page).to have_content("behind").and have_content("holds $0.00") }
      within(group("Groceries")) { expect(page).to have_content("$0.00 left").and have_no_content("holds") }
    end
  end

  describe "rules no distribution reaches", :aggregate_failures do
    before do
      rate(envelope("Groceries"), 400)
      create(:budget, category: create(:category, :expense, user: user, name: "Shopping"), amount: 200)
      rate(create(:pool, :savings_pool, user: user, account: nil, name: "Retirement"), 150)
      visit budget_page_path
    end

    it "lists them apart from the fill order, each with its own reason" do
      within(group("Not in the fill order")) do
        expect(page).to have_content("caps a category — no envelope to fill")
        expect(page).to have_content("no account — nothing can fund it")
      end
    end

    it "keeps them out of the pool groups, and keeps a real rule out of them" do
      expect(page.all("[data-pool-group]").pluck("data-pool-group"))
        .to eq(["Groceries", "Not in the fill order"])
      within(group("Groceries")) { expect(page).to have_no_content("no envelope to fill") }
    end
  end

  # THE THIRD STATE, and it is not the empty one: this user HAS rules, so telling them they have
  # none above a list of their own rules would be a screen contradicting itself.
  describe "a user whose every rule is an orphan", :aggregate_failures do
    before do
      create(:budget, category: create(:category, :expense, user: user, name: "Shopping"), amount: 200)
      visit budget_page_path
    end

    it "says the fill order is empty rather than that there are no rules" do
      expect(page).to have_content("Nothing is in the fill order yet")
      expect(page).to have_no_content("No funding rules yet")
      within(group("Not in the fill order")) { expect(page).to have_content("Shopping") }
    end
  end

  describe "a brand-new user", :aggregate_failures do
    before { visit budget_page_path }

    # The first screen every real user meets. The sentence points at the two places a rule is
    # actually made and promises nothing this page does not yet do.
    it "sees the frame, one sentence and no groups at all" do
      expect(page).to have_content("No funding rules yet")
      expect(page).to have_content("A rule claims part of every paycheck for one envelope")
      expect(page).to have_no_content("Nothing is in the fill order yet")
      expect(page).to have_no_css("[data-pool-group]")
      expect(page).to have_no_css("[data-rule]")
    end
  end

  describe "the nav", :aggregate_failures do
    it "reaches the page from anywhere and marks it current" do
      visit categories_path
      click_link "Budget"

      expect(page).to have_current_path(budget_page_path)
      expect(page).to have_content("The rules that fill your envelopes")
    end
  end

  # AMENDMENT B's second trap, closed. Before this page existed nothing linked a pool-mode rule to
  # its form, and the form offered one a CATEGORY picker whose every option makes the record
  # invalid. The link is user-reachable now, so the round trip is asserted end to end.
  describe "editing a rule", :aggregate_failures do
    before do
      rate(envelope("Groceries"), 400)
      visit budget_page_path
      within(rule_row("Groceries")) { click_link "Edit" }
    end

    it "opens a form about the pool rather than about a category" do
      expect(page).to have_content("How Groceries gets filled each period")
      expect(page).to have_field("Rule Amount")
      expect(page).to have_no_select("Category")
    end

    it "saves the new amount and comes back to the Budget page" do
      fill_in "Rule Amount", with: "425"
      click_button "Update Budget"

      expect(page).to have_current_path(budget_page_path)
      within(rule_row("Groceries")) { expect(page).to have_content("$425.00 / period") }
    end
  end
end
