# frozen_string_literal: true

require "rails_helper"

# "THIS PERIOD" splits into a Budget section and a Savings section, each carrying its own total —
# and a rule with no item names its row by what it covers rather than "Whole category". The grid is
# biweekly anchored 2026-02-06, so the period containing Sep 9 is Sep 4 – Sep 17.
RSpec.describe "Home sections", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }

  before do
    create(:account, user: user, name: "Checking", opening_balance: 5_000)
    sign_in user, scope: :user
  end

  def read_home = travel_to(today) { visit root_path }

  def rule_for(name, rate:) = create(:rule, :rate, amount: rate, starts_on: Date.new(2026, 1, 1), category: create(:category, user: user, name: name))

  def savings_for(name, amount:) = create(:savings_target, account: create(:account, user: user, name: name), amount: amount, starts_on: Date.new(2026, 9, 4))

  it "splits this period into Budget and Savings, each with its total", :aggregate_failures do
    rule_for("Groceries", rate: 400)
    savings_for("Emergency", amount: 200)

    read_home

    budget = find("[data-budget-section]")
    savings = find("[data-savings-section]")
    expect(budget).to have_css("[data-section-total]", text: "$400.00 claimed")
    expect(budget).to have_css("[data-category-block='Groceries']")
    expect(savings).to have_css("[data-section-total]", text: "$200.00 owed")
    expect(savings).to have_css("[data-savings-block='Emergency']")
  end

  it "shows no Savings section without a targeted account" do
    rule_for("Groceries", rate: 400)
    read_home
    expect(page).to have_no_css("[data-savings-section]")
  end

  it "names an item-less rule by what it covers", :aggregate_failures do
    groceries = create(:category, user: user, name: "Groceries")
    create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1))
    pets = create(:category, user: user, name: "Pets")
    create(:rule, :rate, amount: 60, category: pets, starts_on: Date.new(2026, 1, 1))
    create(:rule, :rate, amount: 40, category: pets, item: create(:item, category: pets, name: "Vet"), starts_on: Date.new(2026, 1, 1))

    read_home

    expect(find("[data-category-block='Groceries']")).to have_content("All of Groceries")
    expect(find("[data-category-block='Pets']")).to have_content("Everything else in Pets")
    expect(page).to have_no_content("Whole category")
  end
end
