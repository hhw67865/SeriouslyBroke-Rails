# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Activity" do
  let(:user) { create(:user, :biweekly) }

  before do
    create(:account, user: user, name: "Checking")
    sign_in user, scope: :user
  end

  it "renders an empty state for a user with nothing logged yet", :aggregate_failures do
    get activity_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Nothing has happened yet. Log an entry and it shows up here.")
  end

  it "renders rows for entries, transfers and adjustments", :aggregate_failures do
    groceries = create(:category, user: user, name: "Groceries")
    emergency = create(:account, user: user, name: "Emergency")
    create(:entry, item: create(:item, category: groceries, name: "Bread"), amount: 5, date: Date.current)
    create(:transfer, from_account: user.accounts.find_by!(name: "Checking"), to_account: emergency, amount: 20, date: Date.current)

    get activity_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Bread · Groceries").and include("Checking → Emergency")
  end
end
