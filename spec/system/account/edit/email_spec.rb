# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account Edit - Email", type: :system do
  let!(:user) { create(:user, email: "old@example.com", password: "password123") }

  before do
    sign_in user, scope: :user
    visit edit_user_registration_path
  end

  describe "updating email", :aggregate_failures do
    it "rejects update when email and confirmation do not match" do
      fill_in "Email", with: "new@example.com"
      fill_in "Confirm email", with: "different@example.com"
      fill_in "Current password", with: "password123"
      click_button "Save Changes"

      expect(user.reload.email).to eq("old@example.com")
      expect(page).to have_content(/doesn't match/i)
    end

    it "rejects update with wrong current password" do
      fill_in "Email", with: "new@example.com"
      fill_in "Confirm email", with: "new@example.com"
      fill_in "Current password", with: "wrongpassword"
      click_button "Save Changes"

      expect(user.reload.email).to eq("old@example.com")
      expect(page).to have_content(/invalid/i)
    end

    it "saves when email, confirmation, and current password are correct" do
      fill_in "Email", with: "new@example.com"
      fill_in "Confirm email", with: "new@example.com"
      fill_in "Current password", with: "password123"
      click_button "Save Changes"

      expect(page).to have_current_path(account_path)
      expect(user.reload.email).to eq("new@example.com")
    end
  end
end
