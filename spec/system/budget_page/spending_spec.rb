# frozen_string_literal: true

require "rails_helper"

# The figure opens onto the entries behind it. The frame itself needs a real browser — Turbo's own
# lazy load fires on the details becoming visible — so only one example runs `:js`; the rest checks
# what the server rendered before any script runs.
RSpec.describe "Budget page rule spending", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }

  around { |example| travel_to(today) { example.run } }

  before do
    create(:account, user: user, name: "Checking", opening_balance: 5_000)
    sign_in user, scope: :user
  end

  def rate_rule(owner) = create(:rule, :rate, category: owner, amount: 400, starts_on: Date.new(2026, 1, 1))
  def open_panel(owner) = visit budget_page_path(open: owner.id)
  def rule_row(name) = find("[data-rule='#{name}']")

  it "opens the entries behind the figure and closes them again", :aggregate_failures, :js do
    rate_rule(groceries)
    create(:entry, item: create(:item, category: groceries, name: "Bread"), amount: 30, date: today)

    open_panel(groceries)
    within(rule_row("Groceries")) { find("[data-rule-figure]").click }

    expect(page).to have_content("Bread")
    expect(page).to have_content("$30.00")

    within(rule_row("Groceries")) { find("[data-rule-figure]").click }

    expect(page).to have_no_content("Bread")
  end

  it "renders the disclosure and the frame's src for a ruled category", :aggregate_failures do
    rule = rate_rule(groceries)

    open_panel(groceries)

    within(rule_row("Groceries")) do
      expect(page).to have_css("[data-rule-spending]")
      expect(find("turbo-frame", visible: :all)[:src]).to eq(spending_rule_path(rule))
    end
  end
end
