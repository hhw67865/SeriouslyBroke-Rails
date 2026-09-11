# frozen_string_literal: true

require "rails_helper"

# ACCOUNTS: the spending account as a tinted card with Home's own figures, everything else set
# aside as a ledger, and Move money between them. Edit and delete live on each set-aside row.
RSpec.describe "Accounts", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let!(:checking) { create(:account, user: user, name: "Checking", opening_balance: 1_000) }

  before { sign_in user, scope: :user }

  def elsewhere(name, balance) = create(:account, user: user, name: name, opening_balance: balance)

  def read_accounts = travel_to(today) { visit accounts_path }

  def row(name) = find("[data-account-row='#{name}']")

  def add_account(name, balance: nil)
    find("[data-add-account] summary").click
    within("[data-add-account]") do
      fill_in "Account name", with: name
      fill_in "What's in it right now", with: balance if balance
      click_button "Add an account"
    end
  end

  def move_money(from:, to:, amount:)
    find("[data-move-money] summary").click
    within("[data-move-money]") do
      select from, from: "From"
      select to, from: "To"
      fill_in "Amount", with: amount
      click_button "Move"
    end
  end

  it "shows the spending account's card with Home's own figures", :aggregate_failures do
    create(:rule, category: create(:category, user: user, name: "Groceries"), amount: 400, starts_on: Date.new(2026, 1, 1))
    read_accounts

    within("[data-spending-account]") do
      expect(page).to have_content("Checking")
      expect(page).to have_content("Spending account")
      expect(page).to have_css("[data-spending-balance]", text: "$1,000.00")
      expect(page).to have_css("[data-spending-claimed]", text: "$400.00")
      expect(page).to have_css("[data-spending-free]", text: "$600.00")
      expect(page).to have_link("Edit name or balance", href: edit_account_path(checking))
    end
  end

  it "lists every other account as a ledger row and totals them", :aggregate_failures do
    elsewhere("Ally", 222_000)
    elsewhere("Vanguard", 544.87)

    read_accounts

    expect(row("Ally")).to have_content("$222,000.00")
    expect(row("Vanguard")).to have_content("$544.87")
    expect(page).to have_css("[data-set-aside-total]", text: "$222,544.87")
    expect(page).to have_css("[data-set-aside-footer]", text: "$222,544.87")
  end

  it "shows the empty state with nothing set aside" do
    read_accounts

    expect(page).to have_css("[data-set-aside-empty]", text: "Nothing set aside yet. Add an account below to start.")
  end

  it "adds an account", :aggregate_failures do
    read_accounts
    add_account("Ally Savings", balance: "250.50")

    expect(page).to have_content("Ally Savings added.")
    expect(row("Ally Savings")).to have_content("$250.50")
  end

  it "moves money and changes both balances", :aggregate_failures do
    elsewhere("Ally", 100)
    read_accounts
    move_money(from: "Checking", to: "Ally", amount: "50.00")

    expect(page).to have_content("Moved $50.00 from Checking to Ally.")
    expect(page).to have_css("[data-spending-balance]", text: "$950.00")
    expect(row("Ally")).to have_content("$150.00")
  end

  it "deletes an account and returns its money to the spending account", :aggregate_failures do
    ally = elsewhere("Ally", 0)
    create(:transfer, from_account: checking, to_account: ally, amount: 300, date: today)

    read_accounts
    within(row("Ally")) { click_button "Delete" }

    expect(page).to have_content("Ally deleted — $300.00 is back in checking.")
    expect(page).to have_no_css("[data-account-row='Ally']", visible: :all)
    expect(page).to have_css("[data-spending-balance]", text: "$1,000.00")
  end

  it "links to Edit on a set-aside row" do
    ally = elsewhere("Ally", 400)

    read_accounts

    expect(row("Ally")).to have_link("Edit", href: edit_account_path(ally))
  end

  it "is reachable from the sidebar" do
    read_accounts

    expect(page).to have_link("Accounts", href: accounts_path)
  end
end
