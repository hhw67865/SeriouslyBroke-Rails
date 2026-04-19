# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account Navigation - Sidebar link", type: :system do
  let!(:user) { create(:user, name: "Henry Wu") }

  before { sign_in user, scope: :user }

  it "navigates from sidebar profile block to the account page", :aggregate_failures do
    visit root_path

    within("[data-controller='shared--sidebar']") do
      click_link href: account_path, match: :first
    end

    expect(page).to have_current_path(account_path)
    expect(page).to have_content("Account Information")
  end
end
