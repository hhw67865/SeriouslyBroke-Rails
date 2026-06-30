# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account Show - Info Card", type: :system do
  let!(:user) { create(:user, name: "Henry Wu", email: "demo@example.com") }

  before { sign_in user, scope: :user }

  describe "account information", :aggregate_failures do
    before { visit account_path }

    it "renders the Account page with the user's name and email" do
      expect(page).to have_content("Account")
      expect(page).to have_content("Account Information")
      expect(page).to have_content("Henry Wu")
      expect(page).to have_content("demo@example.com")
      expect(page).to have_content(user.created_at.strftime("%b %d, %Y"))
    end

    it "shows an Edit action that links to the Devise edit page" do
      expect(page).to have_link("Edit", href: edit_user_registration_path)
    end
  end

  describe "timezone display", :aggregate_failures do
    it "shows the user's timezone when set" do
      user.update!(timezone: "America/New_York")
      visit account_path

      expect(page).to have_content("Timezone")
      expect(page).to have_content("Eastern Time (US & Canada)")
    end

    it "shows a not-set notice when the user has no timezone" do
      visit account_path

      expect(page).to have_content("Not set (defaults to UTC)")
    end
  end
end
