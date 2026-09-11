# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings adjustments", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let(:emergency) { create(:account, user: user, name: "Emergency") }

  around { |example| travel_to(today) { example.run } }

  # Checking is created first, so `Account.open` makes it main; `emergency` is a plain `let`
  # (not `let!`) so referencing it here is what creates it, second.
  before do
    create(:account, user: user, name: "Checking", opening_balance: 4_000)
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 8, 21))
    sign_in user, scope: :user
  end

  context "when reducing this period from the owed cell" do
    before do
      visit savings_path
      within("[data-adjust='Emergency']") do
        find("summary").click
        fill_in "Reduce by", with: "50"
        click_button "Reduce this period"
      end
    end

    it "confirms the reduction and the new owed figure", :aggregate_failures do
      expect(page).to have_content("Reduced what Emergency is owed by $50.00 this period.")
      expect(page).to have_css("[data-account-owed='Emergency']", text: "$350.00")
    end

    it "lists the change, and persists it", :aggregate_failures do
      within("[data-adjust='Emergency']") do
        find("summary").click
        expect(page).to have_css("[data-change-amount]", text: "-$50.00")
      end
      expect(emergency.adjustments.sole.amount).to eq(-50)
    end
  end

  it "skips the period for exactly what is owed this period", :aggregate_failures do
    visit savings_path

    within("[data-adjust='Emergency']") do
      find("summary").click
      click_button "Skip this period (−$200.00)"
    end

    expect(page).to have_content("Skipped this period for Emergency — $200.00 less owed.")
    expect(page).to have_css("[data-account-owed='Emergency']", text: "$200.00")
  end
end
