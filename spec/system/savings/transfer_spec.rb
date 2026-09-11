# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Savings transfers", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let!(:checking) { create(:account, user: user, name: "Checking", opening_balance: 4_000) }
  let!(:emergency) { create(:account, user: user, name: "Emergency") }

  around { |example| travel_to(today) { example.run } }
  before { sign_in user, scope: :user }

  it "pays what is owed in one click", :aggregate_failures do
    create(:savings_target, account: emergency, amount: 200, starts_on: Date.new(2026, 9, 4))
    visit savings_path

    click_button "Transfer $200.00"

    expect(page).to have_content("Transferred $200.00 from Checking to Emergency.")
    expect(page).to have_css("[data-account-owed='Emergency']", text: "On pace")
    expect(Transfer.sole).to have_attributes(from_account: checking, to_account: emergency, amount: 200, date: today)
  end

  it "transfers any amount from the drawer", :aggregate_failures do
    visit savings_path(open: "transfer")

    within("[data-drawer-name='transfer']") do
      select "Checking", from: "From"
      select "Emergency", from: "To"
      fill_in "Amount", with: "75"
      click_button "Transfer"
    end

    expect(page).to have_content("Transferred $75.00 from Checking to Emergency.")
    expect(page).to have_css("[data-account-moved='Emergency']", text: "+$75.00 in on Sep 9")
  end

  it "keeps the drawer open with the reason when a transfer is refused" do
    visit savings_path(open: "transfer")

    within("[data-drawer-name='transfer']") do
      select "Checking", from: "From"
      select "Checking", from: "To"
      fill_in "Amount", with: "75"
      click_button "Transfer"
    end

    expect(page).to have_css("[data-drawer-name='transfer'][open]", text: "must differ from the source account")
  end
end
