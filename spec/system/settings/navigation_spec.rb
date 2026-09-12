# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account Navigation - Sidebar link", type: :system do
  let!(:user) { create(:user, name: "Henry Wu") }

  before { sign_in user, scope: :user }

  it "navigates from sidebar profile block to the account page", :aggregate_failures do
    # Starts from entries: the dashboard is rebuilt in a later plan.
    visit entries_path

    within("[data-controller='shared--sidebar']") do
      click_link href: settings_path, match: :first
    end

    expect(page).to have_current_path(settings_path)
    expect(page).to have_content("Account Information")
  end
end
