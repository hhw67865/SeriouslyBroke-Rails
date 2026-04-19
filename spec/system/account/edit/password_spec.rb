# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account Edit - Password", type: :system do
  let!(:user) { create(:user, password: "password123") }

  before do
    sign_in user, scope: :user
    visit edit_user_registration_path
  end

  describe "updating password", :aggregate_failures do
    it "rejects update when new password and confirmation do not match" do
      fill_in "New password", with: "newpassword1"
      fill_in "Confirm new password", with: "different1"
      fill_in "Current password", with: "password123"
      click_button "Save Changes"

      expect(user.reload.valid_password?("password123")).to be true
      expect(page).to have_content(/doesn't match/i)
    end

    it "rejects update with wrong current password" do
      fill_in "New password", with: "newpassword1"
      fill_in "Confirm new password", with: "newpassword1"
      fill_in "Current password", with: "wrongpassword"
      click_button "Save Changes"

      expect(user.reload.valid_password?("password123")).to be true
      expect(page).to have_content(/invalid/i)
    end

    it "saves when new password, confirmation, and current password are correct" do
      fill_in "New password", with: "newpassword1"
      fill_in "Confirm new password", with: "newpassword1"
      fill_in "Current password", with: "password123"
      click_button "Save Changes"

      expect(page).to have_current_path(account_path)
      expect(user.reload.valid_password?("newpassword1")).to be true
    end
  end
end
