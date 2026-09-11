# frozen_string_literal: true

require "rails_helper"

# The Budget page is the list of every expense category. One row each: a drag handle where the
# reorder can take it, the name, how many rules it carries, a dot per rule in its type's colour,
# what it takes this period, and a chevron.
#
# `Capybara.exact` is unset in this suite, so every row assertion is scoped — an unscoped
# `have_content("Groceries")` matches the row, the rule inside it and the nav at once.
RSpec.describe "Budget page list", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }

  around { |example| travel_to(today) { example.run } }

  before do
    create(:account, user: user, name: "Checking", opening_balance: 5_000)
    sign_in user, scope: :user
  end

  def category(name, priority: 0) = create(:category, user: user, name: name, priority: priority)

  def rule_on(name, amount:, type: :usage, priority: 0)
    create(
      :rule,
      :rate,
      rule_type: type,
      amount: amount,
      starts_on: Date.new(2026, 1, 1),
      category: category(name, priority: priority)
    )
  end

  def lane_rule(owner, item_name, amount:, type: :usage)
    create(
      :rule,
      :rate,
      rule_type: type,
      amount: amount,
      starts_on: Date.new(2026, 1, 1),
      category: owner,
      item: create(:item, category: owner, name: item_name)
    )
  end

  def row(name) = find("[data-category-row='#{name}']")
  def rows = page.all("[data-category-row]").pluck("data-category-row")

  describe "which rows the page draws, and in what order", :aggregate_failures do
    # The order is PRIORITY — the number the arrows on these rows write. The give-way order Home
    # draws is that number UNDER the rule type, which no control here can reach; Home's own half is
    # pinned in `spec/system/home/this_period_spec.rb`.
    it "puts the categories in priority order, whatever kind of rule each carries" do
      rule_on("Rent", amount: 900, type: :bill, priority: 0)
      rule_on("Groceries", amount: 400, type: :usage, priority: 1)
      rule_on("Fun", amount: 100, type: :choice, priority: 2)

      visit budget_page_path

      expect(rows).to eq(["Rent", "Groceries", "Fun"])
    end

    # A category nobody has written a rule for is exactly where the next rule goes, so omitting it
    # would send that user hunting.
    it "lists rule-less categories after the ruled ones, by name" do
      rule_on("Groceries", amount: 400)
      category("Zoo")
      category("Aquarium")

      visit budget_page_path

      expect(rows).to eq(["Groceries", "Aquarium", "Zoo"])
    end

    # A rule cannot claim an income category, so a row for one would be a row with no rule it could
    # ever hold.
    it "leaves out income categories" do
      rule_on("Groceries", amount: 400)
      create(:category, :income, user: user, name: "Salary")

      visit budget_page_path

      expect(rows).to eq(["Groceries"])
    end
  end

  describe "what one row says", :aggregate_failures do
    # A dot per rule, in the RULE's own type: a category may carry a bill beside a choice and they
    # give way at opposite ends of the walk, so a row painting one dot per CATEGORY would be
    # colouring the wrong thing.
    it "counts the rules and paints a dot per rule in its type" do
      groceries = rule_on("Groceries", amount: 400).category
      lane_rule(groceries, "Wine", amount: 50, type: :choice)

      visit budget_page_path

      within(row("Groceries")) do
        expect(page).to have_content("2 rules")
        expect(page.all("[data-type-dot]").pluck("data-type-dot")).to eq(["choice", "usage"])
        expect(find("[data-type-dot='choice']")[:class]).to include("bg-terracotta")
        expect(find("[data-type-dot='usage']")[:class]).to include("bg-dusty-teal")
      end
    end

    # `takes $X this period` is Σ the category's rules' `per_period` — the calculator's own planned
    # figure for this period, not what has been spent. Planted: a $400 rate rule plus a $50 choice
    # lane rule takes $450.
    it "reads what the category takes this period" do
      groceries = rule_on("Groceries", amount: 400).category
      lane_rule(groceries, "Wine", amount: 50, type: :choice)

      visit budget_page_path

      within(row("Groceries")) { expect(page).to have_css("[data-category-takes]", text: "takes $450.00 this period") }
    end

    # Nothing claims a rule-less category's money, so there is no figure to print and no figure
    # invented in its place — and no arrows, because `Category.apply_fill_order` would refuse a list
    # holding it.
    it "says a rule-less category has no rules, and gives it no figure and no arrows" do
      rule_on("Groceries", amount: 400)
      category("Coffee")

      visit budget_page_path

      within(row("Coffee")) do
        expect(page).to have_css("[data-category-unruled]", text: "no rules yet")
        expect(page).to have_no_css("[data-category-takes]")
        expect(page).to have_no_button("Move Coffee up")
      end
    end
  end

  # The gate is "no expense category at all": a user with categories and no rules is not empty —
  # they have a row apiece, each carrying its own door onto a rule.
  describe "a user with nowhere to put a rule", :aggregate_failures do
    it "offers a category rather than a rule" do
      visit budget_page_path

      expect(page).to have_css("[data-budget-empty]")
      expect(page).to have_content("No spending categories yet")
      expect(page).to have_no_css("[data-category-row]")
    end

    it "draws a row for a category with no rule at all" do
      category("Groceries")

      visit budget_page_path

      expect(page).to have_no_css("[data-budget-empty]")
      within(row("Groceries")) { expect(page).to have_css("[data-category-unruled]") }
    end
  end
end
