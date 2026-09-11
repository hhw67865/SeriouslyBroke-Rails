# frozen_string_literal: true

require "rails_helper"

# SAVINGS: checking as a tinted card with what claims it, every other account with what it is owed.
RSpec.describe "Savings page", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let!(:checking) { create(:account, user: user, name: "Checking", opening_balance: 4_000) }

  around { |example| travel_to(today) { example.run } }
  before { sign_in user, scope: :user }

  def row(name) = find("[data-account-row='#{name}']")

  context "with a rule and a targeted savings account" do
    before do
      create(:rule, :rate, amount: 400, category: create(:category, user: user, name: "Groceries"), starts_on: Date.new(2026, 1, 1))
      emergency = create(:account, user: user, name: "Emergency")
      create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
      visit savings_path
    end

    it "shows checking's figures with the budget and savings claims beneath", :aggregate_failures do
      within("[data-checking]") do
        expect(page).to have_css("[data-checking-balance]", text: "$4,000.00")
        expect(page).to have_css("[data-checking-claimed]", text: "$600.00")
        expect(page).to have_css("[data-checking-budget-claim]", text: "$400.00")
        expect(page).to have_css("[data-checking-savings-claim]", text: "$200.00")
        expect(page).to have_css("[data-checking-free]", text: "$3,400.00")
      end
    end

    it "links to itself as Savings" do
      expect(page).to have_link("Savings", href: savings_path)
    end
  end

  context "with a targeted account carrying a fixed target, a share and a transfer, and an untargeted one" do
    let!(:emergency) { create(:account, user: user, name: "Emergency", opening_balance: 500) }

    before do
      create(:account, user: user, name: "Joint", opening_balance: 2_000)
      paycheck = create(:item, :income, user: user, name: "Paycheck")
      create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 8, 21))
      create(:savings_target, :share, account: emergency, item: paycheck, percent: 10, starts_on: Date.new(2026, 8, 21))
      create(:transfer, from_account: checking, to_account: emergency, amount: 150, date: Date.new(2026, 8, 28))
      visit savings_path
    end

    it "shows the targeted account's targets, what it is owed, and its last transfer", :aggregate_failures do
      within(row("Emergency")) do
        expect(page).to have_css("[data-account-targets]", text: "$200.00 a period, plus 10% of Paycheck")
        expect(page).to have_content("keeps extra · since Aug 21")
        expect(page).to have_css("[data-account-owed='Emergency']", text: "$250.00")
        expect(page).to have_css("[data-account-moved='Emergency']", text: "+$150.00 in on Aug 28")
        expect(page).to have_button("Transfer $250.00")
      end
    end

    it "leaves the untargeted account with no owed figure or transfer button", :aggregate_failures do
      within(row("Joint")) do
        expect(page).to have_css("[data-account-untargeted]", text: "No savings target")
        expect(page).to have_link("set one", href: edit_account_path(Account.find_by!(name: "Joint")))
        expect(page).to have_no_button(/Transfer/)
      end
    end

    it "totals savings across both accounts and what is owed", :aggregate_failures do
      expect(page).to have_css("[data-savings-total]", text: "$2,650.00 across 2 accounts")
      expect(page).to have_css("[data-owed-footer]", text: "$250.00")
    end
  end

  it "says on pace when nothing is owed" do
    emergency = create(:account, user: user, name: "Emergency")
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
    create(:transfer, from_account: checking, to_account: emergency, amount: 200, date: Date.new(2026, 9, 5))

    visit savings_path

    expect(row("Emergency")).to have_css("[data-account-owed='Emergency']", text: "On pace")
  end
end
