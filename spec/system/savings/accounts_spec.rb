# frozen_string_literal: true

require "rails_helper"

# Adding and deleting a savings account, and the drawer's own open/close/Escape behaviour — the
# system coverage `spec/system/accounts/index_spec.rb` used to carry, moved here for the Savings
# page's own drawer and row markup.
RSpec.describe "Savings accounts", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }

  around { |example| travel_to(today) { example.run } }

  # Checking must exist and be created first, so `Account.open` makes it main — nothing about it
  # is asserted here, so it is a plain `before`, not a `let!`.
  before do
    create(:account, user: user, name: "Checking", opening_balance: 1_000)
    sign_in user, scope: :user
  end

  def row(name) = find("[data-account-row='#{name}']")
  def drawer(name) = find("[data-drawer-name='#{name}']")

  it "adds an account through the drawer", :aggregate_failures do
    visit savings_path(open: "add")

    within(drawer("add")) do
      fill_in "Account name", with: "Ally Savings"
      fill_in "What's in it right now", with: "250.50"
      click_button "Add account"
    end

    expect(page).to have_content("Ally Savings added.")
    expect(row("Ally Savings")).to have_content("$250.50")
  end

  it "deletes an account from its row", :aggregate_failures do
    create(:account, user: user, name: "Ally")
    visit savings_path

    within(row("Ally")) { click_button "Delete" }

    expect(page).to have_content("Ally deleted.")
    expect(page).to have_no_css("[data-account-row='Ally']", visible: :all)
  end

  describe "the drawer, opened and closed", :js do
    it "opens Add an account as a modal dialog, and closes on Escape", :aggregate_failures do
      visit savings_path

      click_link "Add an account"
      expect(page).to have_css("[data-drawer-name='add'][open]")

      find("body").send_keys(:escape)
      expect(page).to have_no_css("[data-drawer-name='add'][open]")
    end
  end
end
