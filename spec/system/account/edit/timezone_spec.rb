# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account Edit - Timezone", type: :system do
  let!(:user) { create(:user, timezone: "America/New_York", password: "password123") }

  before do
    sign_in user, scope: :user
    visit edit_user_registration_path
  end

  describe "updating timezone only", :aggregate_failures do
    it "saves without requiring current password" do
      select "(GMT-08:00) Pacific Time (US & Canada)", from: "Timezone"
      click_button "Save Changes"

      expect(page).to have_current_path(account_path)
      expect(user.reload.timezone).to eq("America/Los_Angeles")
    end
  end
end
