# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account Edit - Name", type: :system do
  let!(:user) { create(:user, name: "Old Name", password: "password123") }

  before do
    sign_in user, scope: :user
    visit edit_user_registration_path
  end

  describe "updating name only", :aggregate_failures do
    it "saves without requiring current password" do
      fill_in "Name", with: "New Name"
      click_button "Save Changes"

      expect(page).to have_current_path(account_path)
      expect(user.reload.name).to eq("New Name")
    end
  end
end
