# frozen_string_literal: true

require "rails_helper"

# Everything that happened, newest first, with a door back to Entries and a way to undo a
# transfer or an adjustment. Fixed dates keep "newest first" true without racing created_at.
RSpec.describe "Activity", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :biweekly) }
  let(:today) { Date.new(2026, 9, 9) }
  let!(:checking) { create(:account, user: user, name: "Checking", opening_balance: 1_000) }
  let!(:groceries) { create(:category, user: user, name: "Groceries") }

  around { |example| travel_to(today) { example.run } }

  before { sign_in user, scope: :user }

  # Scoped to the desktop table: the mobile card markup sits beside it in the DOM, invisible only
  # through a CSS media query the Rack::Test driver never evaluates.
  def row(kind) = find("tbody [data-activity-row='#{kind}']")

  it "renders the empty state with nothing logged yet" do
    visit activity_path

    expect(page).to have_content("Nothing has happened yet. Log an entry and it shows up here.")
  end

  describe "the list", :aggregate_failures do
    before do
      create(:entry, item: create(:item, category: groceries, name: "Bread"), amount: 5, date: today - 2)
      emergency = create(:account, user: user, name: "Emergency")
      create(:transfer, from_account: checking, to_account: emergency, amount: 40, date: today - 1)
      rule = create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1))
      create(:adjustment, source: rule, amount: -50, date: today)
      visit activity_path
    end

    it "shows an entry, a transfer and an adjustment newest first with their words and amounts" do
      expect(all("tbody [data-activity-row]").pluck("data-activity-row")).to eq(["adjustment", "transfer", "entry"])
      expect(row("entry")).to have_content("Bread · Groceries").and have_content("$5.00")
      expect(row("transfer")).to have_content("Checking → Emergency").and have_content("$40.00")
      expect(row("adjustment")).to have_content("Groceries · reduced").and have_content("$50.00")
    end

    it "marks the entry's badge with its category's colour dot" do
      expect(row("entry")).to have_css("[data-category-dot]")
    end
  end

  it "removes a transfer from its row and returns to Activity with a notice", :aggregate_failures do
    emergency = create(:account, user: user, name: "Emergency")
    create(:transfer, from_account: checking, to_account: emergency, amount: 40, date: today)
    visit activity_path

    within(row("transfer")) { click_button "Remove" }

    expect(page).to have_current_path(activity_path)
    expect(page).to have_content("Removed the transfer of $40.00 from Checking to Emergency.")
    expect(page).to have_no_css("[data-activity-row='transfer']")
  end

  it "removes an adjustment from its row and returns to Activity with a notice", :aggregate_failures do
    rule = create(:rule, :rate, amount: 400, category: groceries, starts_on: Date.new(2026, 1, 1))
    create(:adjustment, source: rule, amount: -50, date: today)
    visit activity_path

    within(row("adjustment")) { click_button "Remove" }

    expect(page).to have_current_path(activity_path)
    expect(page).to have_content("Removed the $50.00 reduction on Groceries.")
    expect(page).to have_no_css("[data-activity-row='adjustment']")
  end

  it "sends an entry's Edit link to its edit form, back to Activity when saved" do
    entry = create(:entry, item: create(:item, category: groceries, name: "Bread"), amount: 5, date: today)
    visit activity_path

    within(row("entry")) { click_link "Edit" }

    expect(page).to have_current_path(edit_entry_path(entry, previous_url: activity_path))
  end
end
